import 'package:app_data/app_data.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/login_controller.dart';
import '../login_flow_scope.dart';
import '../widgets/auth_components.dart';
import '../widgets/login_flow_components.dart';

final class LoginEmailPage extends StatefulWidget {
  const LoginEmailPage({
    required this.onAccountRecognized,
    required this.onCancel,
    super.key,
  });

  final ValueChanged<UserEntity> onAccountRecognized;
  final VoidCallback onCancel;

  @override
  State<LoginEmailPage> createState() => _LoginEmailPageState();
}

final class _LoginEmailPageState extends State<LoginEmailPage> {
  var _isLeaving = false;

  @override
  Widget build(BuildContext context) {
    final controller = LoginFlowScope.of(context);
    return BackButtonListener(
      onBackButtonPressed: () async {
        _cancel(controller);
        return true;
      },
      child: PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            _cancel(controller);
          }
        },
        child: GetBuilder<LoginController>(
          init: controller,
          global: false,
          autoRemove: false,
          builder: (controller) => AuthFlowPageFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 394),
                const Text('Login', style: AuthFlowTextStyles.largeTitle),
                const SizedBox(height: 4),
                const Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Good to see you back!',
                        style: AuthFlowTextStyles.description,
                      ),
                    ),
                    SizedBox(width: 8),
                    ExcludeSemantics(
                      child: Icon(
                        Icons.favorite,
                        size: 18,
                        color: AppColors.textStrong,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 19),
                AuthCapsuleTextField(
                  key: const ValueKey('login-email'),
                  controller: controller.emailController,
                  hintText: 'Email',
                  semanticsLabel: 'Email',
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.email],
                  enabled: !controller.isFindingAccount,
                  onSubmitted: (_) => _findAccount(controller),
                  errorText: _emailErrorText(controller.emailError),
                ),
                if (controller.formError case LoginFormError.unavailable) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Login is unavailable. Try again.',
                    textAlign: TextAlign.center,
                    style: AuthTextStyles.fieldError,
                  ),
                ],
                const SizedBox(height: 36.625),
                AuthPrimaryButton(
                  key: const ValueKey('login-next'),
                  label: 'Next',
                  isLoading: controller.isFindingAccount,
                  onPressed: controller.isFindingAccount
                      ? null
                      : () => _findAccount(controller),
                ),
                const SizedBox(height: 10),
                Align(
                  child: AuthCancelButton(
                    key: const ValueKey('login-cancel'),
                    onPressed: () => _cancel(controller),
                  ),
                ),
                const SizedBox(height: 15),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _findAccount(LoginController controller) async {
    final user = await controller.findAccount();
    if (user != null && mounted && !_isLeaving) {
      widget.onAccountRecognized(user);
    }
  }

  void _cancel(LoginController controller) {
    if (_isLeaving) {
      return;
    }
    _isLeaving = true;
    controller.resetFlow();
    widget.onCancel();
  }
}

String? _emailErrorText(LoginEmailError? error) => switch (error) {
  null => null,
  LoginEmailError.required => 'Email is required.',
  LoginEmailError.invalid => 'Enter a valid email address.',
  LoginEmailError.accountNotFound => 'No account was found for this email.',
};
