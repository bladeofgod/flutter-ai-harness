import 'package:app_core/app_core.dart';

import '../catalog/catalog_fixture.dart';
import '../catalog/catalog_models.dart';
import '../fixture/fixture_api_transport.dart';
import 'cart_models.dart';

/// Cart 请求键与进程内 Fixture 状态的唯一所有者。
final class CartFixtureHandler implements FixtureRequestHandler {
  CartFixtureHandler({List<CartItem>? initialItems})
    : _itemsById = <String, CartItem>{
        for (final item in initialItems ?? _initialCartItems()) item.id: item,
      };

  static const String loadKey = 'cart.load';
  static const String upsertKey = 'cart.line.upsert';
  static const String updateQuantityKey = 'cart.line.quantity.update';
  static const String removeKey = 'cart.line.remove';
  static const String clearAfterCheckoutKey = 'cart.checkout.clear';

  final Map<String, CartItem> _itemsById;
  final Set<String> _completedCheckoutAttempts = <String>{};

  void resetSession() {
    _itemsById
      ..clear()
      ..addEntries(
        _initialCartItems().map(
          (item) => MapEntry<String, CartItem>(item.id, item),
        ),
      );
    _completedCheckoutAttempts.clear();
  }

  @override
  Set<String> get requestKeys => const <String>{
    loadKey,
    upsertKey,
    updateQuantityKey,
    removeKey,
    clearAfterCheckoutKey,
  };

  @override
  Future<ApiResponse<Object?>> handle(ApiRequest request) async =>
      switch (request.key) {
        loadKey => ApiResponse<Object?>.success(_resultPayload(false)),
        upsertKey => _upsert(request.payload),
        updateQuantityKey => _updateQuantity(request.payload),
        removeKey => _remove(request.payload),
        clearAfterCheckoutKey => _clearAfterCheckout(request.payload),
        _ => throw UnknownApiRequestException(request.key),
      };

  ApiResponse<Object?> _upsert(Object? payload) {
    final input = _lineInput(payload);
    if (input == null) {
      return _invalidInput();
    }
    final current = _itemsById[input.lineId];
    _itemsById[input.lineId] = CartItem(
      // Cart 的既有行拥有已确认的价格与商品快照；重复加购只增加数量，
      // 不允许新的入口摘要覆盖这两个事实。
      product: current?.product ?? input.product,
      variation: input.variation,
      quantity: (current?.quantity ?? 0) + input.quantity,
    );
    return ApiResponse<Object?>.success(_resultPayload(true));
  }

  ApiResponse<Object?> _updateQuantity(Object? payload) {
    final values = _map(payload);
    final lineId = values?['lineId'];
    final quantity = values?['quantity'];
    if (lineId is! String ||
        lineId.isEmpty ||
        quantity is! int ||
        quantity < 1) {
      return _invalidInput();
    }
    final current = _itemsById[lineId];
    if (current == null) {
      return _lineNotFound();
    }
    _itemsById[lineId] = current.copyWithQuantity(quantity);
    return ApiResponse<Object?>.success(_resultPayload(true));
  }

  ApiResponse<Object?> _remove(Object? payload) {
    final values = _map(payload);
    final lineId = values?['lineId'];
    if (lineId is! String || lineId.isEmpty) {
      return _invalidInput();
    }
    if (_itemsById.remove(lineId) == null) {
      return _lineNotFound();
    }
    return ApiResponse<Object?>.success(_resultPayload(true));
  }

  ApiResponse<Object?> _clearAfterCheckout(Object? payload) {
    final values = _map(payload);
    final attemptId = values?['attemptId'];
    if (attemptId is! String || attemptId.trim().isEmpty) {
      return _invalidInput();
    }
    if (!_completedCheckoutAttempts.add(attemptId)) {
      return ApiResponse<Object?>.success(_resultPayload(false));
    }
    _itemsById.clear();
    return ApiResponse<Object?>.success(_resultPayload(true));
  }

  Map<String, Object?> _resultPayload(bool didMutate) => <String, Object?>{
    'didMutate': didMutate,
    'cart': <String, Object?>{
      'currency': Currency.usd.code,
      'items': _itemsById.values.map(_itemPayload).toList(growable: false),
    },
  };

  static CartLineInput? _lineInput(Object? payload) {
    final values = _map(payload);
    final productValues = _map(values?['product']);
    final variationValues = _map(values?['variation']);
    final quantity = values?['quantity'];
    final productId = productValues?['id'];
    final title = productValues?['title'];
    final imageAssetKey = productValues?['imageAssetKey'];
    final minorUnits = productValues?['priceMinorUnits'];
    final currency = productValues?['currency'];
    final color = variationValues?['color'];
    final size = variationValues?['size'];
    if (quantity is! int ||
        quantity < 1 ||
        productId is! String ||
        title is! String ||
        imageAssetKey is! String ||
        minorUnits is! int ||
        currency is! String ||
        color is! String ||
        size is! String) {
      return null;
    }
    try {
      return CartLineInput(
        product: ProductSummary(
          id: productId,
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
    } on ArgumentError {
      return null;
    } on FormatException {
      return null;
    }
  }

  static Map<String, Object?>? _map(Object? value) =>
      value is Map<String, Object?> ? value : null;

  static Map<String, Object?> _itemPayload(CartItem item) => <String, Object?>{
    'product': <String, Object?>{
      'id': item.product.id,
      'title': item.product.title,
      'imageAssetKey': item.product.imageAssetKey,
      'priceMinorUnits': item.unitPrice.minorUnits,
      'currency': item.unitPrice.currency.code,
    },
    'variation': <String, Object?>{
      'color': item.variation.color,
      'size': item.variation.size,
    },
    'quantity': item.quantity,
  };

  static ApiResponse<Object?> _invalidInput() =>
      const ApiResponse<Object?>.failure(
        ApiFailure.rejected(code: 'cart.invalid_input'),
      );

  static ApiResponse<Object?> _lineNotFound() =>
      const ApiResponse<Object?>.failure(
        ApiFailure.rejected(code: 'cart.line_not_found'),
      );
}

List<CartItem> _initialCartItems() => <CartItem>[
  CartItem(
    product: _canonicalCartProduct('product-1'),
    variation: ProductVariation(color: 'Pink', size: 'M'),
    quantity: 1,
  ),
  CartItem(
    product: _canonicalCartProduct('product-2'),
    variation: ProductVariation(color: 'Pink', size: 'M'),
    quantity: 1,
  ),
];

ProductSummary _canonicalCartProduct(String productId) {
  final payload = canonicalCatalogProductPayload(productId);
  return ProductSummary(
    id: payload['id']! as String,
    title: payload['title']! as String,
    imageAssetKey: payload['imageAssetKey']! as String,
    price: Money(
      currency: Currency.fromCode(payload['currency']! as String),
      minorUnits: payload['priceMinorUnits']! as int,
    ),
  );
}
