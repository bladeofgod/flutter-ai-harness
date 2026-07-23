import 'package:app_data/orders.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import '../../shared/catalog/catalog_asset_image.dart';
import '../widgets/orders_components.dart';

final class OrdersActivityPage extends StatelessWidget {
  const OrdersActivityPage({
    required this.filter,
    required this.orders,
    required this.onSelectFilter,
    required this.onOpenOrder,
    super.key,
  });

  final ActivityFilter filter;
  final List<Order> orders;
  final ValueChanged<ActivityFilter> onSelectFilter;
  final ValueChanged<String> onOpenOrder;

  @override
  Widget build(BuildContext context) => OrdersPageScaffold(
    title: 'My Activity',
    child: CustomScrollView(
      key: const ValueKey('orders-activity-scroll'),
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          sliver: SliverToBoxAdapter(
            child: _ActivityFilterBar(
              selected: filter,
              onSelected: onSelectFilter,
            ),
          ),
        ),
        if (orders.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.receipt_long_outlined,
                      size: 52,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      filter == ActivityFilter.activity
                          ? 'No active orders'
                          : 'No order history',
                      style: ordersHeading(size: 19),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Completed Demo checkouts will appear here.',
                      textAlign: TextAlign.center,
                      style: ordersBody(color: const Color(0xFF707070)),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            sliver: SliverList.separated(
              itemCount: orders.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final order = orders[index];
                return _OrderActivityCard(
                  key: ValueKey('activity-order-${order.id}'),
                  order: order,
                  onTap: () => onOpenOrder(order.id),
                );
              },
            ),
          ),
      ],
    ),
  );
}

final class _ActivityFilterBar extends StatelessWidget {
  const _ActivityFilterBar({required this.selected, required this.onSelected});

  final ActivityFilter selected;
  final ValueChanged<ActivityFilter> onSelected;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        for (final filter in ActivityFilter.values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: TextButton(
                key: ValueKey('activity-filter-${filter.name}'),
                onPressed: () => onSelected(filter),
                style: TextButton.styleFrom(
                  backgroundColor: filter == selected
                      ? AppColors.primary
                      : Colors.transparent,
                  foregroundColor: filter == selected
                      ? AppColors.textOnPrimary
                      : AppColors.textPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: Text(
                  filter == ActivityFilter.activity ? 'Activity' : 'History',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

final class _OrderActivityCard extends StatelessWidget {
  const _OrderActivityCard({
    required this.order,
    required this.onTap,
    super.key,
  });

  final Order order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final notification = order.notification;
    return Semantics(
      button: true,
      label: 'Order ${order.id}, ${_statusLabel(order.fulfillmentStatus)}',
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        elevation: 1,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: SizedBox.square(
                    dimension: 72,
                    child: CatalogAssetImage(
                      assetKey: order.lines.first.product.imageAssetKey,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              order.lines.first.product.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ordersHeading(size: 15),
                            ),
                          ),
                          if (notification != null && !notification.isConsumed)
                            const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: CircleAvatar(
                                key: ValueKey('order-update-badge'),
                                radius: 5,
                                backgroundColor: AppColors.success,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _statusLabel(order.fulfillmentStatus),
                        style: ordersBody(
                          size: 13,
                          weight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${order.id}  ·  ${order.total.format()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ordersBody(
                          size: 12,
                          color: const Color(0xFF777777),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, color: AppColors.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _statusLabel(FulfillmentStatus status) => switch (status) {
  FulfillmentStatus.processing => 'Processing',
  FulfillmentStatus.inTransit => 'In transit',
  FulfillmentStatus.outForDelivery => 'To receive',
  FulfillmentStatus.deliveryAttemptFailed => 'Attempt unsuccessful',
  FulfillmentStatus.delivered => 'Delivered',
};
