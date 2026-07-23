import 'package:app_data/app_data.dart';
import 'package:test/test.dart';

void main() {
  test('Money keeps minor-unit precision and deterministic formatting', () {
    final money = Money(currency: Currency.usd, minorUnits: 1705);

    expect(money.currency.code, 'USD');
    expect(money.format(), r'$17,05');
    expect(money, Money(currency: Currency.fromCode('usd'), minorUnits: 1705));
    expect(
      () => Money(currency: Currency.usd, minorUnits: -1),
      throwsArgumentError,
    );
  });

  test('Product display price is derived only from Money', () {
    final product = ProductSummary(
      id: 'product-1',
      title: 'Product',
      imageAssetKey: 'assets/product.png',
      price: Money(currency: Currency.usd, minorUnits: 3200),
    );

    expect(product.displayPrice, r'$32,00');
  });

  test('Category snapshots preview keys and keeps the first-image getter', () {
    final source = <String>['assets/a.png', 'assets/b.png'];
    final category = CategorySummary(
      id: 'category-1',
      name: 'Clothing',
      previewImageAssetKeys: source,
      itemCount: 109,
    );
    source.clear();

    expect(category.previewImageAssetKeys, hasLength(2));
    expect(category.imageAssetKey, 'assets/a.png');
    expect(
      () => category.previewImageAssetKeys.add('assets/c.png'),
      throwsUnsupportedError,
    );
  });

  test('Shop Dashboard owns immutable ordered groups', () {
    final categories = <CategorySummary>[
      CategorySummary(
        id: 'category-1',
        name: 'Clothing',
        imageAssetKey: 'assets/category.png',
        itemCount: 109,
      ),
    ];
    final dashboard = ShopDashboard(
      promotions: const <ShopPromotion>[],
      categories: categories,
      topProducts: const <ProductSummary>[],
      newItems: const <ProductSummary>[],
      flashSale: FlashSale(
        hours: 0,
        minutes: 0,
        seconds: 0,
        products: const <ProductSummary>[],
      ),
      mostPopular: const <ProductSummary>[],
      recommendations: const <ProductSummary>[],
    );
    categories.clear();

    expect(dashboard.categories.single.id, 'category-1');
    expect(() => dashboard.categories.clear(), throwsUnsupportedError);
  });

  test('Catalog query keeps typed audience, sort and filter identity', () {
    final filter = CatalogFilter(
      audience: CatalogAudience.female,
      categoryId: 'category-clothing',
      subcategoryId: 'subcategory-dresses',
    );
    final query = CatalogQuery(
      filter: filter,
      sortOrder: CatalogSortOrder.priceLowToHigh,
    );

    expect(query.filter, filter);
    expect(
      query,
      CatalogQuery(
        filter: CatalogFilter(
          audience: CatalogAudience.female,
          categoryId: 'category-clothing',
          subcategoryId: 'subcategory-dresses',
        ),
        sortOrder: CatalogSortOrder.priceLowToHigh,
      ),
    );
    expect(filter.copyWith(clearSubcategory: true).subcategoryId, isNull);
  });

  test('Catalog browse result snapshots categories and products', () {
    final categories = <CatalogFilterCategory>[
      CatalogFilterCategory(
        id: 'category-clothing',
        name: 'Clothing',
        imageAssetKey: 'assets/category.png',
        subcategories: <CatalogSubcategory>[
          CatalogSubcategory(
            id: 'subcategory-dresses',
            name: 'Dresses',
            imageAssetKey: 'assets/dresses.png',
          ),
        ],
      ),
    ];
    final products = <ProductSummary>[
      ProductSummary(
        id: 'product-1',
        title: 'Product',
        imageAssetKey: 'assets/product.png',
      ),
    ];
    final result = CatalogBrowseResult(
      query: CatalogQuery.initial(),
      categories: categories,
      products: products,
    );
    categories.clear();
    products.clear();

    expect(result.selectedCategory?.name, 'Clothing');
    expect(result.products.single.id, 'product-1');
    expect(() => result.categories.clear(), throwsUnsupportedError);
    expect(() => result.products.clear(), throwsUnsupportedError);
  });
}
