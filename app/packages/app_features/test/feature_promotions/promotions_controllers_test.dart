import 'dart:async';

import 'package:app_data/promotions.dart';
import 'package:app_features/feature_promotions/controllers/promotions_controllers.dart';
import 'package:flutter_test/flutter_test.dart';

import 'promotions_test_fixtures.dart';

void main() {
  test('Flash Sale loads fixed countdown and retries a failure', () async {
    final fixture = promotionsFixture();
    final api = FakePromotionsApi(
      overviewLoader: (count) async {
        if (count == 1) {
          throw const PromotionsFailure(PromotionsFailureCode.unavailable);
        }
        return fixture;
      },
    );
    final controller = FlashSaleController(promotionsApi: api);
    controller.onInit();
    addTearDown(controller.onClose);

    await _waitFor(() => controller.state is PromotionsError<Promotion>);
    await controller.retry();

    final data = controller.state as PromotionsData<Promotion>;
    expect(data.value.flashSale.displayCountdown, '00:36:58');
    expect(api.overviewLoadCount, 2);
  });

  test('Live only moves to an explicit local preview-ready state', () async {
    final controller = LiveController(promotionsApi: FakePromotionsApi());
    controller.onInit();
    addTearDown(controller.onClose);
    await _waitFor(() => controller.state is PromotionsData<LivePreview>);

    expect(controller.isDemoPreviewReady.value, isFalse);
    controller.prepareDemoPreview();
    expect(controller.isDemoPreviewReady.value, isTrue);
  });

  test('Story advances manually, bounds previous, and finishes once', () async {
    var finishCount = 0;
    final controller = StoryController(
      promotionsApi: FakePromotionsApi(),
      storyId: 'story-style-edit',
      onFinished: () => finishCount += 1,
    );
    controller.onInit();
    addTearDown(controller.onClose);
    await _waitFor(() => controller.state is PromotionsData<StorySequence>);

    expect(controller.currentIndex.value, 0);
    controller.previous();
    expect(controller.currentIndex.value, 0);
    controller.next();
    expect(controller.currentIndex.value, 1);
    expect(controller.currentItem, isA<BannerStoryItem>());
    controller.previous();
    expect(controller.currentIndex.value, 0);
    controller.next();
    controller.next();
    expect(controller.currentIndex.value, 2);
    controller.next();
    controller.next();

    expect(finishCount, 1);
  });

  test('ignores a Story delivered after disposal', () async {
    final completer = Completer<StorySequence>();
    final controller = StoryController(
      promotionsApi: FakePromotionsApi(storyLoader: (_, _) => completer.future),
      storyId: 'story-style-edit',
      onFinished: () {},
    );
    controller.onInit();
    controller.onClose();
    completer.complete(promotionsFixture().stories.single);
    await Future<void>.delayed(Duration.zero);

    expect(controller.state, isA<PromotionsLoading<StorySequence>>());
  });
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Condition did not become true.');
}
