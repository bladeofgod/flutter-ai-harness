part of 'settings_payment_local.dart';

abstract final class _SettingsPaymentMapper {
  static SettingsPaymentOverview overview(Object? payload) {
    try {
      final values = _requiredMap(payload, 'overview');
      final receipts = _requiredList(values['receipts'], 'receipts');
      return SettingsPaymentOverview(
        paymentProfile: profile(values['paymentProfile']),
        receipts: receipts.map(receipt).toList(growable: false),
      );
    } on FormatException catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const SettingsPaymentFailure(
          SettingsPaymentFailureCode.invalidResponse,
        ),
        stackTrace,
      );
    } on ArgumentError catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const SettingsPaymentFailure(
          SettingsPaymentFailureCode.invalidResponse,
        ),
        stackTrace,
      );
    }
  }

  static PaymentProfileSnapshot profile(Object? payload) {
    final values = _requiredMap(payload, 'paymentProfile');
    return PaymentProfileSnapshot(
      addresses: _requiredList(
        values['addresses'],
        'addresses',
      ).map(address).toList(growable: false),
      paymentMethods: _requiredList(
        values['paymentMethods'],
        'paymentMethods',
      ).map(paymentMethod).toList(growable: false),
      selectedAddressId: _optionalString(
        values['selectedAddressId'],
        'selectedAddressId',
      ),
      selectedPaymentMethodId: _optionalString(
        values['selectedPaymentMethodId'],
        'selectedPaymentMethodId',
      ),
    );
  }

  static ShippingAddress address(Object? payload) {
    final values = _requiredMap(payload, 'address');
    return ShippingAddress(
      id: _requiredString(values['id'], 'id'),
      recipientName: _requiredString(values['recipientName'], 'recipientName'),
      streetLine: _requiredString(values['streetLine'], 'streetLine'),
      city: _requiredString(values['city'], 'city'),
      region: _requiredString(values['region'], 'region'),
      postalCode: _requiredString(values['postalCode'], 'postalCode'),
      country: _requiredString(values['country'], 'country'),
    );
  }

  static PaymentMethod paymentMethod(Object? payload) {
    final values = _requiredMap(payload, 'paymentMethod');
    return PaymentMethod(
      id: _requiredString(values['id'], 'id'),
      brand: _requiredString(values['brand'], 'brand'),
      lastFour: _requiredString(values['lastFour'], 'lastFour'),
    );
  }

  static CheckoutReceipt receipt(Object? payload) {
    final values = _requiredMap(payload, 'receipt');
    return CheckoutReceipt(
      id: _requiredString(values['id'], 'id'),
      attemptId: _requiredString(values['attemptId'], 'attemptId'),
      amount: _money(values['amount']),
      paymentMethodId: _requiredString(
        values['paymentMethodId'],
        'paymentMethodId',
      ),
      maskedPaymentLabel: _requiredString(
        values['maskedPaymentLabel'],
        'maskedPaymentLabel',
      ),
      shippingAddress: address(values['shippingAddress']),
      issuedAt: DateTime.parse(_requiredString(values['issuedAt'], 'issuedAt')),
    );
  }

  static Map<String, Object?> addressPayload(ShippingAddress address) =>
      <String, Object?>{
        'id': address.id,
        'recipientName': address.recipientName,
        'streetLine': address.streetLine,
        'city': address.city,
        'region': address.region,
        'postalCode': address.postalCode,
        'country': address.country,
      };

  static Map<String, Object?> paymentMethodPayload(PaymentMethod method) =>
      <String, Object?>{
        'id': method.id,
        'brand': method.brand,
        'lastFour': method.lastFour,
      };

  static Map<String, Object?> receiptPayload(CheckoutReceipt receipt) =>
      <String, Object?>{
        'id': receipt.id,
        'attemptId': receipt.attemptId,
        'amount': _moneyPayload(receipt.amount),
        'paymentMethodId': receipt.paymentMethodId,
        'maskedPaymentLabel': receipt.maskedPaymentLabel,
        'shippingAddress': addressPayload(receipt.shippingAddress),
        'issuedAt': receipt.issuedAt.toUtc().toIso8601String(),
      };

  static Money _money(Object? payload) {
    final values = _requiredMap(payload, 'money');
    return Money(
      currency: Currency.fromCode(
        _requiredString(values['currency'], 'currency'),
      ),
      minorUnits: _requiredInt(values['minorUnits'], 'minorUnits'),
    );
  }

  static Map<String, Object?> _moneyPayload(Money money) => <String, Object?>{
    'currency': money.currency.code,
    'minorUnits': money.minorUnits,
  };
}

Map<String, Object?> _requiredMap(Object? value, String name) {
  if (value is Map<String, Object?>) {
    return value;
  }
  throw FormatException('Expected $name map.');
}

List<Object?> _requiredList(Object? value, String name) {
  if (value is List<Object?>) {
    return value;
  }
  throw FormatException('Expected $name list.');
}

String _requiredString(Object? value, String name) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw FormatException('Expected $name string.');
}

String? _optionalString(Object? value, String name) =>
    value == null ? null : _requiredString(value, name);

int _requiredInt(Object? value, String name) {
  if (value is int) {
    return value;
  }
  throw FormatException('Expected $name int.');
}
