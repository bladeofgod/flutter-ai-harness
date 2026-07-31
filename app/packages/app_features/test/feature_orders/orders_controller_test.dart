import 'dart:async';

import 'package:app_data/orders.dart';
import 'package:app_features/api/order_review_media_api.dart';
import 'package:app_features/feature_orders/controllers/orders_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'orders_test_fixtures.dart';

void main() {
  test('loads Activity and changes to History', () async {
    final api = FakeOrdersApi(
      orders: <Order>[
        testOrder(),
        testOrder(id: 'order-history', status: FulfillmentStatus.delivered),
      ],
    );
    final controller = OrdersController.activity(
      ordersApi: api,
      currentUserProvider: TestCurrentUserProvider(),
    );
    addTearDown(controller.onDelete);

    await controller.load();
    expect(controller.viewState, isA<OrdersActivityData>());
    expect((controller.viewState as OrdersActivityData).orders, hasLength(1));

    controller.selectFilter(ActivityFilter.history);
    await Future<void>.delayed(Duration.zero);

    final state = controller.viewState as OrdersActivityData;
    expect(state.filter, ActivityFilter.history);
    expect(state.orders.single.id, 'order-history');
  });

  test('consumes one notification and prevents duplicate calls', () async {
    final api = FakeOrdersApi(orders: <Order>[testOrder()]);
    final controller = OrdersController.order(
      ordersApi: api,
      currentUserProvider: TestCurrentUserProvider(),
      orderId: 'order-test',
    );
    addTearDown(controller.onDelete);
    await controller.load();

    controller.dismissNotificationFromUi();
    controller.dismissNotificationFromUi();
    await Future<void>.delayed(Duration.zero);

    expect(api.consumeCount, 1);
    expect(
      (controller.viewState as OrderDetailData).order.notification?.isConsumed,
      isTrue,
    );
  });

  test('validates and submits a review once', () async {
    final api = FakeOrdersApi(
      orders: <Order>[testOrder(status: FulfillmentStatus.delivered)],
    );
    final controller = OrdersController.order(
      ordersApi: api,
      currentUserProvider: TestCurrentUserProvider(),
      orderId: 'order-test',
    );
    addTearDown(controller.onDelete);
    await controller.load();

    controller.submitReviewFromUi();
    expect(controller.reviewValidationMessage, isNotNull);
    controller.selectRating(5);
    controller.updateReviewComment('Excellent Demo order.');
    controller.submitReviewFromUi();
    controller.submitReviewFromUi();
    await Future<void>.delayed(Duration.zero);

    expect(api.submitCount, 1);
    expect((controller.viewState as OrderDetailData).order.review?.rating, 5);
  });

  test('captures confirmed media and ignores a duplicate launch', () async {
    final mediaApi = FakeOrderReviewMediaApi();
    final controller = _reviewController(mediaApi);
    addTearDown(controller.onDelete);
    await controller.load();

    final completer = Completer<OrderReviewMediaCaptureOutcome>();
    mediaApi.pendingCapture = completer.future;
    final capture = controller.captureMedia();
    await controller.captureMedia();

    expect(mediaApi.captureCount, 1);
    expect(controller.mediaState, isA<OrderReviewMediaLaunching>());

    final attachment = testMediaAttachment();
    completer.complete(OrderReviewMediaConfirmed(attachment));
    await capture;

    expect(
      (controller.mediaState as OrderReviewMediaReady).attachment,
      same(attachment),
    );
  });

  test('treats cancellation as normal and maps a typed failure', () async {
    final mediaApi = FakeOrderReviewMediaApi();
    final controller = _reviewController(mediaApi);
    addTearDown(controller.onDelete);
    await controller.load();

    await controller.captureMedia();
    expect(controller.mediaState, isA<OrderReviewMediaDraftReleased>());

    mediaApi.captureOutcome = const OrderReviewMediaCaptureFailure(
      OrderReviewMediaFailure(
        code: OrderReviewMediaFailureCode.permissionDenied,
        recoverable: true,
      ),
    );
    mediaApi.pendingCapture = null;
    await controller.captureMedia();

    final failure = controller.mediaState as OrderReviewMediaDraftFailure;
    expect(failure.message, contains('Camera access'));
    expect(failure.retainedAttachment, isNull);
  });

  test(
    'retains an attachment when remove fails and retries exactly once',
    () async {
      final mediaApi = FakeOrderReviewMediaApi();
      final attachment = testMediaAttachment();
      mediaApi.captureOutcome = OrderReviewMediaConfirmed(attachment);
      final controller = _reviewController(mediaApi);
      addTearDown(controller.onDelete);
      await controller.load();
      await controller.captureMedia();

      mediaApi.releaseOutcome = const OrderReviewMediaReleaseFailure(
        OrderReviewMediaFailure(
          code: OrderReviewMediaFailureCode.releaseFailed,
          recoverable: true,
        ),
      );
      await controller.removeMedia();

      final failure = controller.mediaState as OrderReviewMediaDraftFailure;
      expect(failure.retainedAttachment, same(attachment));
      expect(mediaApi.releasedAttachments, <OrderReviewMediaAttachment>[
        attachment,
      ]);

      mediaApi.releaseOutcome = const OrderReviewMediaReleased();
      await controller.retryMediaOperation();

      expect(controller.mediaState, isA<OrderReviewMediaDraftReleased>());
      expect(mediaApi.releasedAttachments, <OrderReviewMediaAttachment>[
        attachment,
        attachment,
      ]);
    },
  );

  test('releases the old attachment before launching retake', () async {
    final mediaApi = FakeOrderReviewMediaApi();
    final first = testMediaAttachment();
    final second = testMediaAttachment(type: OrderReviewMediaType.video);
    mediaApi.captureOutcome = OrderReviewMediaConfirmed(first);
    final controller = _reviewController(mediaApi);
    addTearDown(controller.onDelete);
    await controller.load();
    await controller.captureMedia();

    mediaApi.captureOutcome = OrderReviewMediaConfirmed(second);
    await controller.retakeMedia();

    expect(mediaApi.operationLog, <String>['capture', 'release', 'capture']);
    expect(
      (controller.mediaState as OrderReviewMediaReady).attachment,
      same(second),
    );
  });

  test(
    'releases the draft after submit and after a thumbnail decode failure',
    () async {
      final mediaApi = FakeOrderReviewMediaApi();
      final first = testMediaAttachment();
      mediaApi.captureOutcome = OrderReviewMediaConfirmed(first);
      final controller = _reviewController(mediaApi);
      addTearDown(controller.onDelete);
      await controller.load();
      await controller.captureMedia();

      await controller.reportThumbnailDecodeFailure(first);
      expect(controller.mediaState, isA<OrderReviewMediaDraftFailure>());
      expect(mediaApi.releasedAttachments, <OrderReviewMediaAttachment>[first]);

      final second = testMediaAttachment();
      mediaApi.captureOutcome = OrderReviewMediaConfirmed(second);
      await controller.retryMediaOperation();
      controller.selectRating(5);
      controller.updateReviewComment('Media review.');
      controller.submitReviewFromUi();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(mediaApi.releasedAttachments, <OrderReviewMediaAttachment>[
        first,
        second,
      ]);
      expect((controller.viewState as OrderDetailData).order.review, isNotNull);
    },
  );

  test('thumbnail cleanup failure retries release before recapture', () async {
    final mediaApi = FakeOrderReviewMediaApi();
    final first = testMediaAttachment();
    final second = testMediaAttachment(type: OrderReviewMediaType.video);
    mediaApi.captureOutcome = OrderReviewMediaConfirmed(first);
    final controller = _reviewController(mediaApi);
    addTearDown(controller.onDelete);
    await controller.load();
    await controller.captureMedia();

    mediaApi.releaseOutcome = const OrderReviewMediaReleaseFailure(
      OrderReviewMediaFailure(
        code: OrderReviewMediaFailureCode.releaseFailed,
        recoverable: true,
      ),
    );
    await controller.reportThumbnailDecodeFailure(first);

    final failure = controller.mediaState as OrderReviewMediaDraftFailure;
    expect(failure.retryAction, OrderReviewMediaRetryAction.replace);
    expect(failure.retainedAttachment, same(first));

    mediaApi.releaseOutcome = const OrderReviewMediaReleased();
    mediaApi.captureOutcome = OrderReviewMediaConfirmed(second);
    await controller.retryMediaOperation();

    expect(mediaApi.operationLog, <String>[
      'capture',
      'release',
      'release',
      'capture',
    ]);
    expect(
      (controller.mediaState as OrderReviewMediaReady).attachment,
      same(second),
    );
  });

  test(
    'thumbnail cleanup blocks concurrent draft and submit operations',
    () async {
      final mediaApi = FakeOrderReviewMediaApi();
      final attachment = testMediaAttachment();
      mediaApi.captureOutcome = OrderReviewMediaConfirmed(attachment);
      final ordersApi = FakeOrdersApi(
        orders: <Order>[testOrder(status: FulfillmentStatus.delivered)],
      );
      final controller = OrdersController.review(
        ordersApi: ordersApi,
        currentUserProvider: TestCurrentUserProvider(),
        mediaApi: mediaApi,
        orderId: 'order-test',
      );
      addTearDown(controller.onDelete);
      await controller.load();
      await controller.captureMedia();
      final release = Completer<OrderReviewMediaReleaseOutcome>();
      mediaApi.pendingRelease = release.future;

      final cleanup = controller.reportThumbnailDecodeFailure(attachment);
      await Future<void>.delayed(Duration.zero);
      expect(controller.mediaState, isA<OrderReviewMediaRemoving>());

      await controller.removeMedia();
      await controller.retakeMedia();
      controller.selectRating(5);
      controller.updateReviewComment('Do not submit during cleanup.');
      controller.submitReviewFromUi();

      expect(mediaApi.captureCount, 1);
      expect(mediaApi.releasedAttachments, <OrderReviewMediaAttachment>[
        attachment,
      ]);
      expect(ordersApi.submitCount, 0);

      release.complete(
        const OrderReviewMediaReleaseFailure(
          OrderReviewMediaFailure(
            code: OrderReviewMediaFailureCode.releaseFailed,
            recoverable: true,
          ),
        ),
      );
      await cleanup;

      final failure = controller.mediaState as OrderReviewMediaDraftFailure;
      expect(failure.retainedAttachment, same(attachment));
      expect(failure.showRetainedThumbnail, isFalse);
    },
  );

  test('retries post-submit cleanup without submitting twice', () async {
    final mediaApi = FakeOrderReviewMediaApi();
    final attachment = testMediaAttachment();
    mediaApi.captureOutcome = OrderReviewMediaConfirmed(attachment);
    final ordersApi = FakeOrdersApi(
      orders: <Order>[testOrder(status: FulfillmentStatus.delivered)],
    );
    final controller = OrdersController.review(
      ordersApi: ordersApi,
      currentUserProvider: TestCurrentUserProvider(),
      mediaApi: mediaApi,
      orderId: 'order-test',
    );
    addTearDown(controller.onDelete);
    await controller.load();
    await controller.captureMedia();
    mediaApi.releaseOutcome = const OrderReviewMediaReleaseFailure(
      OrderReviewMediaFailure(
        code: OrderReviewMediaFailureCode.releaseFailed,
        recoverable: true,
      ),
    );
    controller.selectRating(5);
    controller.updateReviewComment('Cleanup should not resubmit.');

    controller.submitReviewFromUi();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(ordersApi.submitCount, 1);
    expect((controller.viewState as OrderDetailData).order.review, isNull);
    final failure = controller.mediaState as OrderReviewMediaDraftFailure;
    expect(failure.retryAction, OrderReviewMediaRetryAction.finishSubmission);
    expect(failure.retainedAttachment, same(attachment));

    mediaApi.releaseOutcome = const OrderReviewMediaReleased();
    await controller.retryMediaOperation();

    expect(ordersApi.submitCount, 1);
    expect((controller.viewState as OrderDetailData).order.review, isNotNull);
    expect(mediaApi.releasedAttachments, <OrderReviewMediaAttachment>[
      attachment,
      attachment,
    ]);
  });

  test('releases a confirmed late result after route disposal', () async {
    final mediaApi = FakeOrderReviewMediaApi();
    final controller = _reviewController(mediaApi);
    await controller.load();
    final completer = Completer<OrderReviewMediaCaptureOutcome>();
    mediaApi.pendingCapture = completer.future;

    final capture = controller.captureMedia();
    controller.onDelete();
    final attachment = testMediaAttachment();
    completer.complete(OrderReviewMediaConfirmed(attachment));
    await capture;

    expect(mediaApi.releasedAttachments, <OrderReviewMediaAttachment>[
      attachment,
    ]);
  });

  test('clears a ready attachment once when the review route closes', () async {
    final attachment = testMediaAttachment();
    final mediaApi = FakeOrderReviewMediaApi()
      ..captureOutcome = OrderReviewMediaConfirmed(attachment);
    final controller = _reviewController(mediaApi);
    await controller.load();
    await controller.captureMedia();

    expect(controller.mediaState, isA<OrderReviewMediaReady>());

    controller.onDelete();
    await Future<void>.delayed(Duration.zero);

    expect(mediaApi.clearCount, 1);
    expect(mediaApi.releasedAttachments, isEmpty);
    expect(controller.mediaState, isA<OrderReviewMediaDraftReleased>());
  });
}

OrdersController _reviewController(FakeOrderReviewMediaApi mediaApi) {
  return OrdersController.review(
    ordersApi: FakeOrdersApi(
      orders: <Order>[testOrder(status: FulfillmentStatus.delivered)],
    ),
    currentUserProvider: TestCurrentUserProvider(),
    mediaApi: mediaApi,
    orderId: 'order-test',
  );
}
