import '../catalog/catalog_models.dart';

/// 商品加入购物车前已经确认的规格组合。
final class ProductVariation {
  factory ProductVariation({required String color, required String size}) =>
      ProductVariation._(
        color: _requiredText(color, 'color'),
        size: _requiredText(size, 'size'),
      );

  const ProductVariation._({required this.color, required this.size});

  final String color;
  final String size;

  String get stableKey =>
      'color=${Uri.encodeComponent(color.toLowerCase())}'
      '&size=${Uri.encodeComponent(size.toLowerCase())}';

  @override
  bool operator ==(Object other) =>
      other is ProductVariation && other.color == color && other.size == size;

  @override
  int get hashCode => Object.hash(color, size);
}

/// Product/Wishlist 向 Cart 提交的稳定行项目输入。
final class CartLineInput {
  factory CartLineInput({
    required ProductSummary product,
    required ProductVariation variation,
    int quantity = 1,
  }) {
    _requirePurchasableProduct(product);
    _requirePositiveQuantity(quantity);
    return CartLineInput._(
      product: product,
      variation: variation,
      quantity: quantity,
    );
  }

  const CartLineInput._({
    required this.product,
    required this.variation,
    required this.quantity,
  });

  final ProductSummary product;
  final ProductVariation variation;
  final int quantity;

  String get lineId => CartItem.lineIdFor(product.id, variation);
}

/// Cart 中不可变的单个商品行。
final class CartItem {
  factory CartItem({
    required ProductSummary product,
    required ProductVariation variation,
    required int quantity,
  }) {
    _requirePurchasableProduct(product);
    _requirePositiveQuantity(quantity);
    return CartItem._(
      id: lineIdFor(product.id, variation),
      product: product,
      variation: variation,
      quantity: quantity,
    );
  }

  const CartItem._({
    required this.id,
    required this.product,
    required this.variation,
    required this.quantity,
  });

  final String id;
  final ProductSummary product;
  final ProductVariation variation;
  final int quantity;

  Money get unitPrice => product.price!;

  Money get lineTotal => Money(
    currency: unitPrice.currency,
    minorUnits: unitPrice.minorUnits * quantity,
  );

  CartItem copyWithQuantity(int quantity) =>
      CartItem(product: product, variation: variation, quantity: quantity);

  static String lineIdFor(String productId, ProductVariation variation) =>
      '${Uri.encodeComponent(productId)}::${variation.stableKey}';
}

/// Cart 对所有消费者暴露的不可变一致快照。
final class Cart {
  factory Cart({required Currency currency, required List<CartItem> items}) {
    final ids = <String>{};
    for (final item in items) {
      if (item.unitPrice.currency != currency) {
        throw ArgumentError.value(
          item.unitPrice.currency,
          'items',
          'Every cart item must use the cart currency.',
        );
      }
      if (!ids.add(item.id)) {
        throw ArgumentError.value(item.id, 'items', 'Duplicate cart line.');
      }
    }
    return Cart._(
      currency: currency,
      items: List<CartItem>.unmodifiable(items),
    );
  }

  const Cart._({required this.currency, required this.items});

  final Currency currency;
  final List<CartItem> items;

  bool get isEmpty => items.isEmpty;
  int get totalQuantity => items.fold(0, (sum, item) => sum + item.quantity);
  Money get total => Money(
    currency: currency,
    minorUnits: items.fold(0, (sum, item) => sum + item.lineTotal.minorUnits),
  );
}

String _requiredText(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, 'Value must not be empty.');
  }
  return normalized;
}

void _requirePositiveQuantity(int quantity) {
  if (quantity < 1) {
    throw ArgumentError.value(
      quantity,
      'quantity',
      'Cart quantity must be at least one.',
    );
  }
}

void _requirePurchasableProduct(ProductSummary product) {
  if (product.price == null) {
    throw ArgumentError.value(
      product.id,
      'product',
      'A cart product must have a price.',
    );
  }
}
