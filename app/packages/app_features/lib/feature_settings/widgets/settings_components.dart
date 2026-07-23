import 'package:app_data/app_data.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

const settingsContentMaxWidth = 420.0;

TextStyle settingsTitleStyle({
  double size = 28,
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

TextStyle settingsBodyStyle({
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

final class SettingsPageFrame extends StatelessWidget {
  const SettingsPageFrame({
    required this.title,
    required this.child,
    this.bottom,
    super.key,
  });

  final String title;
  final Widget child;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        tooltip: 'Back',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
      ),
      title: Text(title, style: settingsTitleStyle(size: 22)),
    ),
    body: SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: settingsContentMaxWidth),
          child: child,
        ),
      ),
    ),
    bottomNavigationBar: bottom,
  );
}

final class SettingsSectionTitle extends StatelessWidget {
  const SettingsSectionTitle(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Text(label, style: settingsTitleStyle(size: 17)),
  );
}

final class SettingsTile extends StatelessWidget {
  const SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.keyValue,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final String? keyValue;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(8),
    child: InkWell(
      key: keyValue == null ? null : ValueKey<String>(keyValue!),
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 58),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 36,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: AppColors.primarySurface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 19, color: AppColors.primary),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: settingsTitleStyle(size: 15),
                    ),
                    if (subtitle case final value?) ...[
                      const SizedBox(height: 2),
                      Text(
                        value,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: settingsBodyStyle(
                          size: 12,
                          color: const Color(0xFF737373),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing ??
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: onTap == null
                        ? const Color(0xFFC2C2C2)
                        : AppColors.primary,
                  ),
            ],
          ),
        ),
      ),
    ),
  );
}

String settingsCountryLabel(SettingsCountry value) => switch (value) {
  SettingsCountry.unitedStates => 'United States',
  SettingsCountry.unitedKingdom => 'United Kingdom',
  SettingsCountry.china => 'China',
  SettingsCountry.japan => 'Japan',
  SettingsCountry.vietnam => 'Vietnam',
  SettingsCountry.germany => 'Germany',
};

String settingsCountrySymbol(SettingsCountry value) => switch (value) {
  SettingsCountry.unitedStates => 'US',
  SettingsCountry.unitedKingdom => 'GB',
  SettingsCountry.china => 'CN',
  SettingsCountry.japan => 'JP',
  SettingsCountry.vietnam => 'VN',
  SettingsCountry.germany => 'DE',
};

String settingsLanguageLabel(SettingsLanguage value) => switch (value) {
  SettingsLanguage.english => 'English',
  SettingsLanguage.simplifiedChinese => 'Chinese (Simplified)',
  SettingsLanguage.japanese => 'Japanese',
  SettingsLanguage.vietnamese => 'Vietnamese',
  SettingsLanguage.german => 'German',
};

String settingsCurrencyLabel(SettingsCurrency value) => switch (value) {
  SettingsCurrency.usd => 'USD - US Dollar',
  SettingsCurrency.eur => 'EUR - Euro',
  SettingsCurrency.gbp => 'GBP - Pound Sterling',
  SettingsCurrency.jpy => 'JPY - Japanese Yen',
  SettingsCurrency.cny => 'CNY - Chinese Yuan',
  SettingsCurrency.vnd => 'VND - Vietnamese Dong',
};

String settingsSizeTypeLabel(SettingsSizeType value) => switch (value) {
  SettingsSizeType.international => 'International',
  SettingsSizeType.unitedStates => 'United States',
  SettingsSizeType.europe => 'Europe',
  SettingsSizeType.unitedKingdom => 'United Kingdom',
};
