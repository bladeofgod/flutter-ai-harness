import 'dart:async';

import 'package:app_data/app_data.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../api/catalog_api.dart';

sealed class ShopDashboardViewState {
  const ShopDashboardViewState();
}

final class ShopDashboardLoading extends ShopDashboardViewState {
  const ShopDashboardLoading();
}

final class ShopDashboardData extends ShopDashboardViewState {
  const ShopDashboardData(this.dashboard);

  final ShopDashboard dashboard;
}

final class ShopDashboardError extends ShopDashboardViewState {
  const ShopDashboardError(this.failure);

  final CatalogFailure failure;
}

/// 管理 Shop 首页 Catalog 快照的加载与重试。
final class ShopDashboardController extends GetxController {
  ShopDashboardController({required CatalogApi catalogApi})
    : _catalogApi = catalogApi;

  final CatalogApi _catalogApi;
  final Rx<ShopDashboardViewState> _viewState = Rx<ShopDashboardViewState>(
    const ShopDashboardLoading(),
  );

  bool _isLoading = false;
  bool _isDisposed = false;

  ShopDashboardViewState get viewState => _viewState.value;

  @override
  void onInit() {
    super.onInit();
    _loadFromLifecycle();
  }

  Future<void> load() async {
    if (_isLoading || _isDisposed) {
      return;
    }
    _isLoading = true;
    _viewState.value = const ShopDashboardLoading();
    try {
      final dashboard = await _catalogApi.loadShop();
      if (!_isDisposed) {
        _viewState.value = ShopDashboardData(dashboard);
      }
    } on CatalogFailure catch (failure) {
      if (!_isDisposed) {
        _viewState.value = ShopDashboardError(failure);
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
          context: ErrorDescription('while loading the Shop Dashboard'),
        ),
      );
    }
  }

  @override
  void onClose() {
    _isDisposed = true;
    super.onClose();
  }
}
