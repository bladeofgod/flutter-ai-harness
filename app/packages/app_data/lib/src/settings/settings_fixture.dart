import 'dart:typed_data';

import 'package:app_core/app_core.dart';

import '../auth/auth_models.dart';
import '../fixture/fixture_api_transport.dart';
import 'settings_models.dart';

/// Settings 请求、偏好状态与 Fixture Payload 的唯一所有者。
final class SettingsFixtureHandler implements FixtureRequestHandler {
  static const String loadKey = 'settings.preferences.load';
  static const String updatePreferencesKey = 'settings.preferences.update';
  static const String updateProfileKey = 'settings.profile.update';

  SettingsPreferences _preferences = defaultSettingsPreferences;

  void resetSession() => _preferences = defaultSettingsPreferences;

  static const SettingsPreferences defaultSettingsPreferences =
      SettingsPreferences(
        country: SettingsCountry.unitedStates,
        language: SettingsLanguage.english,
        currency: SettingsCurrency.usd,
        sizeType: SettingsSizeType.international,
        notificationsEnabled: true,
      );

  @override
  Set<String> get requestKeys => const <String>{
    loadKey,
    updatePreferencesKey,
    updateProfileKey,
  };

  @override
  Future<ApiResponse<Object?>> handle(ApiRequest request) async =>
      switch (request.key) {
        loadKey => ApiResponse<Object?>.success(
          _preferencesPayload(_preferences),
        ),
        updatePreferencesKey => _updatePreferences(request.payload),
        updateProfileKey => _updateProfile(request.payload),
        _ => throw UnknownApiRequestException(request.key),
      };

  ApiResponse<Object?> _updatePreferences(Object? payload) {
    try {
      _preferences = _preferencesFromPayload(payload);
      return ApiResponse<Object?>.success(_preferencesPayload(_preferences));
    } on FormatException {
      return const ApiResponse<Object?>.failure(
        ApiFailure.rejected(code: 'settings.invalid_request'),
      );
    }
  }

  ApiResponse<Object?> _updateProfile(Object? payload) {
    if (payload is! Map<String, Object?>) {
      return const ApiResponse<Object?>.failure(
        ApiFailure.rejected(code: 'settings.invalid_request'),
      );
    }
    final id = payload['id'];
    final displayName = payload['displayName'];
    final email = payload['email'];
    final callingCode = payload['callingCode'];
    final phoneNumber = payload['phoneNumber'];
    final avatarKind = payload['avatarKind'];
    final avatarValue = payload['avatarValue'];
    if (id is! String ||
        id.isEmpty ||
        displayName is! String ||
        displayName.trim().isEmpty ||
        email is! String ||
        callingCode is! String ||
        phoneNumber is! String ||
        avatarKind is! String ||
        (avatarValue is! String && avatarValue is! Uint8List)) {
      return const ApiResponse<Object?>.failure(
        ApiFailure.rejected(code: 'settings.invalid_request'),
      );
    }
    try {
      EmailAddress(email);
      CountryCallingCode(callingCode);
      PhoneNumber(phoneNumber);
      if (avatarKind == UserAvatarKind.asset.name && avatarValue is String) {
        UserAvatar.asset(avatarValue);
      } else if (avatarKind == UserAvatarKind.memory.name &&
          avatarValue is Uint8List) {
        UserAvatar.memory(avatarValue);
      } else {
        throw const FormatException('Invalid avatar payload.');
      }
    } on FormatException {
      return const ApiResponse<Object?>.failure(
        ApiFailure.rejected(code: 'settings.invalid_request'),
      );
    } on ArgumentError {
      return const ApiResponse<Object?>.failure(
        ApiFailure.rejected(code: 'settings.invalid_request'),
      );
    }
    return ApiResponse<Object?>.success(
      Map<String, Object?>.unmodifiable(<String, Object?>{
        'id': id,
        'displayName': displayName.trim(),
        'email': email,
        'callingCode': callingCode,
        'phoneNumber': phoneNumber,
        'avatarKind': avatarKind,
        'avatarValue': avatarValue,
      }),
    );
  }
}

Map<String, Object?> _preferencesPayload(SettingsPreferences preferences) =>
    <String, Object?>{
      'countryId': preferences.country.id,
      'languageId': preferences.language.id,
      'currencyId': preferences.currency.id,
      'sizeTypeId': preferences.sizeType.id,
      'notificationsEnabled': preferences.notificationsEnabled,
    };

SettingsPreferences _preferencesFromPayload(Object? payload) {
  if (payload is! Map<String, Object?>) {
    throw const FormatException('Invalid Settings preferences payload.');
  }
  final countryId = payload['countryId'];
  final languageId = payload['languageId'];
  final currencyId = payload['currencyId'];
  final sizeTypeId = payload['sizeTypeId'];
  final notificationsEnabled = payload['notificationsEnabled'];
  if (countryId is! String ||
      languageId is! String ||
      currencyId is! String ||
      sizeTypeId is! String ||
      notificationsEnabled is! bool) {
    throw const FormatException('Invalid Settings preferences fields.');
  }
  return SettingsPreferences(
    country: SettingsCountry.fromId(countryId),
    language: SettingsLanguage.fromId(languageId),
    currency: SettingsCurrency.fromId(currencyId),
    sizeType: SettingsSizeType.fromId(sizeTypeId),
    notificationsEnabled: notificationsEnabled,
  );
}
