import 'package:app_data/app_data.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/settings_controller.dart';
import '../widgets/settings_components.dart';

enum SettingsPreferenceKind { country, language, currency, sizeType }

final class SettingsPreferencePage extends StatelessWidget {
  const SettingsPreferencePage({
    required this.controller,
    required this.kind,
    super.key,
  });

  final SettingsController controller;
  final SettingsPreferenceKind kind;

  @override
  Widget build(BuildContext context) => GetBuilder<SettingsController>(
    init: controller,
    global: false,
    autoRemove: false,
    dispose: (state) => state.controller.onDelete(),
    builder: (managedController) => Obx(() {
      final state = managedController.viewState;
      return switch (state) {
        SettingsLoading() => SettingsPageFrame(
          title: _title,
          child: const Center(child: CircularProgressIndicator()),
        ),
        SettingsError() => SettingsPageFrame(
          title: _title,
          child: Center(
            child: FilledButton.icon(
              key: const ValueKey('settings-preference-retry'),
              onPressed: managedController.retryFromUi,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ),
        ),
        SettingsData(:final preferences) => SettingsPageFrame(
          title: _title,
          child: _PreferenceList(
            kind: kind,
            preferences: preferences,
            saving: managedController.isSaving,
            hasError: managedController.operationFailure != null,
            controller: managedController,
          ),
        ),
      };
    }),
  );

  String get _title => switch (kind) {
    SettingsPreferenceKind.country => 'Choose Your Country',
    SettingsPreferenceKind.language => 'Choose Your Language',
    SettingsPreferenceKind.currency => 'Choose Your Currency',
    SettingsPreferenceKind.sizeType => 'Size Types',
  };
}

final class _PreferenceList extends StatelessWidget {
  const _PreferenceList({
    required this.kind,
    required this.preferences,
    required this.saving,
    required this.hasError,
    required this.controller,
  });

  final SettingsPreferenceKind kind;
  final SettingsPreferences preferences;
  final bool saving;
  final bool hasError;
  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    final options = switch (kind) {
      SettingsPreferenceKind.country =>
        <({String id, String label, String? mark})>[
          for (final value in SettingsCountry.values)
            (
              id: value.id,
              label: settingsCountryLabel(value),
              mark: settingsCountrySymbol(value),
            ),
        ],
      SettingsPreferenceKind.language =>
        <({String id, String label, String? mark})>[
          for (final value in SettingsLanguage.values)
            (id: value.id, label: settingsLanguageLabel(value), mark: null),
        ],
      SettingsPreferenceKind.currency =>
        <({String id, String label, String? mark})>[
          for (final value in SettingsCurrency.values)
            (id: value.id, label: settingsCurrencyLabel(value), mark: null),
        ],
      SettingsPreferenceKind.sizeType =>
        <({String id, String label, String? mark})>[
          for (final value in SettingsSizeType.values)
            (id: value.id, label: settingsSizeTypeLabel(value), mark: null),
        ],
    };
    final selectedId = switch (kind) {
      SettingsPreferenceKind.country => preferences.country.id,
      SettingsPreferenceKind.language => preferences.language.id,
      SettingsPreferenceKind.currency => preferences.currency.id,
      SettingsPreferenceKind.sizeType => preferences.sizeType.id,
    };

    return ListView(
      key: const ValueKey('settings-preference-list'),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
      children: [
        if (hasError)
          Container(
            key: const ValueKey('settings-preference-error'),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEEEE),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Unable to save this preference. Please try again.',
              style: settingsBodyStyle(color: const Color(0xFFB42A31)),
            ),
          ),
        for (final option in options) ...[
          _PreferenceOption(
            key: ValueKey<String>('settings-preference-${option.id}'),
            label: option.label,
            mark: option.mark,
            selected: selectedId == option.id,
            onTap: saving ? null : () => _select(option.id),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Future<void> _select(String id) async {
    switch (kind) {
      case SettingsPreferenceKind.country:
        await controller.setCountry(SettingsCountry.fromId(id));
      case SettingsPreferenceKind.language:
        await controller.setLanguage(SettingsLanguage.fromId(id));
      case SettingsPreferenceKind.currency:
        await controller.setCurrency(SettingsCurrency.fromId(id));
      case SettingsPreferenceKind.sizeType:
        await controller.setSizeType(SettingsSizeType.fromId(id));
    }
  }
}

final class _PreferenceOption extends StatelessWidget {
  const _PreferenceOption({
    required this.label,
    required this.mark,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final String? mark;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: Material(
      color: selected ? AppColors.primarySurface : AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 58),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                if (mark case final value?) ...[
                  Container(
                    width: 34,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(value, style: settingsTitleStyle(size: 11)),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(label, style: settingsTitleStyle(size: 15)),
                ),
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  color: selected ? AppColors.primary : const Color(0xFFBBBBBB),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
