import 'package:app_core/app_core.dart';
import 'package:app_data/app_data.dart';
import 'package:test/test.dart';

void main() {
  test('loads the stable ordered Shop fixture', () async {
    final source = _source(
      FixtureApiTransport(
        handlers: <FixtureRequestHandler>[CatalogFixtureHandler()],
      ),
    );

    final dashboard = await source.loadShop();

    expect(dashboard.promotions.single.id, 'promotion-big-sale');
    expect(dashboard.categories.map((item) => item.name), <String>[
      'Clothing',
      'Shoes',
      'Bags',
      'Lingerie',
      'Watch',
      'Hoodies',
    ]);
    expect(
      dashboard.categories.every(
        (category) => category.previewImageAssetKeys.length == 4,
      ),
      isTrue,
    );
    expect(
      dashboard.topProducts.first.title,
      'Lorem ipsum dolor sit amet consectetur.',
    );
    expect(dashboard.newItems.map((item) => item.displayPrice), <String?>[
      r'$26,00',
      r'$32,00',
      r'$17,00',
    ]);
    expect(dashboard.newItems[1].price?.minorUnits, 3200);
    expect(dashboard.flashSale.displayCountdown, '00:36:58');
    expect(dashboard.recommendations, hasLength(8));
    expect(dashboard.mostPopular.map((item) => item.tag), <String?>[
      'New',
      'Sale',
      'Hot',
      'Hot',
    ]);
  });

  test(
    'keeps purchasable Shop summaries aligned with Product Detail',
    () async {
      final source = _source(
        FixtureApiTransport(
          handlers: <FixtureRequestHandler>[CatalogFixtureHandler()],
        ),
      );
      final dashboard = await source.loadShop();

      for (final summary in <ProductSummary>[
        dashboard.newItems.first,
        dashboard.flashSale.products.first,
        dashboard.mostPopular.first,
        dashboard.recommendations.first,
      ]) {
        final detail = await source.loadProductDetail(summary.id);
        expect(detail.product.id, summary.id);
        expect(detail.product.title, summary.title);
        expect(detail.product.imageAssetKey, summary.imageAssetKey);
        expect(detail.product.price, summary.price);
      }
    },
  );

  test('uses only local asset keys', () async {
    final dashboard = await _source(
      FixtureApiTransport(
        handlers: <FixtureRequestHandler>[CatalogFixtureHandler()],
      ),
    ).loadShop();
    final keys = <String>{
      ...dashboard.promotions.map((item) => item.imageAssetKey),
      ...dashboard.categories.expand((item) => item.previewImageAssetKeys),
      ...dashboard.topProducts.map((item) => item.imageAssetKey),
      ...dashboard.newItems.map((item) => item.imageAssetKey),
      ...dashboard.flashSale.products.map((item) => item.imageAssetKey),
      ...dashboard.mostPopular.map((item) => item.imageAssetKey),
      ...dashboard.recommendations.map((item) => item.imageAssetKey),
    };

    expect(keys, isNotEmpty);
    expect(keys.any((key) => Uri.parse(key).hasScheme), isFalse);
    expect(keys.any((key) => key.contains('localhost')), isFalse);
  });

  test('maps empty groups without inventing content', () async {
    final dashboard = await _source(
      const _PayloadTransport(<String, Object?>{
        'promotions': <Object?>[],
        'categories': <Object?>[],
        'topProducts': <Object?>[],
        'newItems': <Object?>[],
        'flashSale': <String, Object?>{
          'hours': 0,
          'minutes': 0,
          'seconds': 0,
          'products': <Object?>[],
        },
        'mostPopular': <Object?>[],
        'recommendations': <Object?>[],
      }),
    ).loadShop();

    expect(dashboard.promotions, isEmpty);
    expect(dashboard.categories, isEmpty);
    expect(dashboard.recommendations, isEmpty);
  });

  test('normalizes malformed prices to invalidResponse', () async {
    final payload = _minimalPayload();
    payload['newItems'] = <Object?>[
      <String, Object?>{
        'id': 'product-1',
        'title': 'Product',
        'imageAssetKey': 'assets/product.png',
        'priceMinorUnits': '17',
        'currency': 'USD',
      },
    ];

    await expectLater(
      _source(_PayloadTransport(payload)).loadShop(),
      throwsA(const CatalogFailure(CatalogFailureCode.invalidResponse)),
    );
  });

  test('uses the stable Catalog request key', () async {
    final transport = _KeyRecordingTransport();
    await _source(transport).loadShop();

    expect(transport.key, 'catalog.shop.load');
  });

  test('browses deterministic category results and applies filters', () async {
    final source = _source(
      FixtureApiTransport(
        handlers: <FixtureRequestHandler>[CatalogFixtureHandler()],
      ),
    );
    final initial = await source.browse(CatalogQuery.initial());

    expect(initial.selectedCategory?.name, 'Clothing');
    expect(initial.categories, hasLength(6));
    expect(initial.selectedCategory?.subcategories, hasLength(10));
    expect(initial.products.length, greaterThan(10));
    expect(
      initial.products.every(
        (product) => product.imageAssetKey.startsWith('assets/'),
      ),
      isTrue,
    );

    final dresses = await source.browse(
      CatalogQuery(
        filter: CatalogFilter(
          audience: CatalogAudience.female,
          categoryId: 'category-clothing',
          subcategoryId: 'subcategory-dresses',
        ),
        sortOrder: CatalogSortOrder.priceHighToLow,
      ),
    );
    expect(dresses.products, isNotEmpty);
    expect(
      dresses.products.map((product) => product.price!.minorUnits),
      orderedEquals(
        dresses.products.map((product) => product.price!.minorUnits).toList()
          ..sort((left, right) => right.compareTo(left)),
      ),
    );
  });

  test('maps malformed browse response to invalidResponse', () async {
    final source = _source(
      const _PayloadTransport(<String, Object?>{
        'categories': <Object?>[],
        'products': <Object?>[
          <String, Object?>{'id': 'missing-fields'},
        ],
      }),
    );

    await expectLater(
      source.browse(CatalogQuery.initial()),
      throwsA(const CatalogFailure(CatalogFailureCode.invalidResponse)),
    );
  });

  test('sends a transport-neutral browse query payload', () async {
    final transport = _BrowseRecordingTransport();
    final query = CatalogQuery(
      filter: CatalogFilter(
        audience: CatalogAudience.male,
        categoryId: 'category-shoes',
      ),
      sortOrder: CatalogSortOrder.priceLowToHigh,
    );

    await _source(transport).browse(query);

    expect(transport.key, CatalogFixtureHandler.browseKey);
    expect(transport.payload, <String, Object?>{
      'audience': 'male',
      'categoryId': 'category-shoes',
      'sortOrder': 'priceLowToHigh',
    });
  });
}

CatalogLocalDataSource _source(ApiTransport transport) =>
    CatalogLocalDataSource(apiClient: ApiClient(transport: transport));

Map<String, Object?> _minimalPayload() => <String, Object?>{
  'promotions': <Object?>[],
  'categories': <Object?>[],
  'topProducts': <Object?>[],
  'newItems': <Object?>[],
  'flashSale': <String, Object?>{
    'hours': 0,
    'minutes': 0,
    'seconds': 0,
    'products': <Object?>[],
  },
  'mostPopular': <Object?>[],
  'recommendations': <Object?>[],
};

final class _PayloadTransport implements ApiTransport {
  const _PayloadTransport(this.payload);

  final Object? payload;

  @override
  Future<ApiResponse<Object?>> send(ApiRequest request) async =>
      ApiResponse<Object?>.success(payload);
}

final class _KeyRecordingTransport implements ApiTransport {
  String? key;

  @override
  Future<ApiResponse<Object?>> send(ApiRequest request) async {
    key = request.key;
    return ApiResponse<Object?>.success(_minimalPayload());
  }
}

final class _BrowseRecordingTransport implements ApiTransport {
  String? key;
  Object? payload;

  @override
  Future<ApiResponse<Object?>> send(ApiRequest request) async {
    key = request.key;
    payload = request.payload;
    return const ApiResponse<Object?>.success(<String, Object?>{
      'categories': <Object?>[],
      'products': <Object?>[],
    });
  }
}
