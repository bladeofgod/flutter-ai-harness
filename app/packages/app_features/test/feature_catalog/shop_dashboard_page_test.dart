import 'dart:async';

import 'package:app_data/app_data.dart';
import 'package:app_features/feature_catalog/controllers/shop_dashboard_controller.dart';
import 'package:app_features/feature_catalog/pages/shop_dashboard_page.dart';
import 'package:app_features/feature_catalog/routes.dart';
import 'package:app_features/features_registry.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'catalog_test_fixtures.dart';

void main() {
  testWidgets(
    'matches the Shop first viewport structure without an App Shell',
    (tester) async {
      await _setViewport(tester, const Size(375, 812));
      await _pumpShop(tester);

      expect(find.text('Shop'), findsOneWidget);
      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Big Sale'), findsOneWidget);
      expect(find.text('Up to 50%'), findsOneWidget);
      expect(find.text('Categories'), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsNothing);
      expect(
        find.byKey(const ValueKey('profile-bottom-navigation')),
        findsNothing,
      );

      expect(
        tester.getSize(find.byKey(const ValueKey('shop-search'))).height,
        36,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('shop-big-sale-banner'))),
        const Size(335, 130),
      );
    },
  );

  testWidgets('keeps every designed section in one vertical owner', (
    tester,
  ) async {
    await _setViewport(tester, const Size(375, 812));
    await _pumpShop(tester);
    final scrollView = find.byKey(const ValueKey('shop-dashboard-scroll'));
    final verticalScrollable = find
        .descendant(of: scrollView, matching: find.byType(Scrollable))
        .first;
    const titles = <String>[
      'Categories',
      'Top Products',
      'New Items',
      'Flash Sale',
      'Most Popular',
      'Just for You',
    ];
    var previousOffset = 0.0;

    for (final title in titles) {
      await tester.scrollUntilVisible(
        find.text(title),
        500,
        scrollable: verticalScrollable,
      );
      final state = tester.state<ScrollableState>(verticalScrollable);
      expect(state.position.pixels, greaterThanOrEqualTo(previousOffset));
      previousOffset = state.position.pixels;
    }

    expect(previousOffset, greaterThan(0));
    expect(
      find.descendant(of: scrollView, matching: find.byType(CustomScrollView)),
      findsNothing,
    );
  });

  testWidgets('provides bounded horizontal product rails', (tester) async {
    await _setViewport(tester, const Size(375, 812));
    await _pumpShop(tester);
    final scrollView = find.byKey(const ValueKey('shop-dashboard-scroll'));
    final verticalScrollable = find
        .descendant(of: scrollView, matching: find.byType(Scrollable))
        .first;
    const rails = <({String title, String key})>[
      (title: 'Top Products', key: 'shop-top-products-list'),
      (title: 'New Items', key: 'shop-new-items-list'),
      (title: 'Most Popular', key: 'shop-most-popular-list'),
    ];

    for (final rail in rails) {
      await tester.scrollUntilVisible(
        find.text(rail.title),
        500,
        scrollable: verticalScrollable,
      );
      final list = find.byKey(ValueKey<String>(rail.key));
      final horizontal = find.descendant(
        of: list,
        matching: find.byType(Scrollable),
      );
      final state = tester.state<ScrollableState>(horizontal);
      expect(
        state.position.maxScrollExtent,
        greaterThan(0),
        reason: rail.title,
      );
    }
  });

  testWidgets('opens Product Detail from every Shop feed product rail', (
    tester,
  ) async {
    final openedProductIds = <String>[];
    await _setViewport(tester, const Size(375, 812));
    await _pumpShop(tester, onOpenProduct: openedProductIds.add);
    final scrollView = find.byKey(const ValueKey('shop-dashboard-scroll'));
    final verticalScrollable = find
        .descendant(of: scrollView, matching: find.byType(Scrollable))
        .first;

    const targets = <({String section, String key, String productId})>[
      (
        section: 'Top Products',
        key: 'shop-open-product-product-16',
        productId: 'product-16',
      ),
      (
        section: 'New Items',
        key: 'shop-open-product-product-1',
        productId: 'product-1',
      ),
      (
        section: 'Flash Sale',
        key: 'shop-open-product-product-10',
        productId: 'product-10',
      ),
      (
        section: 'Most Popular',
        key: 'shop-open-product-product-6',
        productId: 'product-6',
      ),
      (
        section: 'Just for You',
        key: 'shop-open-product-product-8',
        productId: 'product-8',
      ),
    ];
    for (final target in targets) {
      await tester.scrollUntilVisible(
        find.text(target.section),
        500,
        scrollable: verticalScrollable,
      );
      final card = find.byKey(ValueKey<String>(target.key));
      await tester.ensureVisible(card);
      await tester.tap(card);
      await tester.pump();
    }

    expect(openedProductIds, <String>[
      'product-16',
      'product-1',
      'product-10',
      'product-6',
      'product-8',
    ]);
  });

  testWidgets(
    'renders stable empty groups and a responsive recommendation grid',
    (tester) async {
      await _setViewport(tester, const Size(320, 568));
      await _pumpShop(
        tester,
        dashboard: catalogTestDashboard(emptySections: true),
      );

      expect(find.text('No promotions available.'), findsOneWidget);
      expect(find.text('No categories available.'), findsOneWidget);
      final scrollView = find.byKey(const ValueKey('shop-dashboard-scroll'));
      await tester.scrollUntilVisible(
        find.text('No recommendations available.'),
        500,
        scrollable: find
            .descendant(of: scrollView, matching: find.byType(Scrollable))
            .first,
      );

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('renders retryable error and recovers', (tester) async {
    final dashboard = catalogTestDashboard();
    final api = FakeCatalogApi((loadCount) async {
      if (loadCount == 1) {
        throw const CatalogFailure(CatalogFailureCode.unavailable);
      }
      return dashboard;
    });
    await _setViewport(tester, const Size(375, 812));
    await _pumpShop(tester, api: api);

    expect(find.text('Unable to load the shop'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('shop-retry')));
    await tester.pump();
    await tester.pump();

    expect(find.text('Big Sale'), findsOneWidget);
    expect(api.loadCount, 2);
  });

  testWidgets('keeps loading stable until Catalog data arrives', (
    tester,
  ) async {
    final completer = Completer<ShopDashboard>();
    final api = FakeCatalogApi((_) => completer.future);
    await _setViewport(tester, const Size(375, 812));
    await _pumpShop(tester, api: api);

    expect(find.byKey(const ValueKey('shop-loading')), findsOneWidget);
    completer.complete(catalogTestDashboard());
    await tester.pump();
    await tester.pump();

    expect(find.text('Big Sale'), findsOneWidget);
  });

  testWidgets('releases the Shop Controller when the page leaves', (
    tester,
  ) async {
    final controller = ShopDashboardController(
      catalogApi: FakeCatalogApi((_) async => catalogTestDashboard()),
    );
    await _setViewport(tester, const Size(375, 812));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ShopDashboardPage(controller: controller),
      ),
    );
    await tester.pump();
    expect(controller.isClosed, isFalse);

    await tester.pumpWidget(const SizedBox());

    expect(controller.isClosed, isTrue);
  });

  testWidgets('has no overflow on compact, landscape, or scaled viewports', (
    tester,
  ) async {
    const cases = <({Size size, double textScale})>[
      (size: Size(320, 568), textScale: 1),
      (size: Size(812, 375), textScale: 1),
      (size: Size(375, 812), textScale: 1.3),
    ];

    for (final testCase in cases) {
      await tester.pumpWidget(const SizedBox());
      await _setViewport(tester, testCase.size);
      await _pumpShop(tester, textScale: testCase.textScale);
      final scrollView = find.byKey(const ValueKey('shop-dashboard-scroll'));
      await tester.scrollUntilVisible(
        find.text('Just for You'),
        600,
        scrollable: find
            .descendant(of: scrollView, matching: find.byType(Scrollable))
            .first,
      );

      expect(tester.takeException(), isNull, reason: '${testCase.size}');
    }
  });

  testWidgets('buildShopRoutes renders real local Catalog data at /shop', (
    tester,
  ) async {
    final registry = FeaturesRegistry.local();
    final router = GoRouter(
      initialLocation: shopRoutePath,
      routes: buildShopRoutes(catalogApi: registry.catalogApi),
    );
    addTearDown(router.dispose);
    await _setViewport(tester, const Size(375, 812));

    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    );
    await tester.pump();
    await tester.pump();

    expect(router.routeInformationProvider.value.uri.path, shopRoutePath);
    expect(find.text('Big Sale'), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsNothing);
  });
}

Future<void> _pumpShop(
  WidgetTester tester, {
  ShopDashboard? dashboard,
  FakeCatalogApi? api,
  double textScale = 1,
  ValueChanged<String>? onOpenProduct,
}) async {
  final resolvedApi =
      api ?? FakeCatalogApi((_) async => dashboard ?? catalogTestDashboard());
  final controller = ShopDashboardController(catalogApi: resolvedApi);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: ShopDashboardPage(
        controller: controller,
        onOpenProduct: onOpenProduct,
      ),
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
  await tester.pump();
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}
