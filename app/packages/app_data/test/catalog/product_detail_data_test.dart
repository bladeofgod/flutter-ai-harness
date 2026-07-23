import 'package:app_core/app_core.dart';
import 'package:app_data/app_data.dart';
import 'package:test/test.dart';

void main() {
  test('maps normal and Sale Product detail fixtures', () async {
    final source = _source(
      FixtureApiTransport(
        handlers: <FixtureRequestHandler>[CatalogFixtureHandler()],
      ),
    );

    final normal = await source.loadProductDetail('product-1');
    final sale = await source.loadProductDetail('product-2');

    expect(normal.product.id, 'product-1');
    expect(normal.gallery, hasLength(4));
    expect(normal.optionGroups.map((group) => group.id), <String>[
      'color',
      'size',
    ]);
    expect(normal.rating.displayRating, '4.7');
    expect(normal.reviews, hasLength(2));
    expect(normal.originalPrice, isNull);
    expect(sale.isOnSale, isTrue);
    expect(sale.displayOriginalPrice, r'$29,00');
  });

  test('returns a stable not-found failure for an unknown product', () async {
    final source = _source(
      FixtureApiTransport(
        handlers: <FixtureRequestHandler>[CatalogFixtureHandler()],
      ),
    );

    await expectLater(
      source.loadProductDetail('unknown-product'),
      throwsA(const CatalogFailure(CatalogFailureCode.notFound)),
    );
    await expectLater(
      source.loadProductDetail('product-999999'),
      throwsA(const CatalogFailure(CatalogFailureCode.notFound)),
    );
  });

  test(
    'normalizes supported feature source ids to the canonical product id',
    () async {
      final source = _source(
        FixtureApiTransport(
          handlers: <FixtureRequestHandler>[CatalogFixtureHandler()],
        ),
      );

      expect(
        (await source.loadProductDetail('browse-product-20')).product.id,
        'product-20',
      );
      expect(
        (await source.loadProductDetail('recommended-1')).product.id,
        'product-1',
      );
    },
  );

  test('maps malformed Product detail payload to invalidResponse', () async {
    final source = _source(
      const _PayloadTransport(<String, Object?>{
        'product': <String, Object?>{
          'id': 'product-1',
          'title': 'Product',
          'imageAssetKey': 'assets/product.png',
          'priceMinorUnits': 1700,
          'currency': 'USD',
        },
        'gallery': <Object?>[],
        'description': 'Description',
        'optionGroups': <Object?>[],
        'stockCount': 2,
        'rating': <String, Object?>{
          'averageRatingHundredths': 400,
          'reviewCount': 0,
          'distribution': <String, Object?>{},
        },
        'reviews': <Object?>[],
      }),
    );

    await expectLater(
      source.loadProductDetail('product-1'),
      throwsA(const CatalogFailure(CatalogFailureCode.invalidResponse)),
    );
  });

  test('sends a transport-neutral Product detail request', () async {
    final transport = _KeyRecordingTransport();
    await _source(transport).loadProductDetail('product-7');

    expect(transport.key, CatalogFixtureHandler.productDetailKey);
    expect(transport.payload, <String, Object?>{'productId': 'product-7'});
  });
}

CatalogLocalDataSource _source(ApiTransport transport) =>
    CatalogLocalDataSource(apiClient: ApiClient(transport: transport));

final class _PayloadTransport implements ApiTransport {
  const _PayloadTransport(this.payload);

  final Object? payload;

  @override
  Future<ApiResponse<Object?>> send(ApiRequest request) async =>
      ApiResponse<Object?>.success(payload);
}

final class _KeyRecordingTransport implements ApiTransport {
  String? key;
  Object? payload;

  @override
  Future<ApiResponse<Object?>> send(ApiRequest request) async {
    key = request.key;
    payload = request.payload;
    return const ApiResponse<Object?>.success(<String, Object?>{
      'product': <String, Object?>{
        'id': 'product-7',
        'title': 'Product',
        'imageAssetKey': 'assets/product.png',
        'priceMinorUnits': 1700,
        'currency': 'USD',
      },
      'gallery': <Object?>[
        <String, Object?>{
          'id': 'gallery-1',
          'imageAssetKey': 'assets/product.png',
        },
      ],
      'description': 'Description',
      'optionGroups': <Object?>[
        <String, Object?>{
          'id': 'color',
          'label': 'Color',
          'options': <Object?>[
            <String, Object?>{'id': 'pink', 'label': 'Pink'},
          ],
        },
      ],
      'stockCount': 1,
      'rating': <String, Object?>{
        'averageRatingHundredths': 400,
        'reviewCount': 0,
        'distribution': <String, Object?>{},
      },
      'reviews': <Object?>[],
    });
  }
}
