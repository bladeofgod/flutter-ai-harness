import 'dart:async';

import 'package:app_data/app_data.dart';

import '../../api/wishlist_api.dart';

/// 通过本地数据源实现 Wishlist 进程内能力。
final class LocalWishlistApi implements WishlistApi, WishlistSnapshotSource {
  LocalWishlistApi({required WishlistLocalDataSource dataSource})
    : _dataSource = dataSource;

  final WishlistLocalDataSource _dataSource;
  final StreamController<WishlistOverview> _snapshotController =
      StreamController<WishlistOverview>.broadcast(sync: true);

  @override
  Stream<WishlistOverview> get snapshots => _snapshotController.stream;

  @override
  Future<WishlistOverview> loadWishlist() => _dataSource.loadWishlist();

  @override
  Future<WishlistOverview> addWishlistItem({
    required ProductSummary product,
    required String color,
    required String size,
  }) async {
    final overview = await _dataSource.addWishlistItem(
      product: product,
      color: color,
      size: size,
    );
    _snapshotController.add(overview);
    return overview;
  }

  @override
  Future<RecentlyViewedSnapshot> loadRecentlyViewed() =>
      _dataSource.loadRecentlyViewed();

  @override
  Future<WishlistOverview> removeWishlistItem(String productId) async {
    final overview = await _dataSource.removeWishlistItem(productId);
    _snapshotController.add(overview);
    return overview;
  }
}
