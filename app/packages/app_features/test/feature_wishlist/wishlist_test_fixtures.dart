import 'package:app_data/app_data.dart';
import 'package:app_features/api/wishlist_api.dart';

final class FakeWishlistApi implements WishlistApi {
  FakeWishlistApi({
    required this.loadWishlistHandler,
    this.addHandler,
    required this.removeHandler,
    required this.loadRecentlyViewedHandler,
  });

  final Future<WishlistOverview> Function(int loadCount) loadWishlistHandler;
  final Future<WishlistOverview> Function(
    ProductSummary product,
    String color,
    String size,
  )?
  addHandler;
  final Future<WishlistOverview> Function(String productId, int removeCount)
  removeHandler;
  final Future<RecentlyViewedSnapshot> Function(int loadCount)
  loadRecentlyViewedHandler;

  var wishlistLoadCount = 0;
  var addCount = 0;
  var removeCount = 0;
  var recentLoadCount = 0;

  @override
  Future<WishlistOverview> loadWishlist() {
    wishlistLoadCount += 1;
    return loadWishlistHandler(wishlistLoadCount);
  }

  @override
  Future<WishlistOverview> addWishlistItem({
    required ProductSummary product,
    required String color,
    required String size,
  }) {
    addCount += 1;
    return addHandler?.call(product, color, size) ?? loadWishlist();
  }

  @override
  Future<RecentlyViewedSnapshot> loadRecentlyViewed() {
    recentLoadCount += 1;
    return loadRecentlyViewedHandler(recentLoadCount);
  }

  @override
  Future<WishlistOverview> removeWishlistItem(String productId) {
    removeCount += 1;
    return removeHandler(productId, removeCount);
  }
}

WishlistOverview wishlistTestOverview({int itemCount = 2}) => WishlistOverview(
  items: List<WishlistItem>.generate(
    itemCount,
    (index) => WishlistItem(
      product: wishlistTestProduct(index + 1),
      color: 'Pink',
      size: 'M',
      originalPrice: index == 1
          ? Money(currency: Currency.usd, minorUnits: 2100)
          : null,
    ),
  ),
  recentlyViewed: List<ProductSummary>.generate(
    5,
    (index) => wishlistTestProduct(index + 10),
  ),
  recommendations: List<ProductSummary>.generate(
    4,
    (index) => ProductSummary(
      id: 'recommended-${index + 1}',
      title: 'Recommended ${index + 1}',
      imageAssetKey:
          'assets/images/profile/product_${(index + 1).toString().padLeft(2, '0')}.png',
      price: Money(currency: Currency.usd, minorUnits: 1700),
      tag: 'Hot',
      popularityCount: 1780,
    ),
  ),
);

RecentlyViewedSnapshot recentlyViewedTestSnapshot() {
  final today = WishlistDate(year: 2026, month: 4, day: 19);
  final yesterday = today.addDays(-1);
  return RecentlyViewedSnapshot(
    referenceDate: today,
    items: <RecentlyViewedItem>[
      for (var index = 0; index < 4; index += 1)
        RecentlyViewedItem(
          id: 'today-$index',
          product: wishlistTestProduct(index + 1),
          viewedOn: today,
        ),
      for (var index = 0; index < 3; index += 1)
        RecentlyViewedItem(
          id: 'yesterday-$index',
          product: wishlistTestProduct(index + 10),
          viewedOn: yesterday,
        ),
      RecentlyViewedItem(
        id: 'custom-1',
        product: wishlistTestProduct(20),
        viewedOn: WishlistDate(year: 2026, month: 4, day: 17),
      ),
    ],
  );
}

ProductSummary wishlistTestProduct(int number) => ProductSummary(
  id: 'product-$number',
  title: 'Demo product $number',
  imageAssetKey:
      'assets/images/profile/product_${((number - 1) % 20 + 1).toString().padLeft(2, '0')}.png',
  price: Money(currency: Currency.usd, minorUnits: 1700),
);

FakeWishlistApi successfulWishlistApi({WishlistOverview? overview}) {
  final value = overview ?? wishlistTestOverview();
  return FakeWishlistApi(
    loadWishlistHandler: (_) async => value,
    addHandler: (product, color, size) async => WishlistOverview(
      items: <WishlistItem>[
        ...value.items,
        WishlistItem(product: product, color: color, size: size),
      ],
      recentlyViewed: value.recentlyViewed,
      recommendations: value.recommendations,
    ),
    removeHandler: (productId, _) async => WishlistOverview(
      items: value.items
          .where((item) => item.product.id != productId)
          .toList(growable: false),
      recentlyViewed: value.recentlyViewed,
      recommendations: value.recommendations,
    ),
    loadRecentlyViewedHandler: (_) async => recentlyViewedTestSnapshot(),
  );
}
