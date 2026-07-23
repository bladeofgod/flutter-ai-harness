import 'dart:async';

import 'package:app_data/app_data.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../api/current_user_provider.dart';
import '../../api/settings_api.dart';

sealed class SettingsViewState {
  const SettingsViewState();
}

final class SettingsLoading extends SettingsViewState {
  const SettingsLoading();
}

final class SettingsData extends SettingsViewState {
  const SettingsData(this.preferences);

  final SettingsPreferences preferences;
}

final class SettingsError extends SettingsViewState {
  const SettingsError(this.failure);

  final SettingsFailure failure;
}

typedef SettingsUserUpdated = void Function(UserEntity user);

/// 协调 Settings 偏好、当前用户快照和根 Auth 回调。
final class SettingsController extends GetxController {
  SettingsController({
    required SettingsApi settingsApi,
    required CurrentUserProvider currentUserProvider,
    required SettingsUserUpdated onUserUpdated,
    required VoidCallback onDeleteAccount,
  }) : _settingsApi = settingsApi,
       _currentUserProvider = currentUserProvider,
       _onUserUpdated = onUserUpdated,
       _onDeleteAccount = onDeleteAccount,
       _currentUser = Rxn<UserEntity>(currentUserProvider.value);

  final SettingsApi _settingsApi;
  final CurrentUserProvider _currentUserProvider;
  final SettingsUserUpdated _onUserUpdated;
  final VoidCallback _onDeleteAccount;
  final Rxn<UserEntity> _currentUser;
  final Rx<SettingsViewState> _viewState = Rx<SettingsViewState>(
    const SettingsLoading(),
  );
  final RxBool _isSaving = false.obs;
  final Rxn<SettingsFailure> _operationFailure = Rxn<SettingsFailure>();

  bool _isLoading = false;
  bool _isDisposed = false;
  bool _deleteRequested = false;

  UserEntity? get currentUser => _currentUser.value;
  SettingsViewState get viewState => _viewState.value;
  bool get isSaving => _isSaving.value;
  SettingsFailure? get operationFailure => _operationFailure.value;

  @override
  void onInit() {
    super.onInit();
    _currentUserProvider.addListener(_handleCurrentUserChanged);
    _startLoad();
  }

  Future<void> load() async {
    if (_isLoading || _isDisposed) {
      return;
    }
    _isLoading = true;
    _operationFailure.value = null;
    _viewState.value = const SettingsLoading();
    try {
      final preferences = await _settingsApi.load();
      if (!_isDisposed) {
        _viewState.value = SettingsData(preferences);
      }
    } on SettingsFailure catch (failure) {
      if (!_isDisposed) {
        _viewState.value = SettingsError(failure);
      }
    } finally {
      _isLoading = false;
    }
  }

  Future<bool> updatePreferences(SettingsPreferences preferences) async {
    if (_isSaving.value || _isDisposed) {
      return false;
    }
    _isSaving.value = true;
    _operationFailure.value = null;
    try {
      final updated = await _settingsApi.updatePreferences(preferences);
      if (!_isDisposed) {
        _viewState.value = SettingsData(updated);
      }
      return !_isDisposed;
    } on SettingsFailure catch (failure) {
      if (!_isDisposed) {
        _operationFailure.value = failure;
      }
      return false;
    } finally {
      if (!_isDisposed) {
        _isSaving.value = false;
      }
    }
  }

  Future<bool> updateProfile(ProfileEditInput input) async {
    final user = _currentUser.value;
    if (user == null || _isSaving.value || _isDisposed) {
      return false;
    }
    _isSaving.value = true;
    _operationFailure.value = null;
    try {
      final updated = await _settingsApi.updateProfile(
        currentUser: user,
        input: input,
      );
      if (_isDisposed) {
        return false;
      }
      if (updated.id != user.id) {
        throw StateError('Settings must not change the authenticated user id.');
      }
      _onUserUpdated(updated);
      return true;
    } on SettingsFailure catch (failure) {
      if (!_isDisposed) {
        _operationFailure.value = failure;
      }
      return false;
    } finally {
      if (!_isDisposed) {
        _isSaving.value = false;
      }
    }
  }

  Future<bool> setCountry(SettingsCountry value) =>
      _mutatePreferences((current) => current.copyWith(country: value));

  Future<bool> setLanguage(SettingsLanguage value) =>
      _mutatePreferences((current) => current.copyWith(language: value));

  Future<bool> setCurrency(SettingsCurrency value) =>
      _mutatePreferences((current) => current.copyWith(currency: value));

  Future<bool> setSizeType(SettingsSizeType value) =>
      _mutatePreferences((current) => current.copyWith(sizeType: value));

  Future<bool> setNotificationsEnabled(bool value) => _mutatePreferences(
    (current) => current.copyWith(notificationsEnabled: value),
  );

  Future<bool> _mutatePreferences(
    SettingsPreferences Function(SettingsPreferences current) mutation,
  ) {
    final state = _viewState.value;
    if (state is! SettingsData) {
      return Future<bool>.value(false);
    }
    return updatePreferences(mutation(state.preferences));
  }

  void setNotificationsFromUi(bool value) {
    unawaited(
      _runAndReport(() async {
        await setNotificationsEnabled(value);
      }, 'updating notification preferences'),
    );
  }

  void retryFromUi() => _startLoad();

  void deleteAccount() {
    if (_deleteRequested || _isDisposed) {
      return;
    }
    _deleteRequested = true;
    _onDeleteAccount();
  }

  void _startLoad() {
    unawaited(_runAndReport(load, 'loading Settings'));
  }

  Future<void> _runAndReport(
    Future<void> Function() operation,
    String context,
  ) async {
    try {
      await operation();
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'app_features',
          context: ErrorDescription('while $context'),
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
