import 'dart:async';

import 'package:app_data/support.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../api/support_chat_api.dart';

typedef SupportTransitionDelay = Future<void> Function(Duration duration);

sealed class SupportChatViewState {
  const SupportChatViewState();
}

final class SupportChatLoading extends SupportChatViewState {
  const SupportChatLoading();
}

final class SupportChatData extends SupportChatViewState {
  const SupportChatData(this.conversation);

  final SupportConversation conversation;
}

final class SupportChatError extends SupportChatViewState {
  const SupportChatError(this.failure);

  final SupportFailure failure;
}

/// 编排单条确定性本地会话，并在 Route 释放时取消待执行转场。
final class SupportChatController extends GetxController {
  SupportChatController({
    required SupportChatApi supportChatApi,
    SupportTransitionDelay transitionDelay = _defaultTransitionDelay,
  }) : _supportChatApi = supportChatApi,
       _transitionDelay = transitionDelay;

  static const Duration transitionDuration = Duration(milliseconds: 450);

  final SupportChatApi _supportChatApi;
  final SupportTransitionDelay _transitionDelay;
  final Rx<SupportChatViewState> _viewState = Rx<SupportChatViewState>(
    const SupportChatLoading(),
  );
  final RxString _draft = ''.obs;
  final RxInt _selectedRating = 0.obs;
  final RxInt _scrollRequest = 0.obs;

  bool _isLoading = false;
  bool _isTransitioning = false;
  bool _isSending = false;
  bool _isRating = false;
  bool _isDisposed = false;
  int _transitionGeneration = 0;

  SupportChatViewState get viewState => _viewState.value;
  String get draft => _draft.value;
  int get selectedRating => _selectedRating.value;
  int get scrollRequest => _scrollRequest.value;

  @override
  void onInit() {
    super.onInit();
    retryFromUi();
  }

  Future<void> load() async {
    if (_isLoading || _isDisposed) {
      return;
    }
    _isLoading = true;
    _viewState.value = const SupportChatLoading();
    try {
      final conversation = await _supportChatApi.startConversation();
      if (!_isDisposed) {
        _draft.value = '';
        _selectedRating.value = 0;
        _viewState.value = SupportChatData(conversation);
      }
    } on SupportFailure catch (failure) {
      if (!_isDisposed) {
        _viewState.value = SupportChatError(failure);
      }
    } finally {
      _isLoading = false;
    }
  }

  void retryFromUi() => unawaited(_runGuarded(load, 'while loading Support'));

  void selectQuestionFromUi(String questionId) {
    if (_isTransitioning || _isDisposed) {
      return;
    }
    final state = _viewState.value;
    if (state is! SupportChatData ||
        state.conversation.stage != SupportConversationStage.starting) {
      return;
    }
    _isTransitioning = true;
    final generation = ++_transitionGeneration;
    unawaited(_connect(questionId, generation));
  }

  Future<void> _connect(String questionId, int generation) async {
    try {
      final connecting = await _supportChatApi.selectQuestion(questionId);
      if (!_isCurrent(generation)) {
        return;
      }
      _publish(connecting);
      await _transitionDelay(transitionDuration);
      if (!_isCurrent(generation)) {
        return;
      }
      final typing = await _supportChatApi.advanceTransition();
      if (!_isCurrent(generation)) {
        return;
      }
      _publish(typing);
      await _transitionDelay(transitionDuration);
      if (!_isCurrent(generation)) {
        return;
      }
      _publish(await _supportChatApi.advanceTransition(), requestScroll: true);
    } on SupportFailure catch (failure) {
      if (_isCurrent(generation)) {
        _viewState.value = SupportChatError(failure);
      }
    } on Object catch (error, stackTrace) {
      _reportUnexpected(error, stackTrace, 'while connecting Support Chat');
    } finally {
      if (_isCurrent(generation)) {
        _isTransitioning = false;
      }
    }
  }

  void updateDraft(String value) {
    if (value.length <= 500) {
      _draft.value = value;
    }
  }

  Future<bool> send() async {
    final state = _viewState.value;
    final text = _draft.value.trim();
    if (_isSending ||
        _isDisposed ||
        state is! SupportChatData ||
        state.conversation.stage != SupportConversationStage.active ||
        text.isEmpty) {
      return false;
    }
    _isSending = true;
    final generation = ++_transitionGeneration;
    try {
      final typing = await _supportChatApi.sendMessage(text);
      if (!_isCurrent(generation)) {
        return false;
      }
      _draft.value = '';
      _publish(typing, requestScroll: true);
      await _transitionDelay(transitionDuration);
      if (!_isCurrent(generation)) {
        return false;
      }
      _publish(await _supportChatApi.receiveReply(), requestScroll: true);
      return true;
    } on SupportFailure catch (failure) {
      if (_isCurrent(generation)) {
        _viewState.value = SupportChatError(failure);
      }
      return false;
    } on Object catch (error, stackTrace) {
      _reportUnexpected(error, stackTrace, 'while sending a Support message');
      return false;
    } finally {
      if (_isCurrent(generation)) {
        _isSending = false;
      }
    }
  }

  void requestRatingFromUi() {
    if (_isRating || _isDisposed) {
      return;
    }
    final state = _viewState.value;
    if (state is! SupportChatData ||
        state.conversation.stage != SupportConversationStage.active) {
      return;
    }
    _isRating = true;
    unawaited(_requestRating());
  }

  Future<void> _requestRating() async {
    try {
      _publish(await _supportChatApi.requestRating());
    } on SupportFailure catch (failure) {
      if (!_isDisposed) {
        _viewState.value = SupportChatError(failure);
      }
    } on Object catch (error, stackTrace) {
      _reportUnexpected(error, stackTrace, 'while opening Support rating');
    } finally {
      _isRating = false;
    }
  }

  void selectRating(int score) {
    if (score >= 1 && score <= 5 && !_isRating) {
      _selectedRating.value = score;
    }
  }

  void submitRatingFromUi() {
    if (_selectedRating.value == 0 || _isRating || _isDisposed) {
      return;
    }
    final state = _viewState.value;
    if (state is! SupportChatData ||
        state.conversation.stage != SupportConversationStage.rating) {
      return;
    }
    _isRating = true;
    unawaited(_submitRating());
  }

  Future<void> _submitRating() async {
    try {
      _publish(await _supportChatApi.submitRating(_selectedRating.value));
    } on SupportFailure catch (failure) {
      if (!_isDisposed) {
        _viewState.value = SupportChatError(failure);
      }
    } on Object catch (error, stackTrace) {
      _reportUnexpected(error, stackTrace, 'while submitting Support rating');
    } finally {
      _isRating = false;
    }
  }

  void _publish(
    SupportConversation conversation, {
    bool requestScroll = false,
  }) {
    if (_isDisposed) {
      return;
    }
    _viewState.value = SupportChatData(conversation);
    if (requestScroll) {
      _scrollRequest.value += 1;
    }
  }

  bool _isCurrent(int generation) =>
      !_isDisposed && generation == _transitionGeneration;

  Future<void> _runGuarded(
    Future<void> Function() operation,
    String context,
  ) async {
    try {
      await operation();
    } on Object catch (error, stackTrace) {
      _reportUnexpected(error, stackTrace, context);
    }
  }

  void _reportUnexpected(
    Object error,
    StackTrace stackTrace,
    String operation,
  ) {
    if (_isDisposed) {
      return;
    }
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
    _transitionGeneration += 1;
    _draft.value = '';
    super.onClose();
  }
}

Future<void> _defaultTransitionDelay(Duration duration) =>
    Future<void>.delayed(duration);
