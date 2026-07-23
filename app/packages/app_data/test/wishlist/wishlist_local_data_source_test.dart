import 'package:app_core/app_core.dart';
import 'package:app_data/app_data.dart';
import 'package:test/test.dart';

void main() {
  test('loads fixed Wishlist and Recently Viewed fixtures', () async {
    final source = _source(WishlistFixtureHandler());

    final overview = await source.loadWishlist();
    final recent = await source.loadRecentlyViewed();

    expect(overview.items, hasLength(5));
    expect(overview.items.first.product.id, 'product-1');
    expect(overview.items[1].originalPrice?.format(), r'$25,00');
    expect(overview.recentlyViewed, hasLength(5));
    expect(overview.recommendations, hasLength(4));
    expect(recent.referenceDate, WishlistDate(year: 2026, month: 4, day: 19));
    expect(
      recent.items.where(
        (item) => item.viewedOn == WishlistDate(year: 2026, month: 4, day: 18),
      ),
      hasLength(6),
    );
  });

  test('removes idempotently until empty', () async {
    final source = _source(WishlistFixtureHandler());

    for (var index = 1; index <= 5; index += 1) {
      await source.removeWishlistItem('wishlist-product-$index');
    }
    final repeated = await source.removeWishlistItem('wishlist-product-1');

    expect(repeated.items, isEmpty);
    expect(repeated.recommendations, isNotEmpty);
  });

  test(
    'adds a Domain product idempotently through the public mutation',
    () async {
      final source = _source(WishlistFixtureHandler());
      final product = ProductSummary(
        id: 'product-20',
        title: 'New product',
        imageAssetKey: 'assets/images/profile/product_20.png',
        price: Money(currency: Currency.usd, minorUnits: 1700),
      );

      final added = await source.addWishlistItem(
        product: product,
        color: 'Pink',
        size: 'M',
      );
      final repeated = await source.addWishlistItem(
        product: product,
        color: 'Pink',
        size: 'M',
      );

      expect(
        added.items.where((item) => item.product.id == 'product-20'),
        hasLength(1),
      );
      expect(
        repeated.items.where((item) => item.product.id == 'product-20'),
        hasLength(1),
      );
    },
  );

  test(
    'handler instances isolate state and reconstruction restores fixture',
    () async {
      final first = _source(WishlistFixtureHandler());
      final second = _source(WishlistFixtureHandler());

      await first.removeWishlistItem('wishlist-product-1');

      expect((await first.loadWishlist()).items, hasLength(4));
      expect((await second.loadWishlist()).items, hasLength(5));
      expect(
        (await _source(WishlistFixtureHandler()).loadWishlist()).items,
        hasLength(5),
      );
    },
  );

  test('uses stable request keys', () async {
    final transport = _RecordingTransport();
    final source = WishlistLocalDataSource(
      apiClient: ApiClient(transport: transport),
    );

    await source.loadWishlist();
    await source.addWishlistItem(
      product: ProductSummary(
        id: 'product-1',
        title: 'Product',
        imageAssetKey: 'assets/product.png',
        price: Money(currency: Currency.usd, minorUnits: 1700),
      ),
      color: 'Pink',
      size: 'M',
    );
    await source.removeWishlistItem('product-1');
    await source.loadRecentlyViewed();

    expect(transport.keys, <String>[
      'wishlist.overview.load',
      'wishlist.item.add',
      'wishlist.item.remove',
      'wishlist.recently_viewed.load',
    ]);
  });

  test('maps malformed payload to invalidResponse', () async {
    final source = WishlistLocalDataSource(
      apiClient: ApiClient(transport: const _PayloadTransport(<Object?>[])),
    );

    await expectLater(
      source.loadWishlist(),
      throwsA(const WishlistFailure(WishlistFailureCode.invalidResponse)),
    );
  });

  test('rejects invalid mutation payload without changing state', () async {
    final handler = WishlistFixtureHandler();
    final response = await handler.handle(
      const ApiRequest(key: WishlistFixtureHandler.removeWishlistItemKey),
    );

    expect(response, isA<ApiError<Object?>>());
    expect((await _source(handler).loadWishlist()).items, hasLength(5));
  });
}

WishlistLocalDataSource _source(WishlistFixtureHandler handler) =>
    WishlistLocalDataSource(
      apiClient: ApiClient(
        transport: FixtureApiTransport(
          handlers: <FixtureRequestHandler>[handler],
        ),
      ),
    );

final class _PayloadTransport implements ApiTransport {
  const _PayloadTransport(this.payload);

  final Object? payload;

  @override
  Future<ApiResponse<Object?>> send(ApiRequest request) async =>
      ApiResponse<Object?>.success(payload);
}

final class _RecordingTransport implements ApiTransport {
  final keys = <String>[];

  @override
  Future<ApiResponse<Object?>> send(ApiRequest request) async {
    keys.add(request.key);
    return switch (request.key) {
      WishlistFixtureHandler.loadRecentlyViewedKey =>
        ApiResponse<Object?>.success(<String, Object?>{
          'referenceDate': <String, Object?>{
            'year': 2026,
            'month': 4,
            'day': 19,
          },
          'items': <Object?>[],
        }),
      _ => ApiResponse<Object?>.success(<String, Object?>{
        'items': <Object?>[],
        'recentlyViewed': <Object?>[],
        'recommendations': <Object?>[],
      }),
    };
  }
}
