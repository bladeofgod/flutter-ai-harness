import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'pages/welcome_page.dart';

const welcomeRoutePath = '/';

List<RouteBase> buildWelcomeRoutes({
  required void Function(BuildContext context) onGetStarted,
  required void Function(BuildContext context) onSignIn,
}) => [
  GoRoute(
    path: welcomeRoutePath,
    builder: (context, state) => WelcomePage(
      onGetStarted: () => onGetStarted(context),
      onSignIn: () => onSignIn(context),
    ),
  ),
];
