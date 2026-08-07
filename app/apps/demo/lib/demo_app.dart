library;

import 'dart:async';

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
    this.featuresRegistryFactory,
    this.authStateCoordinator,
    this.initialLocation = welcomeRoutePath,
  }) : assert(
         featuresRegistry == null || featuresRegistryFactory == null,
         'Provide either featuresRegistry or featuresRegistryFactory.',
       );

  final FeaturesRegistry? featuresRegistry;
  final FeaturesRegistry Function()? featuresRegistryFactory;
  final AuthStateCoordinator? authStateCoordinator;
  final String initialLocation;

  @override
  State<DemoApp> createState() => _DemoAppState();
}

class _DemoAppState extends State<DemoApp> {
  late final FeaturesRegistry _featuresRegistry;
  late final bool _ownsFeaturesRegistry;
  late final AuthStateCoordinator _authStateCoordinator;
  late final bool _ownsAuthStateCoordinator;
  late final GoRouter _router;
  late final VoidCallback _detachSessionReset;

  @override
  void initState() {
    super.initState();
    _ownsFeaturesRegistry = widget.featuresRegistry == null;
    _featuresRegistry =
        widget.featuresRegistry ??
        widget.featuresRegistryFactory?.call() ??
        FeaturesRegistry.local();
    _ownsAuthStateCoordinator = widget.authStateCoordinator == null;
    _authStateCoordinator =
        widget.authStateCoordinator ?? AuthStateCoordinator();
    if (!_ownsFeaturesRegistry && !_authStateCoordinator.isLoggedIn) {
      _featuresRegistry.resetUserSession();
    }
    _detachSessionReset = _authStateCoordinator.attachSessionReset(
      _featuresRegistry.resetUserSession,
    );
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
    _detachSessionReset();
    if (_ownsFeaturesRegistry) {
      unawaited(_disposeOwnedFeaturesRegistry());
    }
    if (_ownsAuthStateCoordinator) {
      _authStateCoordinator.dispose();
    }
    super.dispose();
  }

  Future<void> _disposeOwnedFeaturesRegistry() async {
    try {
      await _featuresRegistry.dispose();
    } on Object catch (_, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: const _FeaturesRegistryDisposalFailure(),
          stack: stackTrace,
          library: 'demo_app',
          context: ErrorDescription('while disposing app feature resources'),
        ),
      );
    }
  }
}

final class _FeaturesRegistryDisposalFailure implements Exception {
  const _FeaturesRegistryDisposalFailure();

  @override
  String toString() => 'FeaturesRegistryDisposalFailure(<redacted>)';
}
