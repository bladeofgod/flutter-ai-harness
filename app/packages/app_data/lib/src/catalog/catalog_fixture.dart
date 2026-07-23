import 'package:app_core/app_core.dart';

import '../fixture/fixture_api_transport.dart';

/// Shop Catalog 请求与 Fixture Payload 的唯一所有者。
final class CatalogFixtureHandler implements FixtureRequestHandler {
  static const String loadShopKey = 'catalog.shop.load';
  static const String browseKey = 'catalog.browse.load';
  static const String productDetailKey = 'catalog.product.detail.load';
  static const String _invalidQueryCode = 'catalog.invalid_query';

  @override
  Set<String> get requestKeys => const <String>{
    loadShopKey,
    browseKey,
    productDetailKey,
  };

  @override
  Future<ApiResponse<Object?>> handle(ApiRequest request) async {
    return switch (request.key) {
      loadShopKey => ApiResponse<Object?>.success(_shopDashboardPayload()),
      browseKey => _browse(request.payload),
      productDetailKey => _productDetail(request.payload),
      _ => throw UnknownApiRequestException(request.key),
    };
  }

  ApiResponse<Object?> _productDetail(Object? payload) {
    final productId = payload is Map<String, Object?>
        ? payload['productId']
        : null;
    if (productId is! String || !_isKnownProductId(productId)) {
      return const ApiResponse<Object?>.failure(
        ApiFailure.rejected(code: 'catalog.product_not_found'),
      );
    }
    return ApiResponse<Object?>.success(_productDetailPayload(productId));
  }

  ApiResponse<Object?> _browse(Object? payload) {
    final query = _CatalogFixtureQuery.tryParse(payload);
    if (query == null) {
      return const ApiResponse<Object?>.failure(
        ApiFailure.rejected(code: _invalidQueryCode),
      );
    }
    final products = _browseProducts()
        .where((product) => product['categoryId'] == query.categoryId)
        .where(
          (product) =>
              query.subcategoryId == null ||
              product['subcategoryId'] == query.subcategoryId,
        )
        .where(
          (product) =>
              query.audience == 'all' ||
              product['audience'] == 'all' ||
              product['audience'] == query.audience,
        )
        .map(_publicProductPayload)
        .toList(growable: false);
    switch (query.sortOrder) {
      case 'priceLowToHigh':
        products.sort(
          (left, right) => (left['priceMinorUnits']! as int).compareTo(
            right['priceMinorUnits']! as int,
          ),
        );
      case 'priceHighToLow':
        products.sort(
          (left, right) => (right['priceMinorUnits']! as int).compareTo(
            left['priceMinorUnits']! as int,
          ),
        );
      case 'featured':
        break;
    }
    return ApiResponse<Object?>.success(<String, Object?>{
      'categories': _filterCategoriesPayload(),
      'products': products,
    });
  }
}

bool _isKnownProductId(String productId) {
  final number = int.tryParse(
    RegExp(r'(\d+)$').firstMatch(productId)?.group(1) ?? '',
  );
  if (number == null) {
    return false;
  }
  return switch (productId.replaceFirst(RegExp(r'\d+$'), '')) {
    'product-' => number >= 1 && number <= 31,
    'browse-product-' =>
      (number >= 1 && number <= 25) ||
          (number >= 30 && number <= 35) ||
          (number >= 40 && number <= 45) ||
          (number >= 50 && number <= 55) ||
          (number >= 60 && number <= 65),
    'wishlist-product-' => number >= 1 && number <= 5,
    'recommended-' => number >= 1 && number <= 4,
    'recent-product-' => number >= 1 && number <= 8,
    'recent-preview-' => number >= 1 && number <= 5,
    'cart-product-' => number >= 1 && number <= 2,
    _ => false,
  };
}

Map<String, Object?> _productDetailPayload(String productId) {
  final number = _productNumber(productId);
  final summary = _detailProductSummary(productId);
  final currentPrice = summary['priceMinorUnits']! as int;
  final onSale = number.isEven;
  return <String, Object?>{
    'product': <String, Object?>{...summary},
    'gallery': <Map<String, Object?>>[
      for (var offset = 0; offset < 4; offset += 1)
        <String, Object?>{
          'id': 'gallery-${offset + 1}',
          'imageAssetKey': _productImage(
            ((_productImageNumber(productId) + offset - 1) % 20) + 1,
          ),
        },
    ],
    if (onSale) ...<String, Object?>{
      'originalPriceMinorUnits': currentPrice + 800,
      'originalPriceCurrency': 'USD',
    },
    'description':
        'A considered everyday piece with a comfortable fit and easy styling.',
    'optionGroups': <Map<String, Object?>>[
      <String, Object?>{
        'id': 'color',
        'label': 'Color',
        'required': true,
        'options': <Map<String, Object?>>[
          <String, Object?>{'id': 'pink', 'label': 'Pink'},
          <String, Object?>{'id': 'black', 'label': 'Black'},
          <String, Object?>{'id': 'white', 'label': 'White'},
        ],
      },
      <String, Object?>{
        'id': 'size',
        'label': 'Size',
        'required': true,
        'options': <Map<String, Object?>>[
          <String, Object?>{'id': 's', 'label': 'S'},
          <String, Object?>{'id': 'm', 'label': 'M'},
          <String, Object?>{'id': 'l', 'label': 'L'},
        ],
      },
    ],
    'stockCount': 12,
    'rating': <String, Object?>{
      'averageRatingHundredths': 475,
      'reviewCount': 24,
      'distribution': <String, Object?>{
        '5': 18,
        '4': 4,
        '3': 2,
        '2': 0,
        '1': 0,
      },
    },
    'reviews': <Map<String, Object?>>[
      <String, Object?>{
        'id': 'review-1',
        'author': 'Anne',
        'comment': 'The fabric feels soft and the fit is exactly as expected.',
        'rating': 5,
        'publishedLabel': '2 weeks ago',
        'avatarAssetKey': 'assets/images/profile/avatar_romina.png',
      },
      <String, Object?>{
        'id': 'review-2',
        'author': 'Mila',
        'comment': 'A versatile piece that works well for everyday outfits.',
        'rating': 4,
        'publishedLabel': '1 month ago',
        'avatarAssetKey': 'assets/images/profile/avatar_romina.png',
      },
    ],
  };
}

Map<String, Object?> _shopDashboardPayload() => <String, Object?>{
  'promotions': <Map<String, Object?>>[
    <String, Object?>{
      'id': 'promotion-big-sale',
      'title': 'Big Sale',
      'subtitle': 'Up to 50%',
      'badge': 'Happening Now',
      'imageAssetKey': 'assets/images/catalog/big_sale.png',
    },
  ],
  'categories': <Map<String, Object?>>[
    _category(1, 'Clothing', 109, <String>[
      _productImage(12),
      _productImage(13),
      _productImage(14),
      _productImage(15),
    ]),
    _category(2, 'Shoes', 530, <String>[
      _productImage(20),
      _categoryImage('shoes_02'),
      _categoryImage('shoes_03'),
      _categoryImage('shoes_04'),
    ]),
    _category(3, 'Bags', 87, <String>[
      _productImage(16),
      _productImage(17),
      _productImage(18),
      _productImage(19),
    ]),
    _category(4, 'Lingerie', 218, <String>[
      for (var number = 1; number <= 4; number += 1)
        _categoryImage('lingerie_0$number'),
    ]),
    _category(5, 'Watch', 218, <String>[
      for (var number = 1; number <= 4; number += 1)
        _categoryImage('watch_0$number'),
    ]),
    _category(6, 'Hoodies', 218, <String>[
      for (var number = 1; number <= 4; number += 1)
        _categoryImage('hoodies_0$number'),
    ]),
  ],
  'topProducts': <Map<String, Object?>>[
    _product(17),
    _product(29),
    _product(30),
    _product(20),
    _product(31),
  ],
  'newItems': <Map<String, Object?>>[_product(27), _product(20), _product(28)],
  'flashSale': <String, Object?>{
    'hours': 0,
    'minutes': 36,
    'seconds': 58,
    'products': <Map<String, Object?>>[
      _product(22, tag: '-20%'),
      _product(23, tag: '-20%'),
      _product(4, tag: '-20%'),
      _product(5, tag: '-20%'),
      _product(3, tag: '-20%'),
      _product(1, tag: '-20%'),
    ],
  },
  'mostPopular': <Map<String, Object?>>[
    _product(23, tag: 'New', popularityCount: 1780),
    _product(22, tag: 'Sale', popularityCount: 1780),
    _product(24, tag: 'Hot', popularityCount: 1780),
    _product(3, tag: 'Hot', popularityCount: 1780),
  ],
  'recommendations': <Map<String, Object?>>[
    _product(21),
    _product(2),
    _product(25),
    _product(1),
    _product(3),
    _product(4),
    _product(26),
    _product(5),
  ],
};

Map<String, Object?> _category(
  int number,
  String name,
  int itemCount,
  List<String> previewImageAssetKeys,
) => <String, Object?>{
  'id': 'category-$number',
  'name': name,
  'itemCount': itemCount,
  'previewImageAssetKeys': previewImageAssetKeys,
};

Map<String, Object?> _product(int number, {String? tag, int? popularityCount}) {
  final payload = canonicalCatalogProductPayload('product-$number');
  return <String, Object?>{
    ...payload,
    if (tag != null) 'tag': tag,
    if (popularityCount != null) 'popularityCount': popularityCount,
  }..removeWhere((key, value) => value == null);
}

/// 共享各 Fixture 的稳定商品摘要。路由仍可使用来源别名，但摘要字段不再
/// 按来源重新生成，避免详情、购物车和列表展示同一商品时出现价格漂移。
Map<String, Object?> canonicalCatalogProductPayload(String productId) {
  final canonicalId = canonicalCatalogProductId(productId);
  final number = _productNumber(canonicalId);
  final special = switch (number) {
    1 => ('Floral summer dress', _productImage(1), 1700),
    2 => ('Classic white shirt', _productImage(2), 2100),
    3 => ('Relaxed blue hoodie', _productImage(3), 2500),
    16 => ('Structured shoulder bag', _productImage(16), 2900),
    20 => ('Everyday running shoes', _productImage(20), 3200),
    _ => (
      'Lorem ipsum dolor sit amet consectetur.',
      _productImage((number - 1) % 20 + 1),
      1700 + (number % 4) * 300,
    ),
  };
  return <String, Object?>{
    'id': canonicalId,
    'title': special.$1,
    'imageAssetKey': special.$2,
    'priceMinorUnits': special.$3,
    'currency': 'USD',
  };
}

/// 将各 Feature 过去使用的来源前缀收敛为同一商品 ID。
String canonicalCatalogProductId(String productId) {
  final number = RegExp(r'\d+$').firstMatch(productId)?.group(0);
  if (number == null) {
    return productId;
  }
  final prefix = productId.substring(0, productId.length - number.length);
  if (const <String>{
    'browse-product-',
    'wishlist-product-',
    'recommended-',
    'recent-product-',
    'recent-preview-',
    'cart-product-',
  }.contains(prefix)) {
    return 'product-$number';
  }
  return productId;
}

Map<String, Object?> _detailProductSummary(String productId) {
  if (productId.startsWith('browse-product-')) {
    final browseProduct = _browseProducts().firstWhere(
      (product) => product['id'] == productId,
      orElse: () => <String, Object?>{},
    );
    if (browseProduct.isNotEmpty) {
      return _publicProductPayload(browseProduct);
    }
  }
  return canonicalCatalogProductPayload(productId);
}

int _productNumber(String productId) =>
    int.tryParse(RegExp(r'(\d+)$').firstMatch(productId)?.group(1) ?? '') ?? 1;

int _productImageNumber(String productId) =>
    (_productNumber(productId) - 1) % 20 + 1;

String _productImage(int number) =>
    'assets/images/profile/product_${number.toString().padLeft(2, '0')}.png';

String _categoryImage(String name) =>
    'assets/images/catalog/categories/category_$name.png';

List<Map<String, Object?>> _filterCategoriesPayload() => <Map<String, Object?>>[
  _filterCategory(
    id: 'category-clothing',
    name: 'Clothing',
    imageAssetKey: _productImage(12),
    subcategories: <({String id, String name, String imageAssetKey})>[
      (
        id: 'subcategory-dresses',
        name: 'Dresses',
        imageAssetKey: _productImage(16),
      ),
      (
        id: 'subcategory-pants',
        name: 'Pants',
        imageAssetKey: _categoryImage('watch_01'),
      ),
      (
        id: 'subcategory-skirts',
        name: 'Skirts',
        imageAssetKey: _categoryImage('hoodies_01'),
      ),
      (
        id: 'subcategory-shorts',
        name: 'Shorts',
        imageAssetKey: _productImage(20),
      ),
      (
        id: 'subcategory-jackets',
        name: 'Jackets',
        imageAssetKey: _categoryImage('lingerie_01'),
      ),
      (
        id: 'subcategory-hoodies',
        name: 'Hoodies',
        imageAssetKey: _categoryImage('shoes_02'),
      ),
      (
        id: 'subcategory-shirts',
        name: 'Shirts',
        imageAssetKey: _categoryImage('lingerie_02'),
      ),
      (
        id: 'subcategory-polo',
        name: 'Polo',
        imageAssetKey: _categoryImage('hoodies_02'),
      ),
      (
        id: 'subcategory-t-shirts',
        name: 'T-Shirts',
        imageAssetKey: _categoryImage('hoodies_03'),
      ),
      (
        id: 'subcategory-tunics',
        name: 'Tunics',
        imageAssetKey: _categoryImage('lingerie_04'),
      ),
    ],
  ),
  _filterCategory(
    id: 'category-shoes',
    name: 'Shoes',
    imageAssetKey: _productImage(20),
  ),
  _filterCategory(
    id: 'category-bags',
    name: 'Bags',
    imageAssetKey: _productImage(16),
  ),
  _filterCategory(
    id: 'category-lingerie',
    name: 'Lingerie',
    imageAssetKey: _categoryImage('lingerie_01'),
  ),
  _filterCategory(
    id: 'category-accessories',
    name: 'Accessories',
    imageAssetKey: _categoryImage('hoodies_01'),
  ),
  _filterCategory(
    id: 'category-for-you',
    name: 'Just for You',
    imageAssetKey: _categoryImage('lingerie_04'),
  ),
];

Map<String, Object?> _filterCategory({
  required String id,
  required String name,
  required String imageAssetKey,
  List<({String id, String name, String imageAssetKey})> subcategories =
      const <({String id, String name, String imageAssetKey})>[],
}) => <String, Object?>{
  'id': id,
  'name': name,
  'imageAssetKey': imageAssetKey,
  'subcategories': <Map<String, Object?>>[
    for (final subcategory in subcategories)
      <String, Object?>{
        'id': subcategory.id,
        'name': subcategory.name,
        'imageAssetKey': subcategory.imageAssetKey,
      },
  ],
};

List<Map<String, Object?>> _browseProducts() => <Map<String, Object?>>[
  for (var cycle = 0; cycle < 2; cycle += 1)
    for (var index = 0; index < 10; index += 1)
      _browseProduct(
        number: cycle * 10 + index + 1,
        categoryId: 'category-clothing',
        subcategoryId: _clothingSubcategoryIds[index % 10],
        audience: index == 4 || index == 7 ? 'male' : 'female',
        imageNumber: (index % 9) + 1,
        priceMinorUnits: 1700 + (index % 4) * 400,
      ),
  for (final category in <String>[
    'category-shoes',
    'category-bags',
    'category-lingerie',
    'category-accessories',
    'category-for-you',
  ])
    for (var index = 0; index < 6; index += 1)
      _browseProduct(
        number: 20 + _categoryProductOffset(category) + index,
        categoryId: category,
        audience: index.isEven ? 'female' : 'all',
        imageNumber: (index % 9) + 1,
        priceMinorUnits: 1900 + index * 300,
      ),
];

const List<String> _clothingSubcategoryIds = <String>[
  'subcategory-dresses',
  'subcategory-pants',
  'subcategory-skirts',
  'subcategory-shorts',
  'subcategory-jackets',
  'subcategory-hoodies',
  'subcategory-shirts',
  'subcategory-polo',
  'subcategory-t-shirts',
  'subcategory-tunics',
];

int _categoryProductOffset(String categoryId) => switch (categoryId) {
  'category-shoes' => 0,
  'category-bags' => 10,
  'category-lingerie' => 20,
  'category-accessories' => 30,
  'category-for-you' => 40,
  _ => 50,
};

Map<String, Object?> _browseProduct({
  required int number,
  required String categoryId,
  required String audience,
  required int imageNumber,
  required int priceMinorUnits,
  String? subcategoryId,
}) => <String, Object?>{
  ...canonicalCatalogProductPayload('product-$number'),
  'categoryId': categoryId,
  if (subcategoryId != null) 'subcategoryId': subcategoryId,
  'audience': audience,
};

Map<String, Object?> _publicProductPayload(Map<String, Object?> product) =>
    <String, Object?>{
      'id': product['id'],
      'title': product['title'],
      'imageAssetKey': product['imageAssetKey'],
      'priceMinorUnits': product['priceMinorUnits'],
      'currency': product['currency'],
    };

final class _CatalogFixtureQuery {
  const _CatalogFixtureQuery({
    required this.audience,
    required this.categoryId,
    required this.subcategoryId,
    required this.sortOrder,
  });

  final String audience;
  final String categoryId;
  final String? subcategoryId;
  final String sortOrder;

  static _CatalogFixtureQuery? tryParse(Object? payload) {
    if (payload is! Map<String, Object?>) {
      return null;
    }
    final audience = payload['audience'];
    final categoryId = payload['categoryId'];
    final subcategoryId = payload['subcategoryId'];
    final sortOrder = payload['sortOrder'];
    if (audience is! String ||
        !const <String>{'all', 'female', 'male'}.contains(audience) ||
        categoryId is! String ||
        categoryId.isEmpty ||
        (subcategoryId != null && subcategoryId is! String) ||
        (subcategoryId is String && subcategoryId.isEmpty) ||
        sortOrder is! String ||
        !const <String>{
          'featured',
          'priceLowToHigh',
          'priceHighToLow',
        }.contains(sortOrder)) {
      return null;
    }
    return _CatalogFixtureQuery(
      audience: audience,
      categoryId: categoryId,
      subcategoryId: subcategoryId as String?,
      sortOrder: sortOrder,
    );
  }
}
