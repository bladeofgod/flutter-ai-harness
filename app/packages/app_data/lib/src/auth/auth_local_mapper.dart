part of 'auth_local.dart';

abstract final class _AuthFixtureMapper {
  static UserEntity user(Object? payload) => _decode(() {
    final values = _map(payload);
    return UserEntity(
      id: _string(values, 'id'),
      displayName: _string(values, 'displayName'),
      email: EmailAddress(_string(values, 'email')),
      callingCode: CountryCallingCode(_string(values, 'callingCode')),
      phoneNumber: PhoneNumber(_string(values, 'phoneNumber')),
      avatar: _avatar(values['avatar']),
    );
  });

  static AuthResult auth(Object? payload) => _decode(() {
    final values = _map(payload);
    final sessionValues = _map(values['session']);
    return AuthResult(
      user: user(values['user']),
      session: AuthSession(
        id: _string(sessionValues, 'id'),
        userId: _string(sessionValues, 'userId'),
      ),
    );
  });

  static T _decode<T>(T Function() decode) {
    try {
      return decode();
    } on AuthFailure {
      rethrow;
    } on FormatException catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const AuthFailure(AuthFailureCode.invalidResponse),
        stackTrace,
      );
    } on ArgumentError catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const AuthFailure(AuthFailureCode.invalidResponse),
        stackTrace,
      );
    }
  }

  static UserAvatar _avatar(Object? payload) {
    final values = _map(payload);
    return switch (_string(values, 'kind')) {
      'asset' => UserAvatar.asset(_string(values, 'assetKey')),
      'memory' => UserAvatar.memory(
        Uint8List.fromList(_intList(values, 'bytes')),
      ),
      _ => throw const AuthFailure(AuthFailureCode.invalidResponse),
    };
  }

  static Map<String, Object?> _map(Object? payload) {
    if (payload is! Map<String, Object?>) {
      throw const AuthFailure(AuthFailureCode.invalidResponse);
    }
    return payload;
  }

  static String _string(Map<String, Object?> values, String key) {
    final value = values[key];
    if (value is! String || value.isEmpty) {
      throw const AuthFailure(AuthFailureCode.invalidResponse);
    }
    return value;
  }

  static List<int> _intList(Map<String, Object?> values, String key) {
    final value = values[key];
    if (value is! List<int> ||
        value.isEmpty ||
        value.any((byte) => byte < 0 || byte > 255)) {
      throw const AuthFailure(AuthFailureCode.invalidResponse);
    }
    return value;
  }
}
