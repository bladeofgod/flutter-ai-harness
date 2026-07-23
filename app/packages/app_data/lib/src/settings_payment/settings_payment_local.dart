import 'package:app_core/app_core.dart';

import '../catalog/catalog_models.dart';
import '../checkout/checkout_models.dart';
import '../checkout/payment_profile_store.dart';
import 'settings_payment_failure.dart';
import 'settings_payment_fixture_handler.dart';
import 'settings_payment_models.dart';

part 'settings_payment_mapper.dart';

final class SettingsPaymentLocalDataSource {
  const SettingsPaymentLocalDataSource({
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

  Future<SettingsPaymentOverview> load() =>
      _overview(const ApiRequest(key: SettingsPaymentFixtureHandler.loadKey));

  Future<SettingsPaymentOverview> upsertAddress(ShippingAddress address) =>
      _overview(
        ApiRequest(
          key: SettingsPaymentFixtureHandler.upsertAddressKey,
          payload: <String, Object?>{
            'address': _SettingsPaymentMapper.addressPayload(address),
          },
        ),
      );

  Future<SettingsPaymentOverview> removeAddress(String addressId) => _overview(
    ApiRequest(
      key: SettingsPaymentFixtureHandler.removeAddressKey,
      payload: <String, Object?>{'addressId': addressId},
    ),
  );

  Future<SettingsPaymentOverview> selectAddress(String addressId) => _overview(
    ApiRequest(
      key: SettingsPaymentFixtureHandler.selectAddressKey,
      payload: <String, Object?>{'addressId': addressId},
    ),
  );

  Future<SettingsPaymentOverview> upsertPaymentMethod(PaymentMethod method) =>
      _overview(
        ApiRequest(
          key: SettingsPaymentFixtureHandler.upsertPaymentMethodKey,
          payload: <String, Object?>{
            'paymentMethod': _SettingsPaymentMapper.paymentMethodPayload(
              method,
            ),
          },
        ),
      );

  Future<SettingsPaymentOverview> removePaymentMethod(String methodId) =>
      _overview(
        ApiRequest(
          key: SettingsPaymentFixtureHandler.removePaymentMethodKey,
          payload: <String, Object?>{'paymentMethodId': methodId},
        ),
      );

  Future<SettingsPaymentOverview> selectPaymentMethod(String methodId) =>
      _overview(
        ApiRequest(
          key: SettingsPaymentFixtureHandler.selectPaymentMethodKey,
          payload: <String, Object?>{'paymentMethodId': methodId},
        ),
      );

  Future<SettingsPaymentOverview> recordReceipt(CheckoutReceipt receipt) =>
      _overview(
        ApiRequest(
          key: SettingsPaymentFixtureHandler.recordReceiptKey,
          payload: <String, Object?>{
            'receipt': _SettingsPaymentMapper.receiptPayload(receipt),
          },
        ),
      );

  Future<SettingsPaymentOverview> _overview(ApiRequest request) async {
    final response = await _apiClient.send<Object?>(request);
    return switch (response) {
      ApiSuccess<Object?>(:final payload) => _SettingsPaymentMapper.overview(
        payload,
      ),
      ApiError<Object?>(:final failure) => _throwMappedFailure(failure),
    };
  }

  Never _throwMappedFailure(ApiFailure failure) {
    final mappedFailure = SettingsPaymentFailure(switch (failure.kind) {
      ApiFailureKind.unknownRequest =>
        SettingsPaymentFailureCode.unknownRequest,
      ApiFailureKind.transport =>
        SettingsPaymentFailureCode.transportUnavailable,
      ApiFailureKind.invalidResponse =>
        SettingsPaymentFailureCode.invalidResponse,
      ApiFailureKind.rejected => switch (failure.code) {
        'settings_payment.invalid_input' =>
          SettingsPaymentFailureCode.invalidInput,
        _ => SettingsPaymentFailureCode.invalidResponse,
      },
    });
    final stackTrace = failure.stackTrace;
    if (stackTrace != null) {
      Error.throwWithStackTrace(mappedFailure, stackTrace);
    }
    throw mappedFailure;
  }
}
