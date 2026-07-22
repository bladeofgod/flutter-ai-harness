import 'package:app_core/app_core.dart';
import 'package:app_data/app_data.dart';

import 'api/auth_api.dart';
import 'api/profile_dashboard_api.dart';
import 'feature_auth/api/local_auth_api.dart';
import 'feature_profile/api/local_profile_dashboard_api.dart';

/// 为 Demo 壳工程创建 Feature 依赖，隐藏具体 Feature 实现。
final class FeaturesRegistry {
  const FeaturesRegistry._({
    required this.authApi,
    required this.profileDashboardApi,
  });

  factory FeaturesRegistry.local() {
    final transport = FixtureApiTransport();
    final client = ApiClient(transport: transport);
    final authDataSource = AuthLocalDataSource(apiClient: client);
    final profileDataSource = ProfileDashboardLocalDataSource(
      apiClient: client,
    );

    return FeaturesRegistry._(
      authApi: LocalAuthApi(dataSource: authDataSource),
      profileDashboardApi: LocalProfileDashboardApi(
        dataSource: profileDataSource,
      ),
    );
  }

  final AuthApi authApi;
  final ProfileDashboardApi profileDashboardApi;
}
