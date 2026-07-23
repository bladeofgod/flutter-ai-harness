part of 'cart_local.dart';

abstract final class _CartFixtureMapper {
  static CartMutationResult mutationResult(Object? payload) => _decode(() {
    final values = _map(payload);
    final didMutate = values['didMutate'];
    if (didMutate is! bool) {
      throw const CartFailure(CartFailureCode.invalidResponse);
    }
    return (cart: _cart(values['cart']), didMutate: didMutate);
  });

  static Map<String, Object?> lineInputPayload(CartLineInput input) =>
      <String, Object?>{
        'product': <String, Object?>{
          'id': input.product.id,
          'title': input.product.title,
          'imageAssetKey': input.product.imageAssetKey,
          'priceMinorUnits': input.product.price!.minorUnits,
          'currency': input.product.price!.currency.code,
        },
        'variation': <String, Object?>{
          'color': input.variation.color,
          'size': input.variation.size,
        },
        'quantity': input.quantity,
      };

  static Cart _cart(Object? payload) {
    final values = _map(payload);
    final currency = values['currency'];
    final items = values['items'];
    if (currency is! String || items is! List<Object?>) {
      throw const CartFailure(CartFailureCode.invalidResponse);
    }
    return Cart(
      currency: Currency.fromCode(currency),
      items: List<CartItem>.unmodifiable(items.map(_item)),
    );
  }

  static CartItem _item(Object? payload) {
    final values = _map(payload);
    final productValues = _map(values['product']);
    final variationValues = _map(values['variation']);
    final quantity = values['quantity'];
    final id = productValues['id'];
    final title = productValues['title'];
    final imageAssetKey = productValues['imageAssetKey'];
    final minorUnits = productValues['priceMinorUnits'];
    final currency = productValues['currency'];
    final color = variationValues['color'];
    final size = variationValues['size'];
    if (id is! String ||
        title is! String ||
        imageAssetKey is! String ||
        minorUnits is! int ||
        currency is! String ||
        color is! String ||
        size is! String ||
        quantity is! int) {
      throw const CartFailure(CartFailureCode.invalidResponse);
    }
    return CartItem(
      product: ProductSummary(
        id: id,
        title: title,
        imageAssetKey: imageAssetKey,
        price: Money(
          currency: Currency.fromCode(currency),
          minorUnits: minorUnits,
        ),
      ),
      variation: ProductVariation(color: color, size: size),
      quantity: quantity,
    );
  }

  static T _decode<T>(T Function() decode) {
    try {
      return decode();
    } on CartFailure {
      rethrow;
    } on FormatException catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const CartFailure(CartFailureCode.invalidResponse),
        stackTrace,
      );
    } on ArgumentError catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const CartFailure(CartFailureCode.invalidResponse),
        stackTrace,
      );
    }
  }

  static Map<String, Object?> _map(Object? payload) {
    if (payload is! Map<String, Object?>) {
      throw const CartFailure(CartFailureCode.invalidResponse);
    }
    return payload;
  }
}
