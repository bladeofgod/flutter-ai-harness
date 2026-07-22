import 'package:app_data/app_data.dart';

import '../../api/profile_dashboard_api.dart';

/// 通过本地数据源实现 Profile Dashboard 能力。
final class LocalProfileDashboardApi implements ProfileDashboardApi {
  const LocalProfileDashboardApi({
    required ProfileDashboardLocalDataSource dataSource,
  }) : _dataSource = dataSource;

  final ProfileDashboardLocalDataSource _dataSource;

  @override
  Future<ProfileDashboard> load() => _dataSource.load();
}
