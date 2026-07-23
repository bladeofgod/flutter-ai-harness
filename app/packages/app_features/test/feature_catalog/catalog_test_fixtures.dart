import 'package:app_data/app_data.dart';
import 'package:app_features/api/catalog_api.dart';

final class FakeCatalogApi implements CatalogApi {
  FakeCatalogApi(this._load);

  final Future<ShopDashboard> Function(int loadCount) _load;
  var loadCount = 0;

  @override
  Future<ShopDashboard> loadShop() {
    loadCount += 1;
    return _load(loadCount);
  }
}

ShopDashboard catalogTestDashboard({bool emptySections = false}) =>
    ShopDashboard(
      promotions: emptySections
          ? const <ShopPromotion>[]
          : <ShopPromotion>[
              ShopPromotion(
                id: 'promotion-big-sale',
                title: 'Big Sale',
                subtitle: 'Up to 50%',
                badge: 'Happening Now',
                imageAssetKey: 'assets/images/catalog/big_sale.png',
              ),
            ],
      categories: emptySections
          ? const <CategorySummary>[]
          : List<CategorySummary>.generate(
              6,
              (index) => CategorySummary(
                id: 'category-${index + 1}',
                name: 'Category ${index + 1}',
                previewImageAssetKeys: <String>[
                  for (var image = 0; image < 4; image += 1)
                    _productImage(((index * 4 + image) % 20) + 1),
                ],
                itemCount: 100 + index,
              ),
            ),
      topProducts: emptySections
          ? const <ProductSummary>[]
          : List<ProductSummary>.generate(
              5,
              (index) => catalogTestProduct(index + 16),
            ),
      newItems: emptySections
          ? const <ProductSummary>[]
          : List<ProductSummary>.generate(
              5,
              (index) => catalogTestProduct(index + 1),
            ),
      flashSale: FlashSale(
        hours: 0,
        minutes: 36,
        seconds: 58,
        products: emptySections
            ? const <ProductSummary>[]
            : List<ProductSummary>.generate(
                6,
                (index) => catalogTestProduct(index + 10, tag: '-20%'),
              ),
      ),
      mostPopular: emptySections
          ? const <ProductSummary>[]
          : List<ProductSummary>.generate(
              4,
              (index) => catalogTestProduct(index + 6, tag: 'New'),
            ),
      recommendations: emptySections
          ? const <ProductSummary>[]
          : List<ProductSummary>.generate(
              8,
              (index) => catalogTestProduct(index + 1),
            ),
    );

ProductSummary catalogTestProduct(int number, {String? tag}) => ProductSummary(
  id: 'product-$number',
  title: 'Demo product $number',
  imageAssetKey: _productImage(number),
  price: Money(currency: Currency.usd, minorUnits: 1700),
  tag: tag,
  popularityCount: 1780,
);

String _productImage(int number) =>
    'assets/images/profile/product_${number.toString().padLeft(2, '0')}.png';
