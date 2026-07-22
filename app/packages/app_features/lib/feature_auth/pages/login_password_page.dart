import 'package:app_data/app_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../controllers/login_controller.dart';
import '../login_flow_scope.dart';
import '../widgets/auth_components.dart';
import '../widgets/login_flow_components.dart';

final class LoginPasswordPage extends StatefulWidget {
  const LoginPasswordPage({
    required this.onAuthenticated,
    required this.onForgotPassword,
    required this.onBack,
    super.key,
  });

  final ValueChanged<AuthResult> onAuthenticated;
  final ValueChanged<UserEntity> onForgotPassword;
  final VoidCallback onBack;

  @override
  State<LoginPasswordPage> createState() => _LoginPasswordPageState();
}

final class _LoginPasswordPageState extends State<LoginPasswordPage> {
  var _isCompleting = false;

  @override
  Widget build(BuildContext context) {
    final controller = LoginFlowScope.of(context);
    return BackButtonListener(
      onBackButtonPressed: () async {
        _back(controller);
        return true;
      },
      child: PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            _back(controller);
          }
        },
        child: GetBuilder<LoginController>(
          init: controller,
          global: false,
          autoRemove: false,
          builder: (controller) {
            final user = controller.recognizedUser;
            if (user == null) {
              return const SizedBox.shrink();
            }
            return AuthFlowPageFrame(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 105),
                  Align(
                    child: LoginUserAvatar(
                      key: const ValueKey('login-user-avatar'),
                      user: user,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Hello, ${user.displayName}!!',
                    textAlign: TextAlign.center,
                    style: AuthFlowTextStyles.userTitle,
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Type your password',
                    textAlign: TextAlign.center,
                    style: AuthFlowTextStyles.description,
                  ),
                  const SizedBox(height: 5),
                  Align(
                    child: PasswordDots(
                      key: const ValueKey('login-password-dots'),
                      enteredCharacters: controller.enteredPasswordCharacters,
                      showError: controller.showFailedPasswordDots,
                      onPressed: controller.passwordFocusNode.requestFocus,
                    ),
                  ),
                  Align(
                    child: ExcludeSemantics(
                      child: SizedBox(
                        width: 1,
                        height: 1,
                        child: TextField(
                          key: const ValueKey('login-password-input'),
                          controller: controller.passwordController,
                          focusNode: controller.passwordFocusNode,
                          autofocus: true,
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          keyboardType: TextInputType.visiblePassword,
                          textInputAction: TextInputAction.go,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(
                              Password.requiredLength,
                            ),
                          ],
                          cursorColor: Colors.transparent,
                          style: const TextStyle(
                            color: Colors.transparent,
                            fontSize: 1,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            isCollapsed: true,
                          ),
                          onChanged: (_) async {
                            if (controller.enteredPasswordCharacters ==
                                Password.requiredLength) {
                              await _submit(controller);
                            }
                          },
                          onSubmitted: (_) async {
                            await _submit(controller);
                          },
                        ),
                      ),
                    ),
                  ),
                  if (controller.passwordError ==
                      LoginPasswordError.exactLength) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Enter exactly 8 characters.',
                      textAlign: TextAlign.center,
                      style: AuthTextStyles.fieldError,
                    ),
                  ],
                  if (controller.formError case LoginFormError.unavailable) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Login is unavailable. Try again.',
                      textAlign: TextAlign.center,
                      style: AuthTextStyles.fieldError,
                    ),
                  ],
                  if (controller.passwordError ==
                      LoginPasswordError.invalidCredentials) ...[
                    const SizedBox(height: 7),
                    Align(
                      child: TextButton(
                        key: const ValueKey('login-forgot-password'),
                        onPressed: () {
                          controller.prepareRecovery();
                          widget.onForgotPassword(user);
                        },
                        child: const Text(
                          'Forgot your password?',
                          style: AuthTextStyles.cancelAction,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _submit(LoginController controller) async {
    if (_isCompleting) {
      return;
    }
    _isCompleting = true;
    try {
      final result = await controller.submitPassword();
      if (result != null && mounted) {
        widget.onAuthenticated(result);
      }
    } finally {
      _isCompleting = false;
    }
  }

  void _back(LoginController controller) {
    controller.returnToEmail();
    widget.onBack();
  }
}
