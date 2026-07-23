part of 'settings_local.dart';

abstract final class _SettingsFixtureMapper {
  static SettingsPreferences preferences(Object? payload) => _decode(() {
    final values = _map(payload);
    return SettingsPreferences(
      country: SettingsCountry.fromId(_string(values, 'countryId')),
      language: SettingsLanguage.fromId(_string(values, 'languageId')),
      currency: SettingsCurrency.fromId(_string(values, 'currencyId')),
      sizeType: SettingsSizeType.fromId(_string(values, 'sizeTypeId')),
      notificationsEnabled: _boolean(values, 'notificationsEnabled'),
    );
  });

  static UserEntity user(Object? payload) => _decode(() {
    final values = _map(payload);
    final avatarKind = _string(values, 'avatarKind');
    final avatarValue = _cloneSettingsAvatarPayload(values['avatarValue']);
    final avatar = switch (avatarKind) {
      'asset' when avatarValue is String => UserAvatar.asset(avatarValue),
      'memory' when avatarValue is Uint8List => UserAvatar.memory(avatarValue),
      _ => throw const FormatException('Invalid Settings avatar.'),
    };
    return UserEntity(
      id: _string(values, 'id'),
      displayName: _string(values, 'displayName'),
      email: EmailAddress(_string(values, 'email')),
      callingCode: CountryCallingCode(_string(values, 'callingCode')),
      phoneNumber: PhoneNumber(_string(values, 'phoneNumber')),
      avatar: avatar,
    );
  });

  static T _decode<T>(T Function() decode) {
    try {
      return decode();
    } on SettingsFailure {
      rethrow;
    } on FormatException catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const SettingsFailure(SettingsFailureCode.invalidResponse),
        stackTrace,
      );
    } on ArgumentError catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const SettingsFailure(SettingsFailureCode.invalidResponse),
        stackTrace,
      );
    }
  }

  static Map<String, Object?> _map(Object? payload) {
    if (payload is! Map<String, Object?>) {
      throw const SettingsFailure(SettingsFailureCode.invalidResponse);
    }
    return payload;
  }

  static String _string(Map<String, Object?> values, String key) {
    final value = values[key];
    if (value is! String || value.trim().isEmpty) {
      throw const SettingsFailure(SettingsFailureCode.invalidResponse);
    }
    return value;
  }

  static bool _boolean(Map<String, Object?> values, String key) {
    final value = values[key];
    if (value is! bool) {
      throw const SettingsFailure(SettingsFailureCode.invalidResponse);
    }
    return value;
  }
}
