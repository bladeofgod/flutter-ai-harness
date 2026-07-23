import 'package:app_data/app_data.dart';

import '../../api/settings_api.dart';

/// 通过本地数据源实现 Settings 进程内能力。
final class LocalSettingsApi implements SettingsApi {
  const LocalSettingsApi({required SettingsLocalDataSource dataSource})
    : _dataSource = dataSource;

  final SettingsLocalDataSource _dataSource;

  @override
  Future<SettingsPreferences> load() => _dataSource.load();

  @override
  Future<SettingsPreferences> updatePreferences(
    SettingsPreferences preferences,
  ) => _dataSource.updatePreferences(preferences);

  @override
  Future<UserEntity> updateProfile({
    required UserEntity currentUser,
    required ProfileEditInput input,
  }) => _dataSource.updateProfile(currentUser: currentUser, input: input);
}
