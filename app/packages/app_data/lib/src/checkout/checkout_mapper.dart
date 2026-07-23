part of 'checkout_local.dart';

abstract final class _CheckoutFixtureMapper {
  static CheckoutAttempt checkoutAttempt(Object? payload) => _decode(() {
    final id = _map(payload)['id'];
    if (id is! String) {
      throw const CheckoutFailure(CheckoutFailureCode.invalidResponse);
    }
    return CheckoutAttempt(id: id);
  });

  static CheckoutSession session(Object? payload) => _decode(() {
    final values = _map(payload);
    final subtotal = _money(values['subtotal']);
    final expectedDiscount = _money(values['discount']);
    final expectedTotal = _money(values['total']);
    final voucherPayload = values['voucher'];
    final result = CheckoutSession(
      subtotal: subtotal,
      paymentProfile: _profile(values['paymentProfile']),
      voucher: voucherPayload == null ? null : _voucher(voucherPayload),
    );
    if (result.discount != expectedDiscount || result.total != expectedTotal) {
      throw const CheckoutFailure(CheckoutFailureCode.invalidResponse);
    }
    return result;
  });

  static CheckoutPaymentResult paymentResult(Object? payload) => _decode(() {
    final values = _map(payload);
    return switch (values['status']) {
      'succeeded' => CheckoutPaymentSucceeded(_receipt(values['receipt'])),
      'failed' when values['reason'] == 'payment_not_completed' =>
        const CheckoutPaymentFailed(
          CheckoutPaymentFailureReason.paymentNotCompleted,
        ),
      _ => throw const CheckoutFailure(CheckoutFailureCode.invalidResponse),
    };
  });

  static Map<String, Object?> moneyPayload(Money money) => <String, Object?>{
    'currency': money.currency.code,
    'minorUnits': money.minorUnits,
  };

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

  static PaymentProfileSnapshot _profile(Object? payload) {
    final values = _map(payload);
    final addresses = values['addresses'];
    final methods = values['paymentMethods'];
    final selectedAddressId = values['selectedAddressId'];
    final selectedPaymentMethodId = values['selectedPaymentMethodId'];
    if (addresses is! List<Object?> ||
        methods is! List<Object?> ||
        selectedAddressId is! String? ||
        selectedPaymentMethodId is! String?) {
      throw const CheckoutFailure(CheckoutFailureCode.invalidResponse);
    }
    return PaymentProfileSnapshot(
      addresses: addresses.map(_address).toList(growable: false),
      paymentMethods: methods.map(_paymentMethod).toList(growable: false),
      selectedAddressId: selectedAddressId,
      selectedPaymentMethodId: selectedPaymentMethodId,
    );
  }

  static ShippingAddress _address(Object? payload) {
    final values = _map(payload);
    final id = values['id'];
    final recipientName = values['recipientName'];
    final streetLine = values['streetLine'];
    final city = values['city'];
    final region = values['region'];
    final postalCode = values['postalCode'];
    final country = values['country'];
    if (id is! String ||
        recipientName is! String ||
        streetLine is! String ||
        city is! String ||
        region is! String ||
        postalCode is! String ||
        country is! String) {
      throw const CheckoutFailure(CheckoutFailureCode.invalidResponse);
    }
    return ShippingAddress(
      id: id,
      recipientName: recipientName,
      streetLine: streetLine,
      city: city,
      region: region,
      postalCode: postalCode,
      country: country,
    );
  }

  static PaymentMethod _paymentMethod(Object? payload) {
    final values = _map(payload);
    final id = values['id'];
    final brand = values['brand'];
    final lastFour = values['lastFour'];
    if (id is! String || brand is! String || lastFour is! String) {
      throw const CheckoutFailure(CheckoutFailureCode.invalidResponse);
    }
    return PaymentMethod(id: id, brand: brand, lastFour: lastFour);
  }

  static Voucher _voucher(Object? payload) {
    final values = _map(payload);
    final id = values['id'];
    final code = values['code'];
    final title = values['title'];
    if (id is! String || code is! String || title is! String) {
      throw const CheckoutFailure(CheckoutFailureCode.invalidResponse);
    }
    return Voucher(
      id: id,
      code: code,
      title: title,
      discount: _money(values['discount']),
      minimumSpend: _money(values['minimumSpend']),
    );
  }

  static CheckoutReceipt _receipt(Object? payload) {
    final values = _map(payload);
    final id = values['id'];
    final attemptId = values['attemptId'];
    final paymentMethodId = values['paymentMethodId'];
    final maskedPaymentLabel = values['maskedPaymentLabel'];
    final issuedAt = values['issuedAt'];
    if (id is! String ||
        attemptId is! String ||
        paymentMethodId is! String ||
        maskedPaymentLabel is! String ||
        issuedAt is! String) {
      throw const CheckoutFailure(CheckoutFailureCode.invalidResponse);
    }
    return CheckoutReceipt(
      id: id,
      attemptId: attemptId,
      amount: _money(values['amount']),
      paymentMethodId: paymentMethodId,
      maskedPaymentLabel: maskedPaymentLabel,
      shippingAddress: _address(values['shippingAddress']),
      issuedAt: DateTime.parse(issuedAt),
    );
  }

  static Money _money(Object? payload) {
    final values = _map(payload);
    final currency = values['currency'];
    final minorUnits = values['minorUnits'];
    if (currency is! String || minorUnits is! int) {
      throw const CheckoutFailure(CheckoutFailureCode.invalidResponse);
    }
    return Money(currency: Currency.fromCode(currency), minorUnits: minorUnits);
  }

  static T _decode<T>(T Function() operation) {
    try {
      return operation();
    } on CheckoutFailure {
      rethrow;
    } on ArgumentError catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const CheckoutFailure(CheckoutFailureCode.invalidResponse),
        stackTrace,
      );
    } on FormatException catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const CheckoutFailure(CheckoutFailureCode.invalidResponse),
        stackTrace,
      );
    }
  }

  static Map<String, Object?> _map(Object? payload) {
    if (payload is! Map<String, Object?>) {
      throw const CheckoutFailure(CheckoutFailureCode.invalidResponse);
    }
    return payload;
  }
}
