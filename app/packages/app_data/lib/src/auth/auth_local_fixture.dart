part of 'auth_local.dart';

abstract final class _FixtureFailureCode {
  static const String accountNotFound = 'auth.account_not_found';
  static const String duplicateAccount = 'auth.duplicate_account';
  static const String invalidCredentials = 'auth.invalid_credentials';
  static const String invalidRequest = 'auth.invalid_request';
}

final class _FixtureRequest {
  const _FixtureRequest._(this._values);

  static _FixtureRequest? tryParse(Object? payload) {
    if (payload is! Map<String, Object?>) {
      return null;
    }
    return _FixtureRequest._(payload);
  }

  final Map<String, Object?> _values;

  String? string(String key) {
    final value = _values[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  String? secretString(String key) {
    final value = _values[key];
    return value is Secret<String> ? value.reveal() : null;
  }

  Map<String, Object?>? map(String key) {
    final value = _values[key];
    if (value is! Map<String, Object?>) {
      return null;
    }
    return Map<String, Object?>.unmodifiable(value);
  }

  @override
  String toString() => '_FixtureRequest(<redacted>)';
}

final class _FixtureAuthRecord {
  _FixtureAuthRecord({
    required this.userId,
    required this.displayName,
    required this.email,
    required this.callingCode,
    required this.phoneNumber,
    required Map<String, Object?> avatar,
  }) : avatar = Map<String, Object?>.unmodifiable(avatar);

  final String userId;
  final String displayName;
  final String email;
  final String callingCode;
  final String phoneNumber;
  final Map<String, Object?> avatar;

  Map<String, Object?> toUserPayload() => <String, Object?>{
    'id': userId,
    'displayName': displayName,
    'email': email,
    'callingCode': callingCode,
    'phoneNumber': phoneNumber,
    'avatar': _copyAvatarPayload(),
  };

  Map<String, Object?> toAuthPayload() => <String, Object?>{
    'user': toUserPayload(),
    'session': <String, Object?>{
      'id': 'fixture-session-$userId',
      'userId': userId,
    },
  };

  Map<String, Object?> _copyAvatarPayload() {
    final bytes = avatar['bytes'];
    return <String, Object?>{
      ...avatar,
      if (bytes is List<int>) 'bytes': List<int>.unmodifiable(bytes),
    };
  }

  @override
  String toString() => '_FixtureAuthRecord(userId: $userId)';
}
