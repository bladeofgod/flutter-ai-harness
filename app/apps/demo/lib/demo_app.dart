library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 产品设计实装前使用的中立 Demo 壳。
class DemoApp extends StatefulWidget {
  const DemoApp({super.key});

  @override
  State<DemoApp> createState() => _DemoAppState();
}

class _DemoAppState extends State<DemoApp> {
  late final GoRouter _router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Flutter AI Harness'))),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(routerConfig: _router);
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }
}
