import 'package:app_core/app_core.dart';

import '../catalog/catalog_fixture.dart';
import '../fixture/fixture_api_transport.dart';

/// Profile Dashboard 请求与 Fixture Payload 的唯一所有者。
final class ProfileDashboardFixtureHandler implements FixtureRequestHandler {
  static const String loadKey = 'profile.dashboard.load';

  @override
  Set<String> get requestKeys => const <String>{loadKey};

  @override
  Future<ApiResponse<Object?>> handle(ApiRequest request) async {
    if (request.key != loadKey) {
      throw UnknownApiRequestException(request.key);
    }
    return ApiResponse<Object?>.success(_profileDashboardFixturePayload());
  }
}

Map<String, Object?> _profileDashboardFixturePayload() => <String, Object?>{
  'announcement': <String, Object?>{
    'title': 'Announcement',
    'message':
        'Lorem ipsum dolor sit amet, consectetur adipiscing elit. '
        'Maecenas hendrerit luctus libero ac vulputate.',
  },
  'recentlyViewed': List<Map<String, Object?>>.generate(
    5,
    (index) => <String, Object?>{
      'id': 'recent-${index + 1}',
      'imageAssetKey': _profileImage('recent', index + 1),
    },
    growable: false,
  ),
  'orders': <String, Object?>{
    'items': <Map<String, Object?>>[
      <String, Object?>{'status': 'to_pay', 'hasNotification': false},
      <String, Object?>{'status': 'to_receive', 'hasNotification': true},
      <String, Object?>{'status': 'to_review', 'hasNotification': false},
    ],
  },
  'stories': <Map<String, Object?>>[
    _storyPayload(1, 'Live Shopping', isLive: true),
    _storyPayload(2, 'The Best New Looks'),
    _storyPayload(3, 'Discover Your Style'),
    _storyPayload(4, 'Weekend Inspiration'),
  ],
  'newItems': List<Map<String, Object?>>.generate(
    5,
    (index) => _productPayload(index + 1),
    growable: false,
  ),
  'mostPopular': <Map<String, Object?>>[
    _productPayload(6, tag: 'New', popularityCount: 1780),
    _productPayload(7, tag: 'Sale', popularityCount: 1780),
    _productPayload(8, tag: 'Hot', popularityCount: 1780),
    _productPayload(9, tag: 'New', popularityCount: 1780),
  ],
  'categories': <Map<String, Object?>>[
    _categoryPayload(1, 'Clothing', 109, productImageNumber: 10),
    _categoryPayload(2, 'Shoes', 530, productImageNumber: 11),
    _categoryPayload(3, 'Bags', 87, productImageNumber: 12),
    _categoryPayload(4, 'Lingerie', 218, productImageNumber: 13),
    _categoryPayload(5, 'Dresses', 156, productImageNumber: 14),
    _categoryPayload(6, 'Jackets', 94, productImageNumber: 15),
    _categoryPayload(7, 'Tops', 264, productImageNumber: 16),
    _categoryPayload(8, 'Accessories', 143, productImageNumber: 17),
  ],
  'flashSale': <String, Object?>{
    'hours': 0,
    'minutes': 36,
    'seconds': 58,
    'products': List<Map<String, Object?>>.generate(
      6,
      (index) => _productPayload(index + 10, tag: '-20%'),
      growable: false,
    ),
  },
  'topProducts': <Map<String, Object?>>[
    _productPayload(16, title: 'Dresses', includePrice: false),
    _productPayload(17, title: 'T-Shirts', includePrice: false),
    _productPayload(18, title: 'Skirts', includePrice: false),
    _productPayload(19, title: 'Shoes', includePrice: false),
    _productPayload(20, title: 'Bags', includePrice: false),
  ],
  'recommendations': List<Map<String, Object?>>.generate(
    8,
    (index) => _productPayload(index + 1),
    growable: false,
  ),
};

Map<String, Object?> _storyPayload(
  int number,
  String title, {
  bool isLive = false,
}) => <String, Object?>{
  'id': 'story-$number',
  'title': title,
  'imageAssetKey': _profileImage('story', number),
  'isLive': isLive,
};

Map<String, Object?> _productPayload(
  int number, {
  String title = 'Lorem ipsum dolor sit amet consectetur.',
  bool includePrice = true,
  String? tag,
  int? popularityCount,
}) => <String, Object?>{
  ...canonicalCatalogProductPayload('product-$number'),
  if (title != 'Lorem ipsum dolor sit amet consectetur.') 'title': title,
  if (!includePrice) ...<String, Object?>{
    'priceMinorUnits': null,
    'currency': null,
  },
  if (tag != null) 'tag': tag,
  if (popularityCount != null) 'popularityCount': popularityCount,
}..removeWhere((key, value) => value == null);

Map<String, Object?> _categoryPayload(
  int number,
  String name,
  int itemCount, {
  required int productImageNumber,
}) => <String, Object?>{
  'id': 'category-$number',
  'name': name,
  'imageAssetKey': _profileImage('product', productImageNumber),
  'itemCount': itemCount,
};

String _profileImage(String family, int number) =>
    'assets/images/profile/${family}_${number.toString().padLeft(2, '0')}.png';
