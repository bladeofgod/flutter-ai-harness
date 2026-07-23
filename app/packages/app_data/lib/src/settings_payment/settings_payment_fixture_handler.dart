import 'package:app_core/app_core.dart';

import '../checkout/checkout_models.dart';
import '../checkout/payment_profile_store.dart';
import '../fixture/fixture_api_transport.dart';

/// Settings 专属请求键；地址与卡片状态始终委托唯一 PaymentProfileStore。
final class SettingsPaymentFixtureHandler implements FixtureRequestHandler {
  SettingsPaymentFixtureHandler({
    required PaymentProfileStore paymentProfileStore,
  }) : _paymentProfileStore = paymentProfileStore;

  static const String loadKey = 'settings.payment_profile.load';
  static const String upsertAddressKey = 'settings.address.upsert';
  static const String removeAddressKey = 'settings.address.remove';
  static const String selectAddressKey = 'settings.address.select';
  static const String upsertPaymentMethodKey = 'settings.payment_method.upsert';
  static const String removePaymentMethodKey = 'settings.payment_method.remove';
  static const String selectPaymentMethodKey = 'settings.payment_method.select';
  static const String recordReceiptKey = 'settings.receipt.record';

  static const String _invalidInputCode = 'settings_payment.invalid_input';

  final PaymentProfileStore _paymentProfileStore;
  final List<Map<String, Object?>> _receiptPayloads = <Map<String, Object?>>[];

  void resetSession() {
    _receiptPayloads.clear();
    _paymentProfileStore.reset();
  }

  @override
  Set<String> get requestKeys => const <String>{
    loadKey,
    upsertAddressKey,
    removeAddressKey,
    selectAddressKey,
    upsertPaymentMethodKey,
    removePaymentMethodKey,
    selectPaymentMethodKey,
    recordReceiptKey,
  };

  @override
  Future<ApiResponse<Object?>> handle(ApiRequest request) async =>
      switch (request.key) {
        loadKey => ApiResponse<Object?>.success(_overviewPayload()),
        upsertAddressKey => _upsertAddress(request.payload),
        removeAddressKey => _removeAddress(request.payload),
        selectAddressKey => _selectAddress(request.payload),
        upsertPaymentMethodKey => _upsertPaymentMethod(request.payload),
        removePaymentMethodKey => _removePaymentMethod(request.payload),
        selectPaymentMethodKey => _selectPaymentMethod(request.payload),
        recordReceiptKey => _recordReceipt(request.payload),
        _ => throw UnknownApiRequestException(request.key),
      };

  ApiResponse<Object?> _upsertAddress(Object? payload) {
    final address = _addressFromPayload(_map(payload)?['address']);
    if (address == null) {
      return _invalidInput();
    }
    _paymentProfileStore.upsertAddress(address);
    return ApiResponse<Object?>.success(_overviewPayload());
  }

  ApiResponse<Object?> _removeAddress(Object? payload) {
    final addressId = _map(payload)?['addressId'];
    if (addressId is! String) {
      return _invalidInput();
    }
    try {
      _paymentProfileStore.removeAddress(addressId);
    } on ArgumentError {
      return _invalidInput();
    }
    return ApiResponse<Object?>.success(_overviewPayload());
  }

  ApiResponse<Object?> _selectAddress(Object? payload) {
    final addressId = _map(payload)?['addressId'];
    if (addressId is! String) {
      return _invalidInput();
    }
    try {
      _paymentProfileStore.selectAddress(addressId);
    } on ArgumentError {
      return _invalidInput();
    }
    return ApiResponse<Object?>.success(_overviewPayload());
  }

  ApiResponse<Object?> _upsertPaymentMethod(Object? payload) {
    final method = _paymentMethodFromPayload(_map(payload)?['paymentMethod']);
    if (method == null) {
      return _invalidInput();
    }
    _paymentProfileStore.upsertPaymentMethod(method);
    return ApiResponse<Object?>.success(_overviewPayload());
  }

  ApiResponse<Object?> _removePaymentMethod(Object? payload) {
    final paymentMethodId = _map(payload)?['paymentMethodId'];
    if (paymentMethodId is! String) {
      return _invalidInput();
    }
    try {
      _paymentProfileStore.removePaymentMethod(paymentMethodId);
    } on ArgumentError {
      return _invalidInput();
    }
    return ApiResponse<Object?>.success(_overviewPayload());
  }

  ApiResponse<Object?> _selectPaymentMethod(Object? payload) {
    final paymentMethodId = _map(payload)?['paymentMethodId'];
    if (paymentMethodId is! String) {
      return _invalidInput();
    }
    try {
      _paymentProfileStore.selectPaymentMethod(paymentMethodId);
    } on ArgumentError {
      return _invalidInput();
    }
    return ApiResponse<Object?>.success(_overviewPayload());
  }

  ApiResponse<Object?> _recordReceipt(Object? payload) {
    final receipt = _map(payload)?['receipt'];
    final receiptId = _map(receipt)?['id'];
    if (receipt is! Map<String, Object?> ||
        receiptId is! String ||
        receiptId.isEmpty ||
        !_isReceiptPayload(receipt)) {
      return _invalidInput();
    }
    if (!_receiptPayloads.any((current) => current['id'] == receiptId)) {
      _receiptPayloads.insert(0, _deepCopyReceipt(receipt));
    }
    return ApiResponse<Object?>.success(_overviewPayload());
  }

  Map<String, Object?> _overviewPayload() => <String, Object?>{
    'paymentProfile': _profilePayload(_paymentProfileStore.current),
    'receipts': _receiptPayloads.map(_deepCopyReceipt).toList(growable: false),
  };

  static ApiResponse<Object?> _invalidInput() =>
      const ApiResponse<Object?>.failure(
        ApiFailure.rejected(code: _invalidInputCode),
      );
}

bool _isReceiptPayload(Map<String, Object?> receipt) {
  final attemptId = receipt['attemptId'];
  final amount = _map(receipt['amount']);
  final currency = amount?['currency'];
  final minorUnits = amount?['minorUnits'];
  final paymentMethodId = receipt['paymentMethodId'];
  final maskedPaymentLabel = receipt['maskedPaymentLabel'];
  final issuedAt = receipt['issuedAt'];
  return attemptId is String &&
      attemptId.isNotEmpty &&
      currency is String &&
      currency.isNotEmpty &&
      minorUnits is int &&
      paymentMethodId is String &&
      paymentMethodId.isNotEmpty &&
      maskedPaymentLabel is String &&
      maskedPaymentLabel.isNotEmpty &&
      issuedAt is String &&
      DateTime.tryParse(issuedAt) != null &&
      _addressFromPayload(receipt['shippingAddress']) != null;
}

Map<String, Object?>? _map(Object? value) =>
    value is Map<String, Object?> ? value : null;

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

Map<String, Object?> _deepCopyReceipt(Map<String, Object?> receipt) =>
    <String, Object?>{
      ...receipt,
      if (receipt['amount'] case final Map<String, Object?> amount)
        'amount': Map<String, Object?>.of(amount),
      if (receipt['shippingAddress']
          case final Map<String, Object?> shippingAddress)
        'shippingAddress': Map<String, Object?>.of(shippingAddress),
    };
