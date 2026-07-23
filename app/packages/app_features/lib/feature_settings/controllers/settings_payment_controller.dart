import 'dart:async';

import 'package:app_data/app_data.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../api/settings_payment_api.dart';

sealed class SettingsPaymentViewState {
  const SettingsPaymentViewState();
}

final class SettingsPaymentLoading extends SettingsPaymentViewState {
  const SettingsPaymentLoading();
}

final class SettingsPaymentReady extends SettingsPaymentViewState {
  const SettingsPaymentReady({
    required this.overview,
    required this.isMutating,
  });

  final SettingsPaymentOverview overview;
  final bool isMutating;
}

final class SettingsPaymentError extends SettingsPaymentViewState {
  const SettingsPaymentError(this.failure);

  final Object failure;
}

/// 完整卡号和 CVV 只在此短生命周期输入对象中存在。
///
/// 对外只允许转换为掩码 PaymentMethod，字符串诊断始终脱敏。
final class PaymentCardInput {
  factory PaymentCardInput({
    required String cardNumber,
    required String cardholderName,
    required String expiry,
    required String securityCode,
  }) {
    final digits = cardNumber.replaceAll(RegExp(r'\D'), '');
    final normalizedName = cardholderName.trim();
    final normalizedExpiry = expiry.trim();
    final normalizedCode = securityCode.trim();
    if (normalizedName.isEmpty) {
      throw const FormatException('Enter the cardholder name.');
    }
    if (!RegExp(r'^\d{12,19}$').hasMatch(digits) || !_passesLuhn(digits)) {
      throw const FormatException('Enter a valid card number.');
    }
    if (!RegExp(r'^(0[1-9]|1[0-2])/\d{2}$').hasMatch(normalizedExpiry)) {
      throw const FormatException('Use MM/YY for expiry.');
    }
    if (!RegExp(r'^\d{3,4}$').hasMatch(normalizedCode)) {
      throw const FormatException('Enter a valid security code.');
    }
    return PaymentCardInput._(digits);
  }

  const PaymentCardInput._(this._cardDigits);

  final String _cardDigits;

  PaymentMethod toPaymentMethod({required String id}) => PaymentMethod(
    id: id,
    brand: _brandFor(_cardDigits),
    lastFour: _cardDigits.substring(_cardDigits.length - 4),
  );

  @override
  String toString() =>
      'PaymentCardInput(card: <redacted>, holder: <redacted>, '
      'expiry: <redacted>, securityCode: <redacted>)';
}

final class SettingsPaymentController extends GetxController {
  SettingsPaymentController({required SettingsPaymentAddressApi api})
    : _api = api;

  final SettingsPaymentAddressApi _api;
  final Rx<SettingsPaymentViewState> _viewState = Rx<SettingsPaymentViewState>(
    const SettingsPaymentLoading(),
  );

  StreamSubscription<PaymentProfileSnapshot>? _profileSubscription;
  SettingsPaymentOverview? _overview;
  bool _isLoading = false;
  bool _isMutating = false;
  bool _isDisposed = false;

  SettingsPaymentViewState get viewState => _viewState.value;
  SettingsPaymentOverview? get overview => _overview;

  @override
  void onInit() {
    super.onInit();
    _profileSubscription = _api.paymentProfileSnapshots.listen(
      _receivePaymentProfile,
    );
    _runFromLifecycle(load);
  }

  Future<void> load() async {
    if (_isLoading || _isDisposed) {
      return;
    }
    _isLoading = true;
    _viewState.value = const SettingsPaymentLoading();
    try {
      _overview = await _api.load();
      _publishReady();
    } on Object catch (error) {
      if (!_isDisposed) {
        _viewState.value = SettingsPaymentError(error);
      }
    } finally {
      _isLoading = false;
    }
  }

  Future<bool> saveCard({String? methodId, required PaymentCardInput input}) {
    final method = input.toPaymentMethod(
      id: methodId ?? _nextPaymentMethodId(),
    );
    return _mutate(() => _api.upsertPaymentMethod(method));
  }

  String nextAddressId() {
    final existingIds = _overview?.paymentProfile.addresses
        .map((address) => address.id)
        .toSet();
    var sequence = 1;
    while (existingIds?.contains('shipping-settings-$sequence') ?? false) {
      sequence += 1;
    }
    return 'shipping-settings-$sequence';
  }

  Future<bool> removePaymentMethod(String methodId) =>
      _mutate(() => _api.removePaymentMethod(methodId));

  Future<bool> selectPaymentMethod(String methodId) =>
      _mutate(() => _api.selectPaymentMethod(methodId));

  Future<bool> saveAddress(ShippingAddress address) =>
      _mutate(() => _api.upsertAddress(address));

  Future<bool> removeAddress(String addressId) =>
      _mutate(() => _api.removeAddress(addressId));

  Future<bool> selectAddress(String addressId) =>
      _mutate(() => _api.selectAddress(addressId));

  void retryFromUi() => _runFromLifecycle(load);

  Future<bool> _mutate(
    Future<SettingsPaymentOverview> Function() operation,
  ) async {
    if (_isMutating || _isDisposed || _overview == null) {
      return false;
    }
    _isMutating = true;
    _publishReady();
    var shouldPublishReady = true;
    try {
      _overview = await operation();
      return !_isDisposed;
    } on Object catch (error) {
      if (!_isDisposed) {
        _viewState.value = SettingsPaymentError(error);
        shouldPublishReady = false;
      }
      return false;
    } finally {
      _isMutating = false;
      if (shouldPublishReady) {
        _publishReady();
      }
    }
  }

  String _nextPaymentMethodId() {
    final existingIds = _overview?.paymentProfile.paymentMethods
        .map((method) => method.id)
        .toSet();
    var sequence = 1;
    while (existingIds?.contains('payment-card-settings-$sequence') ?? false) {
      sequence += 1;
    }
    return 'payment-card-settings-$sequence';
  }

  void _receivePaymentProfile(PaymentProfileSnapshot snapshot) {
    final current = _overview;
    if (_isDisposed || current == null) {
      return;
    }
    _overview = current.withPaymentProfile(snapshot);
    _publishReady();
  }

  void _publishReady() {
    final current = _overview;
    if (!_isDisposed && current != null) {
      _viewState.value = SettingsPaymentReady(
        overview: current,
        isMutating: _isMutating,
      );
    }
  }

  void _runFromLifecycle(Future<void> Function() operation) {
    unawaited(_runAndReportUnexpectedError(operation));
  }

  Future<void> _runAndReportUnexpectedError(
    Future<void> Function() operation,
  ) async {
    try {
      await operation();
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'app_features',
          context: ErrorDescription('while updating Settings payment data'),
        ),
      );
    }
  }

  @override
  void onClose() {
    _isDisposed = true;
    unawaited(_profileSubscription?.cancel());
    super.onClose();
  }
}

bool _passesLuhn(String digits) {
  var sum = 0;
  var shouldDouble = false;
  for (var index = digits.length - 1; index >= 0; index -= 1) {
    var value = int.parse(digits[index]);
    if (shouldDouble) {
      value *= 2;
      if (value > 9) {
        value -= 9;
      }
    }
    sum += value;
    shouldDouble = !shouldDouble;
  }
  return sum % 10 == 0;
}

String _brandFor(String digits) {
  if (digits.startsWith('4')) {
    return 'Visa';
  }
  if (digits.startsWith('5')) {
    return 'Mastercard';
  }
  if (digits.startsWith('34') || digits.startsWith('37')) {
    return 'American Express';
  }
  return 'Card';
}
