import 'package:app_core/app_core.dart';
import 'package:app_data/app_data.dart';
import 'package:test/test.dart';

void main() {
  test('loads stable promotions, live and story content', () async {
    final source = _source(
      FixtureApiTransport(
        handlers: const <FixtureRequestHandler>[PromotionsFixtureHandler()],
      ),
    );

    final overview = await source.loadOverview();

    expect(overview.flashSale.id, 'promotion-flash-sale');
    expect(overview.flashSale.flashSale.displayCountdown, '00:36:58');
    expect(
      overview.flashSale.flashSale.products.map((item) => item.id),
      <String>[
        'product-21',
        'product-22',
        'product-23',
        'product-24',
        'product-25',
        'product-26',
      ],
    );
    expect(overview.livePreviews.single.id, 'live-summer-edit');
    expect(overview.stories.single.items, hasLength(3));
    expect(overview.stories.single.items[0], isA<ProductStoryItem>());
    expect(overview.stories.single.items[1], isA<BannerStoryItem>());
    expect(overview.stories.single.items[2], isA<ProductStoryItem>());
  });

  test('loads a Story by stable id and rejects an unknown id', () async {
    final source = _source(
      FixtureApiTransport(
        handlers: const <FixtureRequestHandler>[PromotionsFixtureHandler()],
      ),
    );

    final story = await source.loadStory('story-style-edit');
    expect(story.title, 'Style Edit');

    await expectLater(
      source.loadStory('missing-story'),
      throwsA(
        isA<PromotionsFailure>().having(
          (failure) => failure.code,
          'code',
          PromotionsFailureCode.notFound,
        ),
      ),
    );
  });

  test('uses only local immutable assets and collections', () async {
    final overview = await _source(
      FixtureApiTransport(
        handlers: const <FixtureRequestHandler>[PromotionsFixtureHandler()],
      ),
    ).loadOverview();
    final keys = <String>{
      overview.flashSale.imageAssetKey,
      ...overview.flashSale.flashSale.products.map(
        (product) => product.imageAssetKey,
      ),
      ...overview.livePreviews.map((preview) => preview.coverAssetKey),
      ...overview.stories.expand(
        (story) => <String>[
          story.coverAssetKey,
          ...story.items.map((item) => item.imageAssetKey),
        ],
      ),
    };

    expect(keys.any((key) => Uri.parse(key).hasScheme), isFalse);
    expect(keys.any((key) => key.contains('localhost')), isFalse);
    expect(
      () => overview.stories.add(overview.stories.single),
      throwsUnsupportedError,
    );
    expect(
      () => overview.stories.single.items.add(
        overview.stories.single.items.first,
      ),
      throwsUnsupportedError,
    );
  });

  test('maps malformed payload to invalidResponse', () async {
    await expectLater(
      _source(const _PayloadTransport(<String, Object?>{})).loadOverview(),
      throwsA(
        isA<PromotionsFailure>().having(
          (failure) => failure.code,
          'code',
          PromotionsFailureCode.invalidResponse,
        ),
      ),
    );
  });

  test(
    'sends stable request keys and transport-neutral story payload',
    () async {
      final transport = _RecordingTransport();
      final source = _source(transport);

      await source.loadOverview();
      expect(transport.key, PromotionsFixtureHandler.loadOverviewKey);

      await source.loadStory('story-style-edit');
      expect(transport.key, PromotionsFixtureHandler.loadStoryKey);
      expect(transport.payload, <String, Object?>{
        'storyId': 'story-style-edit',
      });
    },
  );

  test('model rejects remote assets and empty Story sequences', () {
    expect(
      () => LivePreview(
        id: 'live',
        title: 'Live',
        subtitle: 'Demo',
        coverAssetKey: 'https://example.com/live.png',
        product: _product(),
      ),
      throwsArgumentError,
    );
    expect(
      () => StorySequence(
        id: 'story',
        title: 'Story',
        coverAssetKey: 'assets/story.png',
        items: const <StoryItem>[],
      ),
      throwsArgumentError,
    );
  });
}

PromotionsLocalDataSource _source(ApiTransport transport) =>
    PromotionsLocalDataSource(apiClient: ApiClient(transport: transport));

ProductSummary _product() => ProductSummary(
  id: 'product',
  title: 'Product',
  imageAssetKey: 'assets/product.png',
  price: Money(currency: Currency.usd, minorUnits: 1200),
);

final class _PayloadTransport implements ApiTransport {
  const _PayloadTransport(this.payload);

  final Object? payload;

  @override
  Future<ApiResponse<Object?>> send(ApiRequest request) async =>
      ApiResponse<Object?>.success(payload);
}

final class _RecordingTransport implements ApiTransport {
  String? key;
  Object? payload;

  @override
  Future<ApiResponse<Object?>> send(ApiRequest request) async {
    key = request.key;
    payload = request.payload;
    if (request.key == PromotionsFixtureHandler.loadOverviewKey) {
      return PromotionsFixtureHandler().handle(request);
    }
    return PromotionsFixtureHandler().handle(request);
  }
}
