import 'dart:collection';
import 'dart:typed_data';

import 'package:app_core/app_core.dart';
import 'package:app_data/app_data.dart';
import 'package:test/test.dart';

void main() {
  group('stateless login fixture', () {
    late FixtureApiTransport transport;
    late AuthLocalDataSource dataSource;

    setUp(() {
      transport = _authTransport();
      dataSource = _dataSource(transport);
    });

    test('finds the deterministic Romina account', () async {
      final user = await dataSource.findAccountByEmail(
        EmailAddress('ROMINA@example.com'),
      );

      expect(user, isNotNull);
      expect(user!.id, 'fixture-user-romina');
      expect(user.displayName, 'Romina');
      expect(user.email.value, 'romina@example.com');
      expect(user.callingCode.value, '+1');
      expect(user.phoneNumber.value, '2015550123');
      expect(user.avatar.kind, UserAvatarKind.asset);
      expect(user.avatar.assetKey, 'assets/images/profile/avatar_romina.png');
    });

    test('synthesizes stable distinct users for every valid email', () async {
      final first = await dataSource.findAccountByEmail(
        EmailAddress('Taylor.Reed@example.com'),
      );
      final rebuilt = await _dataSource(
        _authTransport(),
      ).findAccountByEmail(EmailAddress('taylor.reed@example.com'));
      final other = await dataSource.findAccountByEmail(
        EmailAddress('other@example.com'),
      );

      expect(first, isNotNull);
      expect(rebuilt, first);
      expect(first?.displayName, 'Taylor Reed');
      expect(first?.id, isNot(other?.id));
      expect(first?.avatar.assetKey, 'assets/images/profile/avatar_romina.png');
    });

    test('logs in with the published demo fixture', () async {
      final result = await dataSource.login(
        LoginInput(
          email: EmailAddress('romina@example.com'),
          password: Password('shoppe01'),
        ),
      );

      expect(result.user.id, 'fixture-user-romina');
      expect(result.session.userId, result.user.id);
      expect(result.session.id, 'fixture-session-fixture-user-romina');
    });

    test('accepts any non-reserved eight-character password', () async {
      final result = await dataSource.login(
        LoginInput(
          email: EmailAddress('new.shopper@example.com'),
          password: Password('wrong001'),
        ),
      );

      expect(result.user.displayName, 'New Shopper');
      expect(result.user.email.value, 'new.shopper@example.com');
      expect(result.session.userId, result.user.id);
    });

    test('maps the reserved demo password to a stable failure', () async {
      await expectLater(
        dataSource.login(
          LoginInput(
            email: EmailAddress('romina@example.com'),
            password: Password('00000000'),
          ),
        ),
        throwsA(const AuthFailure(AuthFailureCode.invalidCredentials)),
      );
    });

    test('does not expose fixture credentials through diagnostics', () {
      expect(transport.toString(), isNot(contains('shoppe01')));
      expect(transport.toString(), contains('<redacted>'));
    });
  });

  group('stateless registration fixture', () {
    test(
      'returns submitted profile without seeding subsequent login state',
      () async {
        final dataSource = _dataSource(_authTransport());
        final input = _registrationInput();

        final registered = await dataSource.register(input);
        final found = await dataSource.findAccountByEmail(input.email);
        final loggedIn = await dataSource.login(
          LoginInput(email: input.email, password: input.password),
        );

        expect(registered.user.displayName, 'Taylor Reed');
        expect(registered.user.callingCode.value, '+44');
        expect(registered.user.phoneNumber.value, '2071234567');
        expect(
          registered.user.avatar.assetKey,
          'assets/images/profile/taylor.png',
        );
        expect(found?.id, registered.user.id);
        expect(found?.callingCode.value, '+1');
        expect(
          found?.avatar.assetKey,
          'assets/images/profile/avatar_romina.png',
        );
        expect(loggedIn.user, found);
      },
    );

    test('allows repeated registration without storing an account', () async {
      final dataSource = _dataSource(_authTransport());
      final input = _registrationInput();

      final first = await dataSource.register(input);
      final second = await dataSource.register(input);

      expect(second, first);
    });

    test(
      'transport recreation keeps the same synthetic account rule',
      () async {
        final first = _dataSource(_authTransport());
        final input = _registrationInput();
        await first.register(input);

        final rebuilt = _dataSource(_authTransport());

        final found = await rebuilt.findAccountByEmail(input.email);
        expect(found?.displayName, 'Taylor Reed');
        expect(found?.callingCode.value, '+1');
        expect(found?.avatar.kind, UserAvatarKind.asset);
      },
    );

    test('round-trips defensive in-memory avatar bytes', () async {
      final sourceBytes = Uint8List.fromList(<int>[10, 20, 30]);
      final dataSource = _dataSource(_authTransport());
      final input = RegistrationInput(
        email: EmailAddress('memory@example.com'),
        password: Password('memory01'),
        callingCode: CountryCallingCode('+81'),
        phoneNumber: PhoneNumber('9012345678'),
        avatar: UserAvatar.memory(sourceBytes),
      );

      final result = await dataSource.register(input);
      sourceBytes[0] = 99;
      final resultBytes = result.user.avatar.bytes!;
      resultBytes[1] = 99;

      final found = await dataSource.findAccountByEmail(input.email);
      expect(result.user.avatar.bytes, <int>[10, 20, 30]);
      expect(found?.avatar.kind, UserAvatarKind.asset);
      expect(found?.avatar.assetKey, 'assets/images/profile/avatar_romina.png');
    });
  });

  group('mapper and failure boundary', () {
    test('maps malformed fixture payload to invalidResponse', () async {
      final dataSource = _dataSource(
        const _PayloadTransport(<String, Object?>{'id': 42}),
      );

      await expectLater(
        dataSource.findAccountByEmail(EmailAddress('romina@example.com')),
        throwsA(const AuthFailure(AuthFailureCode.invalidResponse)),
      );
    });

    test('normalizes value object parsing failures from payloads', () async {
      final dataSource = _dataSource(
        const _PayloadTransport(<String, Object?>{
          'id': 'fixture-user-romina',
          'displayName': 'Romina',
          'email': 'not-an-email',
          'callingCode': '+1',
          'phoneNumber': '2015550123',
          'avatar': <String, Object?>{
            'kind': 'asset',
            'assetKey': 'assets/romina.png',
          },
        }),
      );

      await expectLater(
        dataSource.findAccountByEmail(EmailAddress('romina@example.com')),
        throwsA(const AuthFailure(AuthFailureCode.invalidResponse)),
      );
    });

    test('normalizes inconsistent auth snapshots from payloads', () async {
      final dataSource = _dataSource(
        const _PayloadTransport(<String, Object?>{
          'user': <String, Object?>{
            'id': 'user-1',
            'displayName': 'Romina',
            'email': 'romina@example.com',
            'callingCode': '+1',
            'phoneNumber': '2015550123',
            'avatar': <String, Object?>{
              'kind': 'asset',
              'assetKey': 'assets/romina.png',
            },
          },
          'session': <String, Object?>{
            'id': 'session-1',
            'userId': 'different-user',
          },
        }),
      );

      await expectLater(
        dataSource.login(
          LoginInput(
            email: EmailAddress('romina@example.com'),
            password: Password('shoppe01'),
          ),
        ),
        throwsA(const AuthFailure(AuthFailureCode.invalidResponse)),
      );
    });

    test('rejects out-of-range memory image bytes', () async {
      final dataSource = _dataSource(
        const _PayloadTransport(<String, Object?>{
          'id': 'fixture-user-romina',
          'displayName': 'Romina',
          'email': 'romina@example.com',
          'callingCode': '+1',
          'phoneNumber': '2015550123',
          'avatar': <String, Object?>{
            'kind': 'memory',
            'bytes': <int>[0, 256],
          },
        }),
      );

      await expectLater(
        dataSource.findAccountByEmail(EmailAddress('romina@example.com')),
        throwsA(const AuthFailure(AuthFailureCode.invalidResponse)),
      );
    });

    test('uses stable keys for lookup, registration, and login', () async {
      final transport = _KeyRecordingTransport();
      final dataSource = _dataSource(transport);

      await dataSource.findAccountByEmail(EmailAddress('none@example.com'));
      await expectLater(
        dataSource.register(_registrationInput()),
        throwsA(isA<AuthFailure>()),
      );
      await expectLater(
        dataSource.login(
          LoginInput(
            email: EmailAddress('romina@example.com'),
            password: Password('shoppe01'),
          ),
        ),
        throwsA(isA<AuthFailure>()),
      );

      expect(transport.keys, <String>[
        'auth.account.lookup',
        'auth.register',
        'auth.login',
      ]);
    });

    test(
      'maps transport failures and preserves their original stack',
      () async {
        final dataSource = _dataSource(_ThrowingTransport());

        try {
          await dataSource.login(
            LoginInput(
              email: EmailAddress('romina@example.com'),
              password: Password('shoppe01'),
            ),
          );
          fail('Expected an AuthFailure.');
        } on AuthFailure catch (failure, stackTrace) {
          expect(failure.code, AuthFailureCode.transportUnavailable);
          expect(failure.toString(), isNot(contains('private detail')));
          expect(stackTrace.toString(), contains('_ThrowingTransport.send'));
        }
      },
    );

    test('does not hide unexpected mapper programming errors', () async {
      final dataSource = _dataSource(_PayloadTransport(_ProgrammingErrorMap()));

      await expectLater(
        dataSource.findAccountByEmail(EmailAddress('romina@example.com')),
        throwsStateError,
      );
    });

    test('outgoing request diagnostics redact password payloads', () async {
      final transport = _CapturingRejectedTransport();
      final dataSource = _dataSource(transport);

      await expectLater(
        dataSource.login(
          LoginInput(
            email: EmailAddress('romina@example.com'),
            password: Password('shoppe01'),
          ),
        ),
        throwsA(const AuthFailure(AuthFailureCode.invalidCredentials)),
      );

      expect(transport.request.toString(), isNot(contains('shoppe01')));
      expect(transport.request.toString(), contains('payload: <redacted>'));
    });
  });
}

AuthLocalDataSource _dataSource(ApiTransport transport) =>
    AuthLocalDataSource(apiClient: ApiClient(transport: transport));

FixtureApiTransport _authTransport() => FixtureApiTransport(
  handlers: <FixtureRequestHandler>[AuthFixtureHandler()],
);

RegistrationInput _registrationInput() => RegistrationInput(
  email: EmailAddress('taylor.reed@example.com'),
  password: Password('taylor01'),
  callingCode: CountryCallingCode('+44'),
  phoneNumber: PhoneNumber('2071234567'),
  avatar: UserAvatar.asset('assets/images/profile/taylor.png'),
);

final class _PayloadTransport implements ApiTransport {
  const _PayloadTransport(this.payload);

  final Object? payload;

  @override
  Future<ApiResponse<Object?>> send(ApiRequest request) async =>
      ApiResponse<Object?>.success(payload);
}

final class _ThrowingTransport implements ApiTransport {
  @override
  Future<ApiResponse<Object?>> send(ApiRequest request) async {
    throw const ApiTransportException(cause: 'private detail');
  }
}

final class _ProgrammingErrorMap extends MapBase<String, Object?> {
  @override
  Object? operator [](Object? key) {
    throw StateError('programming error');
  }

  @override
  void operator []=(String key, Object? value) {
    throw UnsupportedError('read only');
  }

  @override
  void clear() {
    throw UnsupportedError('read only');
  }

  @override
  Iterable<String> get keys => const <String>[];

  @override
  Object? remove(Object? key) {
    throw UnsupportedError('read only');
  }
}

final class _CapturingRejectedTransport implements ApiTransport {
  late ApiRequest request;

  @override
  Future<ApiResponse<Object?>> send(ApiRequest request) async {
    this.request = request;
    return const ApiResponse<Object?>.failure(
      ApiFailure.rejected(code: 'auth.invalid_credentials'),
    );
  }
}

final class _KeyRecordingTransport implements ApiTransport {
  final List<String> keys = <String>[];

  @override
  Future<ApiResponse<Object?>> send(ApiRequest request) async {
    keys.add(request.key);
    if (request.key == 'auth.account.lookup') {
      return const ApiResponse<Object?>.success(null);
    }
    return const ApiResponse<Object?>.failure(
      ApiFailure.rejected(code: 'auth.invalid_credentials'),
    );
  }
}
