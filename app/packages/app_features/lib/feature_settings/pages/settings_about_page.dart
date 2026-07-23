import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import '../widgets/settings_components.dart';

final class SettingsAboutPage extends StatelessWidget {
  const SettingsAboutPage({super.key});

  @override
  Widget build(BuildContext context) => SettingsPageFrame(
    title: 'About',
    child: ListView(
      key: const ValueKey('settings-about-scroll'),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      children: [
        const Center(
          child: CircleAvatar(
            radius: 42,
            backgroundColor: AppColors.primarySurface,
            child: Icon(
              Icons.shopping_bag_outlined,
              size: 40,
              color: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'AI-Harness Shoppe Demo',
          textAlign: TextAlign.center,
          style: settingsTitleStyle(size: 24),
        ),
        const SizedBox(height: 6),
        Text(
          'Demo version 1.0.0',
          textAlign: TextAlign.center,
          style: settingsBodyStyle(color: const Color(0xFF737373)),
        ),
        const SizedBox(height: 28),
        _AboutBlock(
          title: 'Design source',
          body:
              'Based on the Shoppe eCommerce mobile app design by Joy Patel. '
              'The design is used under CC BY 4.0.',
        ),
        const SizedBox(height: 12),
        const _AboutBlock(
          title: 'Demo scope',
          body:
              'This application demonstrates the Flutter AI Harness workflow. '
              'Settings are local to the current process and are not synced to '
              'a remote account or system preferences.',
        ),
      ],
    ),
  );
}

final class _AboutBlock extends StatelessWidget {
  const _AboutBlock({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: settingsTitleStyle(size: 16)),
        const SizedBox(height: 6),
        Text(body, style: settingsBodyStyle(height: 1.45)),
      ],
    ),
  );
}
