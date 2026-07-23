import 'dart:async';

import 'package:app_data/rewards.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../api/rewards_api.dart';

sealed class RewardsViewState {
  const RewardsViewState();
}

final class RewardsLoading extends RewardsViewState {
  const RewardsLoading();
}

final class RewardsData extends RewardsViewState {
  const RewardsData(this.snapshot);

  final RewardsSnapshot snapshot;
}

final class RewardsEmpty extends RewardsViewState {
  const RewardsEmpty({required this.balance, required this.progress});

  final RewardBalance balance;
  final RewardProgress progress;
}

final class RewardsError extends RewardsViewState {
  const RewardsError(this.failure);

  final RewardsFailure failure;
}

final class RewardsController extends GetxController {
  RewardsController({required RewardsApi rewardsApi})
    : _rewardsApi = rewardsApi;

  final RewardsApi _rewardsApi;
  final Rx<RewardsViewState> _viewState = Rx<RewardsViewState>(
    const RewardsLoading(),
  );
  final RxnString _selectedVoucherId = RxnString();
  final RxBool _isConsumingReminder = false.obs;

  bool _isLoading = false;
  bool _isDisposed = false;

  RewardsViewState get viewState => _viewState.value;
  String? get selectedVoucherId => _selectedVoucherId.value;
  bool get isConsumingReminder => _isConsumingReminder.value;

  @override
  void onInit() {
    super.onInit();
    unawaited(load());
  }

  Future<void> load() async {
    if (_isLoading || _isDisposed) {
      return;
    }
    _isLoading = true;
    _viewState.value = const RewardsLoading();
    try {
      final snapshot = await _rewardsApi.load();
      if (!_isDisposed) {
        _setSnapshot(snapshot);
      }
    } on RewardsFailure catch (failure) {
      if (!_isDisposed) {
        _viewState.value = RewardsError(failure);
      }
    } on Object catch (error, stackTrace) {
      _handleUnexpected(error, stackTrace, 'while loading Rewards');
    } finally {
      _isLoading = false;
    }
  }

  void retryFromUi() => unawaited(load());

  void selectVoucher(String voucherId) {
    final snapshot = _snapshot;
    if (snapshot == null ||
        !snapshot.vouchers.any((item) => item.voucher.id == voucherId)) {
      return;
    }
    _selectedVoucherId.value = _selectedVoucherId.value == voucherId
        ? null
        : voucherId;
  }

  void consumeReminderFromUi(String voucherId) {
    if (_isConsumingReminder.value || _isDisposed) {
      return;
    }
    final snapshot = _snapshot;
    if (snapshot?.summary.expiringVoucher?.voucher.id != voucherId) {
      return;
    }
    _isConsumingReminder.value = true;
    unawaited(_consumeReminder(voucherId));
  }

  Future<void> _consumeReminder(String voucherId) async {
    try {
      final snapshot = await _rewardsApi.consumeReminder(voucherId: voucherId);
      if (!_isDisposed) {
        _setSnapshot(snapshot);
      }
    } on RewardsFailure catch (failure) {
      if (!_isDisposed) {
        _viewState.value = RewardsError(failure);
      }
    } on Object catch (error, stackTrace) {
      _handleUnexpected(
        error,
        stackTrace,
        'while consuming a Rewards reminder',
      );
    } finally {
      if (!_isDisposed) {
        _isConsumingReminder.value = false;
      }
    }
  }

  RewardsSnapshot? get _snapshot => switch (_viewState.value) {
    RewardsData(:final snapshot) => snapshot,
    _ => null,
  };

  void _setSnapshot(RewardsSnapshot snapshot) {
    final selectedId = _selectedVoucherId.value;
    if (selectedId != null &&
        !snapshot.vouchers.any((item) => item.voucher.id == selectedId)) {
      _selectedVoucherId.value = null;
    }
    _viewState.value = snapshot.vouchers.isEmpty
        ? RewardsEmpty(balance: snapshot.balance, progress: snapshot.progress)
        : RewardsData(snapshot);
  }

  void _handleUnexpected(Object error, StackTrace stackTrace, String context) {
    if (!_isDisposed) {
      _viewState.value = const RewardsError(
        RewardsFailure(RewardsFailureCode.unexpected),
      );
    }
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'app_features',
        context: ErrorDescription(context),
      ),
    );
  }

  @override
  void onClose() {
    _isDisposed = true;
    super.onClose();
  }
}
