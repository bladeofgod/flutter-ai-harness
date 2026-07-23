import '../catalog/catalog_models.dart';
import '../checkout/checkout_models.dart';

/// Profile 订单摘要的稳定三态，保留已有公共契约。
enum OrderStatus { toPay, toReceive, toReview }

final class OrderStatusSummary {
  const OrderStatusSummary({
    required this.status,
    this.hasNotification = false,
  });

  final OrderStatus status;
  final bool hasNotification;
}

final class OrderSummary {
  factory OrderSummary({required List<OrderStatusSummary> items}) =>
      OrderSummary._(List<OrderStatusSummary>.unmodifiable(items));

  const OrderSummary._(this.items);

  final List<OrderStatusSummary> items;
}

/// Activity 页的两个真实筛选视图。
enum ActivityFilter { activity, history }

/// 物流状态由数据驱动，同一订单详情 Route 渲染全部状态。
enum FulfillmentStatus {
  processing,
  inTransit,
  outForDelivery,
  deliveryAttemptFailed,
  delivered,
}

enum OrderNotificationKind { deliveryUpdate, deliveryAttemptFailed }

final class OrderLine {
  factory OrderLine({
    required ProductSummary product,
    required int quantity,
    required Money unitPrice,
    String? variationLabel,
  }) {
    if (quantity < 1) {
      throw ArgumentError.value(quantity, 'quantity', 'Must be positive.');
    }
    if (product.price != null &&
        product.price!.currency != unitPrice.currency) {
      throw ArgumentError('Product and order line currencies must match.');
    }
    return OrderLine._(
      product: product,
      quantity: quantity,
      unitPrice: unitPrice,
      variationLabel: _optionalText(variationLabel, 'variationLabel'),
    );
  }

  const OrderLine._({
    required this.product,
    required this.quantity,
    required this.unitPrice,
    required this.variationLabel,
  });

  final ProductSummary product;
  final int quantity;
  final Money unitPrice;
  final String? variationLabel;
}

final class FulfillmentStep {
  factory FulfillmentStep({
    required String id,
    required String title,
    required String description,
    required bool isCompleted,
    required bool isCurrent,
  }) => FulfillmentStep._(
    id: _requiredText(id, 'id'),
    title: _requiredText(title, 'title'),
    description: _requiredText(description, 'description'),
    isCompleted: isCompleted,
    isCurrent: isCurrent,
  );

  const FulfillmentStep._({
    required this.id,
    required this.title,
    required this.description,
    required this.isCompleted,
    required this.isCurrent,
  });

  final String id;
  final String title;
  final String description;
  final bool isCompleted;
  final bool isCurrent;
}

final class OrderNotification {
  factory OrderNotification({
    required String id,
    required OrderNotificationKind kind,
    required String title,
    required String message,
    bool isConsumed = false,
  }) => OrderNotification._(
    id: _requiredText(id, 'id'),
    kind: kind,
    title: _requiredText(title, 'title'),
    message: _requiredText(message, 'message'),
    isConsumed: isConsumed,
  );

  const OrderNotification._({
    required this.id,
    required this.kind,
    required this.title,
    required this.message,
    required this.isConsumed,
  });

  final String id;
  final OrderNotificationKind kind;
  final String title;
  final String message;
  final bool isConsumed;
}

final class Order {
  factory Order({
    required String id,
    required String? receiptId,
    required DateTime placedAt,
    required Money total,
    required ShippingAddress shippingAddress,
    required List<OrderLine> lines,
    required FulfillmentStatus fulfillmentStatus,
    required List<FulfillmentStep> fulfillmentSteps,
    OrderNotification? notification,
    ProductReview? review,
  }) {
    if (lines.isEmpty) {
      throw ArgumentError.value(lines, 'lines', 'Order must have a line.');
    }
    if (lines.any((line) => line.unitPrice.currency != total.currency)) {
      throw ArgumentError('Order amounts must use one currency.');
    }
    final stepIds = <String>{};
    for (final step in fulfillmentSteps) {
      if (!stepIds.add(step.id)) {
        throw ArgumentError.value(
          fulfillmentSteps,
          'fulfillmentSteps',
          'Step ids must be unique.',
        );
      }
    }
    if (fulfillmentSteps.where((step) => step.isCurrent).length > 1) {
      throw ArgumentError('Only one fulfillment step may be current.');
    }
    return Order._(
      id: _requiredText(id, 'id'),
      receiptId: _optionalText(receiptId, 'receiptId'),
      placedAt: placedAt.toUtc(),
      total: total,
      shippingAddress: shippingAddress,
      lines: List<OrderLine>.unmodifiable(lines),
      fulfillmentStatus: fulfillmentStatus,
      fulfillmentSteps: List<FulfillmentStep>.unmodifiable(fulfillmentSteps),
      notification: notification,
      review: review,
    );
  }

  const Order._({
    required this.id,
    required this.receiptId,
    required this.placedAt,
    required this.total,
    required this.shippingAddress,
    required this.lines,
    required this.fulfillmentStatus,
    required this.fulfillmentSteps,
    required this.notification,
    required this.review,
  });

  final String id;
  final String? receiptId;
  final DateTime placedAt;
  final Money total;
  final ShippingAddress shippingAddress;
  final List<OrderLine> lines;
  final FulfillmentStatus fulfillmentStatus;
  final List<FulfillmentStep> fulfillmentSteps;
  final OrderNotification? notification;
  final ProductReview? review;

  bool get isHistory => fulfillmentStatus == FulfillmentStatus.delivered;
  bool get canReview => isHistory && review == null;
}

String _requiredText(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, 'Value must not be empty.');
  }
  return normalized;
}

String? _optionalText(String? value, String name) =>
    value == null ? null : _requiredText(value, name);
