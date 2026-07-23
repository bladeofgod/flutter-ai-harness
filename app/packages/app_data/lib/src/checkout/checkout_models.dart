import '../catalog/catalog_models.dart';

enum PaymentState { ready, inProgress, failed, succeeded }

enum CheckoutPaymentFailureReason { paymentNotCompleted, invalidSession }

final class CheckoutAttempt {
  factory CheckoutAttempt({required String id}) =>
      CheckoutAttempt._(_requiredText(id, 'id'));

  const CheckoutAttempt._(this.id);

  final String id;
}

final class ShippingAddress {
  factory ShippingAddress({
    required String id,
    required String recipientName,
    required String streetLine,
    required String city,
    required String region,
    required String postalCode,
    required String country,
  }) => ShippingAddress._(
    id: _requiredText(id, 'id'),
    recipientName: _requiredText(recipientName, 'recipientName'),
    streetLine: _requiredText(streetLine, 'streetLine'),
    city: _requiredText(city, 'city'),
    region: _requiredText(region, 'region'),
    postalCode: _requiredText(postalCode, 'postalCode'),
    country: _requiredText(country, 'country'),
  );

  const ShippingAddress._({
    required this.id,
    required this.recipientName,
    required this.streetLine,
    required this.city,
    required this.region,
    required this.postalCode,
    required this.country,
  });

  final String id;
  final String recipientName;
  final String streetLine;
  final String city;
  final String region;
  final String postalCode;
  final String country;

  String get summary => '$streetLine, $city, $region $postalCode, $country';

  @override
  String toString() => 'ShippingAddress(id: $id, details: <redacted>)';
}

/// 仅保存支付方式的展示摘要，不保存完整卡号、CVV 或支付 Token。
final class PaymentMethod {
  factory PaymentMethod({
    required String id,
    required String brand,
    required String lastFour,
  }) {
    final normalizedLastFour = lastFour.trim();
    if (!RegExp(r'^\d{4}$').hasMatch(normalizedLastFour)) {
      throw ArgumentError.value(
        lastFour,
        'lastFour',
        'A masked payment method requires exactly four trailing digits.',
      );
    }
    return PaymentMethod._(
      id: _requiredText(id, 'id'),
      brand: _requiredText(brand, 'brand'),
      lastFour: normalizedLastFour,
    );
  }

  const PaymentMethod._({
    required this.id,
    required this.brand,
    required this.lastFour,
  });

  final String id;
  final String brand;
  final String lastFour;

  String get maskedLabel => '$brand •••• $lastFour';

  @override
  String toString() => 'PaymentMethod(id: $id, card: <redacted>)';
}

final class PaymentProfileSnapshot {
  factory PaymentProfileSnapshot({
    required List<ShippingAddress> addresses,
    required List<PaymentMethod> paymentMethods,
    required String? selectedAddressId,
    required String? selectedPaymentMethodId,
  }) {
    _requireUniqueIds(addresses.map((address) => address.id), 'addresses');
    _requireUniqueIds(
      paymentMethods.map((method) => method.id),
      'paymentMethods',
    );
    if (selectedAddressId != null &&
        !addresses.any((address) => address.id == selectedAddressId)) {
      throw ArgumentError.value(
        selectedAddressId,
        'selectedAddressId',
        'Selected address is not present in the snapshot.',
      );
    }
    if (selectedPaymentMethodId != null &&
        !paymentMethods.any((method) => method.id == selectedPaymentMethodId)) {
      throw ArgumentError.value(
        selectedPaymentMethodId,
        'selectedPaymentMethodId',
        'Selected payment method is not present in the snapshot.',
      );
    }
    return PaymentProfileSnapshot._(
      addresses: List<ShippingAddress>.unmodifiable(addresses),
      paymentMethods: List<PaymentMethod>.unmodifiable(paymentMethods),
      selectedAddressId: selectedAddressId,
      selectedPaymentMethodId: selectedPaymentMethodId,
    );
  }

  const PaymentProfileSnapshot._({
    required this.addresses,
    required this.paymentMethods,
    required this.selectedAddressId,
    required this.selectedPaymentMethodId,
  });

  final List<ShippingAddress> addresses;
  final List<PaymentMethod> paymentMethods;
  final String? selectedAddressId;
  final String? selectedPaymentMethodId;

  ShippingAddress? get selectedAddress => _firstWhereOrNull(
    addresses,
    (address) => address.id == selectedAddressId,
  );

  PaymentMethod? get selectedPaymentMethod => _firstWhereOrNull(
    paymentMethods,
    (method) => method.id == selectedPaymentMethodId,
  );
}

final class Voucher {
  factory Voucher({
    required String id,
    required String code,
    required String title,
    required Money discount,
    required Money minimumSpend,
  }) {
    if (discount.currency != minimumSpend.currency) {
      throw ArgumentError('Voucher amounts must use the same currency.');
    }
    return Voucher._(
      id: _requiredText(id, 'id'),
      code: _requiredText(code, 'code').toUpperCase(),
      title: _requiredText(title, 'title'),
      discount: discount,
      minimumSpend: minimumSpend,
    );
  }

  const Voucher._({
    required this.id,
    required this.code,
    required this.title,
    required this.discount,
    required this.minimumSpend,
  });

  final String id;
  final String code;
  final String title;
  final Money discount;
  final Money minimumSpend;

  Money discountFor(Money subtotal) {
    if (subtotal.currency != discount.currency ||
        subtotal.minorUnits < minimumSpend.minorUnits) {
      return Money(currency: subtotal.currency, minorUnits: 0);
    }
    return Money(
      currency: subtotal.currency,
      minorUnits: discount.minorUnits > subtotal.minorUnits
          ? subtotal.minorUnits
          : discount.minorUnits,
    );
  }
}

final class CheckoutReceipt {
  factory CheckoutReceipt({
    required String id,
    required String attemptId,
    required Money amount,
    required String paymentMethodId,
    required String maskedPaymentLabel,
    required ShippingAddress shippingAddress,
    required DateTime issuedAt,
  }) => CheckoutReceipt._(
    id: _requiredText(id, 'id'),
    attemptId: _requiredText(attemptId, 'attemptId'),
    amount: amount,
    paymentMethodId: _requiredText(paymentMethodId, 'paymentMethodId'),
    maskedPaymentLabel: _requiredText(maskedPaymentLabel, 'maskedPaymentLabel'),
    shippingAddress: shippingAddress,
    issuedAt: issuedAt.toUtc(),
  );

  const CheckoutReceipt._({
    required this.id,
    required this.attemptId,
    required this.amount,
    required this.paymentMethodId,
    required this.maskedPaymentLabel,
    required this.shippingAddress,
    required this.issuedAt,
  });

  final String id;
  final String attemptId;
  final Money amount;
  final String paymentMethodId;
  final String maskedPaymentLabel;
  final ShippingAddress shippingAddress;
  final DateTime issuedAt;

  @override
  String toString() =>
      'CheckoutReceipt(id: $id, attemptId: $attemptId, payment: <redacted>)';
}

sealed class CheckoutPaymentResult {
  const CheckoutPaymentResult();
}

final class CheckoutPaymentSucceeded extends CheckoutPaymentResult {
  const CheckoutPaymentSucceeded(this.receipt);

  final CheckoutReceipt receipt;
}

final class CheckoutPaymentFailed extends CheckoutPaymentResult {
  const CheckoutPaymentFailed(this.reason);

  final CheckoutPaymentFailureReason reason;
}

final class CheckoutSession {
  factory CheckoutSession({
    required Money subtotal,
    required PaymentProfileSnapshot paymentProfile,
    Voucher? voucher,
    PaymentState paymentState = PaymentState.ready,
    CheckoutReceipt? receipt,
    CheckoutPaymentFailureReason? failureReason,
  }) {
    final discount =
        voucher?.discountFor(subtotal) ??
        Money(currency: subtotal.currency, minorUnits: 0);
    if (paymentState == PaymentState.succeeded && receipt == null) {
      throw ArgumentError('A successful session requires a receipt.');
    }
    if (paymentState == PaymentState.failed && failureReason == null) {
      throw ArgumentError('A failed session requires a failure reason.');
    }
    return CheckoutSession._(
      subtotal: subtotal,
      discount: discount,
      total: Money(
        currency: subtotal.currency,
        minorUnits: subtotal.minorUnits - discount.minorUnits,
      ),
      paymentProfile: paymentProfile,
      voucher: voucher,
      paymentState: paymentState,
      receipt: receipt,
      failureReason: failureReason,
    );
  }

  const CheckoutSession._({
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.paymentProfile,
    required this.voucher,
    required this.paymentState,
    required this.receipt,
    required this.failureReason,
  });

  final Money subtotal;
  final Money discount;
  final Money total;
  final PaymentProfileSnapshot paymentProfile;
  final Voucher? voucher;
  final PaymentState paymentState;
  final CheckoutReceipt? receipt;
  final CheckoutPaymentFailureReason? failureReason;

  CheckoutSession withPaymentState(
    PaymentState state, {
    CheckoutReceipt? receipt,
    CheckoutPaymentFailureReason? failureReason,
  }) => CheckoutSession(
    subtotal: subtotal,
    paymentProfile: paymentProfile,
    voucher: voucher,
    paymentState: state,
    receipt: receipt,
    failureReason: failureReason,
  );
}

String _requiredText(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, 'Value must not be empty.');
  }
  return normalized;
}

void _requireUniqueIds(Iterable<String> ids, String name) {
  final uniqueIds = <String>{};
  for (final id in ids) {
    if (!uniqueIds.add(id)) {
      throw ArgumentError.value(id, name, 'Duplicate ID.');
    }
  }
}

T? _firstWhereOrNull<T>(Iterable<T> values, bool Function(T value) test) {
  for (final value in values) {
    if (test(value)) {
      return value;
    }
  }
  return null;
}
