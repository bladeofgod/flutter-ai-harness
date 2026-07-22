import 'dart:typed_data';

import 'package:app_core/app_core.dart';

import 'auth_failure.dart';
import 'auth_models.dart';

part '../profile/profile_dashboard_fixture.dart';
part 'auth_local_fixture.dart';
part 'auth_local_mapper.dart';

/// `app_data` 内部 LocalDataSource 与 Fixture Transport 的稳定请求键。
///
/// 根包入口不会导出该类型。
abstract final class FixtureRequestKeys {
  static const String profileDashboard = 'profile.dashboard.load';
}

/// Auth Fixture 支持的确定性、无状态 Transport。
final class FixtureApiTransport implements ApiTransport {
  static const String _lookupAccountKey = 'auth.account.lookup';
  static const String _registerKey = 'auth.register';
  static const String _loginKey = 'auth.login';
  static const String _rominaEmail = 'romina@example.com';
  static const String _invalidDemoPassword = '00000000';
  static const String _defaultCallingCode = '+1';
  static const String _defaultPhoneNumber = '2015550123';
  static const Map<String, Object?> _defaultAvatar = <String, Object?>{
    'kind': 'asset',
    'assetKey': 'assets/images/profile/avatar_romina.png',
  };

  @override
  Future<ApiResponse<Object?>> send(ApiRequest request) async {
    return switch (request.key) {
      _lookupAccountKey => _lookupAccount(request.payload),
      _registerKey => _register(request.payload),
      _loginKey => _login(request.payload),
      FixtureRequestKeys.profileDashboard => ApiResponse<Object?>.success(
        _profileDashboardFixturePayload(),
      ),
      _ => throw UnknownApiRequestException(request.key),
    };
  }

  ApiResponse<Object?> _lookupAccount(Object? payload) {
    final input = _FixtureRequest.tryParse(payload);
    final email = _normalizedEmail(input?.string('email'));
    if (email == null) {
      return _invalidRequest();
    }
    return ApiResponse<Object?>.success(_recordForEmail(email).toUserPayload());
  }

  ApiResponse<Object?> _register(Object? payload) {
    final input = _FixtureRequest.tryParse(payload);
    final email = _normalizedEmail(input?.string('email'));
    final password = input?.secretString('password');
    final callingCode = input?.string('callingCode');
    final phoneNumber = input?.string('phoneNumber');
    final avatar = input?.map('avatar');
    if (email == null ||
        password == null ||
        password.length != Password.requiredLength ||
        callingCode == null ||
        phoneNumber == null ||
        avatar == null) {
      return _invalidRequest();
    }
    final record = _FixtureAuthRecord(
      userId: _userIdFromEmail(email),
      displayName: _displayNameFromEmail(email),
      email: email,
      callingCode: callingCode,
      phoneNumber: phoneNumber,
      avatar: avatar,
    );
    return ApiResponse<Object?>.success(record.toAuthPayload());
  }

  ApiResponse<Object?> _login(Object? payload) {
    final input = _FixtureRequest.tryParse(payload);
    final email = _normalizedEmail(input?.string('email'));
    final password = input?.secretString('password');
    if (email == null ||
        password == null ||
        password.length != Password.requiredLength) {
      return _invalidRequest();
    }
    if (password == _invalidDemoPassword) {
      return const ApiResponse<Object?>.failure(
        ApiFailure.rejected(code: _FixtureFailureCode.invalidCredentials),
      );
    }
    return ApiResponse<Object?>.success(_recordForEmail(email).toAuthPayload());
  }

  ApiResponse<Object?> _invalidRequest() => const ApiResponse<Object?>.failure(
    ApiFailure.rejected(code: _FixtureFailureCode.invalidRequest),
  );

  String? _normalizedEmail(String? input) {
    if (input == null) {
      return null;
    }
    try {
      return EmailAddress(input).value;
    } on FormatException {
      return null;
    }
  }

  _FixtureAuthRecord _recordForEmail(String email) => _FixtureAuthRecord(
    userId: _userIdFromEmail(email),
    displayName: _displayNameFromEmail(email),
    email: email,
    callingCode: _defaultCallingCode,
    phoneNumber: _defaultPhoneNumber,
    avatar: _defaultAvatar,
  );

  String _userIdFromEmail(String email) => email == _rominaEmail
      ? 'fixture-user-romina'
      : 'fixture-user-${Uri.encodeComponent(email)}';

  String _displayNameFromEmail(String email) {
    final localPart = email.split('@').first;
    final words = localPart
        .split(RegExp(r'[._-]+'))
        .where((word) => word.isNotEmpty)
        .map((word) => '${word[0].toUpperCase()}${word.substring(1)}');
    final displayName = words.join(' ');
    return displayName.isEmpty ? 'Shoppe User' : displayName;
  }

  @override
  String toString() =>
      'FixtureApiTransport(mode: stateless, credentials: <redacted>)';
}

/// 通过 [ApiClient] 访问 Auth Fixture，并在本包内完成 Payload 映射。
final class AuthLocalDataSource {
  const AuthLocalDataSource({required ApiClient apiClient})
    : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<UserEntity?> findAccountByEmail(EmailAddress email) async {
    final response = await _apiClient.send<Object?>(
      ApiRequest(
        key: FixtureApiTransport._lookupAccountKey,
        payload: <String, Object?>{'email': email.value},
      ),
    );
    return switch (response) {
      ApiSuccess<Object?>(:final payload) =>
        payload == null ? null : _AuthFixtureMapper.user(payload),
      ApiError<Object?>(:final failure) => _throwMappedFailure(failure),
    };
  }

  Future<AuthResult> register(RegistrationInput input) async {
    final response = await _apiClient.send<Object?>(
      ApiRequest(
        key: FixtureApiTransport._registerKey,
        payload: <String, Object?>{
          'email': input.email.value,
          'password': input.password.toSecret(),
          'callingCode': input.callingCode.value,
          'phoneNumber': input.phoneNumber.value,
          'avatar': _avatarPayload(input.avatar),
        },
      ),
    );
    return _mapAuthResponse(response);
  }

  Future<AuthResult> login(LoginInput input) async {
    final response = await _apiClient.send<Object?>(
      ApiRequest(
        key: FixtureApiTransport._loginKey,
        payload: <String, Object?>{
          'email': input.email.value,
          'password': input.password.toSecret(),
        },
      ),
    );
    return _mapAuthResponse(response);
  }

  AuthResult _mapAuthResponse(ApiResponse<Object?> response) {
    return switch (response) {
      ApiSuccess<Object?>(:final payload) => _AuthFixtureMapper.auth(payload),
      ApiError<Object?>(:final failure) => _throwMappedFailure(failure),
    };
  }

  Never _throwMappedFailure(ApiFailure failure) {
    final mappedFailure = _mapFailure(failure);
    final stackTrace = failure.stackTrace;
    if (stackTrace != null) {
      Error.throwWithStackTrace(mappedFailure, stackTrace);
    }
    throw mappedFailure;
  }

  Map<String, Object?> _avatarPayload(UserAvatar avatar) {
    return switch (avatar.kind) {
      UserAvatarKind.asset => <String, Object?>{
        'kind': 'asset',
        'assetKey': avatar.assetKey,
      },
      UserAvatarKind.memory => <String, Object?>{
        'kind': 'memory',
        'bytes': avatar.bytes?.toList(growable: false),
      },
    };
  }

  AuthFailure _mapFailure(ApiFailure failure) {
    final code = switch (failure.kind) {
      ApiFailureKind.unknownRequest => AuthFailureCode.unknownRequest,
      ApiFailureKind.transport => AuthFailureCode.transportUnavailable,
      ApiFailureKind.invalidResponse => AuthFailureCode.invalidResponse,
      ApiFailureKind.rejected => switch (failure.code) {
        _FixtureFailureCode.accountNotFound => AuthFailureCode.accountNotFound,
        _FixtureFailureCode.duplicateAccount =>
          AuthFailureCode.duplicateAccount,
        _FixtureFailureCode.invalidCredentials =>
          AuthFailureCode.invalidCredentials,
        _FixtureFailureCode.invalidRequest => AuthFailureCode.invalidRequest,
        _ => AuthFailureCode.invalidResponse,
      },
    };
    return AuthFailure(code);
  }
}
