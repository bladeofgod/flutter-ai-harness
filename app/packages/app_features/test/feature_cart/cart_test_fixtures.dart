import 'dart:async';

import 'package:app_data/app_data.dart';
import 'package:app_features/api/cart_api.dart';

final class FakeCartApi implements CartApi {
  FakeCartApi({Cart? initialCart, this.loadCompleter})
    : current = initialCart ?? cartTestCart();

  Cart current;
  final Completer<Cart>? loadCompleter;
  final StreamController<Cart> _snapshots = StreamController<Cart>.broadcast(
    sync: true,
  );
  Completer<Cart>? nextMutation;
  int loadCount = 0;
  int mutationCount = 0;
  int setQuantityCount = 0;

  @override
  Stream<Cart> get snapshots => _snapshots.stream;

  @override
  Future<Cart> load() {
    loadCount += 1;
    return loadCompleter?.future ?? Future<Cart>.value(current);
  }

  @override
  Future<Cart> upsert(CartLineInput input) async {
    mutationCount += 1;
    final items = <CartItem>[...current.items];
    final index = items.indexWhere((item) => item.id == input.lineId);
    if (index == -1) {
      items.add(
        CartItem(
          product: input.product,
          variation: input.variation,
          quantity: input.quantity,
        ),
      );
    } else {
      items[index] = items[index].copyWithQuantity(
        items[index].quantity + input.quantity,
      );
    }
    return _complete(Cart(currency: current.currency, items: items));
  }

  @override
  Future<Cart> setQuantity({required String lineId, required int quantity}) {
    mutationCount += 1;
    setQuantityCount += 1;
    final items = current.items
        .map(
          (item) => item.id == lineId ? item.copyWithQuantity(quantity) : item,
        )
        .toList(growable: false);
    return _complete(Cart(currency: current.currency, items: items));
  }

  @override
  Future<Cart> remove({required String lineId}) {
    mutationCount += 1;
    return _complete(
      Cart(
        currency: current.currency,
        items: current.items
            .where((item) => item.id != lineId)
            .toList(growable: false),
      ),
    );
  }

  @override
  Future<Cart> clearAfterSuccessfulCheckout({required String attemptId}) {
    mutationCount += 1;
    return _complete(Cart(currency: current.currency, items: const []));
  }

  void emit(Cart cart) {
    current = cart;
    _snapshots.add(cart);
  }

  Future<Cart> _complete(Cart value) async {
    final pending = nextMutation;
    if (pending != null) {
      final resolved = await pending.future;
      current = resolved;
      _snapshots.add(resolved);
      return resolved;
    }
    current = value;
    _snapshots.add(value);
    return value;
  }

  Future<void> close() => _snapshots.close();
}

Cart cartTestCart({
  int itemCount = 2,
  String title = 'Lorem ipsum dolor sit amet consectetur.',
}) => Cart(
  currency: Currency.usd,
  items: List<CartItem>.generate(
    itemCount,
    (index) => CartItem(
      product: ProductSummary(
        id: 'cart-product-${index + 1}',
        title: title,
        imageAssetKey:
            'assets/images/cart/cart_item_${(index + 1).toString().padLeft(2, '0')}.png',
        price: Money(currency: Currency.usd, minorUnits: 1700),
      ),
      variation: ProductVariation(color: 'Pink', size: 'M'),
      quantity: 1,
    ),
  ),
);

Cart emptyCart() => Cart(currency: Currency.usd, items: const <CartItem>[]);
