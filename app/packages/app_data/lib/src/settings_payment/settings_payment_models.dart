import '../checkout/checkout_models.dart';

final class SettingsPaymentOverview {
  factory SettingsPaymentOverview({
    required PaymentProfileSnapshot paymentProfile,
    required List<CheckoutReceipt> receipts,
  }) => SettingsPaymentOverview._(
    paymentProfile: paymentProfile,
    receipts: List<CheckoutReceipt>.unmodifiable(receipts),
  );

  const SettingsPaymentOverview._({
    required this.paymentProfile,
    required this.receipts,
  });

  final PaymentProfileSnapshot paymentProfile;
  final List<CheckoutReceipt> receipts;

  SettingsPaymentOverview withPaymentProfile(
    PaymentProfileSnapshot paymentProfile,
  ) => SettingsPaymentOverview(
    paymentProfile: paymentProfile,
    receipts: receipts,
  );
}
