import 'dart:async';

import 'package:app_data/orders.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../api/current_user_provider.dart';
import '../../api/order_review_media_api.dart';
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

sealed class OrderReviewMediaDraftState {
  const OrderReviewMediaDraftState();
}

final class OrderReviewMediaEmpty extends OrderReviewMediaDraftState {
  const OrderReviewMediaEmpty();
}

final class OrderReviewMediaLaunching extends OrderReviewMediaDraftState {
  const OrderReviewMediaLaunching();
}

final class OrderReviewMediaReady extends OrderReviewMediaDraftState {
  const OrderReviewMediaReady(this.attachment);

  final OrderReviewMediaAttachment attachment;
}

enum OrderReviewMediaRetryAction { capture, remove, replace, finishSubmission }

final class OrderReviewMediaDraftFailure extends OrderReviewMediaDraftState {
  const OrderReviewMediaDraftFailure({
    required this.message,
    required this.retryAction,
    this.retainedAttachment,
    this.showRetainedThumbnail = true,
  });

  final String message;
  final OrderReviewMediaRetryAction retryAction;
  final OrderReviewMediaAttachment? retainedAttachment;
  final bool showRetainedThumbnail;
}

final class OrderReviewMediaRemoving extends OrderReviewMediaDraftState {
  const OrderReviewMediaRemoving(this.attachment);

  final OrderReviewMediaAttachment attachment;
}

final class OrderReviewMediaDraftReleased extends OrderReviewMediaDraftState {
  const OrderReviewMediaDraftReleased();
}

/// 管理 Activity/详情/通知和评价的单 Route 状态。
final class OrdersController extends GetxController {
  OrdersController.activity({
    required OrdersApi ordersApi,
    required CurrentUserProvider currentUserProvider,
    ActivityFilter initialFilter = ActivityFilter.activity,
  }) : _ordersApi = ordersApi,
       _currentUserProvider = currentUserProvider,
       _mediaApi = null,
       _orderId = null,
       _filter = initialFilter;

  OrdersController.order({
    required OrdersApi ordersApi,
    required CurrentUserProvider currentUserProvider,
    required String orderId,
  }) : _ordersApi = ordersApi,
       _currentUserProvider = currentUserProvider,
       _mediaApi = null,
       _orderId = orderId,
       _filter = ActivityFilter.activity;

  OrdersController.review({
    required OrdersApi ordersApi,
    required CurrentUserProvider currentUserProvider,
    required OrderReviewMediaApi mediaApi,
    required String orderId,
  }) : _ordersApi = ordersApi,
       _currentUserProvider = currentUserProvider,
       _mediaApi = mediaApi,
       _orderId = orderId,
       _filter = ActivityFilter.activity;

  final OrdersApi _ordersApi;
  final CurrentUserProvider _currentUserProvider;
  final OrderReviewMediaApi? _mediaApi;
  final String? _orderId;
  final Rx<OrdersViewState> _viewState = Rx<OrdersViewState>(
    const OrdersLoading(),
  );
  final RxInt _rating = 0.obs;
  final RxBool _isSubmittingReview = false.obs;
  final RxnString _reviewValidationMessage = RxnString();
  final Rx<OrderReviewMediaDraftState> _mediaState =
      Rx<OrderReviewMediaDraftState>(const OrderReviewMediaEmpty());

  ActivityFilter _filter;
  String _reviewComment = '';
  bool _isLoading = false;
  bool _isDisposed = false;
  bool _isConsumingNotification = false;
  bool _isMediaOperationInFlight = false;
  int _mediaOperationGeneration = 0;
  Order? _submittedReviewPendingMediaCleanup;

  OrdersViewState get viewState => _viewState.value;
  int get rating => _rating.value;
  bool get isSubmittingReview => _isSubmittingReview.value;
  String? get reviewValidationMessage => _reviewValidationMessage.value;
  OrderReviewMediaDraftState get mediaState => _mediaState.value;

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

  Future<void> captureMedia() async {
    if (_currentAttachment != null || !_canStartMediaOperation()) {
      return;
    }
    _isMediaOperationInFlight = true;
    _mediaState.value = const OrderReviewMediaLaunching();
    try {
      await _captureWithActiveOperation();
    } finally {
      _isMediaOperationInFlight = false;
    }
  }

  Future<void> retakeMedia() async {
    final attachment = _currentAttachment;
    if (attachment == null) {
      await captureMedia();
      return;
    }
    if (!_canStartMediaOperation()) {
      return;
    }
    _isMediaOperationInFlight = true;
    _mediaState.value = OrderReviewMediaRemoving(attachment);
    try {
      final released = await _releaseAttachment(attachment);
      if (_isDisposed) {
        return;
      }
      if (!released) {
        _mediaState.value = OrderReviewMediaDraftFailure(
          message: 'The current attachment could not be replaced. Try again.',
          retryAction: OrderReviewMediaRetryAction.replace,
          retainedAttachment: attachment,
        );
        return;
      }
      _mediaState.value = const OrderReviewMediaLaunching();
      await _captureWithActiveOperation();
    } finally {
      _isMediaOperationInFlight = false;
    }
  }

  Future<void> removeMedia() async {
    final attachment = _currentAttachment;
    if (attachment == null || !_canStartMediaOperation()) {
      return;
    }
    _isMediaOperationInFlight = true;
    _mediaState.value = OrderReviewMediaRemoving(attachment);
    try {
      final released = await _releaseAttachment(attachment);
      if (_isDisposed) {
        return;
      }
      _mediaState.value = released
          ? const OrderReviewMediaDraftReleased()
          : OrderReviewMediaDraftFailure(
              message: 'The attachment could not be removed. Try again.',
              retryAction: OrderReviewMediaRetryAction.remove,
              retainedAttachment: attachment,
            );
    } finally {
      _isMediaOperationInFlight = false;
    }
  }

  Future<void> retryMediaOperation() async {
    final state = _mediaState.value;
    if (state is! OrderReviewMediaDraftFailure) {
      return;
    }
    switch (state.retryAction) {
      case OrderReviewMediaRetryAction.capture:
        await captureMedia();
      case OrderReviewMediaRetryAction.remove:
        await removeMedia();
      case OrderReviewMediaRetryAction.replace:
        await retakeMedia();
      case OrderReviewMediaRetryAction.finishSubmission:
        if (_isSubmittingReview.value) {
          return;
        }
        _isSubmittingReview.value = true;
        await _finishSubmittedReviewCleanup();
    }
  }

  Future<void> reportThumbnailDecodeFailure(
    OrderReviewMediaAttachment attachment,
  ) async {
    if (_isDisposed ||
        _isMediaOperationInFlight ||
        !identical(_currentAttachment, attachment)) {
      return;
    }
    _isMediaOperationInFlight = true;
    final generation = ++_mediaOperationGeneration;
    _mediaState.value = OrderReviewMediaRemoving(attachment);
    try {
      final released = await _releaseAttachment(attachment);
      if (_isDisposed ||
          generation != _mediaOperationGeneration ||
          !identical(_currentAttachment, attachment)) {
        return;
      }
      _mediaState.value = OrderReviewMediaDraftFailure(
        message: 'The captured preview could not be displayed. Try again.',
        retryAction: released
            ? OrderReviewMediaRetryAction.capture
            : OrderReviewMediaRetryAction.replace,
        retainedAttachment: released ? null : attachment,
        showRetainedThumbnail: false,
      );
    } finally {
      if (generation == _mediaOperationGeneration) {
        _isMediaOperationInFlight = false;
      }
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
    if (_isSubmittingReview.value || _isMediaOperationInFlight) {
      return;
    }
    if (_submittedReviewPendingMediaCleanup != null) {
      _isSubmittingReview.value = true;
      unawaited(_finishSubmittedReviewCleanup());
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
      final released = await _releaseDraftAfterSubmit();
      if (_isDisposed) {
        return;
      }
      if (released) {
        _viewState.value = OrderDetailData(order);
        _reviewValidationMessage.value = null;
      } else {
        _submittedReviewPendingMediaCleanup = order;
        _mediaState.value = OrderReviewMediaDraftFailure(
          message:
              'Your review was saved, but the attachment still needs cleanup.',
          retryAction: OrderReviewMediaRetryAction.finishSubmission,
          retainedAttachment: _currentAttachment,
        );
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

  bool _canStartMediaOperation() =>
      !_isDisposed &&
      !_isSubmittingReview.value &&
      !_isMediaOperationInFlight &&
      _mediaApi != null;

  OrderReviewMediaAttachment? get _currentAttachment {
    return switch (_mediaState.value) {
      OrderReviewMediaReady(:final attachment) => attachment,
      OrderReviewMediaRemoving(:final attachment) => attachment,
      OrderReviewMediaDraftFailure(:final retainedAttachment) =>
        retainedAttachment,
      _ => null,
    };
  }

  Future<void> _captureWithActiveOperation() async {
    final mediaApi = _mediaApi;
    if (mediaApi == null) {
      return;
    }
    OrderReviewMediaCaptureOutcome outcome;
    try {
      outcome = await mediaApi.capture();
    } on Object catch (_, stackTrace) {
      _reportMediaBoundaryFailure(stackTrace);
      outcome = const OrderReviewMediaCaptureFailure(
        OrderReviewMediaFailure(
          code: OrderReviewMediaFailureCode.interrupted,
          recoverable: true,
        ),
      );
    }
    if (_isDisposed) {
      if (outcome case OrderReviewMediaConfirmed(:final attachment)) {
        await _releaseAttachment(attachment);
      }
      return;
    }
    _mediaState.value = switch (outcome) {
      OrderReviewMediaConfirmed(:final attachment) => OrderReviewMediaReady(
        attachment,
      ),
      OrderReviewMediaCancelled() => const OrderReviewMediaDraftReleased(),
      OrderReviewMediaCaptureFailure(:final failure) =>
        OrderReviewMediaDraftFailure(
          message: _mediaFailureMessage(failure.code),
          retryAction: OrderReviewMediaRetryAction.capture,
        ),
    };
  }

  Future<bool> _releaseAttachment(OrderReviewMediaAttachment attachment) async {
    final mediaApi = _mediaApi;
    if (mediaApi == null) {
      return true;
    }
    try {
      final result = await mediaApi.release(attachment);
      return result is OrderReviewMediaReleased;
    } on Object catch (_, stackTrace) {
      _reportMediaBoundaryFailure(stackTrace);
      return false;
    }
  }

  Future<bool> _releaseDraftAfterSubmit() async {
    final attachment = _currentAttachment;
    if (attachment == null) {
      return true;
    }
    final released = await _releaseAttachment(attachment);
    if (!_isDisposed && released) {
      _mediaState.value = const OrderReviewMediaDraftReleased();
    }
    return released;
  }

  Future<void> _finishSubmittedReviewCleanup() async {
    final order = _submittedReviewPendingMediaCleanup;
    if (order == null) {
      return;
    }
    try {
      final released = await _releaseDraftAfterSubmit();
      if (_isDisposed) {
        return;
      }
      if (released) {
        _submittedReviewPendingMediaCleanup = null;
        _viewState.value = OrderDetailData(order);
        _reviewValidationMessage.value = null;
      } else {
        _mediaState.value = OrderReviewMediaDraftFailure(
          message:
              'Your review was saved, but the attachment still needs cleanup.',
          retryAction: OrderReviewMediaRetryAction.finishSubmission,
          retainedAttachment: _currentAttachment,
        );
      }
    } finally {
      if (!_isDisposed) {
        _isSubmittingReview.value = false;
      }
    }
  }

  String _mediaFailureMessage(OrderReviewMediaFailureCode code) {
    return switch (code) {
      OrderReviewMediaFailureCode.permissionDenied =>
        'Camera access is needed to add a photo or video.',
      OrderReviewMediaFailureCode.unavailable =>
        'The camera is busy or unavailable. Try again.',
      OrderReviewMediaFailureCode.thumbnailUnavailable =>
        'The captured preview could not be prepared. Try again.',
      OrderReviewMediaFailureCode.releaseFailed =>
        'The attachment could not be released. Try again.',
      OrderReviewMediaFailureCode.interrupted =>
        'Capture was interrupted. Try again.',
    };
  }

  void _reportMediaBoundaryFailure(StackTrace stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: const _OrderReviewMediaOperationFailure(),
        stack: stackTrace,
        library: 'app_features',
        context: ErrorDescription('while managing an order review attachment'),
      ),
    );
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
    _mediaOperationGeneration += 1;
    _mediaState.value = const OrderReviewMediaDraftReleased();
    _submittedReviewPendingMediaCleanup = null;
    final mediaApi = _mediaApi;
    if (mediaApi != null) {
      unawaited(_clearMediaDraftsOnClose(mediaApi));
    }
    super.onClose();
  }

  Future<void> _clearMediaDraftsOnClose(OrderReviewMediaApi mediaApi) async {
    try {
      await mediaApi.clearDrafts();
    } on Object catch (_, stackTrace) {
      _reportMediaBoundaryFailure(stackTrace);
    }
  }
}

final class _OrderReviewMediaOperationFailure implements Exception {
  const _OrderReviewMediaOperationFailure();

  @override
  String toString() => 'OrderReviewMediaOperationFailure(<redacted>)';
}
