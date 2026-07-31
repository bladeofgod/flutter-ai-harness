import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show SemanticsAction;

import 'package:app_data/orders.dart';
import 'package:app_features/api/order_review_media_api.dart';
import 'package:app_features/feature_orders/controllers/orders_controller.dart';
import 'package:app_features/feature_orders/pages/order_review_page.dart';
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

  testWidgets('shows a real thumbnail and exposes retake/remove semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _setViewport(tester, const Size(375, 812));
    final mediaApi = FakeOrderReviewMediaApi();
    mediaApi.captureOutcome = OrderReviewMediaConfirmed(
      testMediaAttachment(type: OrderReviewMediaType.video),
    );
    final fixture = await _pumpOrders(
      tester,
      initialLocation: '/orders/order-1003/review',
      mediaApi: mediaApi,
    );
    addTearDown(fixture.dispose);

    await tester.tap(find.byKey(const ValueKey('order-review-media-add')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('order-review-media-ready')),
      findsOneWidget,
    );
    expect(find.text('Video attached'), findsOneWidget);
    expect(find.text('0:07'), findsOneWidget);
    expect(find.byTooltip('Retake'), findsOneWidget);
    expect(find.byTooltip('Remove attachment'), findsOneWidget);
    expect(find.bySemanticsLabel('Captured video thumbnail'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('order-review-media-retake')))
          .label,
      contains('Retake'),
    );
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('order-review-media-remove')))
          .label,
      contains('Remove attachment'),
    );
    expect(mediaApi.captureCount, 1);
    semantics.dispose();
  });

  testWidgets('evicts captured thumbnail pixels after removal', (tester) async {
    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.clear();
    imageCache.clearLiveImages();
    addTearDown(() {
      imageCache.clear();
      imageCache.clearLiveImages();
    });
    final mediaApi = FakeOrderReviewMediaApi()
      ..captureOutcome = OrderReviewMediaConfirmed(testMediaAttachment());
    final fixture = await _pumpOrders(
      tester,
      initialLocation: '/orders/order-1003/review',
      mediaApi: mediaApi,
    );
    addTearDown(fixture.dispose);
    await tester.tap(find.byKey(const ValueKey('order-review-media-add')));
    await tester.pumpAndSettle();
    final image = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const ValueKey('order-review-media-ready')),
        matching: find.byType(Image),
      ),
    );
    final provider = image.image as MemoryImage;
    final cacheKey = await provider.obtainKey(const ImageConfiguration());
    expect(imageCache.statusForKey(cacheKey).live, isTrue);

    await tester.tap(find.byKey(const ValueKey('order-review-media-remove')));
    await tester.pumpAndSettle();
    await tester.pump();
    final status = imageCache.statusForKey(cacheKey);
    expect(status.pending, isFalse);
    expect(status.keepAlive, isFalse);
    expect(status.live, isFalse);
  });

  testWidgets('popping a ready review clears its draft after UI unmounts', (
    tester,
  ) async {
    final attachment = testMediaAttachment();
    final mediaApi = FakeOrderReviewMediaApi()
      ..captureOutcome = OrderReviewMediaConfirmed(attachment);
    final fixture = await _pumpOrders(
      tester,
      initialLocation: '/orders/order-1003/review',
      mediaApi: mediaApi,
    );
    addTearDown(fixture.dispose);

    await tester.tap(find.byKey(const ValueKey('order-review-media-add')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('order-review-media-ready')),
      findsOneWidget,
    );

    fixture.router.go('/orders/order-1003');
    await tester.pumpAndSettle();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('order-review-media-ready')),
      findsNothing,
    );
    expect(mediaApi.clearCount, 1);
    expect(mediaApi.releasedAttachments, isEmpty);
  });

  testWidgets(
    'disables every media action while review submission is pending',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final attachment = testMediaAttachment();

      Future<void> pump(OrderReviewMediaDraftState state) => tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: OrderReviewPage(
            order: testOrder(status: FulfillmentStatus.delivered),
            rating: 5,
            isSubmitting: true,
            validationMessage: null,
            mediaState: state,
            onSelectRating: (_) {},
            onCommentChanged: (_) {},
            onSubmit: () {},
            onCaptureMedia: () {},
            onRetakeMedia: () {},
            onRemoveMedia: () {},
            onRetryMedia: () {},
            onThumbnailDecodeFailure: (_) {},
            onDone: (_) {},
          ),
        ),
      );

      await pump(const OrderReviewMediaEmpty());
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('order-review-media-add')),
            )
            .onPressed,
        isNull,
      );

      await pump(OrderReviewMediaReady(attachment));
      for (final key in const <String>[
        'order-review-media-retake',
        'order-review-media-remove',
      ]) {
        final finder = find.byKey(ValueKey(key));
        expect(
          tester
              .getSemantics(finder)
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isFalse,
        );
      }

      await pump(
        OrderReviewMediaDraftFailure(
          message: 'Try again.',
          retryAction: OrderReviewMediaRetryAction.capture,
        ),
      );
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('order-review-media-retry')),
            )
            .onPressed,
        isNull,
      );
      semantics.dispose();
    },
  );

  testWidgets('releases a thumbnail that cannot be rendered', (tester) async {
    final mediaApi = FakeOrderReviewMediaApi();
    final attachment = OrderReviewMediaAttachment(
      type: OrderReviewMediaType.photo,
      thumbnailBytes: Uint8List.fromList(<int>[1, 2, 3]),
      thumbnailPixelWidth: 1,
      thumbnailPixelHeight: 1,
      duration: null,
    );
    mediaApi.captureOutcome = OrderReviewMediaConfirmed(attachment);
    final fixture = await _pumpOrders(
      tester,
      initialLocation: '/orders/order-1003/review',
      mediaApi: mediaApi,
    );
    addTearDown(fixture.dispose);

    await tester.tap(find.byKey(const ValueKey('order-review-media-add')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('order-review-media-failure')),
      findsOneWidget,
    );
    expect(mediaApi.releasedAttachments, <OrderReviewMediaAttachment>[
      attachment,
    ]);
  });

  testWidgets('bad retained thumbnail waits for explicit cleanup retry', (
    tester,
  ) async {
    final mediaApi = FakeOrderReviewMediaApi()
      ..releaseOutcome = const OrderReviewMediaReleaseFailure(
        OrderReviewMediaFailure(
          code: OrderReviewMediaFailureCode.releaseFailed,
          recoverable: true,
        ),
      );
    final attachment = OrderReviewMediaAttachment(
      type: OrderReviewMediaType.photo,
      thumbnailBytes: Uint8List.fromList(<int>[1, 2, 3]),
      thumbnailPixelWidth: 1,
      thumbnailPixelHeight: 1,
      duration: null,
    );
    mediaApi.captureOutcome = OrderReviewMediaConfirmed(attachment);
    final fixture = await _pumpOrders(
      tester,
      initialLocation: '/orders/order-1003/review',
      mediaApi: mediaApi,
    );
    addTearDown(fixture.dispose);

    await tester.tap(find.byKey(const ValueKey('order-review-media-add')));
    await tester.pumpAndSettle();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('order-review-media-failure')),
      findsOneWidget,
    );
    expect(mediaApi.releasedAttachments, <OrderReviewMediaAttachment>[
      attachment,
    ]);
  });

  testWidgets(
    'keeps the review media section stable on compact and landscape layouts',
    (tester) async {
      await _setViewport(tester, const Size(320, 568), textScale: 1.3);
      final mediaApi = FakeOrderReviewMediaApi();
      mediaApi.captureOutcome = OrderReviewMediaConfirmed(
        testMediaAttachment(),
      );
      final fixture = await _pumpOrders(
        tester,
        initialLocation: '/orders/order-1003/review',
        textScale: 1.3,
        mediaApi: mediaApi,
      );
      addTearDown(fixture.dispose);

      await tester.drag(
        find.byKey(const ValueKey('order-review-form')),
        const Offset(0, -420),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('order-review-media-add')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(375, 812);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('order-review-media-ready')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(812, 375);
      await tester.pump();
      await tester.drag(
        find.byKey(const ValueKey('order-review-form')),
        const Offset(0, -320),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('order-review-media-ready')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'keeps launching and removing stable with keyboard and safe areas',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _setViewport(tester, const Size(375, 812));
      final mediaApi = FakeOrderReviewMediaApi();
      final capture = Completer<OrderReviewMediaCaptureOutcome>();
      mediaApi.pendingCapture = capture.future;
      final fixture = await _pumpOrders(
        tester,
        initialLocation: '/orders/order-1003/review',
        textScale: 1.3,
        keyboardInset: 300,
        safePadding: const EdgeInsets.only(top: 24, bottom: 34),
        mediaApi: mediaApi,
      );
      addTearDown(fixture.dispose);

      await tester.drag(
        find.byKey(const ValueKey('order-review-form')),
        const Offset(0, -520),
      );
      await tester.pump();
      final add = find.byKey(const ValueKey('order-review-media-add'));
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('order-review-media-launching')),
        findsOneWidget,
      );
      expect(
        tester
            .getSemantics(
              find.byKey(const ValueKey('order-review-media-launching')),
            )
            .label,
        contains('Opening camera...'),
      );
      expect(tester.takeException(), isNull);

      final attachment = testMediaAttachment();
      capture.complete(OrderReviewMediaConfirmed(attachment));
      await tester.pumpAndSettle();
      mediaApi.pendingCapture = null;
      final release = Completer<OrderReviewMediaReleaseOutcome>();
      mediaApi.pendingRelease = release.future;
      final remove = find.byKey(const ValueKey('order-review-media-remove'));
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pump();

      expect(
        find.byKey(const ValueKey('order-review-media-removing')),
        findsOneWidget,
      );
      expect(
        tester
            .getSemantics(
              find.byKey(const ValueKey('order-review-media-removing')),
            )
            .label,
        contains('Removing attachment...'),
      );
      expect(tester.takeException(), isNull);

      release.complete(const OrderReviewMediaReleased());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

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
  double keyboardInset = 0,
  EdgeInsets safePadding = EdgeInsets.zero,
  FakeOrderReviewMediaApi? mediaApi,
}) async {
  final stack = TestOrdersStack();
  final resolvedMediaApi = mediaApi ?? FakeOrderReviewMediaApi();
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: buildOrdersRoutes(
      ordersApi: stack.api,
      mediaApi: resolvedMediaApi,
      currentUserProvider: TestCurrentUserProvider(),
    ),
  );
  await tester.pumpWidget(
    MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          padding: safePadding,
          viewPadding: safePadding,
          viewInsets: EdgeInsets.only(bottom: keyboardInset),
        ),
        child: child!,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _OrdersRouteFixture(router, resolvedMediaApi);
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
  const _OrdersRouteFixture(this.router, this.mediaApi);

  final GoRouter router;
  final FakeOrderReviewMediaApi mediaApi;

  void dispose() => router.dispose();
}
