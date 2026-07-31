import 'dart:async';
import 'dart:collection';

import 'package:app_core/app_core.dart';
import 'package:app_data/support.dart';
import 'package:app_media/app_media.dart';

import '../../api/support_chat_api.dart';

final class LocalSupportChatApi implements SupportChatApi {
  LocalSupportChatApi({
    required SupportLocalDataSource dataSource,
    required MediaResourceStore mediaResourceStore,
  }) : _dataSource = dataSource,
       _mediaResourceStore = mediaResourceStore;

  final SupportLocalDataSource _dataSource;
  final MediaResourceStore _mediaResourceStore;
  final Map<MediaResourceId, MediaResourceLease> _sessionLeases =
      <MediaResourceId, MediaResourceLease>{};
  final List<MediaResourceLease> _retiredLeases = <MediaResourceLease>[];
  final Map<MediaResourceId, SupportMediaPoster> _posters =
      <MediaResourceId, SupportMediaPoster>{};
  final Queue<void Function()> _queuedResourceOperations =
      Queue<void Function()>();
  Future<void>? _disposeFuture;
  bool _resourceOperationActive = false;
  bool _closing = false;
  bool _sessionTransitionPending = false;

  @override
  Future<SupportConversation> startConversation() {
    if (_closing || _sessionTransitionPending) {
      return Future<SupportConversation>.error(
        const SupportFailure(SupportFailureCode.transportUnavailable),
      );
    }
    _sessionTransitionPending = true;
    return _serializeResourceOperation(() async {
      final conversation = await _dataSource.startConversation();
      _retireSessionResources();
      return conversation;
    }).whenComplete(() => _sessionTransitionPending = false);
  }

  @override
  Future<SupportConversation> selectQuestion(String questionId) async =>
      _enrich(await _dataSource.selectQuestion(questionId));

  @override
  Future<SupportConversation> advanceTransition() async =>
      _enrich(await _dataSource.advanceTransition());

  @override
  Future<SupportConversation> sendMessage(String text) async =>
      _enrich(await _dataSource.sendMessage(text));

  @override
  Future<SupportMediaSendReceipt> sendMedia(SupportMediaContent media) {
    if (_closing || _sessionTransitionPending) {
      return Future<SupportMediaSendReceipt>.error(
        const SupportFailure(SupportFailureCode.transportUnavailable),
      );
    }
    return _serializeResourceOperation(() => _sendMedia(media));
  }

  Future<SupportMediaSendReceipt> _sendMedia(SupportMediaContent media) async {
    final retained = await _mediaResourceStore.retain(media.resourceId);
    if (retained case MediaResourceError<MediaResourceLease>()) {
      throw const SupportFailure(SupportFailureCode.transportUnavailable);
    }
    final candidate =
        (retained as MediaResourceSuccess<MediaResourceLease>).value;
    var accepted = false;
    try {
      final rawConversation = await _dataSource.sendMedia(media);
      final acceptedMessage = rawConversation.messages.lastWhere(
        (message) => switch (message.content) {
          SupportMediaContent(:final resourceId) =>
            resourceId == media.resourceId,
          _ => false,
        },
        orElse: () =>
            throw const SupportFailure(SupportFailureCode.invalidResponse),
      );
      final existing = _sessionLeases[media.resourceId];
      if (existing == null) {
        _sessionLeases[media.resourceId] = candidate;
        accepted = true;
      }
      final poster = media.poster;
      if (poster != null) {
        _posters[media.resourceId] = poster;
      }
      final conversation = _enrich(rawConversation);
      return SupportMediaSendReceipt(
        conversation: conversation,
        acceptedMessageId: acceptedMessage.id,
        resourceId: media.resourceId,
      );
    } finally {
      if (!accepted) {
        try {
          final released = await _mediaResourceStore.release(candidate);
          if (released case MediaResourceError<void>()) {
            _retiredLeases.add(candidate);
          }
        } on Object {
          _retiredLeases.add(candidate);
        }
      }
    }
  }

  @override
  Future<SupportConversation> receiveReply() async =>
      _enrich(await _dataSource.receiveReply());

  @override
  Future<SupportConversation> requestRating() async =>
      _enrich(await _dataSource.requestRating());

  @override
  Future<SupportConversation> submitRating(int score) async =>
      _enrich(await _dataSource.submitRating(score));

  @override
  Future<void> releaseRetiredMedia() =>
      _serializeResourceOperation(() => _releaseLeases(_retiredLeases));

  @override
  Future<void> clearSessionMedia() {
    if (_sessionTransitionPending) {
      return _serializeResourceOperation(_clearSessionResources);
    }
    _sessionTransitionPending = true;
    return _serializeResourceOperation(
      _clearSessionResources,
    ).whenComplete(() => _sessionTransitionPending = false);
  }

  Future<void> _clearSessionResources() async {
    _retireSessionResources();
    await _releaseLeases(_retiredLeases);
  }

  @override
  Future<void> dispose() {
    final existing = _disposeFuture;
    if (existing != null) {
      return existing;
    }
    _closing = true;
    _sessionTransitionPending = true;
    return _disposeFuture = _performDispose();
  }

  Future<void> _performDispose() async {
    try {
      await _serializeResourceOperation(_clearSessionResources);
    } on Object {
      _disposeFuture = null;
      rethrow;
    }
  }

  void _retireSessionResources() {
    _retiredLeases.addAll(_sessionLeases.values);
    _sessionLeases.clear();
    _posters.clear();
  }

  Future<T> _serializeResourceOperation<T>(Future<T> Function() operation) {
    if (!_resourceOperationActive) {
      _resourceOperationActive = true;
      return _runResourceOperation(operation);
    }
    final completer = Completer<T>();
    _queuedResourceOperations.add(() {
      unawaited(
        _runResourceOperation(operation).then<void>(
          completer.complete,
          onError: (Object error, StackTrace stackTrace) =>
              completer.completeError(error, stackTrace),
        ),
      );
    });
    return completer.future;
  }

  Future<T> _runResourceOperation<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } finally {
      if (_queuedResourceOperations.isEmpty) {
        _resourceOperationActive = false;
      } else {
        _queuedResourceOperations.removeFirst()();
      }
    }
  }

  SupportConversation _enrich(SupportConversation conversation) {
    return SupportConversation(
      id: conversation.id,
      stage: conversation.stage,
      suggestedQuestions: conversation.suggestedQuestions,
      messages: conversation.messages
          .map(_enrichMessage)
          .toList(growable: false),
      rating: conversation.rating,
    );
  }

  SupportMessage _enrichMessage(SupportMessage message) {
    final content = message.content;
    if (content is! SupportMediaContent) {
      return message;
    }
    return SupportMessage(
      id: message.id,
      participant: message.participant,
      content: SupportMediaContent(
        resourceId: content.resourceId,
        type: content.type,
        label: content.label,
        poster: _posters[content.resourceId],
        duration: content.duration,
      ),
    );
  }

  Future<void> _releaseLeases(List<MediaResourceLease> leases) async {
    while (leases.isNotEmpty) {
      final lease = leases.removeAt(0);
      try {
        final released = await _mediaResourceStore.release(lease);
        if (released case MediaResourceError<void>()) {
          leases.insert(0, lease);
          throw const SupportFailure(SupportFailureCode.transportUnavailable);
        }
      } on Object {
        if (!leases.contains(lease)) {
          leases.insert(0, lease);
        }
        rethrow;
      }
    }
  }
}
