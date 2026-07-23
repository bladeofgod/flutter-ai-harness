import 'package:app_core/app_core.dart';

import '../catalog/catalog_fixture.dart';
import '../fixture/fixture_api_transport.dart';

/// Wishlist 请求、进程内状态与 Fixture Payload 的唯一所有者。
final class WishlistFixtureHandler implements FixtureRequestHandler {
  static const String loadWishlistKey = 'wishlist.overview.load';
  static const String addWishlistItemKey = 'wishlist.item.add';
  static const String removeWishlistItemKey = 'wishlist.item.remove';
  static const String loadRecentlyViewedKey = 'wishlist.recently_viewed.load';

  final List<String> _wishlistProductIds = <String>[
    'product-1',
    'product-2',
    'product-3',
    'product-4',
    'product-5',
  ];

  void resetSession() {
    _wishlistProductIds
      ..clear()
      ..addAll(const <String>[
        'product-1',
        'product-2',
        'product-3',
        'product-4',
        'product-5',
      ]);
  }

  @override
  Set<String> get requestKeys => const <String>{
    loadWishlistKey,
    addWishlistItemKey,
    removeWishlistItemKey,
    loadRecentlyViewedKey,
  };

  @override
  Future<ApiResponse<Object?>> handle(ApiRequest request) async =>
      switch (request.key) {
        loadWishlistKey => ApiResponse<Object?>.success(_wishlistPayload()),
        addWishlistItemKey => _addWishlistItem(request.payload),
        removeWishlistItemKey => _removeWishlistItem(request.payload),
        loadRecentlyViewedKey => ApiResponse<Object?>.success(
          _recentlyViewedPayload(),
        ),
        _ => throw UnknownApiRequestException(request.key),
      };

  ApiResponse<Object?> _removeWishlistItem(Object? payload) {
    final productId = payload is Map<String, Object?>
        ? payload['productId']
        : null;
    if (productId is! String || productId.trim().isEmpty) {
      return const ApiResponse<Object?>.failure(
        ApiFailure.rejected(code: 'wishlist.invalid_request'),
      );
    }
    _wishlistProductIds.remove(canonicalCatalogProductId(productId));
    return ApiResponse<Object?>.success(_wishlistPayload());
  }

  ApiResponse<Object?> _addWishlistItem(Object? payload) {
    if (payload is! Map<String, Object?> ||
        payload['product'] is! Map<String, Object?> ||
        payload['color'] is! String ||
        payload['size'] is! String) {
      return const ApiResponse<Object?>.failure(
        ApiFailure.rejected(code: 'wishlist.invalid_request'),
      );
    }
    final product = payload['product']! as Map<String, Object?>;
    final productId = product['id'];
    if (productId is! String || productId.trim().isEmpty) {
      return const ApiResponse<Object?>.failure(
        ApiFailure.rejected(code: 'wishlist.invalid_request'),
      );
    }
    final canonicalId = canonicalCatalogProductId(productId);
    if (!_wishlistProductIds.contains(canonicalId)) {
      _wishlistProductIds.add(canonicalId);
    }
    return ApiResponse<Object?>.success(_wishlistPayload());
  }

  Map<String, Object?> _wishlistPayload() => <String, Object?>{
    'items': <Map<String, Object?>>[
      for (final id in _wishlistProductIds) _wishlistItemPayload(id),
    ],
    'recentlyViewed': <Map<String, Object?>>[
      _productPayload(
        id: 'recent-preview-1',
        imageAssetKey: 'assets/images/profile/recent_01.png',
      ),
      _productPayload(
        id: 'recent-preview-2',
        imageAssetKey: 'assets/images/profile/recent_02.png',
      ),
      _productPayload(
        id: 'recent-preview-3',
        imageAssetKey: 'assets/images/profile/recent_03.png',
      ),
      _productPayload(
        id: 'recent-preview-4',
        imageAssetKey: 'assets/images/profile/recent_04.png',
      ),
      _productPayload(
        id: 'recent-preview-5',
        imageAssetKey: 'assets/images/profile/recent_05.png',
      ),
    ],
    'recommendations': <Map<String, Object?>>[
      _productPayload(
        id: 'product-3',
        title: 'Relaxed blue hoodie',
        imageAssetKey: 'assets/images/profile/product_03.png',
        popularityCount: 1780,
        tag: 'New',
      ),
      _productPayload(
        id: 'product-4',
        imageAssetKey: 'assets/images/profile/product_04.png',
        popularityCount: 1780,
        tag: 'Sale',
      ),
      _productPayload(
        id: 'product-5',
        imageAssetKey: 'assets/images/profile/product_05.png',
        popularityCount: 1780,
        tag: 'Hot',
      ),
      _productPayload(
        id: 'product-6',
        imageAssetKey: 'assets/images/profile/product_03.png',
        popularityCount: 1780,
        tag: 'Hot',
      ),
    ],
  };

  Map<String, Object?> _recentlyViewedPayload() => <String, Object?>{
    'referenceDate': _datePayload(2026, 4, 19),
    'items': <Map<String, Object?>>[
      _recentItem(
        id: 'recent-1',
        productId: 'recent-product-1',
        imageAssetKey: 'assets/images/catalog/products/shop_product_03.png',
        viewedOn: _datePayload(2026, 4, 19),
      ),
      _recentItem(
        id: 'recent-2',
        productId: 'recent-product-2',
        imageAssetKey: 'assets/images/catalog/products/shop_product_05.png',
        viewedOn: _datePayload(2026, 4, 19),
      ),
      _recentItem(
        id: 'recent-3',
        productId: 'recent-product-3',
        imageAssetKey: 'assets/images/profile/product_04.png',
        viewedOn: _datePayload(2026, 4, 19),
      ),
      _recentItem(
        id: 'recent-4',
        productId: 'recent-product-4',
        imageAssetKey: 'assets/images/profile/product_11.png',
        viewedOn: _datePayload(2026, 4, 19),
      ),
      _recentItem(
        id: 'recent-5',
        productId: 'recent-product-5',
        imageAssetKey: 'assets/images/wishlist/recent_pink_dress.png',
        viewedOn: _datePayload(2026, 4, 19),
      ),
      _recentItem(
        id: 'recent-6',
        productId: 'recent-product-6',
        imageAssetKey: 'assets/images/profile/product_03.png',
        viewedOn: _datePayload(2026, 4, 19),
      ),
      _recentItem(
        id: 'recent-7',
        productId: 'recent-product-2',
        imageAssetKey: 'assets/images/catalog/products/shop_product_05.png',
        viewedOn: _datePayload(2026, 4, 18),
      ),
      _recentItem(
        id: 'recent-8',
        productId: 'recent-product-3',
        imageAssetKey: 'assets/images/profile/product_04.png',
        viewedOn: _datePayload(2026, 4, 18),
      ),
      _recentItem(
        id: 'recent-9',
        productId: 'recent-product-7',
        imageAssetKey: 'assets/images/wishlist/recent_hat.png',
        viewedOn: _datePayload(2026, 4, 18),
      ),
      _recentItem(
        id: 'recent-10',
        productId: 'recent-product-5',
        imageAssetKey: 'assets/images/wishlist/recent_pink_dress.png',
        viewedOn: _datePayload(2026, 4, 18),
      ),
      _recentItem(
        id: 'recent-11',
        productId: 'recent-product-8',
        imageAssetKey: 'assets/images/wishlist/recent_red_dress.png',
        viewedOn: _datePayload(2026, 4, 18),
      ),
      _recentItem(
        id: 'recent-12',
        productId: 'recent-product-6',
        imageAssetKey: 'assets/images/profile/product_03.png',
        viewedOn: _datePayload(2026, 4, 18),
      ),
    ],
  };

  Map<String, Object?> _wishlistItemPayload(String productId) {
    final canonicalId = canonicalCatalogProductId(productId);
    final index = int.tryParse(canonicalId.split('-').last) ?? 1;
    final product = canonicalCatalogProductPayload(canonicalId);
    return <String, Object?>{
      'product': _productPayload(
        id: canonicalId,
        title: product['title']! as String,
        imageAssetKey: product['imageAssetKey']! as String,
        priceMinorUnits: product['priceMinorUnits']! as int,
      ),
      'color': 'Pink',
      'size': 'M',
      if (index == 2) ...<String, Object?>{
        'originalPriceMinorUnits': 2500,
        'originalPriceCurrency': 'USD',
      },
    };
  }
}

Map<String, Object?> _recentItem({
  required String id,
  required String productId,
  required String imageAssetKey,
  required Map<String, Object?> viewedOn,
}) => <String, Object?>{
  'id': id,
  'product': () {
    final product = canonicalCatalogProductPayload(productId);
    return _productPayload(
      id: product['id']! as String,
      title: product['title']! as String,
      imageAssetKey: product['imageAssetKey']! as String,
      priceMinorUnits: product['priceMinorUnits']! as int,
    );
  }(),
  'viewedOn': viewedOn,
};

Map<String, Object?> _productPayload({
  required String id,
  required String imageAssetKey,
  String title = 'Lorem ipsum dolor sit amet consectetur.',
  int priceMinorUnits = 1700,
  String? tag,
  int? popularityCount,
}) => <String, Object?>{
  ...canonicalCatalogProductPayload(id),
  if (tag != null) 'tag': tag,
  if (popularityCount != null) 'popularityCount': popularityCount,
};

Map<String, Object?> _datePayload(int year, int month, int day) =>
    <String, Object?>{'year': year, 'month': month, 'day': day};
