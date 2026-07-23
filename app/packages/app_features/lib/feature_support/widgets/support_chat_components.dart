import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

TextStyle supportHeading({
  double size = 24,
  FontWeight weight = FontWeight.w700,
  Color color = AppColors.textPrimary,
  double? height,
}) => TextStyle(
  fontFamily: AppFonts.raleway,
  package: AppFonts.package,
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
  letterSpacing: 0,
);

TextStyle supportBody({
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

final class SupportPrimaryButton extends StatelessWidget {
  const SupportPrimaryButton({
    required this.label,
    required this.onPressed,
    required this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 48,
    child: FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 19),
      label: Text(label, overflow: TextOverflow.ellipsis),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: supportHeading(size: 15, color: AppColors.textOnPrimary),
      ),
    ),
  );
}
