import 'package:app_core/app_core.dart';

import '../catalog/catalog_models.dart';
import 'cart_failure.dart';
import 'cart_fixture_handler.dart';
import 'cart_models.dart';

part 'cart_mapper.dart';

typedef CartMutationResult = ({Cart cart, bool didMutate});

/// 通过 [ApiClient] 读写确定性的进程内 Cart Fixture。
final class CartLocalDataSource {
  const CartLocalDataSource({required ApiClient apiClient})
    : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<Cart> load() async =>
      (await _send(const ApiRequest(key: CartFixtureHandler.loadKey))).cart;

  Future<CartMutationResult> upsert(CartLineInput input) => _send(
    ApiRequest(
      key: CartFixtureHandler.upsertKey,
      payload: _CartFixtureMapper.lineInputPayload(input),
    ),
  );

  Future<CartMutationResult> setQuantity({
    required String lineId,
    required int quantity,
  }) => _send(
    ApiRequest(
      key: CartFixtureHandler.updateQuantityKey,
      payload: <String, Object?>{'lineId': lineId, 'quantity': quantity},
    ),
  );

  Future<CartMutationResult> remove({required String lineId}) => _send(
    ApiRequest(
      key: CartFixtureHandler.removeKey,
      payload: <String, Object?>{'lineId': lineId},
    ),
  );

  Future<CartMutationResult> clearAfterSuccessfulCheckout({
    required String attemptId,
  }) => _send(
    ApiRequest(
      key: CartFixtureHandler.clearAfterCheckoutKey,
      payload: <String, Object?>{'attemptId': attemptId},
    ),
  );

  Future<CartMutationResult> _send(ApiRequest request) async {
    final response = await _apiClient.send<Object?>(request);
    return switch (response) {
      ApiSuccess<Object?>(:final payload) => _CartFixtureMapper.mutationResult(
        payload,
      ),
      ApiError<Object?>(:final failure) => _throwMappedFailure(failure),
    };
  }

  Never _throwMappedFailure(ApiFailure failure) {
    final mappedFailure = CartFailure(switch (failure.kind) {
      ApiFailureKind.unknownRequest => CartFailureCode.unknownRequest,
      ApiFailureKind.transport => CartFailureCode.transportUnavailable,
      ApiFailureKind.invalidResponse => CartFailureCode.invalidResponse,
      ApiFailureKind.rejected => switch (failure.code) {
        'cart.invalid_input' => CartFailureCode.invalidInput,
        'cart.line_not_found' => CartFailureCode.lineNotFound,
        _ => CartFailureCode.invalidResponse,
      },
    });
    final stackTrace = failure.stackTrace;
    if (stackTrace != null) {
      Error.throwWithStackTrace(mappedFailure, stackTrace);
    }
    throw mappedFailure;
  }
}
