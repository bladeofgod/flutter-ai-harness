import 'package:app_core/app_core.dart';
import 'package:app_data/app_data.dart';
import 'package:app_features/api/current_user_provider.dart';
import 'package:app_features/api/orders_api.dart';
import 'package:app_features/feature_orders/api/local_orders_api.dart';
import 'package:flutter/foundation.dart';

final class TestOrdersStack {
  TestOrdersStack()
    : dataSource = OrdersLocalDataSource(
        apiClient: ApiClient(
          transport: FixtureApiTransport(
            handlers: <FixtureRequestHandler>[OrdersFixtureHandler()],
          ),
        ),
      ) {
    api = LocalOrdersApi(dataSource: dataSource);
  }

  final OrdersLocalDataSource dataSource;
  late final LocalOrdersApi api;
}

final class FakeOrdersApi implements OrdersApi {
  FakeOrdersApi({required List<Order> orders}) : _orders = <Order>[...orders];

  final List<Order> _orders;
  var loadCount = 0;
  var consumeCount = 0;
  var submitCount = 0;

  @override
  Future<List<Order>> load({required ActivityFilter filter}) async {
    loadCount += 1;
    return _orders
        .where((order) => order.isHistory == (filter == ActivityFilter.history))
        .toList(growable: false);
  }

  @override
  Future<Order> loadOrder({required String orderId}) async =>
      _orders.firstWhere((order) => order.id == orderId);

  @override
  Future<Order> acceptReceipt(
    CheckoutReceipt receipt, {
    List<OrderLine> lines = const <OrderLine>[],
  }) async => throw UnimplementedError();

  @override
  Future<Order> consumeNotification({required String orderId}) async {
    consumeCount += 1;
    final index = _orders.indexWhere((order) => order.id == orderId);
    final current = _orders[index];
    final updated = testOrder(
      id: current.id,
      status: current.fulfillmentStatus,
      notificationConsumed: true,
      review: current.review,
    );
    _orders[index] = updated;
    return updated;
  }

  @override
  Future<Order> submitReview({
    required String orderId,
    required int rating,
    required String comment,
    required String author,
  }) async {
    submitCount += 1;
    final index = _orders.indexWhere((order) => order.id == orderId);
    final updated = testOrder(
      id: orderId,
      status: FulfillmentStatus.delivered,
      review: ProductReview(
        id: 'review-$orderId',
        author: author,
        comment: comment,
        rating: rating,
        publishedLabel: 'Just now',
      ),
    );
    _orders[index] = updated;
    return updated;
  }
}

final class TestCurrentUserProvider implements CurrentUserProvider {
  TestCurrentUserProvider([this._value]);

  final UserEntity? _value;
  final Set<VoidCallback> _listeners = <VoidCallback>{};

  @override
  UserEntity? get value => _value;

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);
}

Order testOrder({
  String id = 'order-test',
  FulfillmentStatus status = FulfillmentStatus.outForDelivery,
  bool notificationConsumed = false,
  ProductReview? review,
}) => Order(
  id: id,
  receiptId: null,
  placedAt: DateTime.utc(2026, 7, 20),
  total: Money(currency: Currency.usd, minorUnits: 3400),
  shippingAddress: ShippingAddress(
    id: 'shipping-home',
    recipientName: 'Demo Customer',
    streetLine: '42 Market Street',
    city: 'San Francisco',
    region: 'California',
    postalCode: '94105',
    country: 'United States',
  ),
  lines: <OrderLine>[
    OrderLine(
      product: ProductSummary(
        id: 'product-1',
        title: 'Demo dress',
        imageAssetKey: 'assets/images/profile/product_01.png',
        price: Money(currency: Currency.usd, minorUnits: 3400),
      ),
      quantity: 1,
      unitPrice: Money(currency: Currency.usd, minorUnits: 3400),
    ),
  ],
  fulfillmentStatus: status,
  fulfillmentSteps: <FulfillmentStep>[
    FulfillmentStep(
      id: 'current',
      title: status == FulfillmentStatus.delivered
          ? 'Delivered'
          : 'Out for delivery',
      description: 'A deterministic Demo status.',
      isCompleted: status == FulfillmentStatus.delivered,
      isCurrent: true,
    ),
  ],
  notification: status == FulfillmentStatus.outForDelivery
      ? OrderNotification(
          id: 'notification-$id',
          kind: OrderNotificationKind.deliveryUpdate,
          title: 'Arriving today',
          message: 'A Demo delivery is in progress.',
          isConsumed: notificationConsumed,
        )
      : null,
  review: review,
);
