import 'package:app_core/app_core.dart';
import 'package:app_data/app_data.dart';
import 'package:app_features/api/promotions_api.dart';
import 'package:app_features/feature_promotions/api/local_promotions_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Local API exposes deterministic Promotions Domain data', () async {
    final api = _api();

    final overview = await api.loadOverview();
    final story = await api.loadStory('story-style-edit');

    expect(overview.flashSale.flashSale.displayCountdown, '00:36:58');
    expect(overview.livePreviews.single.title, 'Summer Style Edit');
    expect(story.items, hasLength(3));
  });

  test('Local API preserves the typed not-found boundary', () async {
    final api = _api();

    await expectLater(
      api.loadStory('missing'),
      throwsA(
        isA<PromotionsFailure>().having(
          (failure) => failure.code,
          'code',
          PromotionsFailureCode.notFound,
        ),
      ),
    );
  });
}

PromotionsApi _api() => LocalPromotionsApi(
  dataSource: PromotionsLocalDataSource(
    apiClient: ApiClient(
      transport: FixtureApiTransport(
        handlers: const <FixtureRequestHandler>[PromotionsFixtureHandler()],
      ),
    ),
  ),
);
