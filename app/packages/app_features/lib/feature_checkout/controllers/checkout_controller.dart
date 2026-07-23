import 'dart:async';

import 'package:app_data/app_data.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../api/cart_api.dart';
import '../../api/checkout_api.dart';

sealed class CheckoutViewState {
  const CheckoutViewState();
}

final class CheckoutLoading extends CheckoutViewState {
  const CheckoutLoading();
}

final class CheckoutReady extends CheckoutViewState {
  const CheckoutReady({required this.session, required this.isMutating});

  final CheckoutSession session;
  final bool isMutating;
}

final class CheckoutEmptyCart extends CheckoutViewState {
  const CheckoutEmptyCart();
}

final class CheckoutError extends CheckoutViewState {
  const CheckoutError(this.failure);

  final Object failure;
}

final class CheckoutController extends GetxController {
  CheckoutController({
    required CartApi cartApi,
    required CheckoutApi checkoutApi,
    this.onReceiptReady,
  }) : _cartApi = cartApi,
       _checkoutApi = checkoutApi;

  final CartApi _cartApi;
  final CheckoutApi _checkoutApi;
  final Future<void> Function(CheckoutReceipt receipt, Cart cart)?
  onReceiptReady;
  final Rx<CheckoutViewState> _viewState = Rx<CheckoutViewState>(
    const CheckoutLoading(),
  );

  StreamSubscription<PaymentProfileSnapshot>? _profileSubscription;
  Cart? _cart;
  CheckoutSession? _session;
  bool _isLoading = false;
  bool _isMutating = false;
  bool _isPaying = false;
  bool _isDisposed = false;
  String? _pendingVoucherId;
  PaymentProfileSnapshot? _pendingPaymentProfile;
  _PendingCheckoutSettlement? _pendingSettlement;

  CheckoutViewState get viewState => _viewState.value;
  CheckoutSession? get session => _session;
  bool get isPaying => _isPaying;
  bool get hasPendingSettlement => _pendingSettlement != null;

  @override
  void onInit() {
    super.onInit();
    _profileSubscription = _checkoutApi.paymentProfileSnapshots.listen(
      _receiveExternalProfile,
    );
    _runFromLifecycle(load);
  }

  Future<void> load() async {
    if (_isLoading || _isDisposed) {
      return;
    }
    _isLoading = true;
    _viewState.value = const CheckoutLoading();
    try {
      final cart = await _cartApi.load();
      if (_isDisposed) {
        return;
      }
      _cart = cart;
      if (cart.isEmpty) {
        _session = null;
        _viewState.value = const CheckoutEmptyCart();
        return;
      }
      _session = await _checkoutApi.load(subtotal: cart.total);
      await _applyPendingVoucher();
      _publishReady();
    } on Object catch (error) {
      if (!_isDisposed) {
        _viewState.value = CheckoutError(error);
      }
    } finally {
      _isLoading = false;
      _applyPendingPaymentProfile();
    }
  }

  Future<bool> applyVoucher(String code) async {
    final normalized = code.trim();
    if (normalized.isEmpty) {
      return false;
    }
    return _mutate(
      () => _checkoutApi.applyVoucher(
        code: normalized,
        subtotal: _requiredCartTotal,
      ),
      keepReadyFor: CheckoutFailureCode.invalidVoucher,
    );
  }

  void requestVoucherById(String voucherId) {
    final normalized = voucherId.trim();
    if (normalized.isEmpty || _session?.voucher?.id == normalized) {
      return;
    }
    _pendingVoucherId = normalized;
    if (!_isLoading && _session != null) {
      _runFromLifecycle(_applyPendingVoucher);
    }
  }

  Future<bool> clearVoucher() =>
      _mutate(() => _checkoutApi.clearVoucher(subtotal: _requiredCartTotal));

  Future<bool> saveAddress(ShippingAddress address) => _mutate(
    () => _checkoutApi.upsertAddress(
      address: address,
      subtotal: _requiredCartTotal,
    ),
  );

  Future<bool> selectAddress(String addressId) => _mutate(
    () => _checkoutApi.selectAddress(
      addressId: addressId,
      subtotal: _requiredCartTotal,
    ),
  );

  Future<bool> selectPaymentMethod(String paymentMethodId) => _mutate(
    () => _checkoutApi.selectPaymentMethod(
      paymentMethodId: paymentMethodId,
      subtotal: _requiredCartTotal,
    ),
  );

  Future<void> pay() async {
    final current = _session;
    if (_isPaying ||
        _isDisposed ||
        current == null ||
        current.paymentProfile.selectedAddress == null ||
        current.paymentProfile.selectedPaymentMethod == null) {
      return;
    }
    _isPaying = true;
    _session = current.withPaymentState(PaymentState.inProgress);
    _publishReady();
    try {
      final attempt = await _checkoutApi.createPaymentAttempt();
      final result = await _checkoutApi.submitPayment(
        attemptId: attempt.id,
        amount: current.total,
      );
      if (_isDisposed) {
        return;
      }
      switch (result) {
        case CheckoutPaymentSucceeded(:final receipt):
          _pendingSettlement = _PendingCheckoutSettlement(
            attemptId: attempt.id,
            receipt: receipt,
            sourceSession: current,
          );
          await _completePendingSettlement();
        case CheckoutPaymentFailed(:final reason):
          _session = current.withPaymentState(
            PaymentState.failed,
            failureReason: reason,
          );
      }
    } on Object catch (error) {
      if (!_isDisposed) {
        _viewState.value = CheckoutError(error);
      }
      return;
    } finally {
      _isPaying = false;
      _applyPendingPaymentProfile();
    }
    _publishReady();
  }

  Future<void> retry() =>
      _pendingSettlement == null ? load() : _retryPendingSettlement();

  void retryFromUi() => _runFromLifecycle(retry);
  void payFromUi() => _runFromLifecycle(pay);

  Money get _requiredCartTotal {
    final cart = _cart;
    if (cart == null || cart.isEmpty) {
      throw StateError('Checkout requires a non-empty cart.');
    }
    return cart.total;
  }

  Future<bool> _mutate(
    Future<CheckoutSession> Function() operation, {
    CheckoutFailureCode? keepReadyFor,
  }) async {
    if (_isMutating || _isPaying || _isDisposed || _session == null) {
      return false;
    }
    _isMutating = true;
    _publishReady();
    var shouldRestoreReady = true;
    try {
      _session = await operation();
      return !_isDisposed;
    } on CheckoutFailure catch (failure) {
      if (!_isDisposed && failure.code != keepReadyFor) {
        _viewState.value = CheckoutError(failure);
        shouldRestoreReady = false;
      }
      return false;
    } finally {
      _isMutating = false;
      if (shouldRestoreReady) {
        _publishReady();
      }
      _applyPendingPaymentProfile();
    }
  }

  Future<void> _applyPendingVoucher() async {
    final voucherId = _pendingVoucherId;
    if (voucherId == null || _isDisposed || _session == null) {
      return;
    }
    _pendingVoucherId = null;
    final applied = await _mutate(
      () => _checkoutApi.applyVoucherById(
        voucherId: voucherId,
        subtotal: _requiredCartTotal,
      ),
      keepReadyFor: CheckoutFailureCode.invalidVoucher,
    );
    if (!applied && !_isDisposed) {
      _pendingVoucherId = null;
    }
  }

  Future<void> _retryPendingSettlement() async {
    if (_isPaying || _isDisposed) {
      return;
    }
    _isPaying = true;
    try {
      await _completePendingSettlement();
    } on Object catch (error) {
      if (!_isDisposed) {
        _viewState.value = CheckoutError(error);
      }
      return;
    } finally {
      _isPaying = false;
      _applyPendingPaymentProfile();
    }
    _publishReady();
  }

  Future<void> _completePendingSettlement() async {
    final pending = _pendingSettlement;
    if (pending == null) {
      return;
    }
    final cart = _cart;
    if (cart == null || cart.isEmpty) {
      throw StateError('Checkout settlement requires the original Cart.');
    }
    if (onReceiptReady != null) {
      await onReceiptReady!(pending.receipt, cart);
    }
    await _cartApi.clearAfterSuccessfulCheckout(attemptId: pending.attemptId);
    if (!_isDisposed) {
      _session = pending.sourceSession.withPaymentState(
        PaymentState.succeeded,
        receipt: pending.receipt,
      );
      _pendingSettlement = null;
    }
  }

  void _receiveExternalProfile(PaymentProfileSnapshot snapshot) {
    if (_isDisposed) {
      return;
    }
    _pendingPaymentProfile = snapshot;
    _applyPendingPaymentProfile();
  }

  void _applyPendingPaymentProfile() {
    final snapshot = _pendingPaymentProfile;
    final current = _session;
    if (_isDisposed ||
        _isLoading ||
        _isMutating ||
        _isPaying ||
        snapshot == null ||
        current == null) {
      return;
    }
    _pendingPaymentProfile = null;
    _session = CheckoutSession(
      subtotal: current.subtotal,
      paymentProfile: snapshot,
      voucher: current.voucher,
      paymentState: current.paymentState,
      receipt: current.receipt,
      failureReason: current.failureReason,
    );
    _publishReady();
  }

  void _publishReady() {
    final session = _session;
    if (!_isDisposed && session != null) {
      _viewState.value = CheckoutReady(
        session: session,
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
          context: ErrorDescription('while updating Checkout'),
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

final class _PendingCheckoutSettlement {
  const _PendingCheckoutSettlement({
    required this.attemptId,
    required this.receipt,
    required this.sourceSession,
  });

  final String attemptId;
  final CheckoutReceipt receipt;
  final CheckoutSession sourceSession;
}
