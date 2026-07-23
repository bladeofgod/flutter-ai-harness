import 'package:app_data/src/cart/cart_models.dart';
import 'package:app_data/src/catalog/catalog_models.dart';
import 'package:test/test.dart';

void main() {
  test('uses product and confirmed variation as a stable line identity', () {
    final product = _product('product/1', 1700);
    final pink = ProductVariation(color: 'Pink', size: 'M');
    final sameNormalized = ProductVariation(color: 'pink', size: 'm');
    final blue = ProductVariation(color: 'Blue', size: 'M');

    expect(
      CartLineInput(product: product, variation: pink).lineId,
      CartLineInput(product: product, variation: sameNormalized).lineId,
    );
    expect(
      CartLineInput(product: product, variation: pink).lineId,
      isNot(CartLineInput(product: product, variation: blue).lineId),
    );
  });

  test('calculates quantity and total with integer minor units', () {
    final cart = Cart(
      currency: Currency.usd,
      items: <CartItem>[
        CartItem(
          product: _product('one', 1705),
          variation: ProductVariation(color: 'Pink', size: 'M'),
          quantity: 2,
        ),
        CartItem(
          product: _product('two', 995),
          variation: ProductVariation(color: 'Black', size: 'S'),
          quantity: 3,
        ),
      ],
    );

    expect(cart.totalQuantity, 5);
    expect(cart.total.minorUnits, 6395);
    expect(cart.total.format(), r'$63,95');
  });

  test('rejects invalid quantity, missing price, and duplicate lines', () {
    final variation = ProductVariation(color: 'Pink', size: 'M');
    expect(
      () => CartLineInput(
        product: _product('one', 1700),
        variation: variation,
        quantity: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => CartLineInput(
        product: ProductSummary(
          id: 'free',
          title: 'No price',
          imageAssetKey: 'assets/images/example.png',
        ),
        variation: variation,
      ),
      throwsArgumentError,
    );

    final item = CartItem(
      product: _product('one', 1700),
      variation: variation,
      quantity: 1,
    );
    expect(
      () => Cart(currency: Currency.usd, items: <CartItem>[item, item]),
      throwsArgumentError,
    );
  });
}

ProductSummary _product(String id, int minorUnits) => ProductSummary(
  id: id,
  title: 'Product $id',
  imageAssetKey: 'assets/images/$id.png',
  price: Money(currency: Currency.usd, minorUnits: minorUnits),
);
