import 'package:app_data/app_data.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/settings_controller.dart';
import '../widgets/settings_components.dart';

final class SettingsPage extends StatelessWidget {
  const SettingsPage({
    required this.controller,
    required this.onOpenProfile,
    required this.onOpenCountry,
    required this.onOpenLanguage,
    required this.onOpenCurrency,
    required this.onOpenSizeType,
    required this.onOpenAbout,
    this.onOpenPaymentMethods,
    this.onOpenAddresses,
    super.key,
  });

  final SettingsController controller;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenCountry;
  final VoidCallback onOpenLanguage;
  final VoidCallback onOpenCurrency;
  final VoidCallback onOpenSizeType;
  final VoidCallback onOpenAbout;
  final VoidCallback? onOpenPaymentMethods;
  final VoidCallback? onOpenAddresses;

  @override
  Widget build(BuildContext context) => GetBuilder<SettingsController>(
    init: controller,
    global: false,
    autoRemove: false,
    dispose: (state) => state.controller.onDelete(),
    builder: (managedController) => Scaffold(
      body: SafeArea(
        bottom: false,
        child: Obx(() {
          final state = managedController.viewState;
          return switch (state) {
            SettingsLoading() => const Center(
              child: CircularProgressIndicator(
                key: ValueKey('settings-loading'),
              ),
            ),
            SettingsError() => _SettingsLoadError(
              onRetry: managedController.retryFromUi,
            ),
            SettingsData(:final preferences) => _SettingsContent(
              user: managedController.currentUser,
              preferences: preferences,
              isSaving: managedController.isSaving,
              onOpenProfile: onOpenProfile,
              onOpenCountry: onOpenCountry,
              onOpenLanguage: onOpenLanguage,
              onOpenCurrency: onOpenCurrency,
              onOpenSizeType: onOpenSizeType,
              onOpenAbout: onOpenAbout,
              onOpenPaymentMethods: onOpenPaymentMethods,
              onOpenAddresses: onOpenAddresses,
              onNotificationsChanged: managedController.setNotificationsFromUi,
              onDeleteAccount: () =>
                  _confirmDelete(context, managedController.deleteAccount),
            ),
          };
        }),
      ),
    ),
  );
}

Future<void> _confirmDelete(BuildContext context, VoidCallback onDelete) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const ValueKey('settings-delete-dialog'),
      title: const Text('Delete your account?'),
      content: const Text(
        'This Demo only clears the current in-memory account and session. '
        'No remote account is deleted.',
      ),
      actions: [
        TextButton(
          key: const ValueKey('settings-delete-cancel'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('settings-delete-confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFFF5B63),
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed == true && context.mounted) {
    onDelete();
  }
}

final class _SettingsContent extends StatelessWidget {
  const _SettingsContent({
    required this.user,
    required this.preferences,
    required this.isSaving,
    required this.onOpenProfile,
    required this.onOpenCountry,
    required this.onOpenLanguage,
    required this.onOpenCurrency,
    required this.onOpenSizeType,
    required this.onOpenAbout,
    required this.onNotificationsChanged,
    required this.onDeleteAccount,
    required this.onOpenPaymentMethods,
    required this.onOpenAddresses,
  });

  final UserEntity? user;
  final SettingsPreferences preferences;
  final bool isSaving;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenCountry;
  final VoidCallback onOpenLanguage;
  final VoidCallback onOpenCurrency;
  final VoidCallback onOpenSizeType;
  final VoidCallback onOpenAbout;
  final ValueChanged<bool> onNotificationsChanged;
  final VoidCallback onDeleteAccount;
  final VoidCallback? onOpenPaymentMethods;
  final VoidCallback? onOpenAddresses;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    key: const ValueKey('settings-scroll'),
    slivers: [
      _SettingsSliver(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: Text('Settings', style: settingsTitleStyle()),
      ),
      _SettingsSliver(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        child: _AccountCard(user: user, onTap: onOpenProfile),
      ),
      _SettingsSliver(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: Column(
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: SettingsSectionTitle('Account'),
            ),
            SettingsTile(
              icon: Icons.person_outline_rounded,
              title: 'Profile',
              subtitle: 'Name and contact details',
              keyValue: 'settings-profile',
              onTap: onOpenProfile,
            ),
            const SizedBox(height: 8),
            SettingsTile(
              icon: Icons.credit_card_outlined,
              title: 'Payment Methods',
              subtitle: 'Cards and demo payment history',
              keyValue: 'settings-payment-methods',
              onTap: onOpenPaymentMethods,
            ),
            const SizedBox(height: 8),
            SettingsTile(
              icon: Icons.location_on_outlined,
              title: 'Shipping Address',
              subtitle: 'Delivery details',
              keyValue: 'settings-addresses',
              onTap: onOpenAddresses,
            ),
          ],
        ),
      ),
      _SettingsSliver(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: Column(
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: SettingsSectionTitle('App Preferences'),
            ),
            SettingsTile(
              icon: Icons.public_rounded,
              title: 'Country',
              subtitle: settingsCountryLabel(preferences.country),
              keyValue: 'settings-country',
              onTap: onOpenCountry,
            ),
            const SizedBox(height: 8),
            SettingsTile(
              icon: Icons.translate_rounded,
              title: 'Language',
              subtitle: settingsLanguageLabel(preferences.language),
              keyValue: 'settings-language',
              onTap: onOpenLanguage,
            ),
            const SizedBox(height: 8),
            SettingsTile(
              icon: Icons.payments_outlined,
              title: 'Currency',
              subtitle: settingsCurrencyLabel(preferences.currency),
              keyValue: 'settings-currency',
              onTap: onOpenCurrency,
            ),
            const SizedBox(height: 8),
            SettingsTile(
              icon: Icons.straighten_rounded,
              title: 'Size Type',
              subtitle: settingsSizeTypeLabel(preferences.sizeType),
              keyValue: 'settings-size-type',
              onTap: onOpenSizeType,
            ),
            const SizedBox(height: 8),
            SettingsTile(
              icon: Icons.notifications_none_rounded,
              title: 'Notifications',
              subtitle: 'Demo in-app preference only',
              trailing: Switch.adaptive(
                key: const ValueKey('settings-notifications'),
                value: preferences.notificationsEnabled,
                onChanged: isSaving ? null : onNotificationsChanged,
              ),
            ),
          ],
        ),
      ),
      _SettingsSliver(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: Column(
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: SettingsSectionTitle('Information'),
            ),
            SettingsTile(
              icon: Icons.info_outline_rounded,
              title: 'About',
              subtitle: 'Demo source and version',
              keyValue: 'settings-about',
              onTap: onOpenAbout,
            ),
          ],
        ),
      ),
      _SettingsSliver(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        child: OutlinedButton.icon(
          key: const ValueKey('settings-delete-account'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFE2434B),
            side: const BorderSide(color: Color(0xFFFFA7AB)),
            minimumSize: const Size.fromHeight(52),
          ),
          onPressed: onDeleteAccount,
          icon: const Icon(Icons.delete_outline_rounded),
          label: const Text('Delete Account'),
        ),
      ),
    ],
  );
}

final class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.user, required this.onTap});

  final UserEntity? user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.primarySurface,
    borderRadius: BorderRadius.circular(8),
    child: InkWell(
      key: const ValueKey('settings-account-card'),
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.primary,
              child: Text(
                user?.displayName.characters.first.toUpperCase() ?? '?',
                style: settingsTitleStyle(size: 20, color: Colors.white),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user?.displayName ?? 'Shoppe shopper',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: settingsTitleStyle(size: 18),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    user?.email.value ?? 'No profile loaded',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: settingsBodyStyle(
                      size: 12,
                      color: const Color(0xFF5D6470),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.edit_outlined, color: AppColors.primary),
          ],
        ),
      ),
    ),
  );
}

final class _SettingsSliver extends StatelessWidget {
  const _SettingsSliver({required this.padding, required this.child});

  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: settingsContentMaxWidth),
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}

final class _SettingsLoadError extends StatelessWidget {
  const _SettingsLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 40),
          const SizedBox(height: 12),
          Text('Unable to load Settings', style: settingsTitleStyle(size: 20)),
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const ValueKey('settings-retry'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}
