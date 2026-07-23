import 'package:app_core/app_core.dart';

import '../catalog/catalog_models.dart';
import '../fixture/fixture_api_transport.dart';
import '../fixture/shoppe_voucher_fixture.dart';
import 'checkout_models.dart';
import 'payment_profile_store.dart';

/// Checkout 请求键、Voucher 与支付尝试的唯一所有者。
final class CheckoutFixtureHandler implements FixtureRequestHandler {
  CheckoutFixtureHandler({
    required PaymentProfileStore paymentProfileStore,
    Duration paymentDelay = const Duration(milliseconds: 120),
  }) : _paymentProfileStore = paymentProfileStore,
       _paymentDelay = paymentDelay;

  static const String loadKey = 'checkout.load';
  static const String applyVoucherKey = 'checkout.voucher.apply';
  static const String applyVoucherByIdKey = 'checkout.voucher.apply_by_id';
  static const String clearVoucherKey = 'checkout.voucher.clear';
  static const String upsertAddressKey = 'checkout.address.upsert';
  static const String removeAddressKey = 'checkout.address.remove';
  static const String selectAddressKey = 'checkout.address.select';
  static const String upsertPaymentMethodKey = 'checkout.payment_method.upsert';
  static const String removePaymentMethodKey = 'checkout.payment_method.remove';
  static const String selectPaymentMethodKey = 'checkout.payment_method.select';
  static const String createPaymentAttemptKey =
      'checkout.payment.attempt.create';
  static const String submitPaymentKey = 'checkout.payment.submit';

  static const String _invalidInputCode = 'checkout.invalid_input';
  static const String _invalidVoucherCode = 'checkout.invalid_voucher';

  final PaymentProfileStore _paymentProfileStore;
  final Duration _paymentDelay;
  final Map<String, _CheckoutAttemptRecord> _attempts =
      <String, _CheckoutAttemptRecord>{};
  final Set<String> _createdAttemptIds = <String>{};
  int _attemptSequence = 0;
  Voucher? _appliedVoucher;

  void resetSession() {
    _attempts.clear();
    _createdAttemptIds.clear();
    _attemptSequence = 0;
    _appliedVoucher = null;
    _paymentProfileStore.reset();
  }

  @override
  Set<String> get requestKeys => const <String>{
    loadKey,
    applyVoucherKey,
    applyVoucherByIdKey,
    clearVoucherKey,
    upsertAddressKey,
    removeAddressKey,
    selectAddressKey,
    upsertPaymentMethodKey,
    removePaymentMethodKey,
    selectPaymentMethodKey,
    createPaymentAttemptKey,
    submitPaymentKey,
  };

  @override
  Future<ApiResponse<Object?>> handle(ApiRequest request) async =>
      switch (request.key) {
        loadKey => _load(request.payload),
        applyVoucherKey => _applyVoucher(request.payload),
        applyVoucherByIdKey => _applyVoucherById(request.payload),
        clearVoucherKey => _clearVoucher(request.payload),
        upsertAddressKey => _upsertAddress(request.payload),
        removeAddressKey => _removeAddress(request.payload),
        selectAddressKey => _selectAddress(request.payload),
        upsertPaymentMethodKey => _upsertPaymentMethod(request.payload),
        removePaymentMethodKey => _removePaymentMethod(request.payload),
        selectPaymentMethodKey => _selectPaymentMethod(request.payload),
        createPaymentAttemptKey => _createPaymentAttempt(),
        submitPaymentKey => _submitPayment(request.payload),
        _ => throw UnknownApiRequestException(request.key),
      };

  ApiResponse<Object?> _load(Object? payload) {
    final subtotal = _moneyFromPayload(_map(payload)?['subtotal']);
    return subtotal == null
        ? _invalidInput()
        : ApiResponse<Object?>.success(_sessionPayload(subtotal));
  }

  ApiResponse<Object?> _applyVoucher(Object? payload) {
    final values = _map(payload);
    final subtotal = _moneyFromPayload(values?['subtotal']);
    final code = values?['code'];
    if (subtotal == null || code is! String) {
      return _invalidInput();
    }
    if (code.trim().toUpperCase() != shoppeFiveVoucherFixture.code ||
        subtotal.currency != shoppeFiveVoucherFixture.discount.currency ||
        subtotal.minorUnits <
            shoppeFiveVoucherFixture.minimumSpend.minorUnits) {
      return const ApiResponse<Object?>.failure(
        ApiFailure.rejected(code: _invalidVoucherCode),
      );
    }
    _appliedVoucher = shoppeFiveVoucherFixture;
    return ApiResponse<Object?>.success(_sessionPayload(subtotal));
  }

  ApiResponse<Object?> _applyVoucherById(Object? payload) {
    final values = _map(payload);
    final subtotal = _moneyFromPayload(values?['subtotal']);
    final voucherId = values?['voucherId'];
    if (subtotal == null || voucherId is! String) {
      return _invalidInput();
    }
    if (voucherId.trim() != shoppeFiveVoucherFixture.id ||
        subtotal.currency != shoppeFiveVoucherFixture.discount.currency ||
        subtotal.minorUnits <
            shoppeFiveVoucherFixture.minimumSpend.minorUnits) {
      return const ApiResponse<Object?>.failure(
        ApiFailure.rejected(code: _invalidVoucherCode),
      );
    }
    _appliedVoucher = shoppeFiveVoucherFixture;
    return ApiResponse<Object?>.success(_sessionPayload(subtotal));
  }

  ApiResponse<Object?> _clearVoucher(Object? payload) {
    final subtotal = _moneyFromPayload(_map(payload)?['subtotal']);
    if (subtotal == null) {
      return _invalidInput();
    }
    _appliedVoucher = null;
    return ApiResponse<Object?>.success(_sessionPayload(subtotal));
  }

  ApiResponse<Object?> _upsertAddress(Object? payload) {
    final values = _map(payload);
    final subtotal = _moneyFromPayload(values?['subtotal']);
    final address = _addressFromPayload(values?['address']);
    if (subtotal == null || address == null) {
      return _invalidInput();
    }
    _paymentProfileStore.upsertAddress(address);
    return ApiResponse<Object?>.success(_sessionPayload(subtotal));
  }

  ApiResponse<Object?> _removeAddress(Object? payload) {
    final values = _map(payload);
    final subtotal = _moneyFromPayload(values?['subtotal']);
    final addressId = values?['addressId'];
    if (subtotal == null || addressId is! String) {
      return _invalidInput();
    }
    try {
      _paymentProfileStore.removeAddress(addressId);
    } on ArgumentError {
      return _invalidInput();
    }
    return ApiResponse<Object?>.success(_sessionPayload(subtotal));
  }

  ApiResponse<Object?> _selectAddress(Object? payload) {
    final values = _map(payload);
    final subtotal = _moneyFromPayload(values?['subtotal']);
    final addressId = values?['addressId'];
    if (subtotal == null || addressId is! String) {
      return _invalidInput();
    }
    try {
      _paymentProfileStore.selectAddress(addressId);
    } on ArgumentError {
      return _invalidInput();
    }
    return ApiResponse<Object?>.success(_sessionPayload(subtotal));
  }

  ApiResponse<Object?> _upsertPaymentMethod(Object? payload) {
    final values = _map(payload);
    final subtotal = _moneyFromPayload(values?['subtotal']);
    final method = _paymentMethodFromPayload(values?['paymentMethod']);
    if (subtotal == null || method == null) {
      return _invalidInput();
    }
    _paymentProfileStore.upsertPaymentMethod(method);
    return ApiResponse<Object?>.success(_sessionPayload(subtotal));
  }

  ApiResponse<Object?> _removePaymentMethod(Object? payload) {
    final values = _map(payload);
    final subtotal = _moneyFromPayload(values?['subtotal']);
    final paymentMethodId = values?['paymentMethodId'];
    if (subtotal == null || paymentMethodId is! String) {
      return _invalidInput();
    }
    try {
      _paymentProfileStore.removePaymentMethod(paymentMethodId);
    } on ArgumentError {
      return _invalidInput();
    }
    return ApiResponse<Object?>.success(_sessionPayload(subtotal));
  }

  ApiResponse<Object?> _selectPaymentMethod(Object? payload) {
    final values = _map(payload);
    final subtotal = _moneyFromPayload(values?['subtotal']);
    final paymentMethodId = values?['paymentMethodId'];
    if (subtotal == null || paymentMethodId is! String) {
      return _invalidInput();
    }
    try {
      _paymentProfileStore.selectPaymentMethod(paymentMethodId);
    } on ArgumentError {
      return _invalidInput();
    }
    return ApiResponse<Object?>.success(_sessionPayload(subtotal));
  }

  ApiResponse<Object?> _createPaymentAttempt() {
    final id = 'checkout-attempt-${++_attemptSequence}';
    _createdAttemptIds.add(id);
    return ApiResponse<Object?>.success(<String, Object?>{'id': id});
  }

  Future<ApiResponse<Object?>> _submitPayment(Object? payload) async {
    final values = _map(payload);
    final attemptId = values?['attemptId'];
    final amount = _moneyFromPayload(values?['amount']);
    final profile = _paymentProfileStore.current;
    final paymentMethod = profile.selectedPaymentMethod;
    final address = profile.selectedAddress;
    if (attemptId is! String ||
        attemptId.trim().isEmpty ||
        amount == null ||
        paymentMethod == null ||
        address == null ||
        !_createdAttemptIds.contains(attemptId)) {
      return _invalidInput();
    }

    final previous = _attempts[attemptId];
    if (previous != null) {
      if (previous.amount != amount ||
          previous.paymentMethodId != paymentMethod.id) {
        return _invalidInput();
      }
      return ApiResponse<Object?>.success(previous.resultPayload);
    }

    await Future<void>.delayed(_paymentDelay);
    final succeeds =
        _fixturePaymentOutcomes[paymentMethod.id] ??
        _defaultSettingsPaymentOutcome;
    final resultPayload = succeeds
        ? <String, Object?>{
            'status': 'succeeded',
            'receipt': _receiptPayload(
              attemptId: attemptId,
              amount: amount,
              method: paymentMethod,
              address: address,
            ),
          }
        : <String, Object?>{
            'status': 'failed',
            'reason': 'payment_not_completed',
          };
    _attempts[attemptId] = _CheckoutAttemptRecord(
      amount: amount,
      paymentMethodId: paymentMethod.id,
      resultPayload: Map<String, Object?>.unmodifiable(resultPayload),
    );
    return ApiResponse<Object?>.success(resultPayload);
  }

  Map<String, Object?> _sessionPayload(Money subtotal) {
    final voucher = _appliedVoucher;
    final discount =
        voucher?.discountFor(subtotal) ??
        Money(currency: subtotal.currency, minorUnits: 0);
    return <String, Object?>{
      'subtotal': _moneyPayload(subtotal),
      'discount': _moneyPayload(discount),
      'total': _moneyPayload(
        Money(
          currency: subtotal.currency,
          minorUnits: subtotal.minorUnits - discount.minorUnits,
        ),
      ),
      'paymentProfile': _profilePayload(_paymentProfileStore.current),
      if (voucher != null) 'voucher': _voucherPayload(voucher),
    };
  }

  static Map<String, Object?> _receiptPayload({
    required String attemptId,
    required Money amount,
    required PaymentMethod method,
    required ShippingAddress address,
  }) => <String, Object?>{
    'id': 'receipt-$attemptId',
    'attemptId': attemptId,
    'amount': _moneyPayload(amount),
    'paymentMethodId': method.id,
    'maskedPaymentLabel': method.maskedLabel,
    'shippingAddress': _addressPayload(address),
    'issuedAt': '2026-07-22T08:00:00.000Z',
  };

  static ApiResponse<Object?> _invalidInput() =>
      const ApiResponse<Object?>.failure(
        ApiFailure.rejected(code: _invalidInputCode),
      );
}

const Map<String, bool> _fixturePaymentOutcomes = <String, bool>{
  'payment-card-primary': true,
  'payment-card-secondary': false,
};

/// Settings 创建的合法掩码 Demo 卡固定成功；内置 secondary 保留失败演示。
const bool _defaultSettingsPaymentOutcome = true;

final class _CheckoutAttemptRecord {
  const _CheckoutAttemptRecord({
    required this.amount,
    required this.paymentMethodId,
    required this.resultPayload,
  });

  final Money amount;
  final String paymentMethodId;
  final Map<String, Object?> resultPayload;
}

Map<String, Object?>? _map(Object? value) =>
    value is Map<String, Object?> ? value : null;

Money? _moneyFromPayload(Object? payload) {
  final values = _map(payload);
  final currency = values?['currency'];
  final minorUnits = values?['minorUnits'];
  if (currency is! String || minorUnits is! int) {
    return null;
  }
  try {
    return Money(currency: Currency.fromCode(currency), minorUnits: minorUnits);
  } on ArgumentError {
    return null;
  } on FormatException {
    return null;
  }
}

ShippingAddress? _addressFromPayload(Object? payload) {
  final values = _map(payload);
  final id = values?['id'];
  final recipientName = values?['recipientName'];
  final streetLine = values?['streetLine'];
  final city = values?['city'];
  final region = values?['region'];
  final postalCode = values?['postalCode'];
  final country = values?['country'];
  if (id is! String ||
      recipientName is! String ||
      streetLine is! String ||
      city is! String ||
      region is! String ||
      postalCode is! String ||
      country is! String) {
    return null;
  }
  try {
    return ShippingAddress(
      id: id,
      recipientName: recipientName,
      streetLine: streetLine,
      city: city,
      region: region,
      postalCode: postalCode,
      country: country,
    );
  } on ArgumentError {
    return null;
  }
}

PaymentMethod? _paymentMethodFromPayload(Object? payload) {
  final values = _map(payload);
  final id = values?['id'];
  final brand = values?['brand'];
  final lastFour = values?['lastFour'];
  if (id is! String || brand is! String || lastFour is! String) {
    return null;
  }
  try {
    return PaymentMethod(id: id, brand: brand, lastFour: lastFour);
  } on ArgumentError {
    return null;
  }
}

Map<String, Object?> _moneyPayload(Money money) => <String, Object?>{
  'currency': money.currency.code,
  'minorUnits': money.minorUnits,
};

Map<String, Object?> _addressPayload(ShippingAddress address) =>
    <String, Object?>{
      'id': address.id,
      'recipientName': address.recipientName,
      'streetLine': address.streetLine,
      'city': address.city,
      'region': address.region,
      'postalCode': address.postalCode,
      'country': address.country,
    };

Map<String, Object?> _paymentMethodPayload(PaymentMethod method) =>
    <String, Object?>{
      'id': method.id,
      'brand': method.brand,
      'lastFour': method.lastFour,
    };

Map<String, Object?> _profilePayload(
  PaymentProfileSnapshot profile,
) => <String, Object?>{
  'addresses': profile.addresses.map(_addressPayload).toList(growable: false),
  'paymentMethods': profile.paymentMethods
      .map(_paymentMethodPayload)
      .toList(growable: false),
  'selectedAddressId': profile.selectedAddressId,
  'selectedPaymentMethodId': profile.selectedPaymentMethodId,
};

Map<String, Object?> _voucherPayload(Voucher voucher) => <String, Object?>{
  'id': voucher.id,
  'code': voucher.code,
  'title': voucher.title,
  'discount': _moneyPayload(voucher.discount),
  'minimumSpend': _moneyPayload(voucher.minimumSpend),
};
