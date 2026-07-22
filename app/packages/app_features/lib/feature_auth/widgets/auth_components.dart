import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

const authContentMaxWidth = 375.0;
const authHorizontalPadding = 20.0;
const authErrorColor = Color(0xFFEC4E4E);

abstract final class AuthTextStyles {
  static const form = TextStyle(
    color: AppColors.textStrong,
    fontFamily: AppFonts.poppins,
    package: AppFonts.package,
    fontSize: 13.83,
    fontWeight: FontWeight.w500,
    height: 1.4,
    letterSpacing: 0,
  );

  static const placeholder = TextStyle(
    color: AppColors.formPlaceholder,
    fontFamily: AppFonts.poppins,
    package: AppFonts.package,
    fontSize: 13.83,
    fontWeight: FontWeight.w500,
    height: 1.4,
    letterSpacing: 0,
  );

  static const fieldError = TextStyle(
    color: authErrorColor,
    fontFamily: AppFonts.nunitoSans,
    package: AppFonts.package,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.25,
    letterSpacing: 0,
  );

  static const primaryAction = TextStyle(
    color: AppColors.textOnPrimary,
    fontFamily: AppFonts.nunitoSans,
    package: AppFonts.package,
    fontSize: 22,
    fontWeight: FontWeight.w300,
    height: 31 / 22,
    letterSpacing: 0,
  );

  static const cancelAction = TextStyle(
    color: Color(0xE6202020),
    fontFamily: AppFonts.nunitoSans,
    package: AppFonts.package,
    fontSize: 15,
    fontWeight: FontWeight.w300,
    height: 26 / 15,
    letterSpacing: 0,
  );
}

final class AuthBubbleBackground extends StatelessWidget {
  const AuthBubbleBackground({super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SvgPicture.asset(
      'assets/images/auth/registration_bubbles.svg',
      package: 'app_features',
      width: 659.329,
      height: 513.444,
      fit: BoxFit.fill,
    ),
  );
}

final class AuthCapsuleTextField extends StatelessWidget {
  const AuthCapsuleTextField({
    required this.controller,
    required this.hintText,
    required this.semanticsLabel,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.obscureText = false,
    this.enabled = true,
    this.prefix,
    this.suffix,
    this.inputFormatters,
    this.onSubmitted,
    this.errorText,
    this.height = 52.375,
    super.key,
  });

  final TextEditingController controller;
  final String hintText;
  final String semanticsLabel;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final bool obscureText;
  final bool enabled;
  final Widget? prefix;
  final Widget? suffix;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onSubmitted;
  final String? errorText;
  final double height;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        height: height,
        child: Semantics(
          textField: true,
          label: semanticsLabel,
          child: TextField(
            controller: controller,
            enabled: enabled,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            autofillHints: autofillHints,
            obscureText: obscureText,
            autocorrect: false,
            enableSuggestions: !obscureText,
            style: AuthTextStyles.form,
            inputFormatters: inputFormatters,
            onSubmitted: onSubmitted,
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.formBackground,
              hintText: hintText,
              hintStyle: AuthTextStyles.placeholder,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 19.764,
                vertical: 15.811,
              ),
              prefixIcon: prefix,
              prefixIconConstraints: prefix == null
                  ? null
                  : const BoxConstraints(minWidth: 0, minHeight: 0),
              suffixIcon: suffix,
              suffixIconConstraints: suffix == null
                  ? null
                  : const BoxConstraints(minWidth: 48, minHeight: 48),
              border: _border,
              enabledBorder: _border,
              focusedBorder: _border,
              disabledBorder: _border,
            ),
          ),
        ),
      ),
      if (errorText case final error?) ...[
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(error, style: AuthTextStyles.fieldError),
        ),
      ],
    ],
  );

  static const _border = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(60)),
    borderSide: BorderSide.none,
  );
}

final class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 61,
    child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        elevation: 0,
        shadowColor: Colors.transparent,
        backgroundColor: AppColors.primary,
        disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.55),
        foregroundColor: AppColors.textOnPrimary,
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: isLoading
          ? const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.textOnPrimary,
              ),
            )
          : FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label, style: AuthTextStyles.primaryAction),
            ),
    ),
  );
}

final class AuthCancelButton extends StatelessWidget {
  const AuthCancelButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 24),
      ),
      child: const Text('Cancel', style: AuthTextStyles.cancelAction),
    ),
  );
}
