library;

import 'package:app_features/app_features.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'auth/auth_state.dart';
import 'router/demo_router.dart';

class DemoApp extends StatefulWidget {
  const DemoApp({
    super.key,
    this.featuresRegistry,
    this.authStateCoordinator,
    this.initialLocation = welcomeRoutePath,
  });

  final FeaturesRegistry? featuresRegistry;
  final AuthStateCoordinator? authStateCoordinator;
  final String initialLocation;

  @override
  State<DemoApp> createState() => _DemoAppState();
}

class _DemoAppState extends State<DemoApp> {
  late final FeaturesRegistry _featuresRegistry;
  late final AuthStateCoordinator _authStateCoordinator;
  late final bool _ownsAuthStateCoordinator;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _featuresRegistry = widget.featuresRegistry ?? FeaturesRegistry.local();
    _ownsAuthStateCoordinator = widget.authStateCoordinator == null;
    _authStateCoordinator =
        widget.authStateCoordinator ?? AuthStateCoordinator();
    _router = createDemoRouter(
      featuresRegistry: _featuresRegistry,
      authStateCoordinator: _authStateCoordinator,
      initialLocation: widget.initialLocation,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Ai-Harness',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: _router,
    );
  }

  @override
  void dispose() {
    _router.dispose();
    if (_ownsAuthStateCoordinator) {
      _authStateCoordinator.dispose();
    }
    super.dispose();
  }
}
