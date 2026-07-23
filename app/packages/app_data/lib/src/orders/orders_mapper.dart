part of 'orders_local.dart';

abstract final class _OrdersFixtureMapper {
  static List<Order> activity(Object? payload) => _decode(() {
    final values = _map(payload);
    final orders = values['orders'];
    if (orders is! List<Object?>) {
      throw const OrdersFailure(OrdersFailureCode.invalidResponse);
    }
    return List<Order>.unmodifiable(orders.map(order));
  });

  static OrdersMutationResult mutation(Object? payload) => _decode(() {
    final values = _map(payload);
    final didMutate = values['didMutate'];
    if (didMutate is! bool) {
      throw const OrdersFailure(OrdersFailureCode.invalidResponse);
    }
    return (order: order(values['order']), didMutate: didMutate);
  });

  static Order order(Object? payload) => _decode(() {
    final values = _map(payload);
    final receiptId = values['receiptId'];
    final notificationPayload = values['notification'];
    final reviewPayload = values['review'];
    return Order(
      id: _string(values, 'id'),
      receiptId: receiptId == null ? null : _string(values, 'receiptId'),
      placedAt: DateTime.parse(_string(values, 'placedAt')),
      total: _money(values['total']),
      shippingAddress: _address(values['shippingAddress']),
      lines: _list(values, 'lines', _line),
      fulfillmentStatus: switch (_string(values, 'status')) {
        'processing' => FulfillmentStatus.processing,
        'in_transit' => FulfillmentStatus.inTransit,
        'out_for_delivery' => FulfillmentStatus.outForDelivery,
        'delivery_attempt_failed' => FulfillmentStatus.deliveryAttemptFailed,
        'delivered' => FulfillmentStatus.delivered,
        _ => throw const OrdersFailure(OrdersFailureCode.invalidResponse),
      },
      fulfillmentSteps: _list(values, 'steps', _step),
      notification: notificationPayload == null
          ? null
          : _notification(notificationPayload),
      review: reviewPayload == null ? null : _review(reviewPayload),
    );
  });

  static Map<String, Object?> receiptInput(
    CheckoutReceipt receipt, {
    required List<OrderLine> lines,
  }) {
    final orderLines = lines.isEmpty
        ? <OrderLine>[
            OrderLine(
              product: ProductSummary(
                id: 'checkout-${receipt.id}',
                title: 'Demo checkout purchase',
                imageAssetKey: 'assets/images/profile/product_01.png',
                price: receipt.amount,
              ),
              quantity: 1,
              unitPrice: receipt.amount,
            ),
          ]
        : lines;
    return <String, Object?>{
      'receipt': <String, Object?>{
        'id': receipt.id,
        'amount': _moneyPayload(receipt.amount),
        'shippingAddress': _addressPayload(receipt.shippingAddress),
        'issuedAt': receipt.issuedAt.toUtc().toIso8601String(),
      },
      'lines': <Object?>[for (final line in orderLines) _linePayload(line)],
    };
  }

  static OrderLine _line(Object? payload) {
    final values = _map(payload);
    final product = _map(values['product']);
    final variationLabel = values['variationLabel'];
    if (variationLabel != null && variationLabel is! String) {
      throw const OrdersFailure(OrdersFailureCode.invalidResponse);
    }
    return OrderLine(
      product: ProductSummary(
        id: _string(product, 'id'),
        title: _string(product, 'title'),
        imageAssetKey: _string(product, 'imageAssetKey'),
        price: Money(
          currency: Currency.fromCode(_string(product, 'currency')),
          minorUnits: _integer(product, 'priceMinorUnits'),
        ),
      ),
      quantity: _integer(values, 'quantity'),
      unitPrice: _money(values['unitPrice']),
      variationLabel: variationLabel as String?,
    );
  }

  static FulfillmentStep _step(Object? payload) {
    final values = _map(payload);
    return FulfillmentStep(
      id: _string(values, 'id'),
      title: _string(values, 'title'),
      description: _string(values, 'description'),
      isCompleted: _boolean(values, 'isCompleted'),
      isCurrent: _boolean(values, 'isCurrent'),
    );
  }

  static OrderNotification _notification(Object? payload) {
    final values = _map(payload);
    return OrderNotification(
      id: _string(values, 'id'),
      kind: switch (_string(values, 'kind')) {
        'delivery_update' => OrderNotificationKind.deliveryUpdate,
        'delivery_attempt_failed' =>
          OrderNotificationKind.deliveryAttemptFailed,
        _ => throw const OrdersFailure(OrdersFailureCode.invalidResponse),
      },
      title: _string(values, 'title'),
      message: _string(values, 'message'),
      isConsumed: _boolean(values, 'isConsumed'),
    );
  }

  static ProductReview _review(Object? payload) {
    final values = _map(payload);
    final avatarAssetKey = values['avatarAssetKey'];
    if (avatarAssetKey != null && avatarAssetKey is! String) {
      throw const OrdersFailure(OrdersFailureCode.invalidResponse);
    }
    return ProductReview(
      id: _string(values, 'id'),
      author: _string(values, 'author'),
      comment: _string(values, 'comment'),
      rating: _integer(values, 'rating'),
      publishedLabel: _string(values, 'publishedLabel'),
      avatarAssetKey: avatarAssetKey as String?,
    );
  }

  static Money _money(Object? payload) {
    final values = _map(payload);
    return Money(
      currency: Currency.fromCode(_string(values, 'currency')),
      minorUnits: _integer(values, 'minorUnits'),
    );
  }

  static ShippingAddress _address(Object? payload) {
    final values = _map(payload);
    return ShippingAddress(
      id: _string(values, 'id'),
      recipientName: _string(values, 'recipientName'),
      streetLine: _string(values, 'streetLine'),
      city: _string(values, 'city'),
      region: _string(values, 'region'),
      postalCode: _string(values, 'postalCode'),
      country: _string(values, 'country'),
    );
  }

  static Map<String, Object?> _linePayload(OrderLine line) => <String, Object?>{
    'product': <String, Object?>{
      'id': line.product.id,
      'title': line.product.title,
      'imageAssetKey': line.product.imageAssetKey,
      'priceMinorUnits': line.unitPrice.minorUnits,
      'currency': line.unitPrice.currency.code,
    },
    'quantity': line.quantity,
    'unitPrice': _moneyPayload(line.unitPrice),
    'variationLabel': line.variationLabel,
  };

  static Map<String, Object?> _moneyPayload(Money money) => <String, Object?>{
    'currency': money.currency.code,
    'minorUnits': money.minorUnits,
  };

  static Map<String, Object?> _addressPayload(ShippingAddress address) =>
      <String, Object?>{
        'id': address.id,
        'recipientName': address.recipientName,
        'streetLine': address.streetLine,
        'city': address.city,
        'region': address.region,
        'postalCode': address.postalCode,
        'country': address.country,
      };

  static T _decode<T>(T Function() decode) {
    try {
      return decode();
    } on OrdersFailure {
      rethrow;
    } on FormatException catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const OrdersFailure(OrdersFailureCode.invalidResponse),
        stackTrace,
      );
    } on ArgumentError catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const OrdersFailure(OrdersFailureCode.invalidResponse),
        stackTrace,
      );
    }
  }

  static List<T> _list<T>(
    Map<String, Object?> values,
    String key,
    T Function(Object?) mapper,
  ) {
    final value = values[key];
    if (value is! List<Object?>) {
      throw const OrdersFailure(OrdersFailureCode.invalidResponse);
    }
    return List<T>.unmodifiable(value.map(mapper));
  }

  static Map<String, Object?> _map(Object? payload) {
    if (payload is! Map<String, Object?>) {
      throw const OrdersFailure(OrdersFailureCode.invalidResponse);
    }
    return payload;
  }

  static String _string(Map<String, Object?> values, String key) {
    final value = values[key];
    if (value is! String || value.trim().isEmpty) {
      throw const OrdersFailure(OrdersFailureCode.invalidResponse);
    }
    return value;
  }

  static int _integer(Map<String, Object?> values, String key) {
    final value = values[key];
    if (value is! int) {
      throw const OrdersFailure(OrdersFailureCode.invalidResponse);
    }
    return value;
  }

  static bool _boolean(Map<String, Object?> values, String key) {
    final value = values[key];
    if (value is! bool) {
      throw const OrdersFailure(OrdersFailureCode.invalidResponse);
    }
    return value;
  }
}
