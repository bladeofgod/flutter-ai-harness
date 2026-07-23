import 'package:app_data/app_data.dart' show CheckoutReceipt;
import 'package:app_data/orders.dart';

/// Orders 页面与 Checkout 装配只依赖此窄业务边界。
abstract interface class OrdersApi {
  Future<List<Order>> load({required ActivityFilter filter});

  Future<Order> loadOrder({required String orderId});

  /// 把成功 Checkout Receipt 幂等加入当前进程订单列表。
  Future<Order> acceptReceipt(
    CheckoutReceipt receipt, {
    List<OrderLine> lines = const <OrderLine>[],
  });

  Future<Order> consumeNotification({required String orderId});

  Future<Order> submitReview({
    required String orderId,
    required int rating,
    required String comment,
    required String author,
  });
}
