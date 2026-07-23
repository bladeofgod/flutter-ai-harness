import 'dart:async';

import 'package:app_data/app_data.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../api/cart_api.dart';

sealed class CartViewState {
  const CartViewState();
}

final class CartLoading extends CartViewState {
  const CartLoading();
}

final class CartData extends CartViewState {
  const CartData({required this.cart, required this.isMutating});

  final Cart cart;
  final bool isMutating;
}

final class CartEmpty extends CartViewState {
  const CartEmpty({
    required this.cart,
    required this.source,
    required this.isMutating,
  });

  final Cart cart;
  final CartRecommendationSource source;
  final bool isMutating;
}

final class CartError extends CartViewState {
  const CartError(this.failure);

  final CartFailure failure;
}

/// 管理 Cart 加载、mutation 串行化与外部一致快照同步。
final class CartController extends GetxController {
  CartController({required CartApi cartApi, required this.recommendationSource})
    : _cartApi = cartApi;

  final CartApi _cartApi;
  final CartRecommendationSource recommendationSource;
  final Rx<CartViewState> _viewState = Rx<CartViewState>(const CartLoading());

  StreamSubscription<Cart>? _subscription;
  Cart? _cart;
  bool _isLoading = false;
  bool _isMutating = false;
  bool _isDisposed = false;

  CartViewState get viewState => _viewState.value;
  Cart? get cart => _cart;

  @override
  void onInit() {
    super.onInit();
    _subscription = _cartApi.snapshots.listen(_receiveSnapshot);
    _runFromLifecycle(load);
  }

  Future<void> load() async {
    if (_isLoading || _isDisposed) {
      return;
    }
    _isLoading = true;
    _viewState.value = const CartLoading();
    try {
      _receiveSnapshot(await _cartApi.load());
    } on CartFailure catch (failure) {
      if (!_isDisposed) {
        _viewState.value = CartError(failure);
      }
    } finally {
      _isLoading = false;
    }
  }

  Future<void> upsert(CartLineInput input) =>
      _mutate(() => _cartApi.upsert(input));

  Future<void> increment(String lineId) async {
    final item = _findItem(lineId);
    if (item == null) {
      return;
    }
    await _mutate(
      () => _cartApi.setQuantity(lineId: item.id, quantity: item.quantity + 1),
    );
  }

  Future<void> decrement(String lineId) async {
    final item = _findItem(lineId);
    if (item == null || item.quantity <= 1) {
      return;
    }
    await _mutate(
      () => _cartApi.setQuantity(lineId: item.id, quantity: item.quantity - 1),
    );
  }

  Future<void> remove(String lineId) =>
      _mutate(() => _cartApi.remove(lineId: lineId));

  Future<void> retry() => load();

  void retryFromUi() => _runFromLifecycle(retry);
  void incrementFromUi(String lineId) =>
      _runFromLifecycle(() => increment(lineId));
  void decrementFromUi(String lineId) =>
      _runFromLifecycle(() => decrement(lineId));
  void removeFromUi(String lineId) => _runFromLifecycle(() => remove(lineId));
  void addRecommendationFromUi(ProductSummary product) => _runFromLifecycle(
    () => upsert(
      CartLineInput(
        product: product,
        variation: ProductVariation(color: 'Pink', size: 'M'),
      ),
    ),
  );

  CartItem? _findItem(String lineId) {
    for (final item in _cart?.items ?? const <CartItem>[]) {
      if (item.id == lineId) {
        return item;
      }
    }
    return null;
  }

  Future<void> _mutate(Future<Cart> Function() operation) async {
    if (_isMutating || _isDisposed || _cart == null) {
      return;
    }
    _isMutating = true;
    _publish(_cart!);
    try {
      final cart = await operation();
      if (!_isDisposed) {
        _cart = cart;
      }
    } on CartFailure catch (failure) {
      if (!_isDisposed) {
        _viewState.value = CartError(failure);
      }
      return;
    } finally {
      _isMutating = false;
    }
    if (!_isDisposed) {
      _publish(_cart!);
    }
  }

  void _receiveSnapshot(Cart cart) {
    if (_isDisposed) {
      return;
    }
    _cart = cart;
    _publish(cart);
  }

  void _publish(Cart cart) {
    _viewState.value = cart.isEmpty
        ? CartEmpty(
            cart: cart,
            source: recommendationSource,
            isMutating: _isMutating,
          )
        : CartData(cart: cart, isMutating: _isMutating);
  }

  void _runFromLifecycle(Future<void> Function() operation) {
    unawaited(_runAndReportUnexpectedError(operation));
  }

  Future<void> _runAndReportUnexpectedError(
    Future<void> Function() operation,
  ) async {
    try {
      await operation();
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'app_features',
          context: ErrorDescription('while updating the Cart'),
        ),
      );
    }
  }

  @override
  void onClose() {
    _isDisposed = true;
    unawaited(_subscription?.cancel());
    super.onClose();
  }
}
