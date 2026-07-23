import 'package:app_core/app_core.dart';
import 'package:app_data/app_data.dart';
import 'package:test/test.dart';

void main() {
  group('OrdersLocalDataSource', () {
    test('loads deterministic activity and history states', () async {
      final source = _source();

      final activity = await source.load(filter: ActivityFilter.activity);
      final history = await source.load(filter: ActivityFilter.history);

      expect(activity.map((order) => order.id), <String>[
        'order-1001',
        'order-1002',
      ]);
      expect(
        activity.first.fulfillmentStatus,
        FulfillmentStatus.outForDelivery,
      );
      expect(
        activity.last.fulfillmentStatus,
        FulfillmentStatus.deliveryAttemptFailed,
      );
      expect(history.map((order) => order.id), <String>[
        'order-1003',
        'order-1004',
      ]);
      expect(history.first.canReview, isTrue);
      expect(history.last.review?.rating, 5);
    });

    test('adds a Checkout Receipt once and a new handler resets it', () async {
      final source = _source();
      final receipt = _receipt();

      final first = await source.addReceipt(receipt);
      final repeated = await source.addReceipt(receipt);
      final activity = await source.load(filter: ActivityFilter.activity);

      expect(first.didMutate, isTrue);
      expect(repeated.didMutate, isFalse);
      expect(first.order.id, 'order-receipt-100');
      expect(first.order.lines.single.product.title, 'Demo checkout purchase');
      expect(
        activity.where((order) => order.receiptId == receipt.id),
        hasLength(1),
      );
      expect(
        await _source().load(filter: ActivityFilter.activity),
        hasLength(2),
      );
    });

    test('consumes a delivery notification exactly once', () async {
      final source = _source();
      final before = await source.loadOrder(orderId: 'order-1001');

      final first = await source.consumeNotification(orderId: before.id);
      final repeated = await source.consumeNotification(orderId: before.id);

      expect(before.notification?.isConsumed, isFalse);
      expect(first.didMutate, isTrue);
      expect(first.order.notification?.isConsumed, isTrue);
      expect(repeated.didMutate, isFalse);
    });

    test('submits an idempotent review and rejects replacement text', () async {
      final source = _source();

      final first = await source.submitReview(
        orderId: 'order-1003',
        rating: 4,
        comment: 'A useful Demo purchase.',
        author: 'Demo Customer',
      );
      final repeated = await source.submitReview(
        orderId: 'order-1003',
        rating: 4,
        comment: 'A useful Demo purchase.',
        author: 'Demo Customer',
      );

      expect(first.didMutate, isTrue);
      expect(first.order.review?.rating, 4);
      expect(repeated.didMutate, isFalse);
      await expectLater(
        source.submitReview(
          orderId: 'order-1003',
          rating: 2,
          comment: 'Replacement text.',
          author: 'Demo Customer',
        ),
        throwsA(const OrdersFailure(OrdersFailureCode.alreadyReviewed)),
      );
    });

    test('maps not-found and malformed payloads to stable failures', () async {
      await expectLater(
        _source().loadOrder(orderId: 'missing'),
        throwsA(const OrdersFailure(OrdersFailureCode.orderNotFound)),
      );
      final malformed = OrdersLocalDataSource(
        apiClient: const ApiClient(transport: _MalformedOrdersTransport()),
      );
      await expectLater(
        malformed.load(filter: ActivityFilter.activity),
        throwsA(const OrdersFailure(OrdersFailureCode.invalidResponse)),
      );
    });
  });
}

OrdersLocalDataSource _source() => OrdersLocalDataSource(
  apiClient: ApiClient(
    transport: FixtureApiTransport(
      handlers: <FixtureRequestHandler>[OrdersFixtureHandler()],
    ),
  ),
);

CheckoutReceipt _receipt() => CheckoutReceipt(
  id: 'receipt-100',
  attemptId: 'attempt-100',
  amount: Money(currency: Currency.usd, minorUnits: 6800),
  paymentMethodId: 'payment-card-primary',
  maskedPaymentLabel: 'Visa •••• 4242',
  shippingAddress: ShippingAddress(
    id: 'shipping-home',
    recipientName: 'Demo Customer',
    streetLine: '42 Market Street',
    city: 'San Francisco',
    region: 'California',
    postalCode: '94105',
    country: 'United States',
  ),
  issuedAt: DateTime.utc(2026, 7, 22, 10),
);

final class _MalformedOrdersTransport implements ApiTransport {
  const _MalformedOrdersTransport();

  @override
  Future<ApiResponse<Object?>> send(ApiRequest request) async =>
      const ApiResponse<Object?>.success(<String, Object?>{
        'orders': <Object?>[
          <String, Object?>{'id': 'incomplete'},
        ],
      });
}
