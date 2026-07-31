import 'dart:convert';

import 'package:app_core/app_core.dart';
import 'package:app_data/app_data.dart';
import 'package:app_features/api/current_user_provider.dart';
import 'package:app_features/api/order_review_media_api.dart';
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

final class FakeOrderReviewMediaApi implements OrderReviewMediaApi {
  OrderReviewMediaCaptureOutcome captureOutcome =
      const OrderReviewMediaCancelled();
  OrderReviewMediaReleaseOutcome releaseOutcome =
      const OrderReviewMediaReleased();
  Future<OrderReviewMediaCaptureOutcome>? pendingCapture;
  Future<OrderReviewMediaReleaseOutcome>? pendingRelease;

  final List<OrderReviewMediaAttachment> releasedAttachments =
      <OrderReviewMediaAttachment>[];
  final List<String> operationLog = <String>[];
  var captureCount = 0;
  var clearCount = 0;
  var disposeCount = 0;

  @override
  Future<OrderReviewMediaCaptureOutcome> capture() async {
    captureCount += 1;
    operationLog.add('capture');
    return pendingCapture ?? captureOutcome;
  }

  @override
  Future<OrderReviewMediaReleaseOutcome> release(
    OrderReviewMediaAttachment attachment,
  ) async {
    operationLog.add('release');
    releasedAttachments.add(attachment);
    return pendingRelease ?? releaseOutcome;
  }

  @override
  Future<void> clearDrafts() async {
    clearCount += 1;
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }
}

OrderReviewMediaAttachment testMediaAttachment({
  OrderReviewMediaType type = OrderReviewMediaType.photo,
}) => OrderReviewMediaAttachment(
  type: type,
  thumbnailBytes: validOrderReviewJpeg(),
  thumbnailPixelWidth: 1,
  thumbnailPixelHeight: 1,
  duration: type == OrderReviewMediaType.video
      ? const Duration(seconds: 7)
      : null,
);

const String _onePixelJpegBase64 =
    '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////'
    '////////////////////////////////////////////////////////2wBDAf//'
    '////////////////////////////////////////////////////////////////////'
    '////////////////wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAA'
    'AAAAAAf/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAF//8QAFBAB'
    'AAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABBQJ//8QAFBEBAAAAAAAAAAAAAAAAAAAA'
    'AP/aAAgBAwEBPwF//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAgEBPwF//8QA'
    'FBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQAGPwJ//8QAFBABAAAAAAAAAAAAAAAA'
    'AAAAAP/aAAgBAQABPyF//9oADAMBAAIAAwAAABD/xAAUEQEAAAAAAAAAAAAAAAAA'
    'AAAA/9oACAEDAQE/EH//xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAECAQE/EH//'
    'xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAE/EH//2Q==';

Uint8List validOrderReviewJpeg() => base64Decode(_onePixelJpegBase64);

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
