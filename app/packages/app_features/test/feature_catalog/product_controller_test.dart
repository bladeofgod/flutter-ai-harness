import 'package:app_data/app_data.dart';
import 'package:app_features/feature_catalog/controllers/product_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../feature_wishlist/wishlist_test_fixtures.dart';
import 'product_test_fixtures.dart';

void main() {
  test('loads detail and keeps loading failure retryable', () async {
    final detail = productDetailFixture();
    final api = FakeProductApi(
      detail: detail,
      failure: const CatalogFailure(CatalogFailureCode.unavailable),
    );
    final controller = ProductController(
      productApi: api,
      wishlistApi: successfulWishlistApi(),
      cartApi: FakeProductCartApi(),
      productId: detail.product.id,
    );
    controller.onInit();
    addTearDown(controller.onClose);
    await _waitForState<ProductError>(controller);

    expect(
      (controller.viewState as ProductError).failure.code,
      CatalogFailureCode.unavailable,
    );
    api.failure = null;
    await controller.retry();
    expect(controller.viewState, isA<ProductData>());
  });

  test(
    'requires all options and cancel does not change confirmed selection',
    () async {
      final detail = productDetailFixture();
      final controller = _controller(detail);
      controller.onInit();
      addTearDown(controller.onClose);
      await _waitForState<ProductData>(controller);

      expect(
        controller.confirmSelection(const <String, String>{'color': 'pink'}),
        isFalse,
      );
      expect(controller.confirmedSelection, isEmpty);
      expect(
        controller.confirmSelection(const <String, String>{
          'color': 'pink',
          'size': 'm',
        }),
        isTrue,
      );
      expect(controller.confirmedSelection, <String, String>{
        'color': 'pink',
        'size': 'm',
      });
      controller.resetDraftSelection();
      expect(controller.confirmedSelection, <String, String>{
        'color': 'pink',
        'size': 'm',
      });
    },
  );

  test(
    'favorite and Add to Cart use public APIs with stable variation',
    () async {
      final detail = productDetailFixture();
      final wishlist = successfulWishlistApi(
        overview: wishlistTestOverview(itemCount: 0),
      );
      final cart = FakeProductCartApi();
      final controller = ProductController(
        productApi: FakeProductApi(detail: detail),
        wishlistApi: wishlist,
        cartApi: cart,
        productId: detail.product.id,
      );
      controller.onInit();
      addTearDown(controller.onClose);
      addTearDown(cart.close);
      await _waitForState<ProductData>(controller);

      expect(await controller.addToCart(), isFalse);
      expect(cart.upsertCount, 0);
      controller.confirmSelection(const <String, String>{
        'color': 'pink',
        'size': 'm',
      });
      expect(await controller.addToCart(), isTrue);
      expect(cart.upsertCount, 1);
      expect(await controller.toggleFavorite(), isTrue);
      expect(controller.isFavorite.value, isTrue);
      expect(wishlist.addCount, 1);
      expect(await controller.toggleFavorite(), isTrue);
      expect(controller.isFavorite.value, isFalse);
      expect(wishlist.removeCount, 1);
    },
  );
}

ProductController _controller(ProductDetail detail) => ProductController(
  productApi: FakeProductApi(detail: detail),
  wishlistApi: successfulWishlistApi(),
  cartApi: FakeProductCartApi(),
  productId: detail.product.id,
);

Future<void> _waitForState<T extends ProductViewState>(
  ProductController controller,
) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (controller.viewState is T) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Product state did not become $T.');
}
