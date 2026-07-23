import 'package:app_core/app_core.dart';

import '../fixture/fixture_api_transport.dart';

/// Search 请求与确定性 Fixture Payload 的唯一所有者。
final class SearchFixtureHandler implements FixtureRequestHandler {
  static const String textSearchKey = 'search.text.query';
  static const String imageSearchKey = 'search.image.recognize';

  @override
  Set<String> get requestKeys => const <String>{textSearchKey, imageSearchKey};

  @override
  Future<ApiResponse<Object?>> handle(ApiRequest request) async =>
      switch (request.key) {
        textSearchKey => _searchText(request.payload),
        imageSearchKey => _searchImage(request.payload),
        _ => throw UnknownApiRequestException(request.key),
      };

  ApiResponse<Object?> _searchText(Object? payload) {
    final query = _SearchFixtureQuery.tryParse(payload);
    if (query == null) {
      return const ApiResponse<Object?>.failure(
        ApiFailure.rejected(code: 'search.invalid_query'),
      );
    }
    final tokens = query.text.split(' ').where((token) => token.isNotEmpty);
    final products = _searchProducts
        .where((product) => query.matchesFilter(product))
        .where((product) {
          final searchable = <String>{
            product.title,
            product.categoryId,
            product.subcategoryId ?? '',
            ...product.keywords,
          }.join(' ').toLowerCase();
          return tokens.every(searchable.contains);
        })
        .map((product) => product.publicPayload)
        .toList(growable: false);
    return ApiResponse<Object?>.success(<String, Object?>{
      'products': products,
    });
  }

  ApiResponse<Object?> _searchImage(Object? payload) {
    if (payload is! Map<String, Object?> ||
        payload['fixtureInput'] != 'selected_gallery_image' ||
        payload['byteLength'] is! int ||
        (payload['byteLength']! as int) <= 0) {
      return const ApiResponse<Object?>.failure(
        ApiFailure.rejected(code: 'search.invalid_query'),
      );
    }
    return ApiResponse<Object?>.success(<String, Object?>{
      'recognizedLabel': 'Floral summer dress',
      'products': _searchProducts
          .where((product) => product.categoryId == 'category-clothing')
          .take(4)
          .map((product) => product.publicPayload)
          .toList(growable: false),
    });
  }
}

final class _SearchFixtureQuery {
  const _SearchFixtureQuery({
    required this.text,
    required this.audience,
    required this.categoryId,
    required this.subcategoryId,
  });

  final String text;
  final String audience;
  final String categoryId;
  final String? subcategoryId;

  bool matchesFilter(_SearchFixtureProduct product) =>
      product.categoryId == categoryId &&
      (subcategoryId == null || product.subcategoryId == subcategoryId) &&
      (audience == 'all' ||
          product.audience == 'all' ||
          product.audience == audience);

  static _SearchFixtureQuery? tryParse(Object? payload) {
    if (payload is! Map<String, Object?>) {
      return null;
    }
    final text = payload['text'];
    final audience = payload['audience'];
    final categoryId = payload['categoryId'];
    final subcategoryId = payload['subcategoryId'];
    if (text is! String ||
        text.isEmpty ||
        text != text.toLowerCase() ||
        audience is! String ||
        !const <String>{'all', 'female', 'male'}.contains(audience) ||
        categoryId is! String ||
        categoryId.isEmpty ||
        (subcategoryId != null &&
            (subcategoryId is! String || subcategoryId.isEmpty))) {
      return null;
    }
    return _SearchFixtureQuery(
      text: text,
      audience: audience,
      categoryId: categoryId,
      subcategoryId: subcategoryId as String?,
    );
  }
}

final class _SearchFixtureProduct {
  const _SearchFixtureProduct({
    required this.id,
    required this.title,
    required this.imageAssetKey,
    required this.priceMinorUnits,
    required this.categoryId,
    required this.audience,
    required this.keywords,
    this.subcategoryId,
  });

  final String id;
  final String title;
  final String imageAssetKey;
  final int priceMinorUnits;
  final String categoryId;
  final String audience;
  final List<String> keywords;
  final String? subcategoryId;

  Map<String, Object?> get publicPayload => <String, Object?>{
    'id': id,
    'title': title,
    'imageAssetKey': imageAssetKey,
    'priceMinorUnits': priceMinorUnits,
    'currency': 'USD',
  };
}

const List<_SearchFixtureProduct> _searchProducts = <_SearchFixtureProduct>[
  _SearchFixtureProduct(
    id: 'product-1',
    title: 'Floral summer dress',
    imageAssetKey: 'assets/images/profile/product_01.png',
    priceMinorUnits: 1700,
    categoryId: 'category-clothing',
    subcategoryId: 'subcategory-dresses',
    audience: 'female',
    keywords: <String>['floral', 'summer', 'dress', 'pink'],
  ),
  _SearchFixtureProduct(
    id: 'product-2',
    title: 'Classic white shirt',
    imageAssetKey: 'assets/images/profile/product_02.png',
    priceMinorUnits: 2100,
    categoryId: 'category-clothing',
    subcategoryId: 'subcategory-shirts',
    audience: 'all',
    keywords: <String>['classic', 'white', 'shirt', 'office'],
  ),
  _SearchFixtureProduct(
    id: 'product-3',
    title: 'Relaxed blue hoodie',
    imageAssetKey: 'assets/images/profile/product_03.png',
    priceMinorUnits: 2500,
    categoryId: 'category-clothing',
    subcategoryId: 'subcategory-hoodies',
    audience: 'male',
    keywords: <String>['relaxed', 'blue', 'hoodie', 'casual'],
  ),
  _SearchFixtureProduct(
    id: 'product-20',
    title: 'Everyday running shoes',
    imageAssetKey: 'assets/images/profile/product_20.png',
    priceMinorUnits: 3200,
    categoryId: 'category-shoes',
    audience: 'all',
    keywords: <String>['running', 'shoes', 'sport'],
  ),
  _SearchFixtureProduct(
    id: 'product-16',
    title: 'Structured shoulder bag',
    imageAssetKey: 'assets/images/profile/product_16.png',
    priceMinorUnits: 2900,
    categoryId: 'category-bags',
    audience: 'female',
    keywords: <String>['structured', 'shoulder', 'bag'],
  ),
];
