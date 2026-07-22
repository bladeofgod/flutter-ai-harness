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
    expect(AppColors.surfaceMuted, const Color(0xFFF8F8F8));
    expect(AppColors.formBackground, const Color(0xFFF8F8F8));
    expect(AppColors.formPlaceholder, const Color(0xFFD2D2D2));
    expect(AppColors.primarySurface, const Color(0xFFE5EBFC));
    expect(AppColors.textStrong, const Color(0xFF1F1F1F));
    expect(AppColors.success, const Color(0xFF08C514));
    expect(AppFonts.raleway, 'Raleway');
    expect(AppFonts.nunitoSans, 'Nunito Sans');
    expect(AppFonts.poppins, 'Poppins');
  });

  test('bundles the local Shoppe fonts', () async {
    final raleway = await rootBundle.load(
      'packages/app_ui/assets/fonts/raleway/Raleway-Variable.ttf',
    );
    final nunitoSans = await rootBundle.load(
      'packages/app_ui/assets/fonts/nunito_sans/NunitoSans-Variable.ttf',
    );
    final poppins = await rootBundle.load(
      'packages/app_ui/assets/fonts/Poppins-Medium.ttf',
    );
    final poppinsLicense = await rootBundle.load(
      'packages/app_ui/assets/fonts/OFL-Poppins.txt',
    );

    expect(raleway.lengthInBytes, greaterThan(0));
    expect(nunitoSans.lengthInBytes, greaterThan(0));
    expect(poppins.lengthInBytes, greaterThan(0));
    expect(poppinsLicense.lengthInBytes, greaterThan(0));
  });
}
