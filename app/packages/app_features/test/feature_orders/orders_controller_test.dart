import 'package:app_data/orders.dart';
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
}
