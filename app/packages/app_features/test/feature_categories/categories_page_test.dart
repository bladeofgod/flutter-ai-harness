import 'package:app_data/app_data.dart';
import 'package:app_features/feature_categories/controllers/categories_controller.dart';
import 'package:app_features/feature_categories/pages/categories_filter_page.dart';
import 'package:app_features/feature_categories/pages/categories_page.dart';
import 'package:app_features/feature_categories/routes.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'categories_test_fixtures.dart';

void main() {
  testWidgets('renders node 25 first viewport with one vertical owner', (
    tester,
  ) async {
    await _setViewport(tester, const Size(375, 812));
    await _pumpCategories(tester);

    expect(find.text('Shop'), findsOneWidget);
    expect(find.text('Clothing'), findsOneWidget);
    expect(find.text('Dresses'), findsOneWidget);
    expect(find.text('All Items'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('categories-product-grid')),
      findsOneWidget,
    );
    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('categories-scroll')),
        matching: find.byType(CustomScrollView),
      ),
      findsNothing,
    );
  });

  testWidgets('moves filter action into pinned header after scrolling', (
    tester,
  ) async {
    await _setViewport(tester, const Size(375, 812));
    await _pumpCategories(tester);

    expect(
      find.byKey(const ValueKey('categories-list-filter')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('categories-header-filter')),
      findsNothing,
    );

    await tester.drag(
      find.byKey(const ValueKey('categories-scroll')),
      const Offset(0, -350),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Shop'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('categories-header-filter')),
      findsOneWidget,
    );
  });

  testWidgets('exposes only stable product ID through the tap callback', (
    tester,
  ) async {
    String? selectedProductId;
    await _setViewport(tester, const Size(375, 812));
    await _pumpCategories(
      tester,
      onProductSelected: (productId) => selectedProductId = productId,
    );

    await tester.tap(
      find.byKey(const ValueKey('categories-product-product-1')),
    );

    expect(selectedProductId, 'product-1');
  });

  testWidgets('does not expose a camera action in the Shop header', (
    tester,
  ) async {
    await _setViewport(tester, const Size(375, 812));
    await _pumpCategories(tester);

    expect(
      find.byKey(const ValueKey('categories-camera-search')),
      findsNothing,
    );
    expect(find.byTooltip('Search with camera'), findsNothing);
  });

  testWidgets('shows empty and retryable error states', (tester) async {
    await _setViewport(tester, const Size(375, 812));
    await _pumpCategories(tester, empty: true);
    expect(find.byKey(const ValueKey('categories-empty')), findsOneWidget);

    final api = FakeCatalogBrowseApi((query, count) async {
      if (count == 1) {
        throw const CatalogFailure(CatalogFailureCode.unavailable);
      }
      return categoriesTestResult(query);
    });
    await tester.pumpWidget(const SizedBox());
    await _pumpCategories(tester, api: api);
    expect(find.text('Unable to load categories'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('categories-retry')));
    await tester.pump();
    await tester.pump();
    expect(find.text('All Items'), findsOneWidget);
  });

  testWidgets(
    'filter child Route cancels without pollution and applies draft',
    (tester) async {
      final api = FakeCatalogBrowseApi(
        (query, _) async => categoriesTestResult(query),
      );
      final router = GoRouter(
        initialLocation: categoriesRoutePath,
        routes: buildCategoriesRoutes(catalogApi: api),
      );
      addTearDown(router.dispose);
      await _setViewport(tester, const Size(375, 812));
      await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('categories-list-filter')));
      await tester.pumpAndSettle();
      expect(find.text('All Categories'), findsOneWidget);
      expect(router.canPop(), isTrue);
      expect(find.byKey(const ValueKey('audience-female')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('audience-male')));
      await tester.tap(find.byKey(const ValueKey('categories-filter-close')));
      await tester.pumpAndSettle();
      expect(api.loadCount, 1);
      expect(api.queries.last.filter.audience, CatalogAudience.female);

      await tester.tap(find.byKey(const ValueKey('categories-list-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('audience-male')));
      router.pop();
      await tester.pumpAndSettle();
      expect(api.loadCount, 1);

      await tester.tap(find.byKey(const ValueKey('categories-list-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('audience-male')));
      await tester.tap(
        find.byKey(const ValueKey('filter-category-category-shoes')),
      );
      await tester.tap(find.byKey(const ValueKey('categories-filter-apply')));
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        categoriesRoutePath,
      );
      expect(api.queries.last.filter.audience, CatalogAudience.male);
      expect(api.queries.last.filter.categoryId, 'category-shoes');
    },
  );

  testWidgets('Reset restores the initial filter input', (tester) async {
    final initial = CatalogFilter(
      audience: CatalogAudience.female,
      categoryId: 'category-clothing',
      subcategoryId: 'subcategory-1',
    );
    final filterController = CategoriesFilterController(
      initialFilter: initial,
      categories: categoriesTestOptions(),
    );
    CatalogFilter? applied;
    await _setViewport(tester, const Size(375, 812));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: CategoriesFilterPage(
          controller: filterController,
          onCancel: () {},
          onApply: (filter) => applied = filter,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('audience-male')));
    await tester.tap(find.byKey(const ValueKey('categories-filter-reset')));
    await tester.tap(find.byKey(const ValueKey('categories-filter-apply')));

    expect(applied, CatalogQuery.initial().filter);
  });

  testWidgets('direct filter link without draft returns to categories', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: categoriesFilterRoutePath,
      routes: buildCategoriesRoutes(
        catalogApi: FakeCatalogBrowseApi(
          (query, _) async => categoriesTestResult(query),
        ),
      ),
    );
    addTearDown(router.dispose);
    await _setViewport(tester, const Size(375, 812));
    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('categories-scroll')), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, categoriesRoutePath);
    expect(
      find.byKey(const ValueKey('categories-filter-scroll')),
      findsNothing,
    );
  });

  testWidgets('has no overflow on compact, landscape and scaled viewports', (
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
      await _pumpCategories(tester, textScale: testCase.textScale);
      await tester.drag(
        find.byKey(const ValueKey('categories-scroll')),
        const Offset(0, -500),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '${testCase.size}');
    }
  });
}

Future<void> _pumpCategories(
  WidgetTester tester, {
  FakeCatalogBrowseApi? api,
  bool empty = false,
  double textScale = 1,
  ValueChanged<String>? onProductSelected,
}) async {
  final resolvedApi =
      api ??
      FakeCatalogBrowseApi(
        (query, _) async => categoriesTestResult(query, empty: empty),
      );
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: CategoriesPage(
        controller: CategoriesController(catalogApi: resolvedApi),
        openFilter: (_, _) async => null,
        onProductSelected: onProductSelected ?? (_) {},
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
