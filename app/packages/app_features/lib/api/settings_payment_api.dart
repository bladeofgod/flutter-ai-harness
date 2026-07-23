import 'package:app_data/app_data.dart'
    show
        CheckoutReceipt,
        PaymentMethod,
        PaymentProfileSnapshot,
        ShippingAddress;
import 'package:app_data/settings_payment.dart';

/// Settings 支付方式与地址页面消费的窄业务边界。
abstract interface class SettingsPaymentAddressApi {
  Stream<PaymentProfileSnapshot> get paymentProfileSnapshots;

  Future<SettingsPaymentOverview> load();

  Future<SettingsPaymentOverview> upsertPaymentMethod(PaymentMethod method);

  Future<SettingsPaymentOverview> removePaymentMethod(String methodId);

  Future<SettingsPaymentOverview> selectPaymentMethod(String methodId);

  Future<SettingsPaymentOverview> upsertAddress(ShippingAddress address);

  Future<SettingsPaymentOverview> removeAddress(String addressId);

  Future<SettingsPaymentOverview> selectAddress(String addressId);

  /// 根装配点在成功 Checkout 后幂等写入历史。
  Future<SettingsPaymentOverview> recordReceipt(CheckoutReceipt receipt);
}
