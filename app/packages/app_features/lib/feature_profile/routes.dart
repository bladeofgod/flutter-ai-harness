import 'package:go_router/go_router.dart';

import '../api/current_user_provider.dart';
import '../api/profile_dashboard_api.dart';
import 'controllers/profile_dashboard_controller.dart';
import 'pages/profile_dashboard_page.dart';

const profileRoutePath = '/profile';

List<RouteBase> buildProfileRoutes({
  required ProfileDashboardApi profileDashboardApi,
  required CurrentUserProvider currentUserProvider,
}) => [
  GoRoute(
    path: profileRoutePath,
    builder: (context, state) => ProfileDashboardPage(
      controller: ProfileDashboardController(
        profileDashboardApi: profileDashboardApi,
        currentUserProvider: currentUserProvider,
      ),
    ),
  ),
];
