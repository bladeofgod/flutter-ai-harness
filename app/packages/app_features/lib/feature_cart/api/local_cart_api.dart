import 'dart:async';

import 'package:app_data/app_data.dart';

import '../../api/cart_api.dart';

/// 通过本地数据源实现进程内 Cart 能力。
final class LocalCartApi implements CartApi {
  LocalCartApi({required CartLocalDataSource dataSource})
    : _dataSource = dataSource;

  final CartLocalDataSource _dataSource;
  final StreamController<Cart> _snapshots = StreamController<Cart>.broadcast(
    sync: true,
  );

  @override
  Stream<Cart> get snapshots => _snapshots.stream;

  @override
  Future<Cart> load() => _dataSource.load();

  @override
  Future<Cart> upsert(CartLineInput input) =>
      _mutate(() => _dataSource.upsert(input));

  @override
  Future<Cart> setQuantity({required String lineId, required int quantity}) =>
      _mutate(
        () => _dataSource.setQuantity(lineId: lineId, quantity: quantity),
      );

  @override
  Future<Cart> remove({required String lineId}) =>
      _mutate(() => _dataSource.remove(lineId: lineId));

  @override
  Future<Cart> clearAfterSuccessfulCheckout({required String attemptId}) =>
      _mutate(
        () => _dataSource.clearAfterSuccessfulCheckout(attemptId: attemptId),
      );

  Future<Cart> _mutate(Future<CartMutationResult> Function() operation) async {
    final result = await operation();
    if (result.didMutate) {
      _snapshots.add(result.cart);
    }
    return result.cart;
  }

  Future<void> close() => _snapshots.close();
}
