import 'package:app_data/app_data.dart';

import '../api/cart_api.dart';

List<ProductSummary> cartRecommendations(CartRecommendationSource source) =>
    switch (source) {
      CartRecommendationSource.wishlist => <ProductSummary>[
        _product(2),
        _product(3),
      ],
      CartRecommendationSource.popular => <ProductSummary>[
        _popular(2, 'New'),
        _popular(3, 'Sale'),
        _popular(4, 'Hot'),
        _popular(1, 'Hot'),
      ],
    };

ProductSummary _product(int number) => ProductSummary(
  id: 'product-${number + 20}',
  title: 'Lorem ipsum dolor sit amet consectetur.',
  imageAssetKey:
      'assets/images/catalog/products/'
      'shop_product_${number.toString().padLeft(2, '0')}.png',
  price: Money(currency: Currency.usd, minorUnits: 1700),
);

ProductSummary _popular(int number, String tag) => ProductSummary(
  id: 'product-${number + 20}',
  title: 'Popular product $number',
  imageAssetKey:
      'assets/images/catalog/products/'
      'shop_product_${number.toString().padLeft(2, '0')}.png',
  price: Money(currency: Currency.usd, minorUnits: 1700),
  popularityCount: 1780,
  tag: tag,
);
