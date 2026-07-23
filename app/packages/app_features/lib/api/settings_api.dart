import 'package:app_data/app_data.dart';

/// Settings 页面所需的窄业务边界。
abstract interface class SettingsApi {
  Future<SettingsPreferences> load();

  Future<SettingsPreferences> updatePreferences(
    SettingsPreferences preferences,
  );

  Future<UserEntity> updateProfile({
    required UserEntity currentUser,
    required ProfileEditInput input,
  });
}
