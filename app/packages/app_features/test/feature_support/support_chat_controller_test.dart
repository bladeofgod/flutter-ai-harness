import 'dart:async';

import 'package:app_data/support.dart';
import 'package:app_features/feature_support/controllers/support_chat_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support_test_fixtures.dart';

void main() {
  test(
    'advances starting, connecting, typing and active deterministically',
    () async {
      final delays = <Completer<void>>[];
      final controller = SupportChatController(
        supportChatApi: createSupportApi(),
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
    final countingApi = CountingSupportApi(createSupportApi());
    final controller = SupportChatController(
      supportChatApi: countingApi,
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
    final countingApi = CountingSupportApi(createSupportApi());
    final controller = SupportChatController(
      supportChatApi: countingApi,
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

  test('selects and submits one service rating', () async {
    final controller = SupportChatController(
      supportChatApi: createSupportApi(),
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
