import 'package:app_core/app_core.dart';

import '../catalog/catalog_fixture.dart';
import '../fixture/fixture_api_transport.dart';

/// Promotions 请求、固定排序和本地 Fixture Payload 的唯一所有者。
final class PromotionsFixtureHandler implements FixtureRequestHandler {
  static const String loadOverviewKey = 'promotions.overview.load';
  static const String loadStoryKey = 'promotions.story.load';

  const PromotionsFixtureHandler();

  @override
  Set<String> get requestKeys => const <String>{loadOverviewKey, loadStoryKey};

  @override
  Future<ApiResponse<Object?>> handle(ApiRequest request) async =>
      switch (request.key) {
        loadOverviewKey => ApiResponse<Object?>.success(_overviewPayload()),
        loadStoryKey => _loadStory(request.payload),
        _ => throw UnknownApiRequestException(request.key),
      };

  ApiResponse<Object?> _loadStory(Object? payload) {
    final storyId = payload is Map<String, Object?> ? payload['storyId'] : null;
    if (storyId is! String) {
      return const ApiResponse<Object?>.failure(
        ApiFailure.rejected(code: 'promotions.story_not_found'),
      );
    }
    final story = _storiesPayload().where((item) => item['id'] == storyId);
    if (story.isEmpty) {
      return const ApiResponse<Object?>.failure(
        ApiFailure.rejected(code: 'promotions.story_not_found'),
      );
    }
    return ApiResponse<Object?>.success(story.single);
  }
}

Map<String, Object?> _overviewPayload() => <String, Object?>{
  'flashSale': <String, Object?>{
    'id': 'promotion-flash-sale',
    'title': 'Flash Sale',
    'subtitle': 'Today only',
    'imageAssetKey': 'assets/images/catalog/big_sale.png',
    'hours': 0,
    'minutes': 36,
    'seconds': 58,
    'products': <Map<String, Object?>>[
      _product(21, 1500),
      _product(22, 1800),
      _product(23, 2100),
      _product(24, 2400),
      _product(25, 2700),
      _product(26, 3000),
    ],
  },
  'livePreviews': <Map<String, Object?>>[
    <String, Object?>{
      'id': 'live-summer-edit',
      'title': 'Summer Style Edit',
      'subtitle': 'A local demo preview',
      'coverAssetKey': 'assets/images/profile/story_01.png',
      'product': _product(7, 2600),
    },
  ],
  'stories': _storiesPayload(),
};

List<Map<String, Object?>> _storiesPayload() => <Map<String, Object?>>[
  <String, Object?>{
    'id': 'story-style-edit',
    'title': 'Style Edit',
    'coverAssetKey': 'assets/images/profile/story_02.png',
    'items': <Map<String, Object?>>[
      <String, Object?>{
        'id': 'story-item-product-1',
        'type': 'product',
        'title': 'Everyday color',
        'imageAssetKey': 'assets/images/profile/story_02.png',
        'product': _product(8, 1900),
      },
      <String, Object?>{
        'id': 'story-item-banner',
        'type': 'banner',
        'title': 'Dress for your day',
        'body': 'Fresh combinations selected for a simple daily wardrobe.',
        'imageAssetKey': 'assets/images/profile/story_03.png',
      },
      <String, Object?>{
        'id': 'story-item-product-2',
        'type': 'product',
        'title': 'The finishing layer',
        'imageAssetKey': 'assets/images/profile/story_04.png',
        'product': _product(9, 2300),
      },
    ],
  },
];

Map<String, Object?> _product(int number, int priceMinorUnits) {
  return canonicalCatalogProductPayload('product-$number');
}
