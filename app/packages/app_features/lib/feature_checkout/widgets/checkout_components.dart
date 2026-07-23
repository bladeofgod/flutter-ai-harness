import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

const double checkoutContentMaxWidth = 440;

TextStyle checkoutHeading({
  double size = 24,
  FontWeight weight = FontWeight.w700,
  Color color = AppColors.textPrimary,
}) => TextStyle(
  fontFamily: AppFonts.raleway,
  package: AppFonts.package,
  fontSize: size,
  fontWeight: weight,
  color: color,
  letterSpacing: 0,
);

TextStyle checkoutBody({
  double size = 14,
  FontWeight weight = FontWeight.w400,
  Color color = AppColors.textPrimary,
  double? height,
}) => TextStyle(
  fontFamily: AppFonts.nunitoSans,
  package: AppFonts.package,
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
  letterSpacing: 0,
);

final class CheckoutPageScaffold extends StatelessWidget {
  const CheckoutPageScaffold({
    required this.title,
    required this.child,
    this.bottomAction,
    this.showBack = true,
    super.key,
  });

  final String title;
  final Widget child;
  final Widget? bottomAction;
  final bool showBack;

  @override
  Widget build(BuildContext context) => Scaffold(
    resizeToAvoidBottomInset: true,
    backgroundColor: AppColors.background,
    appBar: AppBar(
      automaticallyImplyLeading: showBack,
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      title: Text(title, style: checkoutHeading()),
    ),
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(child: child),
          if (bottomAction case final action?)
            _CheckoutBottomAction(child: action),
        ],
      ),
    ),
  );
}

final class CheckoutPrimaryButton extends StatelessWidget {
  const CheckoutPrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 52,
    child: FilledButton.icon(
      onPressed: onPressed,
      icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 18),
      label: Text(
        label,
        style: checkoutHeading(size: 16, color: AppColors.textOnPrimary),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        disabledBackgroundColor: AppColors.formPlaceholder,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}

final class CheckoutSectionCard extends StatelessWidget {
  const CheckoutSectionCard({required this.child, this.onTap, super.key});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceMuted,
    borderRadius: BorderRadius.circular(8),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );
}

final class CheckoutContent extends StatelessWidget {
  const CheckoutContent({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: checkoutContentMaxWidth),
      child: child,
    ),
  );
}

final class _CheckoutBottomAction extends StatelessWidget {
  const _CheckoutBottomAction({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: AppColors.background,
      border: Border(top: BorderSide(color: Color(0xFFE8E8E8))),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: checkoutContentMaxWidth,
            ),
            child: child,
          ),
        ),
      ),
    ),
  );
}
