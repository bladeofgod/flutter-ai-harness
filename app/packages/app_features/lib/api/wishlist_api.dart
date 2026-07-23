import 'dart:async';

import 'package:app_data/app_data.dart';

/// Wishlist 向 Product/Cart 流程暴露的稳定 ID 回调边界。
final class WishlistProductActions {
  const WishlistProductActions({
    this.onOpenProduct,
    this.onAddToCart,
    this.onAddItemToCart,
    this.onSeeAllRecommendations,
  });

  final void Function(String productId)? onOpenProduct;
  final void Function(String productId)? onAddToCart;
  final Future<void> Function(WishlistItem item)? onAddItemToCart;
  final void Function()? onSeeAllRecommendations;
}

/// Wishlist 与 Recently Viewed 当前消费的窄业务边界。
abstract interface class WishlistApi {
  Future<WishlistOverview> loadWishlist();

  Future<WishlistOverview> addWishlistItem({
    required ProductSummary product,
    required String color,
    required String size,
  });

  Future<WishlistOverview> removeWishlistItem(String productId);

  Future<RecentlyViewedSnapshot> loadRecentlyViewed();
}

/// 可选的进程内变更流，让保活页面同步反映其他 Feature 的成功 mutation。
abstract interface class WishlistSnapshotSource {
  Stream<WishlistOverview> get snapshots;
}
