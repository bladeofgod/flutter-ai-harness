import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../api/wishlist_api.dart';
import '../../shared/catalog/catalog_components.dart';
import '../controllers/recently_viewed_controller.dart';
import '../widgets/recently_viewed_calendar.dart';
import '../widgets/wishlist_components.dart';

const _recentContentMaxWidth = 420.0;

final class RecentlyViewedPage extends StatelessWidget {
  const RecentlyViewedPage({
    required this.controller,
    this.productActions = const WishlistProductActions(),
    super.key,
  });

  final RecentlyViewedController controller;
  final WishlistProductActions productActions;

  @override
  Widget build(BuildContext context) => GetBuilder<RecentlyViewedController>(
    init: controller,
    global: false,
    autoRemove: false,
    dispose: (state) => state.controller.onDelete(),
    builder: (managedController) => Scaffold(
      body: SafeArea(
        bottom: false,
        child: Obx(() {
          final state = managedController.viewState;
          return switch (state) {
            RecentlyViewedLoading() => const Center(
              child: CircularProgressIndicator(
                key: ValueKey('recently-viewed-loading'),
              ),
            ),
            RecentlyViewedData() => PopScope(
              canPop: !state.isCalendarOpen,
              onPopInvokedWithResult: (didPop, result) {
                if (!didPop) {
                  managedController.cancelCalendar();
                }
              },
              child: _RecentlyViewedContent(
                data: state,
                controller: managedController,
                productActions: productActions,
              ),
            ),
            RecentlyViewedError() => WishlistFailureView(
              onRetry: managedController.retryFromUi,
            ),
          };
        }),
      ),
    ),
  );
}

final class _RecentlyViewedContent extends StatelessWidget {
  const _RecentlyViewedContent({
    required this.data,
    required this.controller,
    required this.productActions,
  });

  final RecentlyViewedData data;
  final RecentlyViewedController controller;
  final WishlistProductActions productActions;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    key: const ValueKey('recently-viewed-scroll'),
    slivers: [
      _RecentSliver(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
        child: Text(
          'Recently viewed',
          style: wishlistRaleway(size: 28, height: 36 / 28),
        ),
      ),
      if (data.isCalendarOpen)
        _RecentSliver(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          child: RecentlyViewedCalendar(data: data, controller: controller),
        )
      else
        _RecentSliver(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          child: _DateFilters(data: data, controller: controller),
        ),
      if (data.visibleItems.isEmpty)
        const _RecentSliver(
          padding: EdgeInsets.fromLTRB(20, 40, 20, 28),
          child: CatalogEmptySection(label: 'No items viewed on this date.'),
        )
      else
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            _recentSidePadding(context),
            0,
            _recentSidePadding(context),
            28,
          ),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              crossAxisSpacing: 10,
              mainAxisSpacing: 14,
              childAspectRatio: 0.67,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final item = data.visibleItems[index];
              return Semantics(
                button: true,
                label: 'Open ${item.product.title}',
                child: GestureDetector(
                  key: ValueKey<String>('recent-product-${item.id}'),
                  onTap: () => _invokeProductAction(
                    context,
                    item.product.id,
                    productActions.onOpenProduct,
                  ),
                  child: CatalogRecommendationCard(
                    product: item.product,
                    borderRadius: 8,
                  ),
                ),
              );
            }, childCount: data.visibleItems.length),
          ),
        ),
    ],
  );
}

void _invokeProductAction(
  BuildContext context,
  String productId,
  void Function(String productId)? action,
) {
  if (action != null) {
    action(productId);
    return;
  }
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(
        content: Text('Product details are not available in this demo yet.'),
      ),
    );
}

final class _DateFilters extends StatelessWidget {
  const _DateFilters({required this.data, required this.controller});

  final RecentlyViewedData data;
  final RecentlyViewedController controller;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: WishlistDateChip(
          key: const ValueKey('recent-filter-today'),
          label: 'Today',
          isSelected: data.isToday,
          showCheck: data.isToday,
          onPressed: controller.selectToday,
        ),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: WishlistDateChip(
          key: const ValueKey('recent-filter-secondary'),
          label: data.isToday || data.isYesterday
              ? 'Yesterday'
              : '${_monthNames[data.selectedDate.month - 1]}, '
                    '${data.selectedDate.day}',
          isSelected: !data.isToday,
          showCheck: !data.isToday,
          onPressed: data.isToday
              ? controller.selectYesterday
              : data.isYesterday
              ? controller.selectYesterday
              : controller.openCalendar,
        ),
      ),
      const SizedBox(width: 6),
      IconButton.filled(
        key: const ValueKey('open-date-calendar'),
        tooltip: 'Choose a date',
        onPressed: controller.openCalendar,
        icon: const Icon(Icons.keyboard_arrow_down),
        style: IconButton.styleFrom(
          backgroundColor: const Color(0xFF004CFF),
          foregroundColor: Colors.white,
          fixedSize: const Size.square(36),
          minimumSize: const Size.square(36),
          padding: EdgeInsets.zero,
        ),
      ),
    ],
  );
}

const _monthNames = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

double _recentSidePadding(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  return width > _recentContentMaxWidth
      ? (width - _recentContentMaxWidth) / 2 + 20
      : 20;
}

final class _RecentSliver extends StatelessWidget {
  const _RecentSliver({required this.child, required this.padding});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _recentContentMaxWidth),
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}
