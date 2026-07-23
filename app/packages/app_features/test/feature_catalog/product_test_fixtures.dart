import 'dart:async';

import 'package:app_data/app_data.dart';
import 'package:app_features/api/cart_api.dart';
import 'package:app_features/api/catalog_api.dart';

final class FakeProductApi implements ProductApi {
  FakeProductApi({required this.detail, this.failure});

  final ProductDetail detail;
  CatalogFailure? failure;
  var loadCount = 0;

  @override
  Future<ProductDetail> loadProductDetail(String productId) async {
    loadCount += 1;
    if (failure case final failure?) {
      throw failure;
    }
    return detail;
  }
}

ProductDetail productDetailFixture({bool emptyReviews = false}) {
  final product = ProductSummary(
    id: 'product-1',
    title: 'Demo product',
    imageAssetKey: 'assets/images/profile/product_01.png',
    price: Money(currency: Currency.usd, minorUnits: 1700),
  );
  return ProductDetail(
    product: product,
    gallery: <ProductImage>[
      ProductImage(
        id: 'gallery-1',
        imageAssetKey: 'assets/images/profile/product_01.png',
      ),
      ProductImage(
        id: 'gallery-2',
        imageAssetKey: 'assets/images/profile/product_02.png',
      ),
    ],
    description: 'A demo product description.',
    optionGroups: <ProductOptionGroup>[
      ProductOptionGroup(
        id: 'color',
        label: 'Color',
        options: <ProductOption>[
          ProductOption(id: 'pink', label: 'Pink'),
          ProductOption(id: 'black', label: 'Black'),
        ],
      ),
      ProductOptionGroup(
        id: 'size',
        label: 'Size',
        options: <ProductOption>[
          ProductOption(id: 'm', label: 'M'),
          ProductOption(id: 'l', label: 'L'),
        ],
      ),
    ],
    stockCount: 12,
    rating: ProductRatingSummary(
      averageRatingHundredths: 475,
      reviewCount: emptyReviews ? 0 : 1,
      distribution: const <int, int>{5: 1},
    ),
    reviews: emptyReviews
        ? const <ProductReview>[]
        : <ProductReview>[
            ProductReview(
              id: 'review-1',
              author: 'Anne',
              comment: 'Fits well.',
              rating: 5,
              publishedLabel: 'Yesterday',
            ),
          ],
  );
}

final class FakeProductCartApi implements CartApi {
  FakeProductCartApi({Cart? initial}) : current = initial ?? _emptyCart();

  Cart current;
  var upsertCount = 0;
  final StreamController<Cart> _snapshots = StreamController<Cart>.broadcast();

  @override
  Stream<Cart> get snapshots => _snapshots.stream;

  @override
  Future<Cart> load() async => current;

  @override
  Future<Cart> upsert(CartLineInput input) async {
    upsertCount += 1;
    current = Cart(
      currency: current.currency,
      items: <CartItem>[
        ...current.items,
        CartItem(
          product: input.product,
          variation: input.variation,
          quantity: input.quantity,
        ),
      ],
    );
    _snapshots.add(current);
    return current;
  }

  @override
  Future<Cart> setQuantity({
    required String lineId,
    required int quantity,
  }) async => current;

  @override
  Future<Cart> remove({required String lineId}) async => current;

  @override
  Future<Cart> clearAfterSuccessfulCheckout({
    required String attemptId,
  }) async => current;

  Future<void> close() => _snapshots.close();
}

Cart _emptyCart() => Cart(currency: Currency.usd, items: const <CartItem>[]);
