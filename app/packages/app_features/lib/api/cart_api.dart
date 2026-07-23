import 'package:app_data/app_data.dart';

/// Cart 空态推荐的确定性来源。
enum CartRecommendationSource { wishlist, popular }

/// Product、Cart badge 与 Checkout 共同消费的稳定 Cart 边界。
abstract interface class CartApi {
  /// 只发布成功 mutation 产生的一致快照。
  Stream<Cart> get snapshots;

  Future<Cart> load();

  Future<Cart> upsert(CartLineInput input);

  Future<Cart> setQuantity({required String lineId, required int quantity});

  Future<Cart> remove({required String lineId});

  /// 仅由成功支付流程调用；相同 Attempt ID 重复调用保持幂等。
  Future<Cart> clearAfterSuccessfulCheckout({required String attemptId});
}
