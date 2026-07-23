import 'dart:async';

import 'package:app_data/app_data.dart';
import 'package:app_features/api/cart_api.dart';
import 'package:app_features/feature_cart/controllers/cart_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cart_test_fixtures.dart';

void main() {
  test('loads data and follows read-only external snapshots', () async {
    final api = FakeCartApi();
    addTearDown(api.close);
    final controller = CartController(
      cartApi: api,
      recommendationSource: CartRecommendationSource.wishlist,
    );
    addTearDown(controller.onDelete);

    controller.onInit();
    await Future<void>.delayed(Duration.zero);
    expect(controller.viewState, isA<CartData>());

    api.emit(emptyCart());
    final state = controller.viewState as CartEmpty;
    expect(state.source, CartRecommendationSource.wishlist);
  });

  test('guards the quantity lower bound and duplicate mutations', () async {
    final api = FakeCartApi();
    addTearDown(api.close);
    final controller = CartController(
      cartApi: api,
      recommendationSource: CartRecommendationSource.popular,
    );
    addTearDown(controller.onDelete);
    controller.onInit();
    await Future<void>.delayed(Duration.zero);
    final lineId = controller.cart!.items.first.id;

    await controller.decrement(lineId);
    expect(api.setQuantityCount, 0);

    final pending = Completer<Cart>();
    api.nextMutation = pending;
    final first = controller.increment(lineId);
    final duplicate = controller.increment(lineId);
    expect(api.setQuantityCount, 1);
    pending.complete(
      Cart(
        currency: Currency.usd,
        items: <CartItem>[
          controller.cart!.items.first.copyWithQuantity(2),
          controller.cart!.items.last,
        ],
      ),
    );
    await Future.wait(<Future<void>>[first, duplicate]);
    expect(controller.cart!.totalQuantity, 3);
  });

  test(
    'delete to empty preserves the explicit recommendation source',
    () async {
      final api = FakeCartApi(initialCart: cartTestCart(itemCount: 1));
      addTearDown(api.close);
      final controller = CartController(
        cartApi: api,
        recommendationSource: CartRecommendationSource.popular,
      );
      addTearDown(controller.onDelete);
      controller.onInit();
      await Future<void>.delayed(Duration.zero);

      await controller.remove(controller.cart!.items.single.id);

      final state = controller.viewState as CartEmpty;
      expect(state.source, CartRecommendationSource.popular);
      expect(state.cart.total.minorUnits, 0);
    },
  );
}
