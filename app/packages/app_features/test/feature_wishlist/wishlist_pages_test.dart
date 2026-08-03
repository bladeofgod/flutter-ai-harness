import 'package:app_data/app_data.dart';
import 'package:app_features/api/wishlist_api.dart';
import 'package:app_features/feature_wishlist/controllers/wishlist_controller.dart';
import 'package:app_features/feature_wishlist/pages/wishlist_page.dart';
import 'package:app_features/feature_wishlist/routes.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'wishlist_test_fixtures.dart';

void main() {
  testWidgets('renders data state and emits stable Product/Cart ids', (
    tester,
  ) async {
    String? openedProductId;
    String? cartProductId;
    await _setViewport(tester, const Size(375, 812));
    await _pumpWishlist(
      tester,
      overview: wishlistTestOverview(),
      actions: WishlistProductActions(
        onOpenProduct: (id) => openedProductId = id,
        onAddToCart: (id) => cartProductId = id,
      ),
    );

    expect(find.text('Wishlist'), findsOneWidget);
    expect(find.text('Recently viewed'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('wishlist-recently-viewed-rail')),
      findsOneWidget,
    );
    expect(find.byType(BottomNavigationBar), findsNothing);

    final addButton = find.byKey(const ValueKey('wishlist-add-product-1'));
    await tester.ensureVisible(addButton);
    await tester.tap(addButton);
    await tester.pump();
    final productButton = find.byKey(const ValueKey('wishlist-open-product-1'));
    await tester.ensureVisible(productButton);
    await tester.tap(productButton);
    await tester.pump();

    expect(cartProductId, 'product-1');
    expect(openedProductId, 'product-1');
  });

  testWidgets('removing the last item switches to empty recommendations', (
    tester,
  ) async {
    await _setViewport(tester, const Size(375, 812));
    await _pumpWishlist(tester, overview: wishlistTestOverview(itemCount: 1));

    await tester.tap(find.byKey(const ValueKey('wishlist-remove-product-1')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('wishlist-empty')), findsOneWidget);
    expect(find.text('Most Popular'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('wishlist-recommendations')),
      findsOneWidget,
    );
  });

  testWidgets('empty state exposes semantics and remains scrollable', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _setViewport(tester, const Size(320, 568));
    await _pumpWishlist(tester, overview: wishlistTestOverview(itemCount: 0));

    expect(find.bySemanticsLabel('Wishlist is empty'), findsOneWidget);
    expect(find.byKey(const ValueKey('wishlist-scroll')), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('empty recommendations expose explicit public actions', (
    tester,
  ) async {
    String? openedProductId;
    var seeAllCount = 0;
    await _setViewport(tester, const Size(375, 812));
    await _pumpWishlist(
      tester,
      overview: wishlistTestOverview(itemCount: 0),
      actions: WishlistProductActions(
        onOpenProduct: (productId) => openedProductId = productId,
        onSeeAllRecommendations: () => seeAllCount += 1,
      ),
    );

    final seeAll = find.byKey(
      const ValueKey('wishlist-see-all-recommendations'),
    );
    await tester.ensureVisible(seeAll);
    await tester.tap(seeAll);
    final recommendation = find.byKey(
      const ValueKey('wishlist-recommendation-recommended-1'),
    );
    await tester.ensureVisible(recommendation);
    await tester.tap(recommendation);

    expect(seeAllCount, 1);
    expect(openedProductId, 'recommended-1');
  });

  testWidgets('route opens date picker, commits and cancels selection', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final api = successfulWishlistApi();
    final router = GoRouter(
      initialLocation: wishlistRoutePath,
      routes: buildWishlistRoutes(wishlistApi: api),
    );
    addTearDown(router.dispose);
    await _setViewport(tester, const Size(375, 812));
    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('open-recently-viewed')));
    await tester.pumpAndSettle();
    expect(router.canPop(), isTrue);
    expect(
      find.byKey(const ValueKey('recent-product-today-0')),
      findsOneWidget,
    );
    final todaySemantics = find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == 'Today',
      description: 'Semantics labeled Today',
    );
    expect(todaySemantics, findsOneWidget);
    expect(
      tester.widget<Semantics>(todaySemantics).properties.selected,
      isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('open-date-calendar')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('recently-viewed-calendar')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('calendar-day-17')));
    await tester.pump();
    final selectedDaySemantics = find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == '2026-4-17',
      description: 'Semantics labeled 2026-4-17',
    );
    expect(selectedDaySemantics, findsOneWidget);
    expect(
      tester.widget<Semantics>(selectedDaySemantics).properties.selected,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('calendar-apply')));
    await tester.pump();
    await tester.pump();

    expect(find.text('April, 17'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('recent-product-custom-1')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('open-date-calendar')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('calendar-day-18')));
    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('recently-viewed-calendar')),
      findsNothing,
    );
    expect(find.text('April, 17'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('recently-viewed-scroll')),
      findsOneWidget,
    );
    expect(router.canPop(), isTrue);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Wishlist'), findsOneWidget);
    expect(router.canPop(), isFalse);
    semantics.dispose();
  });

  testWidgets('has no overflow across compact, landscape and scaled layouts', (
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
      await _pumpWishlist(
        tester,
        overview: wishlistTestOverview(),
        textScale: testCase.textScale,
      );
      await tester.drag(
        find.byKey(const ValueKey('wishlist-scroll')),
        const Offset(0, -300),
      );
      await tester.pump();

      expect(tester.takeException(), isNull, reason: '${testCase.size}');

      await tester.pumpWidget(const SizedBox());
      final router = await _pumpRecentlyViewedRoute(
        tester,
        textScale: testCase.textScale,
      );
      await tester.tap(find.byKey(const ValueKey('open-date-calendar')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('recently-viewed-calendar')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull, reason: '${testCase.size} recent');
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    }
  });
}

Future<GoRouter> _pumpRecentlyViewedRoute(
  WidgetTester tester, {
  required double textScale,
}) async {
  final router = GoRouter(
    initialLocation: recentlyViewedRoutePath,
    routes: buildWishlistRoutes(wishlistApi: successfulWishlistApi()),
  );
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
  await tester.pump();
  return router;
}

Future<void> _pumpWishlist(
  WidgetTester tester, {
  required WishlistOverview overview,
  WishlistProductActions actions = const WishlistProductActions(),
  double textScale = 1,
}) async {
  final api = successfulWishlistApi(overview: overview);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: WishlistPage(
        controller: WishlistController(wishlistApi: api),
        onOpenRecentlyViewed: () {},
        productActions: actions,
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
