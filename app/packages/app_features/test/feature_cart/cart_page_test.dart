import 'package:app_data/app_data.dart';
import 'package:app_features/api/cart_api.dart';
import 'package:app_features/feature_cart/controllers/cart_controller.dart';
import 'package:app_features/feature_cart/pages/cart_page.dart';
import 'package:app_features/feature_cart/routes.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'cart_test_fixtures.dart';

void main() {
  testWidgets('renders node 45 data state and forwards checkout snapshot', (
    tester,
  ) async {
    await _setViewport(tester, const Size(375, 812));
    final api = FakeCartApi();
    addTearDown(api.close);
    Cart? checkedOut;
    await _pumpCart(
      tester,
      api: api,
      source: CartRecommendationSource.wishlist,
      onCheckout: (cart) => checkedOut = cart,
    );

    expect(find.text('Cart'), findsOneWidget);
    expect(find.text('Shipping Address'), findsOneWidget);
    expect(find.byKey(const ValueKey('cart-quantity-badge')), findsOneWidget);
    expect(find.text(r'$34,00'), findsOneWidget);
    expect(find.byKey(const ValueKey('cart-checkout-bar')), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsNothing);

    await tester.tap(find.byKey(const ValueKey('cart-checkout')));
    expect(checkedOut?.total.minorUnits, 3400);
  });

  testWidgets('updates quantity and deletes the final item into empty state', (
    tester,
  ) async {
    await _setViewport(tester, const Size(375, 812));
    final api = FakeCartApi(initialCart: cartTestCart(itemCount: 1));
    addTearDown(api.close);
    await _pumpCart(
      tester,
      api: api,
      source: CartRecommendationSource.wishlist,
    );
    final id = api.current.items.single.id;

    await tester.tap(find.byKey(ValueKey<String>('cart-increment-$id')));
    await tester.pump();
    await tester.pump();
    expect(find.text(r'$34,00'), findsOneWidget);
    expect(
      find.byKey(ValueKey<String>('cart-item-quantity-$id')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(ValueKey<String>('cart-remove-$id')));
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('cart-empty-illustration')),
      findsOneWidget,
    );
    expect(find.text(r'$0,00'), findsOneWidget);
    expect(find.byKey(const ValueKey('cart-checkout')), findsOneWidget);
  });

  testWidgets('exposes labeled 44 point cart item actions', (tester) async {
    await _setViewport(tester, const Size(375, 812));
    final api = FakeCartApi(initialCart: cartTestCart(itemCount: 1));
    addTearDown(api.close);
    final semantics = tester.ensureSemantics();
    await _pumpCart(
      tester,
      api: api,
      source: CartRecommendationSource.wishlist,
    );
    final item = api.current.items.single;

    expect(find.byTooltip('Remove ${item.product.title}'), findsOneWidget);
    expect(
      find.byTooltip('Increase ${item.product.title} quantity'),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(ValueKey<String>('cart-remove-${item.id}'))),
      const Size.square(44),
    );
    expect(
      tester.getSize(
        find.descendant(
          of: find.byKey(ValueKey<String>('cart-remove-${item.id}')),
          matching: find.byType(IconButton),
        ),
      ),
      const Size.square(44),
    );
    expect(
      tester.getSize(find.byKey(ValueKey<String>('cart-increment-${item.id}'))),
      const Size.square(44),
    );
    semantics.dispose();
  });

  testWidgets('renders node 46 wishlist empty source explicitly', (
    tester,
  ) async {
    await _setViewport(tester, const Size(375, 812));
    final api = FakeCartApi(initialCart: emptyCart());
    addTearDown(api.close);
    await _pumpCart(
      tester,
      api: api,
      source: CartRecommendationSource.wishlist,
    );

    expect(
      find.byKey(const ValueKey('cart-empty-illustration')),
      findsOneWidget,
    );
    await _scrollTo(tester, find.text('From Your Wishlist'));
    expect(
      find.byKey(const ValueKey('cart-recommendations-wishlist')),
      findsOneWidget,
    );
    expect(find.text('Most Popular'), findsNothing);

    final addButton = find.byKey(
      const ValueKey('cart-add-recommendation-product-22'),
    );
    await tester.ensureVisible(addButton);
    await tester.tap(addButton);
    await tester.pump();
    await tester.pump();

    expect(api.mutationCount, 1);
    expect(find.byKey(const ValueKey('cart-empty-illustration')), findsNothing);
    expect(
      find.byKey(const ValueKey('cart-item-product-22::color=pink&size=m')),
      findsOneWidget,
    );
  });

  testWidgets('renders node 47 popular empty source explicitly', (
    tester,
  ) async {
    await _setViewport(tester, const Size(375, 812));
    final api = FakeCartApi(initialCart: emptyCart());
    addTearDown(api.close);
    await _pumpCart(tester, api: api, source: CartRecommendationSource.popular);

    await _scrollTo(tester, find.text('Most Popular'));
    expect(
      find.byKey(const ValueKey('cart-recommendations-popular')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('cart-popular-list')), findsOneWidget);
    expect(find.text('From Your Wishlist'), findsNothing);
  });

  testWidgets(
    'buildCartRoutes consumes enum extra and public checkout callback',
    (tester) async {
      await _setViewport(tester, const Size(375, 812));
      final api = FakeCartApi(initialCart: emptyCart());
      addTearDown(api.close);
      final router = GoRouter(
        initialLocation: '/',
        routes: <RouteBase>[
          GoRoute(path: '/', builder: (context, state) => const SizedBox()),
          ...buildCartRoutes(cartApi: api),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      );
      router.go(cartRoutePath, extra: CartRecommendationSource.popular);
      await tester.pump();
      await tester.pump();

      expect(router.routeInformationProvider.value.uri.path, cartRoutePath);
      await _scrollTo(tester, find.text('Most Popular'));
      expect(
        find.byKey(const ValueKey('cart-recommendations-popular')),
        findsOneWidget,
      );
    },
  );

  testWidgets('has one vertical owner and no overflow across viewports', (
    tester,
  ) async {
    const cases = <({Size size, double scale})>[
      (size: Size(320, 568), scale: 1),
      (size: Size(812, 375), scale: 1),
      (size: Size(375, 812), scale: 1.3),
    ];

    for (final testCase in cases) {
      await tester.pumpWidget(const SizedBox());
      await _setViewport(tester, testCase.size);
      final api = FakeCartApi(
        initialCart: cartTestCart(
          itemCount: 1,
          title:
              'A deliberately long product description that must stay '
              'inside its responsive row without moving the controls.',
        ),
      );
      await _pumpCart(
        tester,
        api: api,
        source: CartRecommendationSource.wishlist,
        textScale: testCase.scale,
      );
      await _scrollTo(tester, find.text('From Your Wishlist'));

      expect(find.byKey(const ValueKey('cart-scroll')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '${testCase.size}');
      await api.close();
    }
  });
}

Future<void> _pumpCart(
  WidgetTester tester, {
  required FakeCartApi api,
  required CartRecommendationSource source,
  CartCheckoutCallback? onCheckout,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: CartPage(
        controller: CartController(cartApi: api, recommendationSource: source),
        onCheckout: onCheckout,
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

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  final scroll = find.byKey(const ValueKey('cart-scroll'));
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find
        .descendant(of: scroll, matching: find.byType(Scrollable))
        .first,
  );
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}
