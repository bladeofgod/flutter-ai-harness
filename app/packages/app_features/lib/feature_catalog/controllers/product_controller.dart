import 'dart:async';

import 'package:app_data/app_data.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../api/cart_api.dart';
import '../../api/catalog_api.dart';
import '../../api/wishlist_api.dart';

sealed class ProductViewState {
  const ProductViewState();
}

final class ProductLoading extends ProductViewState {
  const ProductLoading();
}

final class ProductData extends ProductViewState {
  const ProductData(this.detail);

  final ProductDetail detail;
}

final class ProductError extends ProductViewState {
  const ProductError(this.failure);

  final CatalogFailure failure;
}

/// 管理商品详情读取、规格确认、收藏和加入购物车。
final class ProductController extends GetxController {
  ProductController({
    required ProductApi productApi,
    required WishlistApi wishlistApi,
    required CartApi cartApi,
    required this.productId,
  }) : _productApi = productApi,
       _wishlistApi = wishlistApi,
       _cartApi = cartApi;

  final ProductApi _productApi;
  final WishlistApi _wishlistApi;
  final CartApi _cartApi;
  final String productId;

  final Rx<ProductViewState> _viewState = Rx<ProductViewState>(
    const ProductLoading(),
  );
  final RxInt galleryIndex = 0.obs;
  final RxInt selectionRevision = 0.obs;
  final RxBool isFavorite = false.obs;
  final RxBool isMutating = false.obs;
  final RxnString selectionError = RxnString();

  Map<String, String> _confirmedSelection = <String, String>{};
  bool _isLoading = false;
  bool _isDisposed = false;

  ProductViewState get viewState => _viewState.value;
  Map<String, String> get confirmedSelection =>
      Map<String, String>.unmodifiable(_confirmedSelection);

  @override
  void onInit() {
    super.onInit();
    _startLoad();
  }

  Future<void> load() async {
    if (_isLoading || _isDisposed) {
      return;
    }
    _isLoading = true;
    _viewState.value = const ProductLoading();
    try {
      final detail = await _productApi.loadProductDetail(productId);
      if (_isDisposed) {
        return;
      }
      try {
        final wishlist = await _wishlistApi.loadWishlist();
        isFavorite.value = wishlist.items.any(
          (item) => item.product.id == detail.product.id,
        );
      } on WishlistFailure {
        // A detail page remains useful when the optional wishlist source fails.
        isFavorite.value = false;
      }
      _viewState.value = ProductData(detail);
    } on CatalogFailure catch (failure) {
      if (!_isDisposed) {
        _viewState.value = ProductError(failure);
      }
    } finally {
      _isLoading = false;
    }
  }

  void setGalleryIndex(int index) {
    final current = _viewState.value;
    if (current is ProductData &&
        index >= 0 &&
        index < current.detail.gallery.length) {
      galleryIndex.value = index;
    }
  }

  bool confirmSelection(Map<String, String> selection) {
    final current = _viewState.value;
    if (current is! ProductData) {
      return false;
    }
    final missing = current.detail.optionGroups
        .where(
          (group) => group.required && !_hasOption(group, selection[group.id]),
        )
        .map((group) => group.label)
        .toList(growable: false);
    if (missing.isNotEmpty) {
      selectionError.value = 'Please select ${missing.join(' and ')}.';
      return false;
    }
    _confirmedSelection = Map<String, String>.from(selection);
    selectionRevision.value += 1;
    selectionError.value = null;
    return true;
  }

  void clearSelectionError() => selectionError.value = null;

  void resetDraftSelection() => selectionError.value = null;

  Future<bool> toggleFavorite() async {
    final current = _viewState.value;
    if (current is! ProductData || isMutating.value || _isDisposed) {
      return false;
    }
    isMutating.value = true;
    try {
      final overview = isFavorite.value
          ? await _wishlistApi.removeWishlistItem(current.detail.product.id)
          : await _wishlistApi.addWishlistItem(
              product: current.detail.product,
              color: _selectedLabel(current.detail, 'color') ?? 'Pink',
              size: _selectedLabel(current.detail, 'size') ?? 'M',
            );
      if (!_isDisposed) {
        isFavorite.value = overview.items.any(
          (item) => item.product.id == current.detail.product.id,
        );
      }
      return true;
    } on WishlistFailure catch (failure) {
      if (!_isDisposed) {
        _reportFailure(failure);
      }
      return false;
    } finally {
      isMutating.value = false;
    }
  }

  Future<bool> addToCart() async {
    final current = _viewState.value;
    if (current is! ProductData || isMutating.value || _isDisposed) {
      return false;
    }
    final variation = _toVariation(current.detail);
    if (variation == null) {
      selectionError.value = 'Please select Color and Size.';
      return false;
    }
    isMutating.value = true;
    try {
      await _cartApi.upsert(
        CartLineInput(product: current.detail.product, variation: variation),
      );
      return true;
    } on CartFailure catch (failure) {
      if (!_isDisposed) {
        _reportFailure(failure);
      }
      return false;
    } finally {
      isMutating.value = false;
    }
  }

  ProductVariation? _toVariation(ProductDetail detail) {
    final color = _selectedLabel(detail, 'color');
    final size = _selectedLabel(detail, 'size');
    if (color == null || size == null) {
      return null;
    }
    return ProductVariation(color: color, size: size);
  }

  String? _selectedLabel(ProductDetail detail, String groupId) {
    final selectedId = _confirmedSelection[groupId];
    if (selectedId == null) {
      return null;
    }
    for (final group in detail.optionGroups) {
      if (group.id != groupId) {
        continue;
      }
      for (final option in group.options) {
        if (option.id == selectedId) {
          return option.label;
        }
      }
    }
    return null;
  }

  bool _hasOption(ProductOptionGroup group, String? selectedId) =>
      selectedId != null &&
      group.options.any((option) => option.id == selectedId);

  void _reportFailure(Object failure) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: failure,
        library: 'app_features',
        context: ErrorDescription('while updating a Product detail'),
      ),
    );
  }

  void _startLoad() {
    unawaited(_runAndReport(load, 'loading a Product detail'));
  }

  Future<void> retry() => load();

  void retryFromUi() => _startLoad();

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
    _confirmedSelection = <String, String>{};
    super.onClose();
  }
}
