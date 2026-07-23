import 'dart:async';

import 'package:app_data/orders.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../api/current_user_provider.dart';
import '../../api/orders_api.dart';

sealed class OrdersViewState {
  const OrdersViewState();
}

final class OrdersLoading extends OrdersViewState {
  const OrdersLoading();
}

final class OrdersActivityData extends OrdersViewState {
  const OrdersActivityData({required this.filter, required this.orders});

  final ActivityFilter filter;
  final List<Order> orders;
}

final class OrderDetailData extends OrdersViewState {
  const OrderDetailData(this.order);

  final Order order;
}

final class OrdersError extends OrdersViewState {
  const OrdersError(this.failure);

  final OrdersFailure failure;
}

/// 管理 Activity/详情/通知和评价的单 Route 状态。
final class OrdersController extends GetxController {
  OrdersController.activity({
    required OrdersApi ordersApi,
    required CurrentUserProvider currentUserProvider,
    ActivityFilter initialFilter = ActivityFilter.activity,
  }) : _ordersApi = ordersApi,
       _currentUserProvider = currentUserProvider,
       _orderId = null,
       _filter = initialFilter;

  OrdersController.order({
    required OrdersApi ordersApi,
    required CurrentUserProvider currentUserProvider,
    required String orderId,
  }) : _ordersApi = ordersApi,
       _currentUserProvider = currentUserProvider,
       _orderId = orderId,
       _filter = ActivityFilter.activity;

  final OrdersApi _ordersApi;
  final CurrentUserProvider _currentUserProvider;
  final String? _orderId;
  final Rx<OrdersViewState> _viewState = Rx<OrdersViewState>(
    const OrdersLoading(),
  );
  final RxInt _rating = 0.obs;
  final RxBool _isSubmittingReview = false.obs;
  final RxnString _reviewValidationMessage = RxnString();

  ActivityFilter _filter;
  String _reviewComment = '';
  bool _isLoading = false;
  bool _isDisposed = false;
  bool _isConsumingNotification = false;

  OrdersViewState get viewState => _viewState.value;
  int get rating => _rating.value;
  bool get isSubmittingReview => _isSubmittingReview.value;
  String? get reviewValidationMessage => _reviewValidationMessage.value;

  @override
  void onInit() {
    super.onInit();
    _loadFromUi();
  }

  Future<void> load() async {
    if (_isLoading || _isDisposed) {
      return;
    }
    _isLoading = true;
    _viewState.value = const OrdersLoading();
    try {
      final orderId = _orderId;
      if (orderId == null) {
        final orders = await _ordersApi.load(filter: _filter);
        if (!_isDisposed) {
          _viewState.value = OrdersActivityData(
            filter: _filter,
            orders: orders,
          );
        }
      } else {
        final order = await _ordersApi.loadOrder(orderId: orderId);
        if (!_isDisposed) {
          _viewState.value = OrderDetailData(order);
          _rating.value = order.review?.rating ?? 0;
        }
      }
    } on OrdersFailure catch (failure) {
      if (!_isDisposed) {
        _viewState.value = OrdersError(failure);
      }
    } finally {
      _isLoading = false;
    }
  }

  void retryFromUi() => _loadFromUi();

  void selectFilter(ActivityFilter filter) {
    if (_orderId != null || filter == _filter || _isLoading) {
      return;
    }
    _filter = filter;
    _loadFromUi();
  }

  void selectRating(int value) {
    if (value < 1 || value > 5 || _isSubmittingReview.value) {
      return;
    }
    _rating.value = value;
    _reviewValidationMessage.value = null;
  }

  void updateReviewComment(String value) {
    _reviewComment = value;
    if (value.trim().isNotEmpty) {
      _reviewValidationMessage.value = null;
    }
  }

  void dismissNotificationFromUi() {
    if (_isConsumingNotification) {
      return;
    }
    final state = _viewState.value;
    if (state is! OrderDetailData ||
        state.order.notification == null ||
        state.order.notification!.isConsumed) {
      return;
    }
    _isConsumingNotification = true;
    unawaited(_consumeNotification(state.order.id));
  }

  Future<void> _consumeNotification(String orderId) async {
    try {
      final order = await _ordersApi.consumeNotification(orderId: orderId);
      if (!_isDisposed) {
        _viewState.value = OrderDetailData(order);
      }
    } on OrdersFailure catch (failure) {
      if (!_isDisposed) {
        _viewState.value = OrdersError(failure);
      }
    } on Object catch (error, stackTrace) {
      _reportUnexpected(error, stackTrace, 'while consuming an order update');
    } finally {
      _isConsumingNotification = false;
    }
  }

  void submitReviewFromUi() {
    if (_isSubmittingReview.value) {
      return;
    }
    final state = _viewState.value;
    if (state is! OrderDetailData || state.order.review != null) {
      return;
    }
    if (_rating.value == 0 || _reviewComment.trim().isEmpty) {
      _reviewValidationMessage.value =
          'Choose a rating and add a short review.';
      return;
    }
    _isSubmittingReview.value = true;
    unawaited(_submitReview(state.order.id));
  }

  Future<void> _submitReview(String orderId) async {
    try {
      final order = await _ordersApi.submitReview(
        orderId: orderId,
        rating: _rating.value,
        comment: _reviewComment.trim(),
        author: _currentUserProvider.value?.displayName ?? 'Demo Customer',
      );
      if (!_isDisposed) {
        _viewState.value = OrderDetailData(order);
        _reviewValidationMessage.value = null;
      }
    } on OrdersFailure catch (failure) {
      if (!_isDisposed) {
        _reviewValidationMessage.value = switch (failure.code) {
          OrdersFailureCode.alreadyReviewed =>
            'This order already has a review.',
          _ => 'The review could not be saved. Try again.',
        };
      }
    } on Object catch (error, stackTrace) {
      _reportUnexpected(error, stackTrace, 'while submitting an order review');
    } finally {
      if (!_isDisposed) {
        _isSubmittingReview.value = false;
      }
    }
  }

  void _loadFromUi() {
    unawaited(_loadAndReportUnexpectedError());
  }

  Future<void> _loadAndReportUnexpectedError() async {
    try {
      await load();
    } on Object catch (error, stackTrace) {
      _reportUnexpected(error, stackTrace, 'while loading Orders');
    }
  }

  void _reportUnexpected(
    Object error,
    StackTrace stackTrace,
    String operation,
  ) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'app_features',
        context: ErrorDescription(operation),
      ),
    );
  }

  @override
  void onClose() {
    _isDisposed = true;
    super.onClose();
  }
}
