import 'package:app_data/app_data.dart';
import 'package:test/test.dart';

void main() {
  test('aggregate and nested product lists are immutable snapshots', () {
    final recentlyViewed = <RecentlyViewed>[
      RecentlyViewed(
        id: 'recent-1',
        imageAssetKey: 'assets/images/profile/recent_01.png',
      ),
    ];
    final flashProducts = <ProductSummary>[_product()];
    final dashboard = ProfileDashboard(
      announcement: Announcement(title: 'Announcement', message: 'Message'),
      recentlyViewed: recentlyViewed,
      orders: OrderSummary(items: const <OrderStatusSummary>[]),
      stories: const <Story>[],
      newItems: const <ProductSummary>[],
      mostPopular: const <ProductSummary>[],
      categories: const <CategorySummary>[],
      flashSale: FlashSale(
        hours: 0,
        minutes: 36,
        seconds: 58,
        products: flashProducts,
      ),
      topProducts: const <ProductSummary>[],
      recommendations: const <ProductSummary>[],
    );

    recentlyViewed.clear();
    flashProducts.clear();

    expect(dashboard.recentlyViewed, hasLength(1));
    expect(dashboard.flashSale.products, hasLength(1));
    expect(
      () => dashboard.recentlyViewed.add(
        RecentlyViewed(
          id: 'recent-2',
          imageAssetKey: 'assets/images/profile/recent_02.png',
        ),
      ),
      throwsUnsupportedError,
    );
  });

  test('Flash Sale exposes a static, padded display countdown', () {
    final sale = FlashSale(
      hours: 0,
      minutes: 36,
      seconds: 58,
      products: const <ProductSummary>[],
    );

    expect(sale.displayCountdown, '00:36:58');
    expect(
      () => FlashSale(
        hours: 0,
        minutes: 60,
        seconds: 0,
        products: const <ProductSummary>[],
      ),
      throwsArgumentError,
    );
  });

  test('image summaries reject URLs and absolute paths', () {
    expect(
      () => RecentlyViewed(id: 'recent-1', imageAssetKey: 'http://localhost/a'),
      throwsArgumentError,
    );
    expect(
      () => Story(
        id: 'story-1',
        title: 'Story',
        imageAssetKey: '/tmp/story.png',
        isLive: false,
      ),
      throwsArgumentError,
    );
  });

  test('counts cannot be negative', () {
    expect(
      () => ProductSummary(
        id: 'product-1',
        title: 'Product',
        imageAssetKey: 'assets/images/profile/product_01.png',
        popularityCount: -1,
      ),
      throwsArgumentError,
    );
    expect(
      () => CategorySummary(
        id: 'category-1',
        name: 'Clothing',
        imageAssetKey: 'assets/images/profile/product_01.png',
        itemCount: -1,
      ),
      throwsArgumentError,
    );
  });
}

ProductSummary _product() => ProductSummary(
  id: 'product-1',
  title: 'Lorem ipsum dolor sit amet consectetur.',
  imageAssetKey: 'assets/images/profile/product_01.png',
  price: Money(currency: Currency.usd, minorUnits: 1700),
);
