import 'dart:async';

import 'package:app_data/app_data.dart';
import 'package:app_features/api/auth_api.dart';
import 'package:app_features/feature_auth/controllers/login_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('validates missing and malformed account identifiers locally', () async {
    final api = _FakeAuthApi();
    final controller = _controller(api);
    addTearDown(controller.onDelete);

    expect(await controller.findAccount(), isNull);
    expect(controller.emailError, LoginEmailError.required);
    controller.emailController.text = 'not-an-email';
    expect(await controller.findAccount(), isNull);
    expect(controller.emailError, LoginEmailError.invalid);
    expect(api.findCount, 0);
  });

  test(
    'recognizes an existing account and reports an unknown account',
    () async {
      final api = _FakeAuthApi(
        findHandler: (email) async => email == _user.email ? _user : null,
      );
      final controller = _controller(api);
      addTearDown(controller.onDelete);

      controller.emailController.text = 'missing@example.com';
      expect(await controller.findAccount(), isNull);
      expect(controller.emailError, LoginEmailError.accountNotFound);

      controller.emailController.text = 'romina@example.com';
      expect(await controller.findAccount(), _user);
      expect(controller.recognizedUser, _user);
      expect(controller.emailError, isNull);
    },
  );

  test('deduplicates account lookup while a request is pending', () async {
    final completer = Completer<UserEntity?>();
    final api = _FakeAuthApi(findHandler: (_) => completer.future);
    final controller = _controller(api);
    addTearDown(controller.onDelete);
    controller.emailController.text = 'romina@example.com';

    final first = controller.findAccount();
    final duplicate = controller.findAccount();
    expect(await duplicate, isNull);
    expect(api.findCount, 1);
    expect(controller.isFindingAccount, isTrue);

    completer.complete(_user);
    expect(await first, _user);
    expect(controller.isFindingAccount, isFalse);
  });

  test(
    'enforces the exact credential length before calling Auth API',
    () async {
      final api = _FakeAuthApi();
      final controller = _controller(api);
      addTearDown(controller.onDelete);
      await _recognize(controller);

      controller.passwordController.text = '1234567';
      expect(await controller.submitPassword(), isNull);
      expect(controller.passwordError, LoginPasswordError.exactLength);
      controller.passwordController.text = '123456789';
      expect(await controller.submitPassword(), isNull);
      expect(controller.passwordError, LoginPasswordError.exactLength);
      expect(api.loginCount, 0);

      controller.passwordController.text = '12345678';
      expect(await controller.submitPassword(), _authResult);
      expect(api.loginCount, 1);
    },
  );

  test('clears rejected secret and exposes stable failed-dot state', () async {
    final api = _FakeAuthApi(
      loginHandler: (_) async =>
          throw const AuthFailure(AuthFailureCode.invalidCredentials),
    );
    final controller = _controller(api);
    addTearDown(controller.onDelete);
    await _recognize(controller);
    controller.passwordController.text = '12345678';

    expect(await controller.submitPassword(), isNull);

    expect(controller.enteredPasswordCharacters, 0);
    expect(controller.passwordError, LoginPasswordError.invalidCredentials);
    expect(controller.showFailedPasswordDots, isTrue);
    controller.passwordController.text = '1';
    expect(controller.passwordError, isNull);
    expect(controller.showFailedPasswordDots, isFalse);
  });

  test(
    'deduplicates successful authentication and returns one result',
    () async {
      final completer = Completer<AuthResult>();
      final api = _FakeAuthApi(loginHandler: (_) => completer.future);
      final controller = _controller(api);
      addTearDown(controller.onDelete);
      await _recognize(controller);
      controller.passwordController.text = '12345678';

      final first = controller.submitPassword();
      final duplicate = controller.submitPassword();
      expect(await duplicate, isNull);
      expect(api.loginCount, 1);
      completer.complete(_authResult);
      expect(await first, _authResult);

      expect(await controller.submitPassword(), isNull);
      expect(api.loginCount, 1);
    },
  );

  test('keeps the account while moving between later flow steps', () async {
    final api = _FakeAuthApi();
    final controller = _controller(api);
    addTearDown(controller.onDelete);
    await _recognize(controller);
    controller.passwordController.text = '1234567';

    controller.prepareRecovery();
    controller.selectRecoveryMethod(PasswordRecoveryMethod.email);
    controller.consumeRecoveryNext();

    expect(controller.recognizedUser, _user);
    expect(controller.enteredPasswordCharacters, 0);
    expect(controller.recoveryMethod, PasswordRecoveryMethod.email);
    expect(api.findCount, 1);
    expect(api.loginCount, 0);

    controller.returnToEmail();
    expect(controller.emailController.text, isNotEmpty);
    expect(controller.recognizedUser, _user);
  });

  test('propagates programming errors and restores pending states', () async {
    final lookupError = StateError('lookup implementation failure');
    final lookupApi = _FakeAuthApi(
      findHandler: (_) => Future<UserEntity?>.error(lookupError),
    );
    final lookupController = _controller(lookupApi);
    addTearDown(lookupController.onDelete);
    lookupController.emailController.text = 'romina@example.com';
    await expectLater(
      lookupController.findAccount(),
      throwsA(same(lookupError)),
    );
    expect(lookupController.isFindingAccount, isFalse);

    final authError = AssertionError('auth implementation failure');
    final authApi = _FakeAuthApi(
      loginHandler: (_) => Future<AuthResult>.error(authError),
    );
    final authController = _controller(authApi);
    addTearDown(authController.onDelete);
    await _recognize(authController);
    authController.passwordController.text = '12345678';
    await expectLater(
      authController.submitPassword(),
      throwsA(same(authError)),
    );
    expect(authController.isLoggingIn, isFalse);
  });

  test(
    'scope disposal clears inputs and closes owned Flutter objects',
    () async {
      final controller = _controller(_FakeAuthApi());
      controller.emailController.text = 'draft@example.com';
      controller.passwordController.text = '12345678';

      controller.onDelete();

      expect(controller.isClosed, isTrue);
      expect(controller.emailController.text, isEmpty);
      expect(controller.passwordController.text, isEmpty);
      expect(controller.recognizedUser, isNull);
      expect(
        () => controller.passwordController.addListener(() {}),
        throwsFlutterError,
      );
    },
  );
}

LoginController _controller(_FakeAuthApi api) =>
    LoginController(authApi: api)..onStart();

Future<void> _recognize(LoginController controller) async {
  controller.emailController.text = 'romina@example.com';
  expect(await controller.findAccount(), _user);
}

final _user = UserEntity(
  id: 'fixture-user-romina',
  displayName: 'Romina',
  email: EmailAddress('romina@example.com'),
  callingCode: CountryCallingCode('+1'),
  phoneNumber: PhoneNumber('2015550123'),
  avatar: UserAvatar.asset('assets/images/profile/avatar_romina.png'),
);
final _authResult = AuthResult(
  user: _user,
  session: AuthSession(id: 'fixture-session-romina', userId: _user.id),
);

final class _FakeAuthApi implements AuthApi {
  _FakeAuthApi({this.findHandler, this.loginHandler});

  final Future<UserEntity?> Function(EmailAddress email)? findHandler;
  final Future<AuthResult> Function(LoginInput input)? loginHandler;
  var findCount = 0;
  var loginCount = 0;

  @override
  Future<UserEntity?> findAccountByEmail(EmailAddress email) {
    findCount += 1;
    return findHandler?.call(email) ?? Future.value(_user);
  }

  @override
  Future<AuthResult> login(LoginInput input) {
    loginCount += 1;
    return loginHandler?.call(input) ?? Future.value(_authResult);
  }

  @override
  Future<AuthResult> register(RegistrationInput input) =>
      throw UnimplementedError();
}
