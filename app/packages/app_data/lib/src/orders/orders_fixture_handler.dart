import 'package:app_core/app_core.dart';

import '../fixture/fixture_api_transport.dart';

/// Orders 请求键、Fixture 状态和确定性 mutation 的唯一所有者。
final class OrdersFixtureHandler implements FixtureRequestHandler {
  OrdersFixtureHandler() : _orders = _fixtureOrders();

  static const String loadActivityKey = 'orders.activity.load';
  static const String loadDetailKey = 'orders.detail.load';
  static const String addReceiptKey = 'orders.receipt.add';
  static const String consumeNotificationKey = 'orders.notification.consume';
  static const String submitReviewKey = 'orders.review.submit';

  final List<Map<String, Object?>> _orders;

  void resetSession() {
    _orders
      ..clear()
      ..addAll(_fixtureOrders());
  }

  @override
  Set<String> get requestKeys => const <String>{
    loadActivityKey,
    loadDetailKey,
    addReceiptKey,
    consumeNotificationKey,
    submitReviewKey,
  };

  @override
  Future<ApiResponse<Object?>> handle(ApiRequest request) async =>
      switch (request.key) {
        loadActivityKey => _loadActivity(request.payload),
        loadDetailKey => _loadDetail(request.payload),
        addReceiptKey => _addReceipt(request.payload),
        consumeNotificationKey => _consumeNotification(request.payload),
        submitReviewKey => _submitReview(request.payload),
        _ => throw UnknownApiRequestException(request.key),
      };

  ApiResponse<Object?> _loadActivity(Object? payload) {
    final values = _map(payload);
    final filter = values?['filter'];
    if (filter != 'activity' && filter != 'history') {
      return _invalidInput();
    }
    final history = filter == 'history';
    return ApiResponse<Object?>.success(<String, Object?>{
      'orders': <Object?>[
        for (final order in _orders)
          if ((order['status'] == 'delivered') == history) _copyOrder(order),
      ],
    });
  }

  ApiResponse<Object?> _loadDetail(Object? payload) {
    final orderId = _map(payload)?['orderId'];
    if (orderId is! String || orderId.isEmpty) {
      return _invalidInput();
    }
    final index = _orders.indexWhere((order) => order['id'] == orderId);
    if (index < 0) {
      return _notFound();
    }
    return ApiResponse<Object?>.success(_copyOrder(_orders[index]));
  }

  ApiResponse<Object?> _addReceipt(Object? payload) {
    final values = _map(payload);
    final receipt = _map(values?['receipt']);
    final lines = values?['lines'];
    final receiptId = receipt?['id'];
    final amount = _map(receipt?['amount']);
    final address = _map(receipt?['shippingAddress']);
    final issuedAt = receipt?['issuedAt'];
    if (receiptId is! String ||
        receiptId.isEmpty ||
        amount == null ||
        address == null ||
        issuedAt is! String ||
        lines is! List<Object?> ||
        lines.isEmpty) {
      return _invalidInput();
    }
    final existing = _orders.indexWhere(
      (order) => order['receiptId'] == receiptId,
    );
    if (existing >= 0) {
      return _mutation(_orders[existing], didMutate: false);
    }
    final order = <String, Object?>{
      'id': 'order-$receiptId',
      'receiptId': receiptId,
      'placedAt': issuedAt,
      'total': Map<String, Object?>.of(amount),
      'shippingAddress': Map<String, Object?>.of(address),
      'lines': <Object?>[
        for (final line in lines)
          if (line is Map<String, Object?>) Map<String, Object?>.of(line),
      ],
      'status': 'processing',
      'steps': <Object?>[
        _step(
          'confirmed',
          'Order confirmed',
          'Your local Demo order has been received.',
          completed: true,
        ),
        _step(
          'processing',
          'Preparing your order',
          'Items are being prepared for delivery.',
          current: true,
        ),
      ],
      'notification': null,
      'review': null,
    };
    if ((order['lines'] as List<Object?>).isEmpty) {
      return _invalidInput();
    }
    _orders.insert(0, order);
    return _mutation(order, didMutate: true);
  }

  ApiResponse<Object?> _consumeNotification(Object? payload) {
    final orderId = _map(payload)?['orderId'];
    if (orderId is! String || orderId.isEmpty) {
      return _invalidInput();
    }
    final index = _orders.indexWhere((order) => order['id'] == orderId);
    if (index < 0) {
      return _notFound();
    }
    final order = _orders[index];
    final notification = _map(order['notification']);
    if (notification == null || notification['isConsumed'] == true) {
      return _mutation(order, didMutate: false);
    }
    final updated = <String, Object?>{
      ...order,
      'notification': <String, Object?>{...notification, 'isConsumed': true},
    };
    _orders[index] = updated;
    return _mutation(updated, didMutate: true);
  }

  ApiResponse<Object?> _submitReview(Object? payload) {
    final values = _map(payload);
    final orderId = values?['orderId'];
    final rating = values?['rating'];
    final comment = values?['comment'];
    final author = values?['author'];
    if (orderId is! String ||
        orderId.isEmpty ||
        rating is! int ||
        rating < 1 ||
        rating > 5 ||
        comment is! String ||
        comment.trim().isEmpty ||
        author is! String ||
        author.trim().isEmpty) {
      return _invalidInput();
    }
    final index = _orders.indexWhere((order) => order['id'] == orderId);
    if (index < 0) {
      return _notFound();
    }
    final order = _orders[index];
    if (order['status'] != 'delivered') {
      return _invalidInput();
    }
    final existingReview = _map(order['review']);
    if (existingReview != null) {
      final sameReview =
          existingReview['rating'] == rating &&
          existingReview['comment'] == comment.trim() &&
          existingReview['author'] == author.trim();
      if (sameReview) {
        return _mutation(order, didMutate: false);
      }
      return const ApiResponse<Object?>.failure(
        ApiFailure.rejected(code: 'orders.already_reviewed'),
      );
    }
    final updated = <String, Object?>{
      ...order,
      'review': <String, Object?>{
        'id': 'review-$orderId',
        'author': author.trim(),
        'comment': comment.trim(),
        'rating': rating,
        'publishedLabel': 'Just now',
        'avatarAssetKey': null,
      },
    };
    _orders[index] = updated;
    return _mutation(updated, didMutate: true);
  }

  ApiResponse<Object?> _mutation(
    Map<String, Object?> order, {
    required bool didMutate,
  }) => ApiResponse<Object?>.success(<String, Object?>{
    'order': _copyOrder(order),
    'didMutate': didMutate,
  });

  ApiResponse<Object?> _invalidInput() => const ApiResponse<Object?>.failure(
    ApiFailure.rejected(code: 'orders.invalid_input'),
  );

  ApiResponse<Object?> _notFound() => const ApiResponse<Object?>.failure(
    ApiFailure.rejected(code: 'orders.order_not_found'),
  );
}

List<Map<String, Object?>> _fixtureOrders() => <Map<String, Object?>>[
  _orderFixture(
    id: 'order-1001',
    status: 'out_for_delivery',
    imageNumber: 2,
    title: 'Linen summer dress',
    totalMinorUnits: 3400,
    steps: <Map<String, Object?>>[
      _step(
        'confirmed',
        'Order confirmed',
        'Your order has been confirmed.',
        completed: true,
      ),
      _step(
        'shipped',
        'Package shipped',
        'The package left the local Demo warehouse.',
        completed: true,
      ),
      _step(
        'out-for-delivery',
        'Out for delivery',
        'Your courier is making a delivery attempt today.',
        current: true,
      ),
    ],
    notification: <String, Object?>{
      'id': 'notification-1001',
      'kind': 'delivery_update',
      'title': 'Your order is arriving today',
      'message': 'A local Demo delivery attempt is in progress.',
      'isConsumed': false,
    },
  ),
  _orderFixture(
    id: 'order-1002',
    status: 'delivery_attempt_failed',
    imageNumber: 5,
    title: 'Classic shoulder bag',
    totalMinorUnits: 2800,
    steps: <Map<String, Object?>>[
      _step(
        'confirmed',
        'Order confirmed',
        'Your order has been confirmed.',
        completed: true,
      ),
      _step(
        'attempt-failed',
        'Delivery attempt was unsuccessful',
        'No action is required in this local Demo.',
        current: true,
      ),
    ],
    notification: <String, Object?>{
      'id': 'notification-1002',
      'kind': 'delivery_attempt_failed',
      'title': 'Delivery attempt update',
      'message': 'The courier could not complete this Demo delivery attempt.',
      'isConsumed': false,
    },
  ),
  _orderFixture(
    id: 'order-1003',
    status: 'delivered',
    imageNumber: 8,
    title: 'Everyday white sneakers',
    totalMinorUnits: 4600,
    steps: <Map<String, Object?>>[
      _step(
        'confirmed',
        'Order confirmed',
        'Your order has been confirmed.',
        completed: true,
      ),
      _step(
        'delivered',
        'Delivered',
        'The local Demo order was delivered.',
        completed: true,
        current: true,
      ),
    ],
  ),
  _orderFixture(
    id: 'order-1004',
    status: 'delivered',
    imageNumber: 11,
    title: 'Soft knit cardigan',
    totalMinorUnits: 5200,
    steps: <Map<String, Object?>>[
      _step(
        'confirmed',
        'Order confirmed',
        'Your order has been confirmed.',
        completed: true,
      ),
      _step(
        'delivered',
        'Delivered',
        'The local Demo order was delivered.',
        completed: true,
        current: true,
      ),
    ],
    review: <String, Object?>{
      'id': 'review-order-1004',
      'author': 'Demo Customer',
      'comment': 'Comfortable and exactly as shown.',
      'rating': 5,
      'publishedLabel': '2 days ago',
      'avatarAssetKey': null,
    },
  ),
];

Map<String, Object?> _orderFixture({
  required String id,
  required String status,
  required int imageNumber,
  required String title,
  required int totalMinorUnits,
  required List<Map<String, Object?>> steps,
  Map<String, Object?>? notification,
  Map<String, Object?>? review,
}) => <String, Object?>{
  'id': id,
  'receiptId': null,
  'placedAt':
      '2026-07-${(20 - imageNumber % 4).toString().padLeft(2, '0')}T09:30:00.000Z',
  'total': <String, Object?>{'currency': 'USD', 'minorUnits': totalMinorUnits},
  'shippingAddress': <String, Object?>{
    'id': 'shipping-home',
    'recipientName': 'Demo Customer',
    'streetLine': '42 Market Street',
    'city': 'San Francisco',
    'region': 'California',
    'postalCode': '94105',
    'country': 'United States',
  },
  'lines': <Object?>[
    <String, Object?>{
      'product': <String, Object?>{
        'id': 'product-$imageNumber',
        'title': title,
        'imageAssetKey':
            'assets/images/profile/product_${imageNumber.toString().padLeft(2, '0')}.png',
        'priceMinorUnits': totalMinorUnits,
        'currency': 'USD',
      },
      'quantity': 1,
      'unitPrice': <String, Object?>{
        'currency': 'USD',
        'minorUnits': totalMinorUnits,
      },
      'variationLabel': 'Blue / M',
    },
  ],
  'status': status,
  'steps': steps,
  'notification': notification,
  'review': review,
};

Map<String, Object?> _step(
  String id,
  String title,
  String description, {
  bool completed = false,
  bool current = false,
}) => <String, Object?>{
  'id': id,
  'title': title,
  'description': description,
  'isCompleted': completed,
  'isCurrent': current,
};

Map<String, Object?> _copyOrder(Map<String, Object?> order) =>
    Map<String, Object?>.of(order);

Map<String, Object?>? _map(Object? value) =>
    value is Map<String, Object?> ? value : null;
