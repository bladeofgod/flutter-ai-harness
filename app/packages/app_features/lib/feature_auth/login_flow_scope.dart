import 'package:flutter/widgets.dart';

import '../api/auth_api.dart';
import 'controllers/login_controller.dart';

/// 在 Login、Password、Recovery 子路由间持有唯一 Controller。
final class LoginFlowScope extends StatefulWidget {
  const LoginFlowScope({
    required this.authApi,
    required this.onControllerAttached,
    required this.onControllerDetached,
    required this.child,
    super.key,
  });

  final AuthApi authApi;
  final ValueChanged<LoginController> onControllerAttached;
  final ValueChanged<LoginController> onControllerDetached;
  final Widget child;

  static LoginController of(BuildContext context) {
    final provider = context
        .dependOnInheritedWidgetOfExactType<_LoginFlowProvider>();
    assert(provider != null, 'LoginFlowScope is missing above this context.');
    return provider!.controller;
  }

  @override
  State<LoginFlowScope> createState() => _LoginFlowScopeState();
}

final class _LoginFlowScopeState extends State<LoginFlowScope> {
  late final LoginController _controller;

  @override
  void initState() {
    super.initState();
    _controller = LoginController(authApi: widget.authApi)..onStart();
    widget.onControllerAttached(_controller);
  }

  @override
  void dispose() {
    widget.onControllerDetached(_controller);
    _controller.onDelete();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _LoginFlowProvider(controller: _controller, child: widget.child);
}

final class _LoginFlowProvider extends InheritedWidget {
  const _LoginFlowProvider({required this.controller, required super.child});

  final LoginController controller;

  @override
  bool updateShouldNotify(_LoginFlowProvider oldWidget) =>
      !identical(controller, oldWidget.controller);
}
