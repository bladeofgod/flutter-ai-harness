import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import 'settings_components.dart';

final class SettingsPaymentSectionCard extends StatelessWidget {
  const SettingsPaymentSectionCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    elevation: 1,
    borderRadius: BorderRadius.circular(8),
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
}

final class SettingsPaymentPrimaryButton extends StatelessWidget {
  const SettingsPaymentPrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: onPressed,
    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
    icon: Icon(icon ?? Icons.check_rounded),
    label: Text(label),
  );
}

final class SettingsPaymentEmptyState extends StatelessWidget {
  const SettingsPaymentEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: AppColors.primary),
          const SizedBox(height: 14),
          Text(title, style: settingsTitleStyle(size: 19)),
          const SizedBox(height: 7),
          Text(
            message,
            textAlign: TextAlign.center,
            style: settingsBodyStyle(color: const Color(0xFF707070)),
          ),
        ],
      ),
    ),
  );
}

String settingsPaymentMoneyLabel(int minorUnits, String currencyCode) {
  final amount = (minorUnits / 100).toStringAsFixed(2);
  return currencyCode == 'USD' ? '\$$amount' : '$currencyCode $amount';
}
