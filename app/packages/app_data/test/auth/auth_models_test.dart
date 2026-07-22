import 'dart:typed_data';

import 'package:app_data/app_data.dart';
import 'package:test/test.dart';

void main() {
  group('EmailAddress', () {
    test('trims and normalizes valid input', () {
      expect(EmailAddress('  Romina@Example.COM ').value, 'romina@example.com');
    });

    test('rejects malformed input without echoing it', () {
      const invalid = 'private-value';

      expect(
        () => EmailAddress(invalid),
        throwsA(
          isA<FormatException>().having(
            (error) => error.toString(),
            'diagnostic',
            isNot(contains(invalid)),
          ),
        ),
      );
    });
  });

  group('Password', () {
    test('accepts exactly eight characters', () {
      expect(Password('shoppe01'), equals(Password('shoppe01')));
    });

    test('rejects other lengths without exposing input', () {
      const invalid = 'secret-too-long';

      expect(
        () => Password(invalid),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.toString(),
            'diagnostic',
            isNot(contains(invalid)),
          ),
        ),
      );
    });

    test('redacts password and Secret diagnostics', () {
      final password = Password('shoppe01');

      expect(password.toString(), 'Password(<redacted>)');
      expect(password.toSecret().toString(), 'Secret(<redacted>)');
      expect(password.toString(), isNot(contains('shoppe01')));
    });
  });

  group('phone value objects', () {
    test('normalizes a formatted local phone number', () {
      expect(PhoneNumber('(201) 555-0123').value, '2015550123');
      expect(CountryCallingCode('+1').value, '+1');
    });

    test('rejects invalid country and local numbers', () {
      expect(() => CountryCallingCode('1'), throwsFormatException);
      expect(() => PhoneNumber('+1'), throwsFormatException);
    });
  });

  group('UserAvatar', () {
    test('defensively owns and returns memory bytes', () {
      final source = Uint8List.fromList(<int>[1, 2, 3]);
      final avatar = UserAvatar.memory(source);
      source[0] = 9;

      final firstRead = avatar.bytes!;
      expect(firstRead, <int>[1, 2, 3]);
      firstRead[1] = 9;

      expect(avatar.bytes, <int>[1, 2, 3]);
      expect(avatar.toString(), isNot(contains('[1, 2, 3]')));
    });

    test('accepts relative asset keys and rejects paths or URIs', () {
      expect(
        UserAvatar.asset('assets/images/profile/romina.png').assetKey,
        'assets/images/profile/romina.png',
      );
      expect(() => UserAvatar.asset('/tmp/avatar.png'), throwsArgumentError);
      expect(
        () => UserAvatar.asset('file:///tmp/avatar.png'),
        throwsArgumentError,
      );
      expect(() => UserAvatar.asset('../avatar.png'), throwsArgumentError);
    });
  });

  test('AuthResult requires matching user and session identifiers', () {
    final user = _user();

    expect(
      () => AuthResult(
        user: user,
        session: AuthSession(id: 'session-1', userId: 'other-user'),
      ),
      throwsArgumentError,
    );
  });

  test('User and Session reject empty stable identifiers at runtime', () {
    expect(() => AuthSession(id: '', userId: 'user-1'), throwsArgumentError);
    expect(
      () => UserEntity(
        id: '',
        displayName: 'Romina',
        email: EmailAddress('romina@example.com'),
        callingCode: CountryCallingCode('+1'),
        phoneNumber: PhoneNumber('2015550123'),
        avatar: UserAvatar.asset('assets/romina.png'),
      ),
      throwsArgumentError,
    );
  });

  test('auth input diagnostics never contain password values', () {
    final password = Password('shoppe01');
    final login = LoginInput(
      email: EmailAddress('romina@example.com'),
      password: password,
    );
    final registration = RegistrationInput(
      email: EmailAddress('new@example.com'),
      password: password,
      callingCode: CountryCallingCode('+44'),
      phoneNumber: PhoneNumber('2071234567'),
      avatar: UserAvatar.asset('assets/new.png'),
    );

    expect(login.toString(), isNot(contains('shoppe01')));
    expect(registration.toString(), isNot(contains('shoppe01')));
  });
}

UserEntity _user() => UserEntity(
  id: 'user-1',
  displayName: 'Romina',
  email: EmailAddress('romina@example.com'),
  callingCode: CountryCallingCode('+1'),
  phoneNumber: PhoneNumber('2015550123'),
  avatar: UserAvatar.asset('assets/romina.png'),
);
