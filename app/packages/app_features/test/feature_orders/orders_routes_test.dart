import 'package:app_features/feature_orders/routes.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'orders_test_fixtures.dart';

void main() {
  testWidgets('switches Activity/History and opens one status-driven detail', (
    tester,
  ) async {
    await _setViewport(tester, const Size(375, 812));
    final fixture = await _pumpOrders(tester);
    addTearDown(fixture.dispose);

    expect(find.text('My Activity'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('activity-order-order-1001')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('activity-order-order-1003')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('activity-filter-history')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('activity-order-order-1003')),
      findsOneWidget,
    );

    final historyCard = find.byKey(const ValueKey('activity-order-order-1003'));
    await tester.ensureVisible(historyCard);
    await tester.pump();
    await tester.tap(historyCard);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('order-open-review')), findsOneWidget);
    expect(fixture.router.canPop(), isTrue);
    expect(find.text('Delivered'), findsWidgets);
  });

  testWidgets('shows and consumes one delivery notification overlay', (
    tester,
  ) async {
    final fixture = await _pumpOrders(
      tester,
      initialLocation: '/orders/order-1001',
    );
    addTearDown(fixture.dispose);

    expect(
      find.byKey(const ValueKey('order-delivery-notification')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('order-dismiss-notification')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('order-delivery-notification')),
      findsNothing,
    );

    fixture.router.go(activityRoutePath);
    await tester.pumpAndSettle();
    fixture.router.go('/orders/order-1001');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('order-delivery-notification')),
      findsNothing,
    );
  });

  testWidgets('opens History directly for the Profile To Review entry', (
    tester,
  ) async {
    final fixture = await _pumpOrders(
      tester,
      initialLocation: activityHistoryRoutePath,
    );
    addTearDown(fixture.dispose);

    expect(
      find.byKey(const ValueKey('activity-order-order-1003')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('activity-order-order-1001')),
      findsNothing,
    );
  });

  testWidgets('merges review form and done state into one review route', (
    tester,
  ) async {
    final fixture = await _pumpOrders(
      tester,
      initialLocation: '/orders/order-1003/review',
    );
    addTearDown(fixture.dispose);

    expect(find.byKey(const ValueKey('order-review-form')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('order-submit-review')));
    await tester.pump();
    expect(
      find.text('Choose a rating and add a short review.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('order-review-rating-5')));
    await tester.enterText(
      find.byKey(const ValueKey('order-review-comment')),
      'Great local Demo order.',
    );
    await tester.tap(find.byKey(const ValueKey('order-submit-review')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('order-review-complete')), findsOneWidget);
    expect(find.text('Thank you for your review'), findsOneWidget);
  });

  testWidgets('refreshes order detail after review Done', (tester) async {
    final fixture = await _pumpOrders(
      tester,
      initialLocation: '/orders/order-1003',
    );
    addTearDown(fixture.dispose);

    await tester.tap(find.byKey(const ValueKey('order-open-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('order-review-rating-5')));
    await tester.enterText(
      find.byKey(const ValueKey('order-review-comment')),
      'Great local Demo order.',
    );
    await tester.tap(find.byKey(const ValueKey('order-submit-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('order-review-done')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('order-open-review')), findsNothing);
    expect(find.text('Your review'), findsOneWidget);
  });

  testWidgets('renders failed-attempt state and compact scaled layout', (
    tester,
  ) async {
    await _setViewport(tester, const Size(320, 568), textScale: 1.3);
    final fixture = await _pumpOrders(
      tester,
      initialLocation: '/orders/order-1002',
      textScale: 1.3,
    );
    addTearDown(fixture.dispose);

    expect(find.text('Delivery attempt was unsuccessful'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byKey(const ValueKey('order-detail-scroll')),
      const Offset(0, -350),
    );
    await tester.pump();
    expect(find.text('Shipping address'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<_OrdersRouteFixture> _pumpOrders(
  WidgetTester tester, {
  String initialLocation = activityRoutePath,
  double textScale = 1,
}) async {
  final stack = TestOrdersStack();
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: buildOrdersRoutes(
      ordersApi: stack.api,
      currentUserProvider: TestCurrentUserProvider(),
    ),
  );
  await tester.pumpWidget(
    MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _OrdersRouteFixture(router);
}

Future<void> _setViewport(
  WidgetTester tester,
  Size size, {
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

final class _OrdersRouteFixture {
  const _OrdersRouteFixture(this.router);

  final GoRouter router;

  void dispose() => router.dispose();
}
