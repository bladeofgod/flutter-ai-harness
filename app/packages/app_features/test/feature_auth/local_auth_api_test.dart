import 'package:app_data/app_data.dart';
import 'package:app_features/app_features.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FeaturesRegistry local Auth API', () {
    test('normalizes account input and returns a Domain user', () async {
      final registry = FeaturesRegistry.local();

      final UserEntity? account = await registry.authApi.findAccountByEmail(
        EmailAddress('  ROMINA@EXAMPLE.COM  '),
      );

      expect(account, isNotNull);
      expect(account?.displayName, 'Romina');
      expect(account?.email.value, 'romina@example.com');
    });

    test('keeps registration snapshot separate from stateless login', () async {
      final registry = FeaturesRegistry.local();
      final email = EmailAddress('  NEW.SHOPPER@EXAMPLE.COM  ');
      final password = Password('shopper1');

      final AuthResult registration = await registry.authApi.register(
        RegistrationInput(
          email: email,
          password: password,
          callingCode: CountryCallingCode('+44'),
          phoneNumber: PhoneNumber('7700 900123'),
          avatar: UserAvatar.asset('assets/images/profile/new-shopper.png'),
        ),
      );
      final AuthResult login = await registry.authApi.login(
        LoginInput(email: email, password: password),
      );

      expect(registration.user, isA<UserEntity>());
      expect(registration.user.email.value, 'new.shopper@example.com');
      expect(registration.user.displayName, 'New Shopper');
      expect(registration.session.userId, registration.user.id);
      expect(login.user.id, registration.user.id);
      expect(
        login.user.avatar.assetKey,
        'assets/images/profile/avatar_romina.png',
      );
      expect(login.user, isNot(registration.user));
      expect(login.session.userId, login.user.id);
    });

    test('preserves stable Auth failures', () async {
      final registry = FeaturesRegistry.local();

      await expectLater(
        registry.authApi.login(
          LoginInput(
            email: EmailAddress('romina@example.com'),
            password: Password('00000000'),
          ),
        ),
        throwsA(
          isA<AuthFailure>().having(
            (failure) => failure.code,
            'code',
            AuthFailureCode.invalidCredentials,
          ),
        ),
      );
    });

    test('creates registries with the same stateless account rule', () async {
      final firstRegistry = FeaturesRegistry.local();
      final email = EmailAddress('temporary@example.com');
      await firstRegistry.authApi.register(
        RegistrationInput(
          email: email,
          password: Password('temp0001'),
          callingCode: CountryCallingCode('+1'),
          phoneNumber: PhoneNumber('2015550199'),
          avatar: UserAvatar.asset('assets/images/profile/temporary.png'),
        ),
      );

      final secondRegistry = FeaturesRegistry.local();

      final account = await secondRegistry.authApi.findAccountByEmail(email);
      expect(account?.displayName, 'Temporary');
      expect(
        account?.avatar.assetKey,
        'assets/images/profile/avatar_romina.png',
      );
      expect(
        await secondRegistry.authApi.findAccountByEmail(
          EmailAddress('romina@example.com'),
        ),
        isNotNull,
      );
    });

    test('logs in an email that was never registered', () async {
      final registry = FeaturesRegistry.local();

      final result = await registry.authApi.login(
        LoginInput(
          email: EmailAddress('first.visit@example.com'),
          password: Password('welcome1'),
        ),
      );

      expect(result.user.displayName, 'First Visit');
      expect(result.user.email.value, 'first.visit@example.com');
    });
  });
}
