import 'package:app_data/app_data.dart' show ProductReview;
import 'package:app_data/orders.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import '../../shared/catalog/catalog_asset_image.dart';
import '../widgets/orders_components.dart';

final class OrderDetailPage extends StatelessWidget {
  const OrderDetailPage({
    required this.order,
    required this.onDismissNotification,
    required this.onReview,
    super.key,
  });

  final Order order;
  final VoidCallback onDismissNotification;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final notification = order.notification;
    return OrdersPageScaffold(
      title: _detailTitle(order.fulfillmentStatus),
      child: Stack(
        children: [
          CustomScrollView(
            key: const ValueKey('order-detail-scroll'),
            slivers: <Widget>[
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  notification != null && !notification.isConsumed ? 112 : 16,
                  20,
                  28,
                ),
                sliver: SliverList.list(
                  children: [
                    _OrderHeader(order: order),
                    const SizedBox(height: 22),
                    Text('Delivery progress', style: ordersHeading(size: 20)),
                    const SizedBox(height: 14),
                    _FulfillmentTimeline(steps: order.fulfillmentSteps),
                    const SizedBox(height: 22),
                    _ShippingSummary(order: order),
                    if (order.canReview) ...[
                      const SizedBox(height: 24),
                      OrdersPrimaryButton(
                        key: const ValueKey('order-open-review'),
                        label: 'Review order',
                        icon: Icons.star_outline,
                        onPressed: onReview,
                      ),
                    ] else if (order.review case final review?) ...[
                      const SizedBox(height: 24),
                      _ReviewSummary(review: review),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (notification != null && !notification.isConsumed)
            Positioned(
              left: 16,
              right: 16,
              top: 8,
              child: _DeliveryNotification(
                notification: notification,
                onDismiss: onDismissNotification,
              ),
            ),
        ],
      ),
    );
  }
}

final class _OrderHeader extends StatelessWidget {
  const _OrderHeader({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox.square(
          dimension: 88,
          child: CatalogAssetImage(
            assetKey: order.lines.first.product.imageAssetKey,
          ),
        ),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              order.lines.first.product.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: ordersHeading(size: 18),
            ),
            const SizedBox(height: 7),
            Text(
              '${order.lines.length} item${order.lines.length == 1 ? '' : 's'}',
              style: ordersBody(color: const Color(0xFF737373)),
            ),
            const SizedBox(height: 3),
            Text(order.total.format(), style: ordersHeading(size: 17)),
          ],
        ),
      ),
    ],
  );
}

final class _FulfillmentTimeline extends StatelessWidget {
  const _FulfillmentTimeline({required this.steps});

  final List<FulfillmentStep> steps;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var index = 0; index < steps.length; index += 1)
        _TimelineStep(
          step: steps[index],
          showConnector: index < steps.length - 1,
        ),
    ],
  );
}

final class _TimelineStep extends StatelessWidget {
  const _TimelineStep({required this.step, required this.showConnector});

  final FulfillmentStep step;
  final bool showConnector;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 28,
          child: Column(
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: step.isCompleted || step.isCurrent
                      ? AppColors.primary
                      : const Color(0xFFDADADA),
                ),
                child: step.isCompleted
                    ? const Icon(Icons.check, size: 12, color: Colors.white)
                    : null,
              ),
              if (showConnector)
                Expanded(
                  child: Container(
                    width: 2,
                    color: step.isCompleted
                        ? AppColors.primary
                        : const Color(0xFFE0E0E0),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.title, style: ordersHeading(size: 15)),
                const SizedBox(height: 4),
                Text(
                  step.description,
                  style: ordersBody(
                    size: 13,
                    height: 1.4,
                    color: const Color(0xFF707070),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

final class _ShippingSummary extends StatelessWidget {
  const _ShippingSummary({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Shipping address', style: ordersHeading(size: 15)),
          const SizedBox(height: 6),
          Text(
            order.shippingAddress.recipientName,
            style: ordersBody(weight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            order.shippingAddress.summary,
            style: ordersBody(size: 13, height: 1.4),
          ),
        ],
      ),
    ),
  );
}

final class _DeliveryNotification extends StatelessWidget {
  const _DeliveryNotification({
    required this.notification,
    required this.onDismiss,
  });

  final OrderNotification notification;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Semantics(
    key: const ValueKey('order-delivery-notification'),
    liveRegion: true,
    label: '${notification.title}. ${notification.message}',
    child: Material(
      elevation: 5,
      color: AppColors.primarySurface,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 3),
              child: Icon(
                Icons.local_shipping_outlined,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(notification.title, style: ordersHeading(size: 14)),
                  const SizedBox(height: 2),
                  Text(notification.message, style: ordersBody(size: 12)),
                ],
              ),
            ),
            IconButton(
              key: const ValueKey('order-dismiss-notification'),
              tooltip: 'Dismiss delivery update',
              onPressed: onDismiss,
              icon: const Icon(Icons.close, size: 19),
            ),
          ],
        ),
      ),
    ),
  );
}

final class _ReviewSummary extends StatelessWidget {
  const _ReviewSummary({required this.review});

  final ProductReview review;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your review', style: ordersHeading(size: 16)),
          const SizedBox(height: 6),
          Row(
            children: List<Widget>.generate(
              5,
              (index) => Icon(
                index < review.rating ? Icons.star : Icons.star_border,
                size: 18,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(review.comment, style: ordersBody(height: 1.4)),
        ],
      ),
    ),
  );
}

String _detailTitle(FulfillmentStatus status) => switch (status) {
  FulfillmentStatus.processing ||
  FulfillmentStatus.inTransit => 'To Receive Progress',
  FulfillmentStatus.outForDelivery => 'To Receive',
  FulfillmentStatus.deliveryAttemptFailed => 'Delivery Update',
  FulfillmentStatus.delivered => 'Delivered',
};
