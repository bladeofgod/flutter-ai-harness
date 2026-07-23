import 'package:app_features/feature_promotions/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'promotions_test_fixtures.dart';

void main() {
  testWidgets('routes merge Flash, Live and Story state families', (
    tester,
  ) async {
    await _setViewport(tester, const Size(375, 812));
    final router = _router(flashSaleRoutePath);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await _settle(tester, const ValueKey('flash-sale-scroll'));
    expect(router.routeInformationProvider.value.uri.path, flashSaleRoutePath);

    router.go(liveRoutePath);
    await _settle(tester, const ValueKey('live-prepare-preview'));
    expect(router.routeInformationProvider.value.uri.path, liveRoutePath);

    router.go(storyLocation('story-style-edit'));
    await _settle(tester, const ValueKey('story-next'));
    expect(
      router.routeInformationProvider.value.uri.path,
      storyLocation('story-style-edit'),
    );
  });

  testWidgets(
    'product and Story exit callbacks navigate through public targets',
    (tester) async {
      await _setViewport(tester, const Size(375, 812));
      final router = _router(storyLocation('story-style-edit'));
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await _settle(tester, const ValueKey('story-next'));

      await tester.tap(find.byKey(const ValueKey('story-open-product')));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/test-product/product-2',
      );

      router.go(storyLocation('story-style-edit'));
      await _settle(tester, const ValueKey('story-next'));
      for (var index = 0; index < 3; index += 1) {
        await tester.tap(find.byKey(const ValueKey('story-next')));
        await tester.pump();
        await tester.pump();
      }
      expect(router.routeInformationProvider.value.uri.path, '/story-finished');
    },
  );

  testWidgets('unknown Story id renders retryable not-found state', (
    tester,
  ) async {
    await _setViewport(tester, const Size(375, 812));
    final router = _router(storyLocation('missing'));
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await _settle(tester, const ValueKey('story-retry'));

    expect(find.text('Story not found'), findsOneWidget);
  });
}

GoRouter _router(String initialLocation) => GoRouter(
  initialLocation: initialLocation,
  routes: <RouteBase>[
    ...buildPromotionRoutes(
      promotionsApi: FakePromotionsApi(),
      onOpenProduct: (context, productId) =>
          context.go('/test-product/$productId'),
      onExitStory: (context) => context.go('/story-finished'),
    ),
    GoRoute(
      path: '/test-product/:productId',
      builder: (context, state) => Text(
        'Product ${state.pathParameters['productId']}',
        textDirection: TextDirection.ltr,
      ),
    ),
    GoRoute(
      path: '/story-finished',
      builder: (context, state) =>
          const Text('Story finished', textDirection: TextDirection.ltr),
    ),
  ],
);

Future<void> _settle(WidgetTester tester, ValueKey<String> key) async {
  for (var attempt = 0; attempt < 30; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 10));
    if (find.byKey(key).evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Route did not settle for $key.');
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}
