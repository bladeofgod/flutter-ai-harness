import 'dart:async';

import 'package:app_data/app_data.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../api/wishlist_api.dart';
import '../../shared/catalog/catalog_components.dart';
import '../controllers/wishlist_controller.dart';
import '../widgets/wishlist_components.dart';

const _wishlistContentMaxWidth = 420.0;

final class WishlistPage extends StatelessWidget {
  const WishlistPage({
    required this.controller,
    required this.onOpenRecentlyViewed,
    this.productActions = const WishlistProductActions(),
    super.key,
  });

  final WishlistController controller;
  final VoidCallback onOpenRecentlyViewed;
  final WishlistProductActions productActions;

  @override
  Widget build(BuildContext context) => GetBuilder<WishlistController>(
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
            WishlistLoading() => const Center(
              child: CircularProgressIndicator(
                key: ValueKey('wishlist-loading'),
              ),
            ),
            WishlistData(:final overview) => _WishlistContent(
              overview: overview,
              controller: managedController,
              onOpenRecentlyViewed: onOpenRecentlyViewed,
              productActions: productActions,
            ),
            WishlistError() => WishlistFailureView(
              onRetry: managedController.retryFromUi,
            ),
          };
        }),
      ),
    ),
  );
}

final class _WishlistContent extends StatelessWidget {
  const _WishlistContent({
    required this.overview,
    required this.controller,
    required this.onOpenRecentlyViewed,
    required this.productActions,
  });

  final WishlistOverview overview;
  final WishlistController controller;
  final VoidCallback onOpenRecentlyViewed;
  final WishlistProductActions productActions;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    key: const ValueKey('wishlist-scroll'),
    slivers: [
      _WishlistSliver(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
        child: Text(
          'Wishlist',
          style: wishlistRaleway(size: 28, height: 36 / 28),
        ),
      ),
      _WishlistSliver(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        child: WishlistRecentlyViewedRail(
          products: overview.recentlyViewed,
          onOpen: onOpenRecentlyViewed,
        ),
      ),
      if (overview.items.isEmpty) ...[
        const _WishlistSliver(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: WishlistEmptyVisual(),
        ),
        _WishlistSliver(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: CatalogSectionHeader(
            title: 'Most Popular',
            trailing: TextButton.icon(
              key: const ValueKey('wishlist-see-all-recommendations'),
              onPressed: () => _invokeAction(
                context,
                productActions.onSeeAllRecommendations,
                'More recommendations are not available in this demo yet.',
              ),
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: const Text('See All'),
            ),
          ),
        ),
        _WishlistSliver(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: _Recommendations(
            products: overview.recommendations,
            onOpenProduct: (productId) => _invokeProductAction(
              context,
              productId,
              productActions.onOpenProduct,
              'Product details are not available in this demo yet.',
            ),
          ),
        ),
      ] else
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            _wishlistSidePadding(context),
            8,
            _wishlistSidePadding(context),
            28,
          ),
          sliver: SliverList.separated(
            itemCount: overview.items.length,
            separatorBuilder: (context, index) => const SizedBox(height: 9),
            itemBuilder: (context, index) {
              final item = overview.items[index];
              return WishlistItemCard(
                item: item,
                onRemove: () => controller.removeFromUi(item.product.id),
                onOpenProduct: () => _invokeProductAction(
                  context,
                  item.product.id,
                  productActions.onOpenProduct,
                  'Product details are not available in this demo yet.',
                ),
                onAddToCart: () =>
                    unawaited(_invokeAddToCart(context, item, productActions)),
              );
            },
          ),
        ),
    ],
  );
}

Future<void> _invokeAddToCart(
  BuildContext context,
  WishlistItem item,
  WishlistProductActions actions,
) async {
  try {
    if (actions.onAddItemToCart case final addItem?) {
      await addItem(item);
    } else if (actions.onAddToCart case final addProduct?) {
      addProduct(item.product.id);
    } else {
      throw StateError('Wishlist Cart action is not configured.');
    }
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Added to cart')));
  } on Object catch (_) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Could not add this item to cart.')),
      );
  }
}

void _invokeAction(
  BuildContext context,
  void Function()? action,
  String unavailableMessage,
) {
  if (action != null) {
    action();
    return;
  }
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(unavailableMessage)));
}

void _invokeProductAction(
  BuildContext context,
  String productId,
  void Function(String productId)? action,
  String unavailableMessage,
) {
  if (action != null) {
    action(productId);
    return;
  }
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(unavailableMessage)));
}

double _wishlistSidePadding(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  return width > _wishlistContentMaxWidth
      ? (width - _wishlistContentMaxWidth) / 2 + 20
      : 20;
}

final class _WishlistSliver extends StatelessWidget {
  const _WishlistSliver({required this.child, required this.padding});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _wishlistContentMaxWidth),
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}

final class _Recommendations extends StatelessWidget {
  const _Recommendations({required this.products, required this.onOpenProduct});

  final List<ProductSummary> products;
  final ValueChanged<String> onOpenProduct;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const CatalogEmptySection(label: 'No recommendations available.');
    }
    return SizedBox(
      height: 162,
      child: ListView.separated(
        key: const ValueKey('wishlist-recommendations'),
        scrollDirection: Axis.horizontal,
        itemCount: products.length,
        separatorBuilder: (context, index) => const SizedBox(width: 7),
        itemBuilder: (context, index) => Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey<String>(
              'wishlist-recommendation-${products[index].id}',
            ),
            borderRadius: BorderRadius.circular(9),
            onTap: () => onOpenProduct(products[index].id),
            child: CatalogPopularCard(
              product: products[index],
              countSize: 15,
              tagSize: 13,
              imageHeight: 112,
              imagePadding: const EdgeInsets.all(5),
              frameImage: true,
              showFavorite: true,
            ),
          ),
        ),
      ),
    );
  }
}
