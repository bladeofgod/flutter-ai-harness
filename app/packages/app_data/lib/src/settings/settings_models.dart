import '../auth/auth_models.dart';

/// Settings 只保存稳定标识，不持有系统 Locale 或展示文案。
enum SettingsCountry {
  unitedStates('us'),
  unitedKingdom('gb'),
  china('cn'),
  japan('jp'),
  vietnam('vn'),
  germany('de');

  const SettingsCountry(this.id);

  final String id;

  static SettingsCountry fromId(String id) => values.firstWhere(
    (value) => value.id == id,
    orElse: () => throw FormatException('Unknown country preference: $id'),
  );
}

enum SettingsLanguage {
  english('en'),
  simplifiedChinese('zh-hans'),
  japanese('ja'),
  vietnamese('vi'),
  german('de');

  const SettingsLanguage(this.id);

  final String id;

  static SettingsLanguage fromId(String id) => values.firstWhere(
    (value) => value.id == id,
    orElse: () => throw FormatException('Unknown language preference: $id'),
  );
}

enum SettingsCurrency {
  usd('usd'),
  eur('eur'),
  gbp('gbp'),
  jpy('jpy'),
  cny('cny'),
  vnd('vnd');

  const SettingsCurrency(this.id);

  final String id;

  static SettingsCurrency fromId(String id) => values.firstWhere(
    (value) => value.id == id,
    orElse: () => throw FormatException('Unknown currency preference: $id'),
  );
}

enum SettingsSizeType {
  international('international'),
  unitedStates('us'),
  europe('eu'),
  unitedKingdom('uk');

  const SettingsSizeType(this.id);

  final String id;

  static SettingsSizeType fromId(String id) => values.firstWhere(
    (value) => value.id == id,
    orElse: () => throw FormatException('Unknown size type preference: $id'),
  );
}

/// 当前进程内生效的 App 偏好快照。
final class SettingsPreferences {
  const SettingsPreferences({
    required this.country,
    required this.language,
    required this.currency,
    required this.sizeType,
    required this.notificationsEnabled,
  });

  final SettingsCountry country;
  final SettingsLanguage language;
  final SettingsCurrency currency;
  final SettingsSizeType sizeType;
  final bool notificationsEnabled;

  SettingsPreferences copyWith({
    SettingsCountry? country,
    SettingsLanguage? language,
    SettingsCurrency? currency,
    SettingsSizeType? sizeType,
    bool? notificationsEnabled,
  }) => SettingsPreferences(
    country: country ?? this.country,
    language: language ?? this.language,
    currency: currency ?? this.currency,
    sizeType: sizeType ?? this.sizeType,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingsPreferences &&
          other.country == country &&
          other.language == language &&
          other.currency == currency &&
          other.sizeType == sizeType &&
          other.notificationsEnabled == notificationsEnabled;

  @override
  int get hashCode =>
      Object.hash(country, language, currency, sizeType, notificationsEnabled);
}

/// Profile 编辑页提交给业务边界的类型化输入。
final class ProfileEditInput {
  factory ProfileEditInput({
    required String displayName,
    required EmailAddress email,
    required CountryCallingCode callingCode,
    required PhoneNumber phoneNumber,
    required UserAvatar avatar,
  }) {
    final normalizedName = displayName.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(
        displayName,
        'displayName',
        'Display name must not be empty.',
      );
    }
    return ProfileEditInput._(
      displayName: normalizedName,
      email: email,
      callingCode: callingCode,
      phoneNumber: phoneNumber,
      avatar: avatar,
    );
  }

  const ProfileEditInput._({
    required this.displayName,
    required this.email,
    required this.callingCode,
    required this.phoneNumber,
    required this.avatar,
  });

  final String displayName;
  final EmailAddress email;
  final CountryCallingCode callingCode;
  final PhoneNumber phoneNumber;
  final UserAvatar avatar;

  @override
  String toString() =>
      'ProfileEditInput(displayName: $displayName, email: <redacted>, '
      'phone: <redacted>, avatar: $avatar)';
}
