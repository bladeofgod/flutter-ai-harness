import 'dart:async';

import 'package:app_data/rewards.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../api/rewards_api.dart';

sealed class ProfileRewardsSummaryState {
  const ProfileRewardsSummaryState();
}

final class ProfileRewardsSummaryLoading extends ProfileRewardsSummaryState {
  const ProfileRewardsSummaryLoading();
}

final class ProfileRewardsSummaryData extends ProfileRewardsSummaryState {
  const ProfileRewardsSummaryData(this.summary);

  final RewardSummary summary;
}

final class ProfileRewardsSummaryError extends ProfileRewardsSummaryState {
  const ProfileRewardsSummaryError();
}

final class ProfileRewardsSummaryController extends GetxController {
  ProfileRewardsSummaryController({required RewardsSummaryApi rewardsApi})
    : _rewardsApi = rewardsApi;

  final RewardsSummaryApi _rewardsApi;
  final Rx<ProfileRewardsSummaryState> _state = Rx<ProfileRewardsSummaryState>(
    const ProfileRewardsSummaryLoading(),
  );
  bool _isDisposed = false;
  bool _isLoading = false;
  var _summaryRevision = 0;
  StreamSubscription<RewardSummary>? _summarySubscription;

  ProfileRewardsSummaryState get state => _state.value;

  @override
  void onInit() {
    super.onInit();
    _summarySubscription = _rewardsApi.summaryUpdates.listen(
      _applySummaryUpdate,
    );
    unawaited(load());
  }

  void _applySummaryUpdate(RewardSummary summary) {
    if (_isDisposed) {
      return;
    }
    _summaryRevision += 1;
    _state.value = ProfileRewardsSummaryData(summary);
  }

  Future<void> load() async {
    if (_isLoading || _isDisposed) {
      return;
    }
    _isLoading = true;
    _state.value = const ProfileRewardsSummaryLoading();
    final revisionAtLoad = _summaryRevision;
    try {
      final summary = await _rewardsApi.loadSummary();
      if (!_isDisposed && revisionAtLoad == _summaryRevision) {
        _state.value = ProfileRewardsSummaryData(summary);
      }
    } on Object catch (error, stackTrace) {
      if (!_isDisposed) {
        _state.value = const ProfileRewardsSummaryError();
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'app_features',
            context: ErrorDescription('while loading Profile Rewards summary'),
          ),
        );
      }
    } finally {
      _isLoading = false;
    }
  }

  @override
  void onClose() {
    _isDisposed = true;
    unawaited(_summarySubscription?.cancel());
    _summarySubscription = null;
    super.onClose();
  }
}
