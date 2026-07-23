import 'package:app_core/app_core.dart';
import 'package:app_data/app_data.dart';
import 'package:app_features/feature_cart/api/local_cart_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('publishes exactly one snapshot for each effective mutation', () async {
    final api = _api();
    addTearDown(api.close);
    final snapshots = <Cart>[];
    final subscription = api.snapshots.listen(snapshots.add);
    addTearDown(subscription.cancel);
    final initial = await api.load();

    await api.setQuantity(lineId: initial.items.first.id, quantity: 2);
    await api.remove(lineId: initial.items.last.id);
    await api.clearAfterSuccessfulCheckout(attemptId: 'paid-1');
    await api.clearAfterSuccessfulCheckout(attemptId: 'paid-1');

    expect(snapshots, hasLength(3));
    expect(snapshots.first.totalQuantity, 3);
    expect(snapshots.last.isEmpty, isTrue);
  });

  test('upsert shares a line only for the same confirmed variation', () async {
    final api = _api(initialItems: const <CartItem>[]);
    addTearDown(api.close);
    final product = ProductSummary(
      id: 'product-1',
      title: 'Product',
      imageAssetKey: 'assets/images/cart/cart_item_01.png',
      price: Money(currency: Currency.usd, minorUnits: 1700),
    );

    await api.upsert(
      CartLineInput(
        product: product,
        variation: ProductVariation(color: 'Pink', size: 'M'),
      ),
    );
    var cart = await api.upsert(
      CartLineInput(
        product: product,
        variation: ProductVariation(color: 'pink', size: 'm'),
      ),
    );
    expect(cart.items.single.quantity, 2);

    cart = await api.upsert(
      CartLineInput(
        product: product,
        variation: ProductVariation(color: 'Blue', size: 'M'),
      ),
    );
    expect(cart.items, hasLength(2));
  });
}

LocalCartApi _api({List<CartItem>? initialItems}) {
  final handler = CartFixtureHandler(initialItems: initialItems);
  return LocalCartApi(
    dataSource: CartLocalDataSource(
      apiClient: ApiClient(
        transport: FixtureApiTransport(
          handlers: <FixtureRequestHandler>[handler],
        ),
      ),
    ),
  );
}
