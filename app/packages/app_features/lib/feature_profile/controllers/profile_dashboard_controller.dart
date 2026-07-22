import 'dart:async';

import 'package:app_data/app_data.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../api/current_user_provider.dart';
import '../../api/profile_dashboard_api.dart';

sealed class ProfileDashboardViewState {
  const ProfileDashboardViewState();
}

final class ProfileDashboardLoading extends ProfileDashboardViewState {
  const ProfileDashboardLoading();
}

final class ProfileDashboardData extends ProfileDashboardViewState {
  const ProfileDashboardData(this.dashboard);

  final ProfileDashboard dashboard;
}

final class ProfileDashboardError extends ProfileDashboardViewState {
  const ProfileDashboardError(this.failure);

  final ProfileDashboardFailure failure;
}

/// 协调 Profile 当前用户快照和 Dashboard 的加载状态。
final class ProfileDashboardController extends GetxController {
  ProfileDashboardController({
    required ProfileDashboardApi profileDashboardApi,
    required CurrentUserProvider currentUserProvider,
  }) : _profileDashboardApi = profileDashboardApi,
       _currentUserProvider = currentUserProvider,
       _currentUser = Rxn<UserEntity>(currentUserProvider.value);

  final ProfileDashboardApi _profileDashboardApi;
  final CurrentUserProvider _currentUserProvider;
  final Rxn<UserEntity> _currentUser;
  final Rx<ProfileDashboardViewState> _viewState =
      Rx<ProfileDashboardViewState>(const ProfileDashboardLoading());

  bool _isLoading = false;
  bool _isDisposed = false;

  UserEntity? get currentUser => _currentUser.value;
  ProfileDashboardViewState get viewState => _viewState.value;

  @override
  void onInit() {
    super.onInit();
    _currentUserProvider.addListener(_handleCurrentUserChanged);
    _loadFromLifecycle();
  }

  Future<void> load() async {
    if (_isLoading || _isDisposed) {
      return;
    }
    _isLoading = true;
    _viewState.value = const ProfileDashboardLoading();
    try {
      final dashboard = await _profileDashboardApi.load();
      if (!_isDisposed) {
        _viewState.value = ProfileDashboardData(dashboard);
      }
    } on ProfileDashboardFailure catch (failure) {
      if (!_isDisposed) {
        _viewState.value = ProfileDashboardError(failure);
      }
    } finally {
      _isLoading = false;
    }
  }

  Future<void> retry() => load();

  void retryFromUi() {
    _loadFromLifecycle();
  }

  void _loadFromLifecycle() {
    unawaited(_loadAndReportUnexpectedError());
  }

  Future<void> _loadAndReportUnexpectedError() async {
    try {
      await load();
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'app_features',
          context: ErrorDescription('while loading the Profile Dashboard'),
        ),
      );
    }
  }

  void _handleCurrentUserChanged() {
    if (!_isDisposed) {
      _currentUser.value = _currentUserProvider.value;
    }
  }

  @override
  void onClose() {
    _isDisposed = true;
    _currentUserProvider.removeListener(_handleCurrentUserChanged);
    super.onClose();
  }
}
