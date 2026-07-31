import 'dart:async';

import 'package:app_data/support.dart' hide SupportMediaType;
import 'package:app_data/support.dart' as app_data show SupportMediaType;
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../api/support_chat_api.dart';
import '../../api/support_media_picker.dart';

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

sealed class SupportMediaSendResult {
  const SupportMediaSendResult();
}

final class SupportMediaSent extends SupportMediaSendResult {
  const SupportMediaSent();
}

final class SupportMediaSendCanceled extends SupportMediaSendResult {
  const SupportMediaSendCanceled();
}

final class SupportMediaSendFailed extends SupportMediaSendResult {
  const SupportMediaSendFailed(this.code);

  final SupportMediaPickFailureCode code;
}

/// 编排单条确定性本地会话，并在 Route 释放时取消待执行转场。
final class SupportChatController extends GetxController {
  SupportChatController({
    required SupportChatApi supportChatApi,
    required SupportMediaPicker supportMediaPicker,
    SupportTransitionDelay transitionDelay = _defaultTransitionDelay,
  }) : _supportChatApi = supportChatApi,
       _supportMediaPicker = supportMediaPicker,
       _transitionDelay = transitionDelay;

  static const Duration transitionDuration = Duration(milliseconds: 450);

  final SupportChatApi _supportChatApi;
  final SupportMediaPicker _supportMediaPicker;
  final SupportTransitionDelay _transitionDelay;
  final Rx<SupportChatViewState> _viewState = Rx<SupportChatViewState>(
    const SupportChatLoading(),
  );
  final RxString _draft = ''.obs;
  final RxInt _selectedRating = 0.obs;
  final RxInt _scrollRequest = 0.obs;
  final RxBool _isSendingMedia = false.obs;

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
  bool get isSendingMedia => _isSendingMedia.value;

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
      await _supportMediaPicker.clearDrafts();
      if (_isDisposed) {
        return;
      }
      final conversation = await _supportChatApi.startConversation();
      if (!_isDisposed) {
        _draft.value = '';
        _selectedRating.value = 0;
        _viewState.value = SupportChatData(conversation);
        await _releaseRetiredMedia();
      }
    } on SupportFailure catch (failure) {
      if (!_isDisposed) {
        _viewState.value = SupportChatError(failure);
      }
    } on SupportMediaPickerDisposalException {
      if (!_isDisposed) {
        _viewState.value = const SupportChatError(
          SupportFailure(SupportFailureCode.transportUnavailable),
        );
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

  Future<SupportMediaSendResult> sendMedia(SupportMediaSource source) async {
    final state = _viewState.value;
    if (_isSending ||
        _isDisposed ||
        state is! SupportChatData ||
        state.conversation.stage != SupportConversationStage.active) {
      return const SupportMediaSendFailed(
        SupportMediaPickFailureCode.unavailable,
      );
    }
    _isSending = true;
    _isSendingMedia.value = true;
    final generation = ++_transitionGeneration;
    SupportMediaAttachment? attachment;
    try {
      final pickResult = await _supportMediaPicker.pick(source);
      switch (pickResult) {
        case SupportMediaPickCanceled():
          return const SupportMediaSendCanceled();
        case SupportMediaPickFailed(:final failure):
          return SupportMediaSendFailed(failure.code);
        case SupportMediaPickSuccess(attachment: final pickedAttachment):
          attachment = pickedAttachment;
      }
      if (!_isCurrent(generation)) {
        return const SupportMediaSendFailed(
          SupportMediaPickFailureCode.unavailable,
        );
      }

      final poster = attachment.poster;
      final receipt = await _supportChatApi.sendMedia(
        SupportMediaContent(
          resourceId: attachment.resource.resourceId,
          type: switch (attachment.type) {
            SupportMediaType.image => app_data.SupportMediaType.image,
            SupportMediaType.video => app_data.SupportMediaType.video,
          },
          label: attachment.label,
          poster: poster == null
              ? null
              : SupportMediaPoster(
                  bytes: poster.bytes,
                  width: poster.width,
                  height: poster.height,
                ),
          duration: attachment.duration,
        ),
      );
      if (!_isCurrent(generation)) {
        return const SupportMediaSendFailed(
          SupportMediaPickFailureCode.unavailable,
        );
      }
      _publish(receipt.conversation, requestScroll: true);
      await _transitionDelay(transitionDuration);
      if (!_isCurrent(generation)) {
        return const SupportMediaSendFailed(
          SupportMediaPickFailureCode.unavailable,
        );
      }
      _publish(await _supportChatApi.receiveReply(), requestScroll: true);
      return const SupportMediaSent();
    } on SupportFailure catch (failure) {
      if (_isCurrent(generation)) {
        _viewState.value = SupportChatError(failure);
      }
      return const SupportMediaSendFailed(
        SupportMediaPickFailureCode.unavailable,
      );
    } on Object catch (error, stackTrace) {
      _reportUnexpected(error, stackTrace, 'while sending Support media');
      return const SupportMediaSendFailed(
        SupportMediaPickFailureCode.unavailable,
      );
    } finally {
      if (attachment case final attachment?) {
        try {
          await _supportMediaPicker.release(attachment);
        } on Object catch (error, stackTrace) {
          _reportUnexpected(
            error,
            stackTrace,
            'while releasing a Support media draft',
          );
        }
      }
      _isSending = false;
      if (!_isDisposed) {
        _isSendingMedia.value = false;
      }
    }
  }

  Future<void> _releaseRetiredMedia() async {
    try {
      await _supportChatApi.releaseRetiredMedia();
    } on Object catch (error, stackTrace) {
      _reportUnexpected(
        error,
        stackTrace,
        'while releasing replaced Support media',
      );
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
    _isSendingMedia.value = false;
    unawaited(_clearMediaDraftsOnClose());
    super.onClose();
  }

  Future<void> _clearMediaDraftsOnClose() async {
    try {
      await _supportMediaPicker.clearDrafts();
    } on Object catch (_, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: const _SupportMediaCleanupFailure(),
          stack: stackTrace,
          library: 'app_features',
          context: ErrorDescription('while clearing Support media drafts'),
        ),
      );
    }
  }
}

final class _SupportMediaCleanupFailure implements Exception {
  const _SupportMediaCleanupFailure();

  @override
  String toString() => 'SupportMediaCleanupFailure(<redacted>)';
}

Future<void> _defaultTransitionDelay(Duration duration) =>
    Future<void>.delayed(duration);
