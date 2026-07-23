import 'package:app_core/app_core.dart';
import 'package:app_data/app_data.dart';
import 'package:app_features/feature_wishlist/api/local_wishlist_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LocalWishlistApi preserves one handler process state', () async {
    final handler = WishlistFixtureHandler();
    final api = LocalWishlistApi(
      dataSource: WishlistLocalDataSource(
        apiClient: ApiClient(
          transport: FixtureApiTransport(
            handlers: <FixtureRequestHandler>[handler],
          ),
        ),
      ),
    );

    expect((await api.loadWishlist()).items, hasLength(5));
    final product = ProductSummary(
      id: 'product-20',
      title: 'New product',
      imageAssetKey: 'assets/images/profile/product_20.png',
      price: Money(currency: Currency.usd, minorUnits: 1700),
    );
    final addedSnapshot = api.snapshots.first;
    expect(
      (await api.addWishlistItem(
        product: product,
        color: 'Pink',
        size: 'M',
      )).items,
      hasLength(6),
    );
    expect((await addedSnapshot).items, hasLength(6));
    expect(
      (await api.removeWishlistItem('wishlist-product-1')).items,
      hasLength(5),
    );
    expect((await api.loadWishlist()).items, hasLength(5));
    expect((await api.loadRecentlyViewed()).items, hasLength(12));
  });
}
