library;

import 'package:app_features/app_features.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class DemoApp extends StatefulWidget {
  const DemoApp({super.key, this.onGetStarted, this.onSignIn});

  final VoidCallback? onGetStarted;
  final VoidCallback? onSignIn;

  @override
  State<DemoApp> createState() => _DemoAppState();
}

class _DemoAppState extends State<DemoApp> {
  late final GoRouter _router = GoRouter(
    routes: buildWelcomeRoutes(
      onGetStarted: _handleGetStarted,
      onSignIn: _handleSignIn,
    ),
  );

  void _handleGetStarted() => widget.onGetStarted?.call();

  void _handleSignIn() => widget.onSignIn?.call();

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
    super.dispose();
  }
}
