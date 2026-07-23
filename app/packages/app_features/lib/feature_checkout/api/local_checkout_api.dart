import 'package:app_data/app_data.dart';

import '../../api/checkout_api.dart';

final class LocalCheckoutApi implements CheckoutApi {
  const LocalCheckoutApi({required CheckoutLocalDataSource dataSource})
    : _dataSource = dataSource;

  final CheckoutLocalDataSource _dataSource;

  @override
  Stream<PaymentProfileSnapshot> get paymentProfileSnapshots =>
      _dataSource.paymentProfileSnapshots;

  @override
  Future<CheckoutSession> load({required Money subtotal}) =>
      _dataSource.load(subtotal: subtotal);

  @override
  Future<CheckoutSession> applyVoucher({
    required String code,
    required Money subtotal,
  }) => _dataSource.applyVoucher(code: code, subtotal: subtotal);

  @override
  Future<CheckoutSession> applyVoucherById({
    required String voucherId,
    required Money subtotal,
  }) => _dataSource.applyVoucherById(voucherId: voucherId, subtotal: subtotal);

  @override
  Future<CheckoutSession> clearVoucher({required Money subtotal}) =>
      _dataSource.clearVoucher(subtotal: subtotal);

  @override
  Future<CheckoutSession> upsertAddress({
    required ShippingAddress address,
    required Money subtotal,
  }) => _dataSource.upsertAddress(address: address, subtotal: subtotal);

  @override
  Future<CheckoutSession> selectAddress({
    required String addressId,
    required Money subtotal,
  }) => _dataSource.selectAddress(addressId: addressId, subtotal: subtotal);

  @override
  Future<CheckoutSession> selectPaymentMethod({
    required String paymentMethodId,
    required Money subtotal,
  }) => _dataSource.selectPaymentMethod(
    paymentMethodId: paymentMethodId,
    subtotal: subtotal,
  );

  @override
  Future<CheckoutAttempt> createPaymentAttempt() =>
      _dataSource.createPaymentAttempt();

  @override
  Future<CheckoutPaymentResult> submitPayment({
    required String attemptId,
    required Money amount,
  }) => _dataSource.submitPayment(attemptId: attemptId, amount: amount);
}
