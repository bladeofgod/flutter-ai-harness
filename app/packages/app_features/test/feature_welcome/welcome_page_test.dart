import 'dart:ui' as ui;

import 'package:app_features/app_features.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadShoppeFonts);

  testWidgets('matches the reference layout at 375 x 812', (tester) async {
    await _setViewport(tester, const Size(375, 812));
    await _pumpWelcome(tester);

    expect(find.text('Shoppe'), findsOneWidget);
    expect(
      find.text('Beautiful eCommerce UI Kit for your online store'),
      findsOneWidget,
    );
    expect(find.text("Let's get started"), findsOneWidget);
    expect(find.text('I already have an account'), findsOneWidget);

    final brandTitle = tester.widget<Text>(find.text('Shoppe'));
    expect(
      brandTitle.style?.fontFamily,
      'packages/${AppFonts.package}/${AppFonts.raleway}',
    );
    expect(brandTitle.style?.fontSize, 52);
    expect(brandTitle.style?.fontWeight, FontWeight.w700);
    expect(brandTitle.style?.height, 61 / 52);
    expect(brandTitle.style?.letterSpacing, 0);
    expect(brandTitle.style?.color, AppColors.textPrimary);

    final description = tester.widget<Text>(
      find.text('Beautiful eCommerce UI Kit for your online store'),
    );
    expect(
      description.style?.fontFamily,
      'packages/${AppFonts.package}/${AppFonts.nunitoSans}',
    );
    expect(description.style?.fontSize, 19);
    expect(description.style?.fontWeight, FontWeight.w300);
    expect(description.style?.height, 33 / 19);
    expect(description.style?.letterSpacing, 0);
    expect(description.style?.color, AppColors.textPrimary);

    final primaryAction = tester.widget<Text>(find.text("Let's get started"));
    expect(primaryAction.style?.fontSize, 22);
    expect(primaryAction.style?.fontWeight, FontWeight.w300);
    expect(primaryAction.style?.height, 31 / 22);
    expect(primaryAction.style?.color, AppColors.textOnPrimary);

    final secondaryAction = tester.widget<Text>(
      find.text('I already have an account'),
    );
    expect(secondaryAction.style?.fontSize, 15);
    expect(secondaryAction.style?.fontWeight, FontWeight.w300);
    expect(secondaryAction.style?.height, 26 / 15);
    expect(secondaryAction.style?.color, const Color(0xE6202020));

    final brandRect = tester.getRect(find.byType(Image));
    expect(brandRect.size, const Size(150, 150));
    expect(brandRect.top, closeTo(227, 0.01));

    final primaryRect = tester.getRect(find.byType(ElevatedButton));
    expect(primaryRect.size, const Size(335, 61));
    expect(primaryRect.top, closeTo(634, 0.01));
  });

  testWidgets('forwards both optional actions', (tester) async {
    var getStartedCount = 0;
    var signInCount = 0;
    await _setViewport(tester, const Size(375, 812));
    await _pumpWelcome(
      tester,
      onGetStarted: () => getStartedCount += 1,
      onSignIn: () => signInCount += 1,
    );

    await tester.tap(find.text("Let's get started"));
    await tester.tap(find.text('I already have an account'));

    expect(getStartedCount, 1);
    expect(signInCount, 1);
  });

  testWidgets('exposes the account action to accessibility services', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _setViewport(tester, const Size(375, 812));
    await _pumpWelcome(tester);

    expect(find.bySemanticsLabel('I already have an account'), findsOneWidget);
    expect(find.bySemanticsLabel('Shoppe'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('remains usable on compact, landscape, and scaled viewports', (
    tester,
  ) async {
    const cases = <({Size size, double textScale})>[
      (size: Size(320, 568), textScale: 1),
      (size: Size(812, 375), textScale: 1),
      (size: Size(375, 812), textScale: 1.3),
    ];

    for (final testCase in cases) {
      await _setViewport(tester, testCase.size);
      await _pumpWelcome(tester, textScale: testCase.textScale);
      await tester.ensureVisible(find.text('I already have an account'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text("Let's get started"), findsOneWidget);
      expect(find.text('I already have an account'), findsOneWidget);
    }
  });

  test('bundles all Shoppe brand image densities', () async {
    const variants = <String, int>{
      'packages/app_features/assets/images/welcome/shoppe_brand.png': 150,
      'packages/app_features/assets/images/welcome/2.0x/shoppe_brand.png': 300,
      'packages/app_features/assets/images/welcome/3.0x/shoppe_brand.png': 450,
    };

    for (final entry in variants.entries) {
      final path = entry.key;
      final asset = await rootBundle.load(path);
      expect(asset.lengthInBytes, greaterThan(0), reason: path);
      final bytes = asset.buffer.asUint8List(
        asset.offsetInBytes,
        asset.lengthInBytes,
      );
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, entry.value, reason: path);
      expect(frame.image.height, entry.value, reason: path);
      frame.image.dispose();
      codec.dispose();
    }
  });
}

Future<void> _loadShoppeFonts() async {
  final raleway = FontLoader('packages/app_ui/${AppFonts.raleway}')
    ..addFont(
      rootBundle.load(
        'packages/app_ui/assets/fonts/raleway/Raleway-Variable.ttf',
      ),
    );
  final nunitoSans = FontLoader('packages/app_ui/${AppFonts.nunitoSans}')
    ..addFont(
      rootBundle.load(
        'packages/app_ui/assets/fonts/nunito_sans/NunitoSans-Variable.ttf',
      ),
    );

  await Future.wait([raleway.load(), nunitoSans.load()]);
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

Future<void> _pumpWelcome(
  WidgetTester tester, {
  VoidCallback? onGetStarted,
  VoidCallback? onSignIn,
  double textScale = 1,
}) async {
  final router = GoRouter(
    routes: buildWelcomeRoutes(
      onGetStarted: onGetStarted ?? () {},
      onSignIn: onSignIn ?? () {},
    ),
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: const EdgeInsets.only(top: 44, bottom: 34),
          viewPadding: const EdgeInsets.only(top: 44, bottom: 34),
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
    ),
  );
  await tester.pump();
}
