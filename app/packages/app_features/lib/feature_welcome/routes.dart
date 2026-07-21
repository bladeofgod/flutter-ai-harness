import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'pages/welcome_page.dart';

const welcomeRoutePath = '/';

List<RouteBase> buildWelcomeRoutes({
  required VoidCallback onGetStarted,
  required VoidCallback onSignIn,
}) => [
  GoRoute(
    path: welcomeRoutePath,
    builder: (context, state) =>
        WelcomePage(onGetStarted: onGetStarted, onSignIn: onSignIn),
  ),
];
