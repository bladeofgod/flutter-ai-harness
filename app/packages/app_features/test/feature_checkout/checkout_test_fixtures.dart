import 'dart:async';

import 'package:app_data/app_data.dart';
import 'package:app_features/api/cart_api.dart';
import 'package:app_features/api/checkout_api.dart';

final class FakeCheckoutApi implements CheckoutApi {
  FakeCheckoutApi() {
    _profiles = StreamController<PaymentProfileSnapshot>.broadcast(
      sync: true,
      onListen: () => activeProfileListeners += 1,
      onCancel: () => activeProfileListeners -= 1,
    );
  }

  late final StreamController<PaymentProfileSnapshot> _profiles;
  PaymentProfileSnapshot profile = fixedPaymentProfileSnapshot();
  Voucher? voucher;
  Completer<CheckoutPaymentResult>? nextPayment;
  Object? loadError;
  int loadCount = 0;
  int attemptSequence = 0;
  int submitCount = 0;
  int activeProfileListeners = 0;

  @override
  Stream<PaymentProfileSnapshot> get paymentProfileSnapshots =>
      _profiles.stream;

  @override
  Future<CheckoutSession> load({required Money subtotal}) async {
    loadCount += 1;
    final error = loadError;
    if (error != null) {
      throw error;
    }
    return _session(subtotal);
  }

  @override
  Future<CheckoutSession> applyVoucher({
    required String code,
    required Money subtotal,
  }) async {
    if (code.trim().toUpperCase() != 'SHOPPE5') {
      throw const CheckoutFailure(CheckoutFailureCode.invalidVoucher);
    }
    voucher = demoVoucher();
    return _session(subtotal);
  }

  @override
  Future<CheckoutSession> applyVoucherById({
    required String voucherId,
    required Money subtotal,
  }) async {
    if (voucherId.trim() != 'voucher-shoppe-five') {
      throw const CheckoutFailure(CheckoutFailureCode.invalidVoucher);
    }
    voucher = demoVoucher();
    return _session(subtotal);
  }

  @override
  Future<CheckoutSession> clearVoucher({required Money subtotal}) async {
    voucher = null;
    return _session(subtotal);
  }

  @override
  Future<CheckoutSession> upsertAddress({
    required ShippingAddress address,
    required Money subtotal,
  }) async {
    final addresses = <ShippingAddress>[
      for (final current in profile.addresses)
        if (current.id != address.id) current,
      address,
    ];
    profile = PaymentProfileSnapshot(
      addresses: addresses,
      paymentMethods: profile.paymentMethods,
      selectedAddressId: address.id,
      selectedPaymentMethodId: profile.selectedPaymentMethodId,
    );
    _profiles.add(profile);
    return _session(subtotal);
  }

  @override
  Future<CheckoutSession> selectAddress({
    required String addressId,
    required Money subtotal,
  }) async {
    profile = PaymentProfileSnapshot(
      addresses: profile.addresses,
      paymentMethods: profile.paymentMethods,
      selectedAddressId: addressId,
      selectedPaymentMethodId: profile.selectedPaymentMethodId,
    );
    _profiles.add(profile);
    return _session(subtotal);
  }

  @override
  Future<CheckoutSession> selectPaymentMethod({
    required String paymentMethodId,
    required Money subtotal,
  }) async {
    profile = PaymentProfileSnapshot(
      addresses: profile.addresses,
      paymentMethods: profile.paymentMethods,
      selectedAddressId: profile.selectedAddressId,
      selectedPaymentMethodId: paymentMethodId,
    );
    _profiles.add(profile);
    return _session(subtotal);
  }

  @override
  Future<CheckoutAttempt> createPaymentAttempt() async =>
      CheckoutAttempt(id: 'checkout-attempt-${++attemptSequence}');

  @override
  Future<CheckoutPaymentResult> submitPayment({
    required String attemptId,
    required Money amount,
  }) async {
    submitCount += 1;
    final pending = nextPayment;
    if (pending != null) {
      nextPayment = null;
      return pending.future;
    }
    if (profile.selectedPaymentMethodId == 'payment-card-secondary') {
      return const CheckoutPaymentFailed(
        CheckoutPaymentFailureReason.paymentNotCompleted,
      );
    }
    return CheckoutPaymentSucceeded(
      demoReceipt(attemptId: attemptId, amount: amount),
    );
  }

  void emitExternalProfile(PaymentProfileSnapshot snapshot) {
    profile = snapshot;
    _profiles.add(snapshot);
  }

  CheckoutSession _session(Money subtotal) => CheckoutSession(
    subtotal: subtotal,
    paymentProfile: profile,
    voucher: voucher,
  );

  Future<void> close() => _profiles.close();
}

final class FakeCheckoutCartApi implements CartApi {
  FakeCheckoutCartApi({Cart? initialCart})
    : current = initialCart ?? checkoutCart();

  Cart current;
  int clearCount = 0;
  int clearFailuresRemaining = 0;
  final List<String> clearedAttemptIds = <String>[];
  final StreamController<Cart> _snapshots = StreamController<Cart>.broadcast(
    sync: true,
  );

  @override
  Stream<Cart> get snapshots => _snapshots.stream;

  @override
  Future<Cart> load() async => current;

  @override
  Future<Cart> clearAfterSuccessfulCheckout({required String attemptId}) async {
    clearCount += 1;
    clearedAttemptIds.add(attemptId);
    if (clearFailuresRemaining > 0) {
      clearFailuresRemaining -= 1;
      throw const CartFailure(CartFailureCode.transportUnavailable);
    }
    current = Cart(currency: Currency.usd, items: const <CartItem>[]);
    _snapshots.add(current);
    return current;
  }

  @override
  Future<Cart> remove({required String lineId}) async => current;

  @override
  Future<Cart> setQuantity({
    required String lineId,
    required int quantity,
  }) async => current;

  @override
  Future<Cart> upsert(CartLineInput input) async => current;

  Future<void> close() => _snapshots.close();
}

Cart checkoutCart() => Cart(
  currency: Currency.usd,
  items: <CartItem>[
    CartItem(
      product: ProductSummary(
        id: 'checkout-product',
        title: 'Demo checkout product',
        imageAssetKey: 'assets/images/cart/cart_item_01.png',
        price: Money(currency: Currency.usd, minorUnits: 3400),
      ),
      variation: ProductVariation(color: 'Pink', size: 'M'),
      quantity: 1,
    ),
  ],
);

Voucher demoVoucher() => Voucher(
  id: 'voucher-shoppe-five',
  code: 'SHOPPE5',
  title: r'$5 off your Demo order',
  discount: Money(currency: Currency.usd, minorUnits: 500),
  minimumSpend: Money(currency: Currency.usd, minorUnits: 1000),
);

CheckoutReceipt demoReceipt({
  required String attemptId,
  required Money amount,
}) => CheckoutReceipt(
  id: 'receipt-$attemptId',
  attemptId: attemptId,
  amount: amount,
  paymentMethodId: 'payment-card-primary',
  maskedPaymentLabel: 'Visa •••• 9843',
  shippingAddress: fixedPaymentProfileSnapshot().selectedAddress!,
  issuedAt: DateTime.utc(2026, 7, 22, 8),
);
