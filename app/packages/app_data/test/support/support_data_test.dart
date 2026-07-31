import 'dart:convert';
import 'dart:typed_data';

import 'package:app_core/app_core.dart';
import 'package:app_data/app_data.dart'
    show FixtureApiTransport, FixtureRequestHandler;
import 'package:app_data/support.dart';
import 'package:test/test.dart';

void main() {
  test('runs the fixed local conversation and reuses Voucher domain', () async {
    final source = _source(SupportFixtureHandler());

    var conversation = await source.startConversation();
    expect(conversation.stage, SupportConversationStage.starting);
    expect(conversation.suggestedQuestions, hasLength(3));
    expect(conversation.messages, isEmpty);

    conversation = await source.selectQuestion('order-status');
    expect(conversation.stage, SupportConversationStage.connecting);
    expect(
      conversation.messages.single.participant,
      SupportParticipant.customer,
    );

    conversation = await source.advanceTransition();
    expect(conversation.stage, SupportConversationStage.typing);
    conversation = await source.advanceTransition();
    expect(conversation.stage, SupportConversationStage.active);
    expect(conversation.messages, hasLength(2));

    conversation = await source.sendMessage('My parcel has not arrived.');
    expect(conversation.stage, SupportConversationStage.typing);
    conversation = await source.receiveReply();
    expect(conversation.stage, SupportConversationStage.active);
    expect(conversation.messages, hasLength(5));
    final voucherContent = conversation.messages
        .map((message) => message.content)
        .whereType<SupportVoucherContent>()
        .single;
    expect(voucherContent.voucher, isA<Voucher>());
    expect(voucherContent.voucher.id, 'voucher-shoppe-five');
    expect(voucherContent.voucher.code, 'SHOPPE5');

    conversation = await source.requestRating();
    expect(conversation.stage, SupportConversationStage.rating);
    conversation = await source.submitRating(5);
    expect(conversation.stage, SupportConversationStage.rated);
    expect(conversation.rating?.score, 5);
  });

  test('round-trips image and video Support messages defensively', () async {
    final source = _source(SupportFixtureHandler());
    await source.startConversation();
    await source.selectQuestion('return-item');
    await source.advanceTransition();
    await source.advanceTransition();

    final imageId = MediaResourceId('mr_00000000000000000000000000000001');
    var conversation = await source.sendMedia(
      SupportMediaContent(
        resourceId: imageId,
        type: SupportMediaType.image,
        label: 'damaged-item.jpg',
      ),
    );
    var media = conversation.messages.last.content as SupportMediaContent;
    expect(media.type, SupportMediaType.image);
    expect(media.resourceId, imageId);
    expect(media.poster, isNull);

    conversation = await source.receiveReply();
    final videoId = MediaResourceId('mr_00000000000000000000000000000002');
    conversation = await source.sendMedia(
      SupportMediaContent(
        resourceId: videoId,
        type: SupportMediaType.video,
        label: 'unboxing.mp4',
        duration: const Duration(seconds: 8),
      ),
    );
    media = conversation.messages.last.content as SupportMediaContent;
    expect(media.type, SupportMediaType.video);
    expect(media.resourceId, videoId);
    expect(media.duration, const Duration(seconds: 8));

    conversation = await source.receiveReply();
    conversation = await source.sendMedia(
      SupportMediaContent(
        resourceId: MediaResourceId('mr_00000000000000000000000000000003'),
        type: SupportMediaType.image,
        label: 'camera-photo.jpg',
      ),
    );
    media = conversation.messages.last.content as SupportMediaContent;
    expect(media.type, SupportMediaType.image);
    expect(media.poster, isNull);
    expect(media.toString(), isNot(contains(media.resourceId.value)));
  });

  test('fixture payload contains only opaque ID and light metadata', () async {
    final handler = SupportFixtureHandler();
    final transport = _CapturingTransport(
      FixtureApiTransport(handlers: <FixtureRequestHandler>[handler]),
    );
    final source = SupportLocalDataSource(
      apiClient: ApiClient(transport: transport),
    );
    await source.startConversation();
    await source.selectQuestion('return-item');
    await source.advanceTransition();
    await source.advanceTransition();

    await source.sendMedia(
      SupportMediaContent(
        resourceId: MediaResourceId('mr_00000000000000000000000000000004'),
        type: SupportMediaType.video,
        label: 'proof.mov',
        duration: const Duration(seconds: 3),
      ),
    );

    final payload = transport.lastPayload! as Map<String, Object?>;
    expect(payload.keys, <String>{
      'resourceId',
      'mediaType',
      'label',
      'durationMillis',
    });
    expect(payload.toString(), isNot(contains('file:')));
    expect(payload.toString(), isNot(contains('handle')));
    expect(() => MediaResourceId('invalid'), throwsA(isA<FormatException>()));
  });

  test(
    'uses stable request keys and rejects invalid script operations',
    () async {
      expect(
        SupportFixtureHandler.startConversationKey,
        'support.conversation.start',
      );
      expect(
        SupportFixtureHandler.selectQuestionKey,
        'support.question.select',
      );
      expect(SupportFixtureHandler.sendMessageKey, 'support.message.send');

      final source = _source(SupportFixtureHandler());
      await source.startConversation();
      await expectLater(
        source.selectQuestion('missing'),
        throwsA(
          isA<SupportFailure>().having(
            (failure) => failure.code,
            'code',
            SupportFailureCode.questionNotFound,
          ),
        ),
      );
      await expectLater(
        source.sendMessage('Too early'),
        throwsA(
          isA<SupportFailure>().having(
            (failure) => failure.code,
            'code',
            SupportFailureCode.invalidState,
          ),
        ),
      );
    },
  );

  test('starting a new route session resets messages and rating', () async {
    final source = _source(SupportFixtureHandler());
    await source.startConversation();
    await source.selectQuestion('return-item');
    await source.advanceTransition();
    await source.advanceTransition();
    await source.requestRating();
    await source.submitRating(4);

    final restarted = await source.startConversation();

    expect(restarted.stage, SupportConversationStage.starting);
    expect(restarted.messages, isEmpty);
    expect(restarted.rating, isNull);
  });

  test('maps malformed fixture payload to invalidResponse', () async {
    final source = SupportLocalDataSource(
      apiClient: ApiClient(transport: const _MalformedTransport()),
    );

    await expectLater(
      source.startConversation(),
      throwsA(
        isA<SupportFailure>().having(
          (failure) => failure.code,
          'code',
          SupportFailureCode.invalidResponse,
        ),
      ),
    );
  });

  test('domain collections are immutable and validate finite states', () {
    final question = SuggestedQuestion(id: 'question', label: 'Help');
    final conversation = SupportConversation(
      id: 'conversation',
      stage: SupportConversationStage.starting,
      suggestedQuestions: <SuggestedQuestion>[question],
      messages: const <SupportMessage>[],
    );

    expect(
      () => conversation.suggestedQuestions.add(question),
      throwsUnsupportedError,
    );
    expect(() => ServiceRating(score: 0), throwsArgumentError);
    expect(
      () => SupportConversation(
        id: 'rated',
        stage: SupportConversationStage.rated,
        suggestedQuestions: const <SuggestedQuestion>[],
        messages: const <SupportMessage>[],
      ),
      throwsArgumentError,
    );
  });

  test('Support poster accepts only bounded sanitized PNG bytes', () {
    final bytes = _onePixelPng();
    final poster = SupportMediaPoster(bytes: bytes, width: 1, height: 1);
    bytes.fillRange(0, bytes.length, 0);

    expect(poster.bytes, _onePixelPng());
    expect(poster.toString(), 'SupportMediaPoster(<redacted>)');
    expect(
      () => SupportMediaPoster(
        bytes: Uint8List.fromList(<int>[137, 80, 78, 71, 13, 10, 26, 10]),
        width: 1,
        height: 1,
      ),
      throwsArgumentError,
    );
  });
}

SupportLocalDataSource _source(SupportFixtureHandler handler) =>
    SupportLocalDataSource(
      apiClient: ApiClient(
        transport: FixtureApiTransport(
          handlers: <FixtureRequestHandler>[handler],
        ),
      ),
    );

final class _MalformedTransport implements ApiTransport {
  const _MalformedTransport();

  @override
  Future<ApiResponse<Object?>> send(ApiRequest request) async =>
      const ApiResponse<Object?>.success(<String, Object?>{});
}

final class _CapturingTransport implements ApiTransport {
  _CapturingTransport(this.delegate);

  final ApiTransport delegate;
  Object? lastPayload;

  @override
  Future<ApiResponse<Object?>> send(ApiRequest request) {
    lastPayload = request.payload;
    return delegate.send(request);
  }
}

Uint8List _onePixelPng() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8A'
  'AQUBAScY42YAAAAASUVORK5CYII=',
);
