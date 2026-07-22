import 'package:app_data/app_data.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../api/auth_api.dart';
import 'avatar/image_picker_registration_avatar_picker.dart';
import 'controllers/login_controller.dart';
import 'controllers/registration_controller.dart';
import 'login_flow_scope.dart';
import 'pages/login_email_page.dart';
import 'pages/login_password_page.dart';
import 'pages/password_recovery_page.dart';
import 'pages/registration_page.dart';

const registrationRoutePath = '/auth/register';
const loginRoutePath = '/auth/login';
const passwordRoutePath = '/auth/password';
const recoveryRoutePath = '/auth/recovery';

List<RouteBase> buildRegistrationRoutes({
  required AuthApi authApi,
  required ValueChanged<AuthResult> onAuthenticated,
  required void Function(BuildContext context) onCancel,
}) => [
  GoRoute(
    path: registrationRoutePath,
    builder: (context, state) => RegistrationPage(
      createController: () => RegistrationController(
        authApi: authApi,
        avatarPicker: ImagePickerRegistrationAvatarPicker(),
      ),
      onAuthenticated: onAuthenticated,
      onCancel: () => onCancel(context),
    ),
  ),
];

List<RouteBase> buildLoginRoutes({
  required AuthApi authApi,
  required ValueChanged<AuthResult> onAuthenticated,
  required void Function(BuildContext context) onCancel,
}) {
  LoginController? activeController;
  final navigatorKey = GlobalKey<NavigatorState>(
    debugLabel: 'login-flow-navigator',
  );

  String? redirectUnrecognizedLoginStep(
    BuildContext context,
    GoRouterState state,
  ) {
    final access = state.extra;
    final recognizedUser = activeController?.recognizedUser;
    return access is _LoginFlowAccess &&
            recognizedUser != null &&
            recognizedUser.id == access.userId
        ? null
        : loginRoutePath;
  }

  return [
    ShellRoute(
      navigatorKey: navigatorKey,
      builder: (context, state, child) => LoginFlowScope(
        key: const ValueKey('login-flow-scope'),
        authApi: authApi,
        onControllerAttached: (controller) => activeController = controller,
        onControllerDetached: (controller) {
          if (identical(activeController, controller)) {
            activeController = null;
          }
        },
        child: child,
      ),
      routes: [
        GoRoute(
          path: loginRoutePath,
          builder: (context, state) => LoginEmailPage(
            onAccountRecognized: (user) =>
                context.go(passwordRoutePath, extra: _LoginFlowAccess(user.id)),
            onCancel: () => onCancel(context),
          ),
        ),
        GoRoute(
          path: passwordRoutePath,
          redirect: redirectUnrecognizedLoginStep,
          builder: (context, state) => LoginPasswordPage(
            onAuthenticated: onAuthenticated,
            onForgotPassword: (user) =>
                context.go(recoveryRoutePath, extra: _LoginFlowAccess(user.id)),
            onBack: () => context.go(loginRoutePath),
          ),
        ),
        GoRoute(
          path: recoveryRoutePath,
          redirect: redirectUnrecognizedLoginStep,
          builder: (context, state) => PasswordRecoveryPage(
            onReturnToPassword: (user) =>
                context.go(passwordRoutePath, extra: _LoginFlowAccess(user.id)),
          ),
        ),
      ],
    ),
  ];
}

final class _LoginFlowAccess {
  const _LoginFlowAccess(this.userId);

  final String userId;
}
