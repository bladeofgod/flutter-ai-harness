import 'package:app_features/app_features.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_state.dart';

GoRouter createDemoRouter({
  required FeaturesRegistry featuresRegistry,
  required AuthStateCoordinator authStateCoordinator,
  String initialLocation = welcomeRoutePath,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: authStateCoordinator,
    redirect: (context, state) {
      final location = state.matchedLocation;
      final isWelcome = location == welcomeRoutePath;
      final isProfile = location == profileRoutePath;
      final isAuth = location == '/auth' || location.startsWith('/auth/');

      if (!authStateCoordinator.isLoggedIn && isProfile) {
        return welcomeRoutePath;
      }
      if (authStateCoordinator.isLoggedIn && (isWelcome || isAuth)) {
        return profileRoutePath;
      }
      return null;
    },
    routes: <RouteBase>[
      ...buildWelcomeRoutes(
        onGetStarted: (context) => context.go(registrationRoutePath),
        onSignIn: (context) => context.go(loginRoutePath),
      ),
      ...buildRegistrationRoutes(
        authApi: featuresRegistry.authApi,
        onAuthenticated: authStateCoordinator.authenticate,
        onCancel: (context) => context.go(welcomeRoutePath),
      ),
      ...buildLoginRoutes(
        authApi: featuresRegistry.authApi,
        onAuthenticated: authStateCoordinator.authenticate,
        onCancel: (context) => context.go(welcomeRoutePath),
      ),
      ...buildProfileRoutes(
        profileDashboardApi: featuresRegistry.profileDashboardApi,
        currentUserProvider: authStateCoordinator,
      ),
    ],
    errorBuilder: (context, state) => const Scaffold(
      body: SafeArea(child: Center(child: Text('Page not found'))),
    ),
  );
}
