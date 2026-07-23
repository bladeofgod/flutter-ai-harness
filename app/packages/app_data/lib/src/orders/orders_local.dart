import 'package:app_core/app_core.dart';

import '../catalog/catalog_models.dart';
import '../checkout/checkout_models.dart';
import 'orders_failure.dart';
import 'orders_fixture_handler.dart';
import 'orders_models.dart';

part 'orders_mapper.dart';

typedef OrdersMutationResult = ({Order order, bool didMutate});

/// 通过 Fixture Transport 读写确定性的进程内 Orders。
final class OrdersLocalDataSource {
  const OrdersLocalDataSource({required ApiClient apiClient})
    : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<Order>> load({required ActivityFilter filter}) async {
    final response = await _apiClient.send<Object?>(
      ApiRequest(
        key: OrdersFixtureHandler.loadActivityKey,
        payload: <String, Object?>{'filter': filter.name},
      ),
    );
    return switch (response) {
      ApiSuccess<Object?>(:final payload) => _OrdersFixtureMapper.activity(
        payload,
      ),
      ApiError<Object?>(:final failure) => _throwMappedFailure(failure),
    };
  }

  Future<Order> loadOrder({required String orderId}) async {
    final response = await _apiClient.send<Object?>(
      ApiRequest(
        key: OrdersFixtureHandler.loadDetailKey,
        payload: <String, Object?>{'orderId': orderId},
      ),
    );
    return switch (response) {
      ApiSuccess<Object?>(:final payload) => _OrdersFixtureMapper.order(
        payload,
      ),
      ApiError<Object?>(:final failure) => _throwMappedFailure(failure),
    };
  }

  Future<OrdersMutationResult> addReceipt(
    CheckoutReceipt receipt, {
    List<OrderLine> lines = const <OrderLine>[],
  }) => _mutate(
    ApiRequest(
      key: OrdersFixtureHandler.addReceiptKey,
      payload: _OrdersFixtureMapper.receiptInput(receipt, lines: lines),
    ),
  );

  Future<OrdersMutationResult> consumeNotification({required String orderId}) =>
      _mutate(
        ApiRequest(
          key: OrdersFixtureHandler.consumeNotificationKey,
          payload: <String, Object?>{'orderId': orderId},
        ),
      );

  Future<OrdersMutationResult> submitReview({
    required String orderId,
    required int rating,
    required String comment,
    required String author,
  }) => _mutate(
    ApiRequest(
      key: OrdersFixtureHandler.submitReviewKey,
      payload: <String, Object?>{
        'orderId': orderId,
        'rating': rating,
        'comment': comment,
        'author': author,
      },
    ),
  );

  Future<OrdersMutationResult> _mutate(ApiRequest request) async {
    final response = await _apiClient.send<Object?>(request);
    return switch (response) {
      ApiSuccess<Object?>(:final payload) => _OrdersFixtureMapper.mutation(
        payload,
      ),
      ApiError<Object?>(:final failure) => _throwMappedFailure(failure),
    };
  }

  Never _throwMappedFailure(ApiFailure failure) {
    final mappedFailure = OrdersFailure(switch (failure.kind) {
      ApiFailureKind.unknownRequest => OrdersFailureCode.unknownRequest,
      ApiFailureKind.transport => OrdersFailureCode.transportUnavailable,
      ApiFailureKind.invalidResponse => OrdersFailureCode.invalidResponse,
      ApiFailureKind.rejected => switch (failure.code) {
        'orders.invalid_input' => OrdersFailureCode.invalidInput,
        'orders.order_not_found' => OrdersFailureCode.orderNotFound,
        'orders.already_reviewed' => OrdersFailureCode.alreadyReviewed,
        _ => OrdersFailureCode.invalidResponse,
      },
    });
    final stackTrace = failure.stackTrace;
    if (stackTrace != null) {
      Error.throwWithStackTrace(mappedFailure, stackTrace);
    }
    throw mappedFailure;
  }
}
