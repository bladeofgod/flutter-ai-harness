import 'dart:async';

import 'package:app_data/app_data.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../api/wishlist_api.dart';

sealed class WishlistViewState {
  const WishlistViewState();
}

final class WishlistLoading extends WishlistViewState {
  const WishlistLoading();
}

final class WishlistData extends WishlistViewState {
  const WishlistData(this.overview);

  final WishlistOverview overview;
}

final class WishlistError extends WishlistViewState {
  const WishlistError(this.failure);

  final WishlistFailure failure;
}

/// 管理 Wishlist 加载、移除、空态与重试。
final class WishlistController extends GetxController {
  WishlistController({required WishlistApi wishlistApi})
    : _wishlistApi = wishlistApi;

  final WishlistApi _wishlistApi;
  final Rx<WishlistViewState> _viewState = Rx<WishlistViewState>(
    const WishlistLoading(),
  );
  final Set<String> _removingProductIds = <String>{};
  final Set<String> _removedProductIds = <String>{};
  StreamSubscription<WishlistOverview>? _snapshotSubscription;

  bool _isLoading = false;
  bool _isDisposed = false;

  WishlistViewState get viewState => _viewState.value;

  @override
  void onInit() {
    super.onInit();
    if (_wishlistApi case final WishlistSnapshotSource source) {
      _snapshotSubscription = source.snapshots.listen(_applyExternalSnapshot);
    }
    _startLoad();
  }

  void _applyExternalSnapshot(WishlistOverview overview) {
    if (_isDisposed) {
      return;
    }
    _removedProductIds.clear();
    _viewState.value = WishlistData(overview);
  }

  Future<void> load() async {
    if (_isLoading || _isDisposed) {
      return;
    }
    _isLoading = true;
    _viewState.value = const WishlistLoading();
    try {
      final overview = await _wishlistApi.loadWishlist();
      if (!_isDisposed) {
        _viewState.value = WishlistData(overview);
      }
    } on WishlistFailure catch (failure) {
      if (!_isDisposed) {
        _viewState.value = WishlistError(failure);
      }
    } finally {
      _isLoading = false;
    }
  }

  Future<void> remove(String productId) async {
    final current = _viewState.value;
    if (_isDisposed ||
        current is! WishlistData ||
        !_removingProductIds.add(productId)) {
      return;
    }
    final itemExists = current.overview.items.any(
      (item) => item.product.id == productId,
    );
    if (!itemExists) {
      _removingProductIds.remove(productId);
      return;
    }
    _removedProductIds.add(productId);

    _viewState.value = WishlistData(_withoutRemovedProducts(current.overview));
    try {
      final overview = await _wishlistApi.removeWishlistItem(productId);
      if (!_isDisposed) {
        _viewState.value = WishlistData(_withoutRemovedProducts(overview));
      }
    } on WishlistFailure catch (failure) {
      _removedProductIds.remove(productId);
      if (!_isDisposed) {
        _viewState.value = WishlistError(failure);
      }
    } finally {
      _removingProductIds.remove(productId);
    }
  }

  WishlistOverview _withoutRemovedProducts(WishlistOverview overview) =>
      WishlistOverview(
        items: overview.items
            .where((item) => !_removedProductIds.contains(item.product.id))
            .toList(growable: false),
        recentlyViewed: overview.recentlyViewed,
        recommendations: overview.recommendations,
      );

  Future<void> retry() => load();

  void retryFromUi() => _startLoad();

  void removeFromUi(String productId) {
    unawaited(
      _runAndReport(() => remove(productId), 'removing a Wishlist item'),
    );
  }

  void _startLoad() {
    unawaited(_runAndReport(load, 'loading Wishlist'));
  }

  Future<void> _runAndReport(
    Future<void> Function() operation,
    String context,
  ) async {
    try {
      await operation();
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'app_features',
          context: ErrorDescription('while $context'),
        ),
      );
    }
  }

  @override
  void onClose() {
    _isDisposed = true;
    unawaited(_snapshotSubscription?.cancel());
    _snapshotSubscription = null;
    _removingProductIds.clear();
    _removedProductIds.clear();
    super.onClose();
  }
}
