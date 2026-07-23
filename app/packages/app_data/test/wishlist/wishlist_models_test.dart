import 'package:app_data/app_data.dart';
import 'package:test/test.dart';

void main() {
  test(
    'WishlistDate validates calendar dates and crosses month boundaries',
    () {
      final date = WishlistDate(year: 2026, month: 4, day: 1);

      expect(date.addDays(-1), WishlistDate(year: 2026, month: 3, day: 31));
      expect(
        () => WishlistDate(year: 2026, month: 2, day: 30),
        throwsArgumentError,
      );
    },
  );

  test('WishlistItem composes ProductSummary and validates original price', () {
    final product = ProductSummary(
      id: 'product-1',
      title: 'Product',
      imageAssetKey: 'assets/product.png',
      price: Money(currency: Currency.usd, minorUnits: 1700),
    );

    final item = WishlistItem(product: product, color: ' Pink ', size: ' M ');

    expect(item.product, same(product));
    expect(item.color, 'Pink');
    expect(item.size, 'M');
    expect(
      () => WishlistItem(
        product: product,
        color: 'Pink',
        size: 'M',
        originalPrice: Money(currency: Currency.usd, minorUnits: 1200),
      ),
      throwsArgumentError,
    );
  });
}
