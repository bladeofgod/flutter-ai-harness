import 'package:app_core/app_core.dart';

import '../catalog/catalog_models.dart';
import 'checkout_failure.dart';
import 'checkout_fixture_handler.dart';
import 'checkout_models.dart';
import 'payment_profile_store.dart';

part 'checkout_mapper.dart';

/// 通过 Fixture Transport 读写 Checkout，并观察唯一 PaymentProfileStore。
final class CheckoutLocalDataSource {
  const CheckoutLocalDataSource({
    required ApiClient apiClient,
    required PaymentProfileStore paymentProfileStore,
  }) : _apiClient = apiClient,
       _paymentProfileStore = paymentProfileStore;

  final ApiClient _apiClient;
  final PaymentProfileStore _paymentProfileStore;

  Stream<PaymentProfileSnapshot> get paymentProfileSnapshots =>
      _paymentProfileStore.snapshots;

  PaymentProfileSnapshot get currentPaymentProfile =>
      _paymentProfileStore.current;

  Future<CheckoutSession> load({required Money subtotal}) =>
      _session(CheckoutFixtureHandler.loadKey, subtotal: subtotal);

  Future<CheckoutSession> applyVoucher({
    required String code,
    required Money subtotal,
  }) => _session(
    CheckoutFixtureHandler.applyVoucherKey,
    subtotal: subtotal,
    values: <String, Object?>{'code': code},
  );

  Future<CheckoutSession> applyVoucherById({
    required String voucherId,
    required Money subtotal,
  }) => _session(
    CheckoutFixtureHandler.applyVoucherByIdKey,
    subtotal: subtotal,
    values: <String, Object?>{'voucherId': voucherId},
  );

  Future<CheckoutSession> clearVoucher({required Money subtotal}) =>
      _session(CheckoutFixtureHandler.clearVoucherKey, subtotal: subtotal);

  Future<CheckoutSession> upsertAddress({
    required ShippingAddress address,
    required Money subtotal,
  }) => _session(
    CheckoutFixtureHandler.upsertAddressKey,
    subtotal: subtotal,
    values: <String, Object?>{
      'address': _CheckoutFixtureMapper.addressPayload(address),
    },
  );

  Future<CheckoutSession> removeAddress({
    required String addressId,
    required Money subtotal,
  }) => _session(
    CheckoutFixtureHandler.removeAddressKey,
    subtotal: subtotal,
    values: <String, Object?>{'addressId': addressId},
  );

  Future<CheckoutSession> selectAddress({
    required String addressId,
    required Money subtotal,
  }) => _session(
    CheckoutFixtureHandler.selectAddressKey,
    subtotal: subtotal,
    values: <String, Object?>{'addressId': addressId},
  );

  Future<CheckoutSession> upsertPaymentMethod({
    required PaymentMethod paymentMethod,
    required Money subtotal,
  }) => _session(
    CheckoutFixtureHandler.upsertPaymentMethodKey,
    subtotal: subtotal,
    values: <String, Object?>{
      'paymentMethod': _CheckoutFixtureMapper.paymentMethodPayload(
        paymentMethod,
      ),
    },
  );

  Future<CheckoutSession> removePaymentMethod({
    required String paymentMethodId,
    required Money subtotal,
  }) => _session(
    CheckoutFixtureHandler.removePaymentMethodKey,
    subtotal: subtotal,
    values: <String, Object?>{'paymentMethodId': paymentMethodId},
  );

  Future<CheckoutSession> selectPaymentMethod({
    required String paymentMethodId,
    required Money subtotal,
  }) => _session(
    CheckoutFixtureHandler.selectPaymentMethodKey,
    subtotal: subtotal,
    values: <String, Object?>{'paymentMethodId': paymentMethodId},
  );

  Future<CheckoutAttempt> createPaymentAttempt() async {
    final response = await _apiClient.send<Object?>(
      const ApiRequest(key: CheckoutFixtureHandler.createPaymentAttemptKey),
    );
    return switch (response) {
      ApiSuccess<Object?>(:final payload) =>
        _CheckoutFixtureMapper.checkoutAttempt(payload),
      ApiError<Object?>(:final failure) => _throwMappedFailure(failure),
    };
  }

  Future<CheckoutPaymentResult> submitPayment({
    required String attemptId,
    required Money amount,
  }) async {
    final response = await _apiClient.send<Object?>(
      ApiRequest(
        key: CheckoutFixtureHandler.submitPaymentKey,
        payload: <String, Object?>{
          'attemptId': attemptId,
          'amount': _CheckoutFixtureMapper.moneyPayload(amount),
        },
      ),
    );
    return switch (response) {
      ApiSuccess<Object?>(:final payload) =>
        _CheckoutFixtureMapper.paymentResult(payload),
      ApiError<Object?>(:final failure) => _throwMappedFailure(failure),
    };
  }

  Future<CheckoutSession> _session(
    String key, {
    required Money subtotal,
    Map<String, Object?> values = const <String, Object?>{},
  }) async {
    final response = await _apiClient.send<Object?>(
      ApiRequest(
        key: key,
        payload: <String, Object?>{
          ...values,
          'subtotal': _CheckoutFixtureMapper.moneyPayload(subtotal),
        },
      ),
    );
    return switch (response) {
      ApiSuccess<Object?>(:final payload) => _CheckoutFixtureMapper.session(
        payload,
      ),
      ApiError<Object?>(:final failure) => _throwMappedFailure(failure),
    };
  }

  Never _throwMappedFailure(ApiFailure failure) {
    final mappedFailure = CheckoutFailure(switch (failure.kind) {
      ApiFailureKind.unknownRequest => CheckoutFailureCode.unknownRequest,
      ApiFailureKind.transport => CheckoutFailureCode.transportUnavailable,
      ApiFailureKind.invalidResponse => CheckoutFailureCode.invalidResponse,
      ApiFailureKind.rejected => switch (failure.code) {
        'checkout.invalid_input' => CheckoutFailureCode.invalidInput,
        'checkout.invalid_voucher' => CheckoutFailureCode.invalidVoucher,
        _ => CheckoutFailureCode.invalidResponse,
      },
    });
    final stackTrace = failure.stackTrace;
    if (stackTrace != null) {
      Error.throwWithStackTrace(mappedFailure, stackTrace);
    }
    throw mappedFailure;
  }
}
