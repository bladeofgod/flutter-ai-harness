import 'dart:async';
import 'dart:typed_data';

import 'package:app_data/app_data.dart';
import 'package:app_features/api/auth_api.dart';
import 'package:app_features/feature_auth/avatar/registration_avatar_picker.dart';
import 'package:app_features/feature_auth/controllers/registration_controller.dart';
import 'package:app_features/feature_auth/models/registration_country.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults to the United Kingdom and exposes the approved countries', () {
    final controller = _controller();
    addTearDown(controller.onClose);

    expect(controller.selectedCountry.name, 'United Kingdom');
    expect(controller.selectedCountry.callingCode, '+44');
    expect(registrationCountries, hasLength(10));
    expect(
      registrationCountries.map((country) => country.name),
      containsAll(<String>['United States', 'China', 'South Korea', 'France']),
    );

    controller.selectCountry(registrationCountries[3]);
    expect(controller.selectedCountry.name, 'China');
    expect(controller.selectedCountry.callingCode, '+86');
  });

  test('validates all required fields without calling Auth API', () async {
    final api = _FakeAuthApi();
    final controller = _controller(api: api);
    addTearDown(controller.onClose);

    expect(await controller.submit(), isNull);

    expect(controller.emailError, RegistrationEmailError.required);
    expect(controller.passwordError, RegistrationPasswordError.required);
    expect(controller.phoneError, RegistrationPhoneError.required);
    expect(api.registrationInputs, isEmpty);
  });

  test(
    'validates email, exact password length, and 6 to 15 phone digits',
    () async {
      final controller = _controller();
      addTearDown(controller.onClose);
      controller.emailController.text = 'not-an-email';
      controller.passwordController.text = '1234567';
      controller.phoneController.text = '12345';

      expect(await controller.submit(), isNull);
      expect(controller.emailError, RegistrationEmailError.invalid);
      expect(controller.passwordError, RegistrationPasswordError.exactLength);
      expect(controller.phoneError, RegistrationPhoneError.invalid);

      controller.emailController.text = 'new@example.com';
      controller.passwordController.text = '123456789';
      controller.phoneController.text = '1234567890123456';
      expect(await controller.submit(), isNull);
      expect(controller.passwordError, RegistrationPasswordError.exactLength);
      expect(controller.phoneError, RegistrationPhoneError.invalid);
    },
  );

  test(
    'keeps avatar on cancel and failure, and replaces it on success',
    () async {
      final picker = _FakeAvatarPicker(<RegistrationAvatarPickResult>[
        RegistrationAvatarPickSuccess(Uint8List.fromList(<int>[1, 2, 3])),
        const RegistrationAvatarPickCanceled(),
        const RegistrationAvatarPickFailed(
          RegistrationAvatarFailure(RegistrationAvatarFailureCode.tooLarge),
        ),
        const RegistrationAvatarPickFailed(
          RegistrationAvatarFailure(RegistrationAvatarFailureCode.invalidImage),
        ),
      ]);
      final controller = _controller(picker: picker);
      addTearDown(controller.onClose);

      await controller.pickAvatar();
      expect(controller.avatarBytes, <int>[1, 2, 3]);
      await controller.pickAvatar();
      expect(controller.avatarBytes, <int>[1, 2, 3]);
      expect(controller.avatarFailure, isNull);
      await controller.pickAvatar();
      expect(controller.avatarBytes, <int>[1, 2, 3]);
      expect(
        controller.avatarFailure?.code,
        RegistrationAvatarFailureCode.tooLarge,
      );
      await controller.pickAvatar();
      expect(controller.avatarBytes, <int>[1, 2, 3]);
      expect(
        controller.avatarFailure?.code,
        RegistrationAvatarFailureCode.invalidImage,
      );
    },
  );

  test(
    'propagates picker programming errors and restores picking state',
    () async {
      final error = StateError('picker programming failure');
      final controller = _controller(picker: _ThrowingAvatarPicker(error));
      addTearDown(controller.onClose);

      await expectLater(controller.pickAvatar(), throwsA(same(error)));

      expect(controller.isPickingAvatar, isFalse);
      expect(controller.avatarFailure, isNull);
      expect(controller.avatarBytes, isNull);
    },
  );

  test('submits one normalized Domain input and returns AuthResult', () async {
    final api = _FakeAuthApi();
    final controller = _controller(api: api);
    addTearDown(controller.onClose);
    _fillValidForm(controller);

    final result = await controller.submit();

    expect(result, _authResult);
    expect(api.registrationInputs, hasLength(1));
    final input = api.registrationInputs.single;
    expect(input.email.value, 'new.shopper@example.com');
    expect(input.callingCode.value, '+44');
    expect(input.phoneNumber.value, '7700900123');
    expect(input.avatar.assetKey, RegistrationController.defaultAvatarAsset);
  });

  test('submits the avatar selected for the registration session', () async {
    final avatarBytes = Uint8List.fromList(<int>[7, 8, 9]);
    final api = _FakeAuthApi();
    final controller = _controller(
      api: api,
      picker: _FakeAvatarPicker(<RegistrationAvatarPickResult>[
        RegistrationAvatarPickSuccess(avatarBytes),
      ]),
    );
    addTearDown(controller.onClose);
    _fillValidForm(controller);

    await controller.pickAvatar();
    await controller.submit();
    avatarBytes[0] = 0;

    expect(api.registrationInputs.single.avatar.kind, UserAvatarKind.memory);
    expect(api.registrationInputs.single.avatar.bytes, <int>[7, 8, 9]);
  });

  test('maps duplicate account to the email field', () async {
    final api = _FakeAuthApi(
      registrationHandler: (_) async =>
          throw const AuthFailure(AuthFailureCode.duplicateAccount),
    );
    final controller = _controller(api: api);
    addTearDown(controller.onClose);
    _fillValidForm(controller);

    expect(await controller.submit(), isNull);
    expect(controller.emailError, RegistrationEmailError.duplicate);
    expect(controller.formError, isNull);
  });

  test('propagates Auth API errors and restores submitting state', () async {
    final error = AssertionError('Auth API programming failure');
    final api = _FakeAuthApi(
      registrationHandler: (_) => Future<AuthResult>.error(error),
    );
    final controller = _controller(api: api);
    addTearDown(controller.onClose);
    _fillValidForm(controller);

    await expectLater(controller.submit(), throwsA(same(error)));

    expect(controller.isSubmitting, isFalse);
    expect(controller.formError, isNull);
    expect(controller.emailError, isNull);
  });

  test('deduplicates submit while an Auth request is in flight', () async {
    final completer = Completer<AuthResult>();
    final api = _FakeAuthApi(registrationHandler: (_) => completer.future);
    final controller = _controller(api: api);
    addTearDown(controller.onClose);
    _fillValidForm(controller);

    final first = controller.submit();
    final second = controller.submit();
    expect(await second, isNull);
    expect(controller.isSubmitting, isTrue);
    expect(api.registrationInputs, hasLength(1));

    completer.complete(_authResult);
    expect(await first, _authResult);
    expect(controller.isSubmitting, isFalse);
  });

  test(
    'reset clears inputs, image, errors, and ignores in-flight success',
    () async {
      final completer = Completer<AuthResult>();
      final api = _FakeAuthApi(registrationHandler: (_) => completer.future);
      final picker = _FakeAvatarPicker(<RegistrationAvatarPickResult>[
        RegistrationAvatarPickSuccess(Uint8List.fromList(<int>[4, 5, 6])),
      ]);
      final controller = _controller(api: api, picker: picker);
      addTearDown(controller.onClose);
      _fillValidForm(controller);
      await controller.pickAvatar();
      final pending = controller.submit();

      controller.reset();
      completer.complete(_authResult);

      expect(await pending, isNull);
      expect(controller.emailController.text, isEmpty);
      expect(controller.passwordController.text, isEmpty);
      expect(controller.phoneController.text, isEmpty);
      expect(controller.avatarBytes, isNull);
      expect(controller.selectedCountry, defaultRegistrationCountry);
      expect(controller.isSubmitting, isFalse);
    },
  );
}

RegistrationController _controller({
  _FakeAuthApi? api,
  RegistrationAvatarPicker? picker,
}) {
  final controller = RegistrationController(
    authApi: api ?? _FakeAuthApi(),
    avatarPicker: picker ?? _FakeAvatarPicker(const []),
  );
  controller.onInit();
  return controller;
}

void _fillValidForm(RegistrationController controller) {
  controller.emailController.text = '  NEW.SHOPPER@EXAMPLE.COM  ';
  controller.passwordController.text = 'shopper1';
  controller.phoneController.text = '7700900123';
}

final _authUser = UserEntity(
  id: 'new-user',
  displayName: 'New Shopper',
  email: EmailAddress('new.shopper@example.com'),
  callingCode: CountryCallingCode('+44'),
  phoneNumber: PhoneNumber('7700900123'),
  avatar: UserAvatar.asset(RegistrationController.defaultAvatarAsset),
);
final _authResult = AuthResult(
  user: _authUser,
  session: AuthSession(id: 'session-new-user', userId: _authUser.id),
);

final class _FakeAuthApi implements AuthApi {
  _FakeAuthApi({this.registrationHandler});

  final Future<AuthResult> Function(RegistrationInput input)?
  registrationHandler;
  final registrationInputs = <RegistrationInput>[];

  @override
  Future<UserEntity?> findAccountByEmail(EmailAddress email) async => null;

  @override
  Future<AuthResult> login(LoginInput input) => throw UnimplementedError();

  @override
  Future<AuthResult> register(RegistrationInput input) {
    registrationInputs.add(input);
    return registrationHandler?.call(input) ?? Future.value(_authResult);
  }
}

final class _FakeAvatarPicker implements RegistrationAvatarPicker {
  _FakeAvatarPicker(List<RegistrationAvatarPickResult> results)
    : _results = List.of(results);

  final List<RegistrationAvatarPickResult> _results;

  @override
  Future<RegistrationAvatarPickResult> pickFromGallery() async =>
      _results.removeAt(0);
}

final class _ThrowingAvatarPicker implements RegistrationAvatarPicker {
  const _ThrowingAvatarPicker(this.error);

  final Object error;

  @override
  Future<RegistrationAvatarPickResult> pickFromGallery() =>
      Future<RegistrationAvatarPickResult>.error(error);
}
