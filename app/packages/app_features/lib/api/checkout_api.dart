import 'package:app_data/app_data.dart';

/// Checkout 页面只消费当前流程需要的窄本地业务边界。
abstract interface class CheckoutApi {
  Stream<PaymentProfileSnapshot> get paymentProfileSnapshots;

  Future<CheckoutSession> load({required Money subtotal});

  Future<CheckoutSession> applyVoucher({
    required String code,
    required Money subtotal,
  });

  Future<CheckoutSession> applyVoucherById({
    required String voucherId,
    required Money subtotal,
  });

  Future<CheckoutSession> clearVoucher({required Money subtotal});

  Future<CheckoutSession> upsertAddress({
    required ShippingAddress address,
    required Money subtotal,
  });

  Future<CheckoutSession> selectAddress({
    required String addressId,
    required Money subtotal,
  });

  Future<CheckoutSession> selectPaymentMethod({
    required String paymentMethodId,
    required Money subtotal,
  });

  Future<CheckoutAttempt> createPaymentAttempt();

  Future<CheckoutPaymentResult> submitPayment({
    required String attemptId,
    required Money amount,
  });
}
