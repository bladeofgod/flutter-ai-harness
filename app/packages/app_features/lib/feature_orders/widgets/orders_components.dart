import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

TextStyle ordersHeading({
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

TextStyle ordersBody({
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

final class OrdersPageScaffold extends StatelessWidget {
  const OrdersPageScaffold({
    required this.title,
    required this.child,
    this.showBack = true,
    super.key,
  });

  final String title;
  final Widget child;
  final bool showBack;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      automaticallyImplyLeading: showBack,
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      title: Text(title, style: ordersHeading(size: 21)),
    ),
    body: SafeArea(top: false, child: child),
  );
}

final class OrdersPrimaryButton extends StatelessWidget {
  const OrdersPrimaryButton({
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
    height: 48,
    child: FilledButton.icon(
      onPressed: onPressed,
      icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 19),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: ordersHeading(size: 15, color: AppColors.textOnPrimary),
      ),
    ),
  );
}
