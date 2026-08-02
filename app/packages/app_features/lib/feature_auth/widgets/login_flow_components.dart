import 'dart:math' as math;

import 'package:app_data/app_data.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/login_controller.dart';
import 'auth_components.dart';

const authFlowSystemUiStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.dark,
  statusBarBrightness: Brightness.light,
  systemNavigationBarColor: AppColors.background,
  systemNavigationBarIconBrightness: Brightness.dark,
);

abstract final class AuthFlowTextStyles {
  static const largeTitle = TextStyle(
    color: AppColors.textStrong,
    fontFamily: AppFonts.raleway,
    package: AppFonts.package,
    fontSize: 52,
    fontWeight: FontWeight.w700,
    height: 61 / 52,
    letterSpacing: 0,
  );

  static const userTitle = TextStyle(
    color: AppColors.textStrong,
    fontFamily: AppFonts.raleway,
    package: AppFonts.package,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 34 / 28,
    letterSpacing: 0,
  );

  static const description = TextStyle(
    color: AppColors.textPrimary,
    fontFamily: AppFonts.nunitoSans,
    package: AppFonts.package,
    fontSize: 19,
    fontWeight: FontWeight.w300,
    height: 33 / 19,
    letterSpacing: 0,
  );

  static const recoveryQuestion = TextStyle(
    color: AppColors.textPrimary,
    fontFamily: AppFonts.nunitoSans,
    package: AppFonts.package,
    fontSize: 17,
    fontWeight: FontWeight.w300,
    height: 27 / 17,
    letterSpacing: 0,
  );

  static const choice = TextStyle(
    color: AppColors.textStrong,
    fontFamily: AppFonts.nunitoSans,
    package: AppFonts.package,
    fontSize: 17,
    fontWeight: FontWeight.w400,
    height: 24 / 17,
    letterSpacing: 0,
  );
}

final class AuthFlowPageFrame extends StatelessWidget {
  const AuthFlowPageFrame({
    required this.child,
    this.liftForKeyboard = false,
    super.key,
  });

  static const referenceSafeHeight = 734.0;
  static const keyboardAnimationDuration = Duration(milliseconds: 250);

  final Widget child;
  final bool liftForKeyboard;

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: authFlowSystemUiStyle,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            const Positioned(
              left: -131.97,
              top: -205.67,
              child: AuthBubbleBackground(),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (liftForKeyboard) {
                    return Column(
                      children: [
                        Expanded(
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: authContentMaxWidth,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: authHorizontalPadding,
                                ),
                                child: child,
                              ),
                            ),
                          ),
                        ),
                        AnimatedContainer(
                          key: const ValueKey('auth-keyboard-spacer'),
                          duration: keyboardAnimationDuration,
                          curve: Curves.easeOutCubic,
                          height: keyboardInset,
                        ),
                      ],
                    );
                  }
                  return SingleChildScrollView(
                    key: const ValueKey('auth-flow-scroll'),
                    physics: const ClampingScrollPhysics(),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: authContentMaxWidth,
                          minHeight: math.max(
                            referenceSafeHeight,
                            constraints.maxHeight,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: authHorizontalPadding,
                          ),
                          child: child,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class LoginUserAvatar extends StatelessWidget {
  const LoginUserAvatar({required this.user, super.key});

  final UserEntity user;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: 'Profile photo for ${user.displayName}',
    child: ExcludeSemantics(
      child: SizedBox.square(
        dimension: 105,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.primarySurface,
            shape: BoxShape.circle,
          ),
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: ClipOval(child: _avatarImage(user.avatar)),
          ),
        ),
      ),
    ),
  );

  Widget _avatarImage(UserAvatar avatar) => switch (avatar.kind) {
    UserAvatarKind.asset => Image.asset(
      avatar.assetKey ?? 'assets/images/profile/avatar_romina.png',
      package: 'app_features',
      fit: BoxFit.cover,
      excludeFromSemantics: true,
      errorBuilder: (context, error, stackTrace) => Image.asset(
        'assets/images/profile/avatar_romina.png',
        package: 'app_features',
        fit: BoxFit.cover,
        excludeFromSemantics: true,
      ),
    ),
    UserAvatarKind.memory => Image.memory(
      avatar.bytes!,
      fit: BoxFit.cover,
      excludeFromSemantics: true,
      errorBuilder: (context, error, stackTrace) => const ColoredBox(
        color: AppColors.primarySurface,
        child: Icon(Icons.person_outline, color: AppColors.primary),
      ),
    ),
  };
}

final class PasswordDots extends StatelessWidget {
  const PasswordDots({
    required this.enteredCharacters,
    required this.showError,
    required this.onPressed,
    super.key,
  });

  final int enteredCharacters;
  final bool showError;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final visibleCount = showError
        ? Password.requiredLength
        : enteredCharacters;
    return Semantics(
      textField: true,
      label:
          'Password entry, $visibleCount of ${Password.requiredLength} characters entered',
      hint: 'Activate to focus password input',
      onTap: onPressed,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(Password.requiredLength, (index) {
                final isEntered = index < visibleCount;
                return Padding(
                  padding: EdgeInsets.only(
                    right: index == Password.requiredLength - 1 ? 0 : 12,
                  ),
                  child: SizedBox.square(
                    dimension: 17,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: showError
                            ? authErrorColor
                            : isEntered
                            ? AppColors.primary
                            : AppColors.primarySurface,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

final class PasswordRecoveryChoice extends StatelessWidget {
  const PasswordRecoveryChoice({
    required this.method,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  static const _unselectedBackground = Color(0xFFFFF0F3);

  final PasswordRecoveryMethod method;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = method == PasswordRecoveryMethod.sms ? 'SMS' : 'Email';
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      selected: selected,
      label: label,
      child: ExcludeSemantics(
        child: Material(
          color: selected ? AppColors.primarySurface : _unselectedBackground,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              width: 199,
              height: 40,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: selected
                          ? AppColors.primary
                          : AppColors.formPlaceholder,
                    ),
                    const SizedBox(width: 10),
                    Text(label, style: AuthFlowTextStyles.choice),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
