import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:app_data/app_data.dart'
    show FixtureApiTransport, FixtureRequestHandler;
import 'package:app_data/support.dart';
import 'package:app_features/api/support_chat_api.dart';
import 'package:app_features/api/support_media_picker.dart';
import 'package:app_features/feature_support/api/local_support_chat_api.dart';
import 'package:app_media/app_media.dart';

final class DataSourceSupportApi implements SupportChatApi {
  const DataSourceSupportApi(this.source);

  final SupportLocalDataSource source;

  @override
  Future<SupportConversation> startConversation() => source.startConversation();

  @override
  Future<SupportConversation> selectQuestion(String questionId) =>
      source.selectQuestion(questionId);

  @override
  Future<SupportConversation> advanceTransition() => source.advanceTransition();

  @override
  Future<SupportConversation> sendMessage(String text) =>
      source.sendMessage(text);

  @override
  Future<SupportMediaSendReceipt> sendMedia(SupportMediaContent media) async {
    final conversation = await source.sendMedia(media);
    return SupportMediaSendReceipt(
      conversation: conversation,
      acceptedMessageId: conversation.messages.last.id,
      resourceId: media.resourceId,
    );
  }

  @override
  Future<SupportConversation> receiveReply() => source.receiveReply();

  @override
  Future<SupportConversation> requestRating() => source.requestRating();

  @override
  Future<SupportConversation> submitRating(int score) =>
      source.submitRating(score);

  @override
  Future<void> releaseRetiredMedia() async {}

  @override
  Future<void> clearSessionMedia() async {}

  @override
  Future<void> dispose() async {}
}

final class CountingSupportApi implements SupportChatApi {
  CountingSupportApi(this.delegate);

  final SupportChatApi delegate;
  int startCount = 0;
  int selectCount = 0;
  int advanceCount = 0;
  int sendCount = 0;
  int replyCount = 0;
  int mediaSendCount = 0;

  @override
  Future<SupportConversation> startConversation() {
    startCount += 1;
    return delegate.startConversation();
  }

  @override
  Future<SupportConversation> selectQuestion(String questionId) {
    selectCount += 1;
    return delegate.selectQuestion(questionId);
  }

  @override
  Future<SupportConversation> advanceTransition() {
    advanceCount += 1;
    return delegate.advanceTransition();
  }

  @override
  Future<SupportConversation> sendMessage(String text) {
    sendCount += 1;
    return delegate.sendMessage(text);
  }

  @override
  Future<SupportMediaSendReceipt> sendMedia(SupportMediaContent media) {
    mediaSendCount += 1;
    return delegate.sendMedia(media);
  }

  @override
  Future<SupportConversation> receiveReply() {
    replyCount += 1;
    return delegate.receiveReply();
  }

  @override
  Future<SupportConversation> requestRating() => delegate.requestRating();

  @override
  Future<SupportConversation> submitRating(int score) =>
      delegate.submitRating(score);

  @override
  Future<void> releaseRetiredMedia() => delegate.releaseRetiredMedia();

  @override
  Future<void> clearSessionMedia() => delegate.clearSessionMedia();

  @override
  Future<void> dispose() => delegate.dispose();
}

SupportChatApi createSupportApi({
  TestSupportMediaResourceStore? mediaResourceStore,
}) {
  final handler = SupportFixtureHandler();
  return LocalSupportChatApi(
    dataSource: SupportLocalDataSource(
      apiClient: ApiClient(
        transport: FixtureApiTransport(
          handlers: <FixtureRequestHandler>[handler],
        ),
      ),
    ),
    mediaResourceStore: mediaResourceStore ?? TestSupportMediaResourceStore(),
  );
}

Future<void> immediateSupportDelay(Duration duration) async {}

final class FakeSupportMediaPicker implements SupportMediaPicker {
  FakeSupportMediaPicker({
    SupportMediaPickResult result = const SupportMediaPickCanceled(),
    this.mediaResourceStore,
  }) : _result = result;

  final TestSupportMediaResourceStore? mediaResourceStore;
  SupportMediaPickResult _result;
  SupportMediaSource? lastSource;
  int pickCount = 0;
  int releaseCount = 0;
  int clearCount = 0;
  int disposeCount = 0;

  set result(SupportMediaPickResult value) => _result = value;

  @override
  Future<SupportMediaPickResult> pick(SupportMediaSource source) async {
    pickCount += 1;
    lastSource = source;
    return _result;
  }

  @override
  Future<void> release(SupportMediaAttachment attachment) async {
    releaseCount += 1;
    final store = mediaResourceStore;
    if (store != null) {
      await store.release(attachment.resource.initialLease);
    } else if (attachment.resource.initialLease
        case final TestSupportMediaResourceLease lease) {
      lease.close();
    }
  }

  @override
  Future<void> clearDrafts() async {
    clearCount += 1;
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }
}

final class TestSupportMediaResourceStore implements MediaResourceStore {
  TestSupportMediaResourceStore({List<String>? events})
    : events = events ?? <String>[];

  final List<String> events;
  final Map<MediaResourceId, Set<TestSupportMediaResourceLease>> _leases =
      <MediaResourceId, Set<TestSupportMediaResourceLease>>{};
  final Map<MediaResourceId, MediaResourceKind> _kinds =
      <MediaResourceId, MediaResourceKind>{};
  final Map<MediaResourceId, Uri> _fileUris = <MediaResourceId, Uri>{};
  final Map<MediaResourceId, Duration?> _durations =
      <MediaResourceId, Duration?>{};
  int _sequence = 1;
  int retainCount = 0;
  int releaseCount = 0;
  int releaseFailuresRemaining = 0;
  int releaseThrowsRemaining = 0;
  int importCount = 0;
  int disposeCount = 0;
  MediaResourceFailure? nextImportFailure;
  MediaImportRequest? lastImportRequest;

  OwnedMediaResource seedOwned({
    MediaResourceKind kind = MediaResourceKind.image,
    Duration? duration,
    Uri? fileUri,
  }) {
    final id = MediaResourceId(
      'mr_${_sequence.toRadixString(16).padLeft(32, '0')}',
    );
    _sequence += 1;
    final lease = TestSupportMediaResourceLease(id);
    _leases[id] = <TestSupportMediaResourceLease>{lease};
    _kinds[id] = kind;
    _durations[id] = duration;
    if (fileUri != null) {
      _fileUris[id] = fileUri;
    }
    return OwnedMediaResource(
      resourceId: id,
      kind: kind,
      contentType: kind == MediaResourceKind.image ? 'image/png' : 'video/mp4',
      length: 64,
      duration: duration,
      initialLease: lease,
    );
  }

  int activeLeaseCount(MediaResourceId id) =>
      _leases[id]?.where((lease) => lease.isActive).length ?? 0;

  @override
  Future<MediaImportResult> importFile(MediaImportRequest request) async {
    importCount += 1;
    events.add('import');
    lastImportRequest = request;
    final failure = nextImportFailure;
    if (failure != null) {
      nextImportFailure = null;
      return MediaResourceError<OwnedMediaResource>(failure);
    }
    return MediaResourceSuccess<OwnedMediaResource>(
      seedOwned(kind: request.kind, duration: request.duration),
    );
  }

  @override
  Future<MediaResourceResult<MediaResourceLease>> retain(
    MediaResourceId resourceId,
  ) async {
    final leases = _leases[resourceId];
    if (leases == null || !leases.any((lease) => lease.isActive)) {
      return _missing<MediaResourceLease>();
    }
    retainCount += 1;
    final lease = TestSupportMediaResourceLease(resourceId);
    leases.add(lease);
    return MediaResourceSuccess<MediaResourceLease>(lease);
  }

  @override
  Future<MediaResourceResult<ResolvedMediaResource>> resolve(
    MediaResourceId resourceId,
    MediaResourceLease lease,
  ) async {
    final kind = _kinds[resourceId];
    final fileUri = _fileUris[resourceId];
    if (kind == null ||
        fileUri == null ||
        lease.resourceId != resourceId ||
        !lease.isActive) {
      return _missing<ResolvedMediaResource>();
    }
    return MediaResourceSuccess<ResolvedMediaResource>(
      ResolvedMediaResource(
        resourceId: resourceId,
        kind: kind,
        contentType: kind == MediaResourceKind.image
            ? 'image/png'
            : 'video/mp4',
        length: 64,
        fileUri: fileUri,
        duration: _durations[resourceId],
      ),
    );
  }

  @override
  Future<MediaResourceResult<void>> release(MediaResourceLease lease) async {
    if (releaseThrowsRemaining > 0) {
      releaseThrowsRemaining -= 1;
      if (lease is TestSupportMediaResourceLease) {
        lease.close();
      }
      throw const FileSystemException('redacted');
    }
    if (releaseFailuresRemaining > 0) {
      releaseFailuresRemaining -= 1;
      if (lease is TestSupportMediaResourceLease) {
        lease.close();
      }
      return const MediaResourceError<void>(
        MediaResourceFailure(
          code: MediaResourceFailureCode.importFailed,
          isRecoverable: true,
        ),
      );
    }
    if (lease is TestSupportMediaResourceLease) {
      if (lease.isActive) {
        lease.close();
      }
      releaseCount += 1;
    }
    return const MediaResourceSuccess<void>(null);
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
    for (final leases in _leases.values) {
      for (final lease in leases) {
        lease.close();
      }
    }
  }
}

final class TestSupportMediaResourceLease implements MediaResourceLease {
  TestSupportMediaResourceLease(this.resourceId);

  @override
  final MediaResourceId resourceId;

  @override
  bool isActive = true;

  void close() => isActive = false;
}

MediaResourceError<T> _missing<T>() => MediaResourceError<T>(
  const MediaResourceFailure(
    code: MediaResourceFailureCode.missing,
    isRecoverable: false,
  ),
);
