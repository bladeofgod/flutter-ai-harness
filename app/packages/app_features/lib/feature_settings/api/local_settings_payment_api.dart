import 'package:app_data/app_data.dart'
    show
        CheckoutReceipt,
        PaymentMethod,
        PaymentProfileSnapshot,
        ShippingAddress;
import 'package:app_data/settings_payment.dart';

import '../../api/settings_payment_api.dart';

final class LocalSettingsPaymentAddressApi
    implements SettingsPaymentAddressApi {
  const LocalSettingsPaymentAddressApi({
    required SettingsPaymentLocalDataSource dataSource,
  }) : _dataSource = dataSource;

  final SettingsPaymentLocalDataSource _dataSource;

  @override
  Stream<PaymentProfileSnapshot> get paymentProfileSnapshots =>
      _dataSource.paymentProfileSnapshots;

  @override
  Future<SettingsPaymentOverview> load() => _dataSource.load();

  @override
  Future<SettingsPaymentOverview> upsertPaymentMethod(PaymentMethod method) =>
      _dataSource.upsertPaymentMethod(method);

  @override
  Future<SettingsPaymentOverview> removePaymentMethod(String methodId) =>
      _dataSource.removePaymentMethod(methodId);

  @override
  Future<SettingsPaymentOverview> selectPaymentMethod(String methodId) =>
      _dataSource.selectPaymentMethod(methodId);

  @override
  Future<SettingsPaymentOverview> upsertAddress(ShippingAddress address) =>
      _dataSource.upsertAddress(address);

  @override
  Future<SettingsPaymentOverview> removeAddress(String addressId) =>
      _dataSource.removeAddress(addressId);

  @override
  Future<SettingsPaymentOverview> selectAddress(String addressId) =>
      _dataSource.selectAddress(addressId);

  @override
  Future<SettingsPaymentOverview> recordReceipt(CheckoutReceipt receipt) =>
      _dataSource.recordReceipt(receipt);
}
