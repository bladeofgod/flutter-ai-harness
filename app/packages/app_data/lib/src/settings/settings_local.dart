import 'dart:typed_data';

import 'package:app_core/app_core.dart';

import '../auth/auth_models.dart';
import 'settings_failure.dart';
import 'settings_fixture.dart';
import 'settings_models.dart';

part 'settings_mapper.dart';

/// 通过 [ApiClient] 读写进程内 Settings Fixture。
final class SettingsLocalDataSource {
  const SettingsLocalDataSource({required ApiClient apiClient})
    : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<SettingsPreferences> load() async {
    final response = await _apiClient.send<Object?>(
      const ApiRequest(key: SettingsFixtureHandler.loadKey),
    );
    return _mapPreferencesResponse(response);
  }

  Future<SettingsPreferences> updatePreferences(
    SettingsPreferences preferences,
  ) async {
    final response = await _apiClient.send<Object?>(
      ApiRequest(
        key: SettingsFixtureHandler.updatePreferencesKey,
        payload: <String, Object?>{
          'countryId': preferences.country.id,
          'languageId': preferences.language.id,
          'currencyId': preferences.currency.id,
          'sizeTypeId': preferences.sizeType.id,
          'notificationsEnabled': preferences.notificationsEnabled,
        },
      ),
    );
    return _mapPreferencesResponse(response);
  }

  Future<UserEntity> updateProfile({
    required UserEntity currentUser,
    required ProfileEditInput input,
  }) async {
    final avatarValue = switch (input.avatar.kind) {
      UserAvatarKind.asset => input.avatar.assetKey,
      UserAvatarKind.memory => input.avatar.bytes,
    };
    final response = await _apiClient.send<Object?>(
      ApiRequest(
        key: SettingsFixtureHandler.updateProfileKey,
        payload: <String, Object?>{
          'id': currentUser.id,
          'displayName': input.displayName,
          'email': input.email.value,
          'callingCode': input.callingCode.value,
          'phoneNumber': input.phoneNumber.value,
          'avatarKind': input.avatar.kind.name,
          'avatarValue': avatarValue,
        },
      ),
    );
    return switch (response) {
      ApiSuccess<Object?>(:final payload) => _SettingsFixtureMapper.user(
        payload,
      ),
      ApiError<Object?>(:final failure) => _throwMappedFailure(failure),
    };
  }

  SettingsPreferences _mapPreferencesResponse(ApiResponse<Object?> response) =>
      switch (response) {
        ApiSuccess<Object?>(:final payload) =>
          _SettingsFixtureMapper.preferences(payload),
        ApiError<Object?>(:final failure) => _throwMappedFailure(failure),
      };

  Never _throwMappedFailure(ApiFailure failure) {
    final mappedFailure = SettingsFailure(switch (failure.kind) {
      ApiFailureKind.unknownRequest => SettingsFailureCode.unknownRequest,
      ApiFailureKind.transport => SettingsFailureCode.transportUnavailable,
      ApiFailureKind.invalidResponse => SettingsFailureCode.invalidResponse,
      ApiFailureKind.rejected =>
        failure.code == 'settings.invalid_request'
            ? SettingsFailureCode.invalidRequest
            : failure.code == 'settings.unavailable'
            ? SettingsFailureCode.unavailable
            : SettingsFailureCode.invalidResponse,
    });
    final stackTrace = failure.stackTrace;
    if (stackTrace != null) {
      Error.throwWithStackTrace(mappedFailure, stackTrace);
    }
    throw mappedFailure;
  }
}

Object? _cloneSettingsAvatarPayload(Object? payload) => switch (payload) {
  final Uint8List value => Uint8List.fromList(value),
  _ => payload,
};
