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
