import 'package:app_core/app_core.dart';

import '../auth/auth_local.dart';
import 'profile_dashboard_failure.dart';
import 'profile_dashboard_models.dart';

part 'profile_dashboard_mapper.dart';

/// 通过 [ApiClient] 加载确定性的 Profile Dashboard Fixture。
final class ProfileDashboardLocalDataSource {
  const ProfileDashboardLocalDataSource({required ApiClient apiClient})
    : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<ProfileDashboard> load() async {
    final response = await _apiClient.send<Object?>(
      const ApiRequest(key: FixtureRequestKeys.profileDashboard),
    );
    return switch (response) {
      ApiSuccess<Object?>(:final payload) =>
        _ProfileDashboardFixtureMapper.dashboard(payload),
      ApiError<Object?>(:final failure) => _throwMappedFailure(failure),
    };
  }

  Never _throwMappedFailure(ApiFailure failure) {
    final mappedFailure = ProfileDashboardFailure(switch (failure.kind) {
      ApiFailureKind.unknownRequest =>
        ProfileDashboardFailureCode.unknownRequest,
      ApiFailureKind.transport =>
        ProfileDashboardFailureCode.transportUnavailable,
      ApiFailureKind.invalidResponse =>
        ProfileDashboardFailureCode.invalidResponse,
      ApiFailureKind.rejected =>
        failure.code == 'profile.dashboard_unavailable'
            ? ProfileDashboardFailureCode.unavailable
            : ProfileDashboardFailureCode.invalidResponse,
    });
    final stackTrace = failure.stackTrace;
    if (stackTrace != null) {
      Error.throwWithStackTrace(mappedFailure, stackTrace);
    }
    throw mappedFailure;
  }
}
