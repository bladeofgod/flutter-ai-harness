import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:app_data/app_data.dart'
    show FixtureApiTransport, FixtureRequestHandler;
import 'package:app_data/support.dart';
import 'package:app_features/api/support_chat_api.dart';
import 'package:app_features/api/support_media_picker.dart' as picker;
import 'package:app_features/feature_support/api/local_support_chat_api.dart';
import 'package:app_features/feature_support/controllers/support_chat_controller.dart';
import 'package:app_media/app_media.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support_test_fixtures.dart';

void main() {
  test(
    'advances starting, connecting, typing and active deterministically',
    () async {
      final delays = <Completer<void>>[];
      final mediaStore = TestSupportMediaResourceStore();
      final controller = SupportChatController(
        supportChatApi: createSupportApi(mediaResourceStore: mediaStore),
        supportMediaPicker: FakeSupportMediaPicker(),
        transitionDelay: (_) {
          final completer = Completer<void>();
          delays.add(completer);
          return completer.future;
        },
      );
      addTearDown(controller.onDelete);
      await controller.load();

      controller.selectQuestionFromUi('order-status');
      await _waitForStage(controller, SupportConversationStage.connecting);
      expect(delays, hasLength(1));

      delays[0].complete();
      await _waitForStage(controller, SupportConversationStage.typing);
      expect(delays, hasLength(2));

      delays[1].complete();
      await _waitForStage(controller, SupportConversationStage.active);
      expect(_conversation(controller).messages, hasLength(2));
    },
  );

  test('deduplicates question and message actions', () async {
    final mediaStore = TestSupportMediaResourceStore();
    final countingApi = CountingSupportApi(
      createSupportApi(mediaResourceStore: mediaStore),
    );
    final controller = SupportChatController(
      supportChatApi: countingApi,
      supportMediaPicker: FakeSupportMediaPicker(),
      transitionDelay: immediateSupportDelay,
    );
    addTearDown(controller.onDelete);
    await controller.load();

    controller.selectQuestionFromUi('order-status');
    controller.selectQuestionFromUi('return-item');
    await _waitForStage(controller, SupportConversationStage.active);
    expect(countingApi.selectCount, 1);

    controller.updateDraft('Please check my order.');
    final first = controller.send();
    final duplicate = controller.send();
    expect(await duplicate, isFalse);
    expect(await first, isTrue);
    expect(countingApi.sendCount, 1);
    expect(countingApi.replyCount, 1);
    expect(controller.draft, isEmpty);
    expect(
      _conversation(controller).messages
          .map((message) => message.content)
          .whereType<SupportVoucherContent>(),
      hasLength(1),
    );
  });

  test('cancels pending transitions and clears draft on release', () async {
    final delay = Completer<void>();
    final mediaStore = TestSupportMediaResourceStore();
    final countingApi = CountingSupportApi(
      createSupportApi(mediaResourceStore: mediaStore),
    );
    final controller = SupportChatController(
      supportChatApi: countingApi,
      supportMediaPicker: FakeSupportMediaPicker(),
      transitionDelay: (_) => delay.future,
    );
    await controller.load();
    controller.updateDraft('Never persist this draft');
    controller.selectQuestionFromUi('order-status');
    await _waitForStage(controller, SupportConversationStage.connecting);

    controller.onDelete();
    delay.complete();
    await Future<void>.delayed(Duration.zero);

    expect(countingApi.advanceCount, 0);
    expect(controller.draft, isEmpty);
  });

  test('starting a new session cancels a pending media pick', () async {
    final mediaStore = TestSupportMediaResourceStore();
    final mediaPicker = _PendingSupportMediaPicker();
    final controller = SupportChatController(
      supportChatApi: createSupportApi(mediaResourceStore: mediaStore),
      supportMediaPicker: mediaPicker,
      transitionDelay: immediateSupportDelay,
    );
    addTearDown(controller.onDelete);
    await controller.load();
    controller.selectQuestionFromUi('return-item');
    await _waitForStage(controller, SupportConversationStage.active);

    final send = controller.sendMedia(picker.SupportMediaSource.camera);
    await mediaPicker.pickStarted.future;
    await controller.load();

    expect(await send, isA<SupportMediaSendCanceled>());
    expect(mediaPicker.clearCount, 2);
    expect(_conversation(controller).stage, SupportConversationStage.starting);
  });

  test('failed draft cleanup shows an error and a retry can load', () async {
    final mediaStore = TestSupportMediaResourceStore();
    final mediaPicker = _RetryingClearSupportMediaPicker();
    final controller = SupportChatController(
      supportChatApi: createSupportApi(mediaResourceStore: mediaStore),
      supportMediaPicker: mediaPicker,
      transitionDelay: immediateSupportDelay,
    );
    addTearDown(controller.onDelete);

    await controller.load();
    final failure = (controller.viewState as SupportChatError).failure;
    expect(failure.code, SupportFailureCode.transportUnavailable);

    await controller.load();
    expect(_conversation(controller).stage, SupportConversationStage.starting);
    expect(mediaPicker.clearCount, 2);
  });

  test('release cancels a pending media pick', () async {
    final mediaStore = TestSupportMediaResourceStore();
    final mediaPicker = _PendingSupportMediaPicker();
    final controller = SupportChatController(
      supportChatApi: createSupportApi(mediaResourceStore: mediaStore),
      supportMediaPicker: mediaPicker,
      transitionDelay: immediateSupportDelay,
    );
    await controller.load();
    controller.selectQuestionFromUi('return-item');
    await _waitForStage(controller, SupportConversationStage.active);

    final send = controller.sendMedia(picker.SupportMediaSource.camera);
    await mediaPicker.pickStarted.future;
    controller.onClose();

    expect(await send, isA<SupportMediaSendCanceled>());
    expect(mediaPicker.clearCount, 2);
  });

  test('selects and submits one service rating', () async {
    final mediaStore = TestSupportMediaResourceStore();
    final controller = SupportChatController(
      supportChatApi: createSupportApi(mediaResourceStore: mediaStore),
      supportMediaPicker: FakeSupportMediaPicker(),
      transitionDelay: immediateSupportDelay,
    );
    addTearDown(controller.onDelete);
    await controller.load();
    controller.selectQuestionFromUi('payment-question');
    await _waitForStage(controller, SupportConversationStage.active);

    controller.requestRatingFromUi();
    await _waitForStage(controller, SupportConversationStage.rating);
    controller.selectRating(5);
    controller.submitRatingFromUi();
    controller.submitRatingFromUi();
    await _waitForStage(controller, SupportConversationStage.rated);

    expect(_conversation(controller).rating?.score, 5);
  });

  test('picks and sends camera video as a media message', () async {
    final mediaStore = TestSupportMediaResourceStore();
    final owned = mediaStore.seedOwned(
      kind: MediaResourceKind.video,
      duration: const Duration(seconds: 4),
    );
    final mediaPicker = FakeSupportMediaPicker(
      mediaResourceStore: mediaStore,
      result: picker.SupportMediaPickSuccess(
        picker.SupportMediaAttachment(
          resource: owned,
          label: 'Camera video',
          duration: const Duration(seconds: 4),
        ),
      ),
    );
    final countingApi = CountingSupportApi(
      createSupportApi(mediaResourceStore: mediaStore),
    );
    final controller = SupportChatController(
      supportChatApi: countingApi,
      supportMediaPicker: mediaPicker,
      transitionDelay: immediateSupportDelay,
    );
    addTearDown(controller.onDelete);
    await controller.load();
    controller.selectQuestionFromUi('order-status');
    await _waitForStage(controller, SupportConversationStage.active);

    final result = await controller.sendMedia(picker.SupportMediaSource.camera);

    expect(result, isA<SupportMediaSent>());
    expect(mediaPicker.lastSource, picker.SupportMediaSource.camera);
    expect(countingApi.mediaSendCount, 1);
    final media = _conversation(controller).messages
        .map((message) => message.content)
        .whereType<SupportMediaContent>()
        .single;
    expect(media.type, SupportMediaType.video);
    expect(media.duration, const Duration(seconds: 4));
    expect(media.resourceId, owned.resourceId);
    expect(mediaStore.activeLeaseCount(owned.resourceId), 1);
    expect(mediaPicker.releaseCount, 1);
  });

  test('sends a confirmed camera photo without a preview', () async {
    final mediaStore = TestSupportMediaResourceStore();
    final owned = mediaStore.seedOwned();
    final mediaPicker = FakeSupportMediaPicker(
      mediaResourceStore: mediaStore,
      result: picker.SupportMediaPickSuccess(
        picker.SupportMediaAttachment(resource: owned, label: 'Camera photo'),
      ),
    );
    final controller = SupportChatController(
      supportChatApi: createSupportApi(mediaResourceStore: mediaStore),
      supportMediaPicker: mediaPicker,
      transitionDelay: immediateSupportDelay,
    );
    addTearDown(controller.onDelete);
    await controller.load();
    controller.selectQuestionFromUi('order-status');
    await _waitForStage(controller, SupportConversationStage.active);

    final result = await controller.sendMedia(picker.SupportMediaSource.camera);

    expect(result, isA<SupportMediaSent>());
    final media = _conversation(controller).messages
        .map((message) => message.content)
        .whereType<SupportMediaContent>()
        .single;
    expect(media.type, SupportMediaType.image);
    expect(media.poster, isNull);
    expect(mediaPicker.releaseCount, 1);
  });

  test('accepted media survives a late Controller disposal', () async {
    final mediaStore = TestSupportMediaResourceStore();
    final owned = mediaStore.seedOwned();
    final delayedApi = _DelayedMediaSupportApi(
      createSupportApi(mediaResourceStore: mediaStore),
    );
    final controller = SupportChatController(
      supportChatApi: delayedApi,
      supportMediaPicker: FakeSupportMediaPicker(
        mediaResourceStore: mediaStore,
        result: picker.SupportMediaPickSuccess(
          picker.SupportMediaAttachment(
            resource: owned,
            label: 'Late camera photo',
          ),
        ),
      ),
      transitionDelay: immediateSupportDelay,
    );
    await controller.load();
    controller.selectQuestionFromUi('order-status');
    await _waitForStage(controller, SupportConversationStage.active);

    final sending = controller.sendMedia(picker.SupportMediaSource.camera);
    await delayedApi.accepted.future;
    controller.onDelete();
    delayedApi.release.complete();

    expect(await sending, isA<SupportMediaSendFailed>());
    expect(mediaStore.activeLeaseCount(owned.resourceId), 1);
    await delayedApi.dispose();
    expect(mediaStore.activeLeaseCount(owned.resourceId), 0);
  });

  test('deduplicates repeated media sends and releases once', () async {
    final mediaStore = TestSupportMediaResourceStore();
    final owned = mediaStore.seedOwned();
    final delayedApi = _DelayedMediaSupportApi(
      createSupportApi(mediaResourceStore: mediaStore),
    );
    final mediaPicker = FakeSupportMediaPicker(
      mediaResourceStore: mediaStore,
      result: picker.SupportMediaPickSuccess(
        picker.SupportMediaAttachment(
          resource: owned,
          label: 'One camera photo',
        ),
      ),
    );
    final controller = SupportChatController(
      supportChatApi: delayedApi,
      supportMediaPicker: mediaPicker,
      transitionDelay: immediateSupportDelay,
    );
    addTearDown(controller.onDelete);
    await controller.load();
    controller.selectQuestionFromUi('order-status');
    await _waitForStage(controller, SupportConversationStage.active);

    final first = controller.sendMedia(picker.SupportMediaSource.camera);
    await delayedApi.accepted.future;
    final duplicate = await controller.sendMedia(
      picker.SupportMediaSource.gallery,
    );
    delayedApi.release.complete();

    expect(duplicate, isA<SupportMediaSendFailed>());
    expect(await first, isA<SupportMediaSent>());
    expect(mediaPicker.pickCount, 1);
    expect(mediaPicker.releaseCount, 1);
    await delayedApi.dispose();
  });

  test(
    'failed conversation write rolls back only the candidate lease',
    () async {
      final mediaStore = TestSupportMediaResourceStore();
      final owned = mediaStore.seedOwned();
      final api = createSupportApi(mediaResourceStore: mediaStore);
      await api.startConversation();

      await expectLater(
        api.sendMedia(
          SupportMediaContent(
            resourceId: owned.resourceId,
            type: SupportMediaType.image,
            label: 'Too early',
          ),
        ),
        throwsA(isA<SupportFailure>()),
      );

      expect(mediaStore.retainCount, 1);
      expect(mediaStore.releaseCount, 1);
      expect(mediaStore.activeLeaseCount(owned.resourceId), 1);
      await mediaStore.release(owned.initialLease);
      await api.dispose();
    },
  );

  test(
    'session reset waits for an in-flight media adoption and clears it',
    () async {
      final mediaStore = TestSupportMediaResourceStore();
      final owned = mediaStore.seedOwned();
      final handler = _DelayedSupportFixtureHandler();
      final api = LocalSupportChatApi(
        dataSource: SupportLocalDataSource(
          apiClient: ApiClient(
            transport: FixtureApiTransport(
              handlers: <FixtureRequestHandler>[handler],
            ),
          ),
        ),
        mediaResourceStore: mediaStore,
      );
      await api.startConversation();
      await api.selectQuestion('return-item');
      await api.advanceTransition();
      await api.advanceTransition();

      final sending = api.sendMedia(
        SupportMediaContent(
          resourceId: owned.resourceId,
          type: SupportMediaType.image,
          label: 'Reset race',
        ),
      );
      await handler.sendStarted.future;
      final clearing = api.clearSessionMedia();
      handler.allowSend.complete();

      await sending;
      await clearing;
      expect(mediaStore.activeLeaseCount(owned.resourceId), 1);
      await mediaStore.release(owned.initialLease);
      await api.dispose();
    },
  );

  test('rollback exceptions retain cleanup ownership for retry', () async {
    final mediaStore = TestSupportMediaResourceStore();
    final owned = mediaStore.seedOwned();
    final api = createSupportApi(mediaResourceStore: mediaStore);
    await api.startConversation();
    mediaStore.releaseThrowsRemaining = 1;

    await expectLater(
      api.sendMedia(
        SupportMediaContent(
          resourceId: owned.resourceId,
          type: SupportMediaType.image,
          label: 'Rejected media',
        ),
      ),
      throwsA(isA<SupportFailure>()),
    );

    await api.releaseRetiredMedia();
    expect(mediaStore.activeLeaseCount(owned.resourceId), 1);
    await mediaStore.release(owned.initialLease);
    await api.dispose();
  });
}

final class _DelayedSupportFixtureHandler implements FixtureRequestHandler {
  final SupportFixtureHandler _delegate = SupportFixtureHandler();
  final Completer<void> sendStarted = Completer<void>();
  final Completer<void> allowSend = Completer<void>();

  @override
  Set<String> get requestKeys => _delegate.requestKeys;

  @override
  Future<ApiResponse<Object?>> handle(ApiRequest request) async {
    if (request.key == SupportFixtureHandler.sendMediaKey) {
      if (!sendStarted.isCompleted) sendStarted.complete();
      await allowSend.future;
    }
    return _delegate.handle(request);
  }
}

final class _PendingSupportMediaPicker implements picker.SupportMediaPicker {
  final Completer<void> pickStarted = Completer<void>();
  Completer<picker.SupportMediaPickResult>? _pendingPick;
  int clearCount = 0;

  @override
  Future<picker.SupportMediaPickResult> pick(picker.SupportMediaSource source) {
    final pending = Completer<picker.SupportMediaPickResult>();
    _pendingPick = pending;
    if (!pickStarted.isCompleted) {
      pickStarted.complete();
    }
    return pending.future;
  }

  @override
  Future<void> release(picker.SupportMediaAttachment attachment) async {}

  @override
  Future<void> clearDrafts() async {
    clearCount += 1;
    final pending = _pendingPick;
    _pendingPick = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete(const picker.SupportMediaPickCanceled());
    }
  }

  @override
  Future<void> dispose() => clearDrafts();
}

final class _RetryingClearSupportMediaPicker
    implements picker.SupportMediaPicker {
  int clearCount = 0;

  @override
  Future<picker.SupportMediaPickResult> pick(
    picker.SupportMediaSource source,
  ) async => const picker.SupportMediaPickCanceled();

  @override
  Future<void> release(picker.SupportMediaAttachment attachment) async {}

  @override
  Future<void> clearDrafts() async {
    clearCount += 1;
    if (clearCount == 1) {
      throw const picker.SupportMediaPickerDisposalException();
    }
  }

  @override
  Future<void> dispose() async {}
}

SupportConversation _conversation(SupportChatController controller) =>
    (controller.viewState as SupportChatData).conversation;

Future<void> _waitForStage(
  SupportChatController controller,
  SupportConversationStage stage,
) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    final state = controller.viewState;
    if (state is SupportChatData && state.conversation.stage == stage) {
      return;
    }
    await Future<void>.delayed(Duration.zero);
  }
  fail('Support Chat did not reach ${stage.name}.');
}

final class _DelayedMediaSupportApi implements SupportChatApi {
  _DelayedMediaSupportApi(this.delegate);

  final SupportChatApi delegate;
  final Completer<void> accepted = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<SupportConversation> startConversation() =>
      delegate.startConversation();

  @override
  Future<SupportConversation> selectQuestion(String questionId) =>
      delegate.selectQuestion(questionId);

  @override
  Future<SupportConversation> advanceTransition() =>
      delegate.advanceTransition();

  @override
  Future<SupportConversation> sendMessage(String text) =>
      delegate.sendMessage(text);

  @override
  Future<SupportMediaSendReceipt> sendMedia(SupportMediaContent media) async {
    final receipt = await delegate.sendMedia(media);
    accepted.complete();
    await release.future;
    return receipt;
  }

  @override
  Future<SupportConversation> receiveReply() => delegate.receiveReply();

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
