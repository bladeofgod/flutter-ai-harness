import 'package:app_data/app_data.dart';

/// Profile Dashboard 需要的只读业务数据边界。
abstract interface class ProfileDashboardApi {
  Future<ProfileDashboard> load();
}
