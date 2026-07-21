import 'package:app_ui/app_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('light theme exposes the Shoppe design tokens', () {
    final theme = AppTheme.light;

    expect(theme.scaffoldBackgroundColor, AppColors.background);
    expect(theme.colorScheme.primary, AppColors.primary);
    expect(theme.colorScheme.onPrimary, AppColors.textOnPrimary);
    expect(theme.colorScheme.onSurface, AppColors.textPrimary);
    expect(AppFonts.raleway, 'Raleway');
    expect(AppFonts.nunitoSans, 'Nunito Sans');
  });

  test('bundles the local Shoppe fonts', () async {
    final raleway = await rootBundle.load(
      'packages/app_ui/assets/fonts/raleway/Raleway-Variable.ttf',
    );
    final nunitoSans = await rootBundle.load(
      'packages/app_ui/assets/fonts/nunito_sans/NunitoSans-Variable.ttf',
    );

    expect(raleway.lengthInBytes, greaterThan(0));
    expect(nunitoSans.lengthInBytes, greaterThan(0));
  });
}
