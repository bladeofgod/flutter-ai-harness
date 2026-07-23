import 'dart:async';

import 'package:app_data/promotions.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../api/promotions_api.dart';

sealed class PromotionsViewState<T> {
  const PromotionsViewState();
}

final class PromotionsLoading<T> extends PromotionsViewState<T> {
  const PromotionsLoading();
}

final class PromotionsData<T> extends PromotionsViewState<T> {
  const PromotionsData(this.value);

  final T value;
}

final class PromotionsError<T> extends PromotionsViewState<T> {
  const PromotionsError(this.failure);

  final PromotionsFailure failure;
}

abstract base class _LoadController<T> extends GetxController {
  _LoadController();

  final Rx<PromotionsViewState<T>> _state = Rx<PromotionsViewState<T>>(
    PromotionsLoading<T>(),
  );
  bool _isLoading = false;
  bool _isDisposed = false;

  PromotionsViewState<T> get state => _state.value;

  Future<T> request();

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
    _state.value = PromotionsLoading<T>();
    try {
      final value = await request();
      if (!_isDisposed) {
        _state.value = PromotionsData<T>(value);
      }
    } on PromotionsFailure catch (failure) {
      if (!_isDisposed) {
        _state.value = PromotionsError<T>(failure);
      }
    } finally {
      _isLoading = false;
    }
  }

  Future<void> retry() => load();

  void retryFromUi() => _startLoad();

  void _startLoad() {
    unawaited(_runAndReport(load));
  }

  Future<void> _runAndReport(Future<void> Function() operation) async {
    try {
      await operation();
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'app_features',
          context: ErrorDescription('while loading Promotions content'),
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

final class FlashSaleController extends _LoadController<Promotion> {
  FlashSaleController({required PromotionsApi promotionsApi})
    : _promotionsApi = promotionsApi;

  final PromotionsApi _promotionsApi;

  @override
  Future<Promotion> request() async =>
      (await _promotionsApi.loadOverview()).flashSale;
}

final class LiveController extends _LoadController<LivePreview> {
  LiveController({required PromotionsApi promotionsApi})
    : _promotionsApi = promotionsApi;

  final PromotionsApi _promotionsApi;
  final RxBool isDemoPreviewReady = false.obs;

  @override
  Future<LivePreview> request() async {
    final previews = (await _promotionsApi.loadOverview()).livePreviews;
    if (previews.isEmpty) {
      throw const PromotionsFailure(PromotionsFailureCode.invalidResponse);
    }
    return previews.first;
  }

  void prepareDemoPreview() {
    if (state is PromotionsData<LivePreview>) {
      isDemoPreviewReady.value = true;
    }
  }
}

final class StoryController extends _LoadController<StorySequence> {
  StoryController({
    required PromotionsApi promotionsApi,
    required this.storyId,
    required VoidCallback onFinished,
  }) : _promotionsApi = promotionsApi,
       _onFinished = onFinished;

  final PromotionsApi _promotionsApi;
  final String storyId;
  final VoidCallback _onFinished;
  final RxInt currentIndex = 0.obs;
  bool _didFinish = false;

  StoryItem? get currentItem {
    final currentState = state;
    if (currentState case PromotionsData<StorySequence>(:final value)) {
      return value.items[currentIndex.value];
    }
    return null;
  }

  @override
  Future<StorySequence> request() async {
    currentIndex.value = 0;
    _didFinish = false;
    return _promotionsApi.loadStory(storyId);
  }

  void previous() {
    if (currentIndex.value > 0) {
      currentIndex.value -= 1;
    }
  }

  void next() {
    final currentState = state;
    if (currentState is! PromotionsData<StorySequence> || _didFinish) {
      return;
    }
    if (currentIndex.value + 1 < currentState.value.items.length) {
      currentIndex.value += 1;
      return;
    }
    _didFinish = true;
    _onFinished();
  }
}
