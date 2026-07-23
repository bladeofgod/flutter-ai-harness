import 'dart:async';

import 'package:app_data/app_data.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../api/wishlist_api.dart';

sealed class RecentlyViewedViewState {
  const RecentlyViewedViewState();
}

final class RecentlyViewedLoading extends RecentlyViewedViewState {
  const RecentlyViewedLoading();
}

final class RecentlyViewedData extends RecentlyViewedViewState {
  const RecentlyViewedData({
    required this.snapshot,
    required this.selectedDate,
    required this.isCalendarOpen,
    required this.pendingDate,
    required this.visibleYear,
    required this.visibleMonth,
  });

  final RecentlyViewedSnapshot snapshot;
  final WishlistDate selectedDate;
  final bool isCalendarOpen;
  final WishlistDate? pendingDate;
  final int visibleYear;
  final int visibleMonth;

  List<RecentlyViewedItem> get visibleItems => snapshot.items
      .where((item) => item.viewedOn == selectedDate)
      .toList(growable: false);

  bool get isToday => selectedDate == snapshot.referenceDate;

  bool get isYesterday => selectedDate == snapshot.referenceDate.addDays(-1);

  RecentlyViewedData copyWith({
    WishlistDate? selectedDate,
    bool? isCalendarOpen,
    WishlistDate? pendingDate,
    bool clearPendingDate = false,
    int? visibleYear,
    int? visibleMonth,
  }) => RecentlyViewedData(
    snapshot: snapshot,
    selectedDate: selectedDate ?? this.selectedDate,
    isCalendarOpen: isCalendarOpen ?? this.isCalendarOpen,
    pendingDate: clearPendingDate ? null : pendingDate ?? this.pendingDate,
    visibleYear: visibleYear ?? this.visibleYear,
    visibleMonth: visibleMonth ?? this.visibleMonth,
  );
}

final class RecentlyViewedError extends RecentlyViewedViewState {
  const RecentlyViewedError(this.failure);

  final WishlistFailure failure;
}

/// 管理固定日期筛选和内联日历的提交/取消状态。
final class RecentlyViewedController extends GetxController {
  RecentlyViewedController({required WishlistApi wishlistApi})
    : _wishlistApi = wishlistApi;

  final WishlistApi _wishlistApi;
  final Rx<RecentlyViewedViewState> _viewState = Rx<RecentlyViewedViewState>(
    const RecentlyViewedLoading(),
  );

  bool _isLoading = false;
  bool _isDisposed = false;

  RecentlyViewedViewState get viewState => _viewState.value;

  @override
  void onInit() {
    super.onInit();
    _startLoad();
  }

  Future<void> load() async {
    if (_isLoading || _isDisposed) {
      return;
    }
    _isLoading = true;
    _viewState.value = const RecentlyViewedLoading();
    try {
      final snapshot = await _wishlistApi.loadRecentlyViewed();
      if (!_isDisposed) {
        final date = snapshot.referenceDate;
        _viewState.value = RecentlyViewedData(
          snapshot: snapshot,
          selectedDate: date,
          isCalendarOpen: false,
          pendingDate: null,
          visibleYear: date.year,
          visibleMonth: date.month,
        );
      }
    } on WishlistFailure catch (failure) {
      if (!_isDisposed) {
        _viewState.value = RecentlyViewedError(failure);
      }
    } finally {
      _isLoading = false;
    }
  }

  void selectToday() {
    final data = _data;
    if (data == null) {
      return;
    }
    _viewState.value = data.copyWith(
      selectedDate: data.snapshot.referenceDate,
      isCalendarOpen: false,
      clearPendingDate: true,
    );
  }

  void selectYesterday() {
    final data = _data;
    if (data == null) {
      return;
    }
    _viewState.value = data.copyWith(
      selectedDate: data.snapshot.referenceDate.addDays(-1),
      isCalendarOpen: false,
      clearPendingDate: true,
    );
  }

  void openCalendar() {
    final data = _data;
    if (data == null || data.isCalendarOpen) {
      return;
    }
    _viewState.value = data.copyWith(
      isCalendarOpen: true,
      pendingDate: data.selectedDate,
      visibleYear: data.selectedDate.year,
      visibleMonth: data.selectedDate.month,
    );
  }

  void selectCalendarDay(int day) {
    final data = _data;
    if (data == null || !data.isCalendarOpen) {
      return;
    }
    final date = WishlistDate(
      year: data.visibleYear,
      month: data.visibleMonth,
      day: day,
    );
    _viewState.value = data.copyWith(pendingDate: date);
  }

  void showPreviousMonth() => _moveMonth(-1);

  void showNextMonth() => _moveMonth(1);

  void _moveMonth(int delta) {
    final data = _data;
    if (data == null || !data.isCalendarOpen) {
      return;
    }
    final month = DateTime.utc(data.visibleYear, data.visibleMonth + delta);
    _viewState.value = data.copyWith(
      visibleYear: month.year,
      visibleMonth: month.month,
      clearPendingDate: true,
    );
  }

  void applyCalendarSelection() {
    final data = _data;
    if (data == null || !data.isCalendarOpen || data.pendingDate == null) {
      return;
    }
    _viewState.value = data.copyWith(
      selectedDate: data.pendingDate,
      isCalendarOpen: false,
      clearPendingDate: true,
    );
  }

  void cancelCalendar() {
    final data = _data;
    if (data == null || !data.isCalendarOpen) {
      return;
    }
    _viewState.value = data.copyWith(
      isCalendarOpen: false,
      clearPendingDate: true,
    );
  }

  bool consumeBack() {
    final data = _data;
    if (data == null || !data.isCalendarOpen) {
      return false;
    }
    cancelCalendar();
    return true;
  }

  Future<void> retry() => load();

  void retryFromUi() => _startLoad();

  RecentlyViewedData? get _data {
    final state = _viewState.value;
    return state is RecentlyViewedData ? state : null;
  }

  void _startLoad() {
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
          context: ErrorDescription('while loading Recently Viewed'),
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
