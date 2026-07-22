import 'package:app_data/app_data.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/login_controller.dart';
import '../login_flow_scope.dart';
import '../widgets/auth_components.dart';
import '../widgets/login_flow_components.dart';

final class PasswordRecoveryPage extends StatelessWidget {
  const PasswordRecoveryPage({required this.onReturnToPassword, super.key});

  final ValueChanged<UserEntity> onReturnToPassword;

  @override
  Widget build(BuildContext context) {
    final controller = LoginFlowScope.of(context);
    return BackButtonListener(
      onBackButtonPressed: () async {
        _returnToPassword(controller);
        return true;
      },
      child: PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            _returnToPassword(controller);
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
                      key: const ValueKey('recovery-user-avatar'),
                      user: user,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Password Recovery',
                    textAlign: TextAlign.center,
                    style: AuthFlowTextStyles.userTitle,
                  ),
                  const SizedBox(height: 18),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 57),
                    child: const Center(
                      child: SizedBox(
                        width: 290,
                        child: Text(
                          'How you would like to restore your password?',
                          textAlign: TextAlign.center,
                          style: AuthFlowTextStyles.recoveryQuestion,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 23),
                  Align(
                    child: PasswordRecoveryChoice(
                      key: const ValueKey('recovery-sms'),
                      method: PasswordRecoveryMethod.sms,
                      selected:
                          controller.recoveryMethod ==
                          PasswordRecoveryMethod.sms,
                      onPressed: () => controller.selectRecoveryMethod(
                        PasswordRecoveryMethod.sms,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    child: PasswordRecoveryChoice(
                      key: const ValueKey('recovery-email'),
                      method: PasswordRecoveryMethod.email,
                      selected:
                          controller.recoveryMethod ==
                          PasswordRecoveryMethod.email,
                      onPressed: () => controller.selectRecoveryMethod(
                        PasswordRecoveryMethod.email,
                      ),
                    ),
                  ),
                  const SizedBox(height: 148),
                  AuthPrimaryButton(
                    key: const ValueKey('recovery-next'),
                    label: 'Next',
                    onPressed: controller.consumeRecoveryNext,
                  ),
                  const SizedBox(height: 10),
                  Align(
                    child: AuthCancelButton(
                      key: const ValueKey('recovery-cancel'),
                      onPressed: () => _returnToPassword(controller),
                    ),
                  ),
                  const SizedBox(height: 15),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _returnToPassword(LoginController controller) {
    final user = controller.recognizedUser;
    if (user == null) {
      return;
    }
    controller.prepareRecovery();
    onReturnToPassword(user);
  }
}
