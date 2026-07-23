import 'package:app_data/app_data.dart' show CheckoutReceipt, ProductSummary;
import 'package:app_data/orders.dart';

import '../../api/orders_api.dart';

final class LocalOrdersApi implements OrdersApi {
  const LocalOrdersApi({required OrdersLocalDataSource dataSource})
    : _dataSource = dataSource;

  final OrdersLocalDataSource _dataSource;

  @override
  Future<List<Order>> load({required ActivityFilter filter}) =>
      _dataSource.load(filter: filter);

  @override
  Future<Order> loadOrder({required String orderId}) =>
      _dataSource.loadOrder(orderId: orderId);

  @override
  Future<Order> acceptReceipt(
    CheckoutReceipt receipt, {
    List<OrderLine> lines = const <OrderLine>[],
  }) async {
    final resolvedLines = lines.isEmpty
        ? <OrderLine>[
            OrderLine(
              product: ProductSummary(
                id: 'receipt-${receipt.id}',
                title: 'Demo order item',
                imageAssetKey:
                    'assets/images/catalog/products/shop_product_01.png',
                price: receipt.amount,
              ),
              quantity: 1,
              unitPrice: receipt.amount,
            ),
          ]
        : lines;
    return (await _dataSource.addReceipt(receipt, lines: resolvedLines)).order;
  }

  @override
  Future<Order> consumeNotification({required String orderId}) async =>
      (await _dataSource.consumeNotification(orderId: orderId)).order;

  @override
  Future<Order> submitReview({
    required String orderId,
    required int rating,
    required String comment,
    required String author,
  }) async => (await _dataSource.submitReview(
    orderId: orderId,
    rating: rating,
    comment: comment,
    author: author,
  )).order;
}
