import 'dart:typed_data';

import 'package:app_core/app_core.dart';
import 'package:app_data/app_data.dart'
    show FixtureApiTransport, FixtureRequestHandler;
import 'package:app_data/search.dart';
import 'package:test/test.dart';

void main() {
  test('matches normalized fixture fields deterministically', () async {
    final source = _fixtureSource();
    final result = await source.searchText(
      SearchQuery(
        text: '  floral   dress ',
        filter: CatalogFilter(
          audience: CatalogAudience.female,
          categoryId: 'category-clothing',
        ),
      ),
    );

    expect(result.query.normalizedText, 'floral dress');
    expect(result.products.map((product) => product.id), <String>['product-1']);
  });

  test(
    'returns an empty result when text or typed filter does not match',
    () async {
      final source = _fixtureSource();
      final result = await source.searchText(
        SearchQuery(
          text: 'dress',
          filter: CatalogFilter(
            audience: CatalogAudience.male,
            categoryId: 'category-clothing',
          ),
        ),
      );

      expect(result.products, isEmpty);
    },
  );

  test('returns one fixed recognized label and stable products', () async {
    final source = _fixtureSource();

    final first = await source.searchImage(
      SearchImageInput(Uint8List.fromList(<int>[1, 2, 3])),
    );
    final second = await source.searchImage(
      SearchImageInput(Uint8List.fromList(<int>[9, 8, 7, 6])),
    );

    expect(first.recognizedLabel, 'Floral summer dress');
    expect(second.recognizedLabel, first.recognizedLabel);
    expect(
      second.products.map((product) => product.id),
      first.products.map((product) => product.id),
    );
  });

  test('image transport payload contains no bytes or file metadata', () async {
    final transport = _RecordingTransport();
    final source = SearchLocalDataSource(
      apiClient: ApiClient(transport: transport),
    );

    await source.searchImage(
      SearchImageInput(Uint8List.fromList(<int>[22, 33, 44])),
    );

    expect(transport.key, SearchFixtureHandler.imageSearchKey);
    expect(transport.payload, <String, Object?>{
      'fixtureInput': 'selected_gallery_image',
      'byteLength': 3,
    });
    expect(transport.payload.toString(), isNot(contains('22')));
    expect(transport.payload.toString(), isNot(contains('path')));
  });

  test('maps malformed fixture output to invalidResponse', () async {
    final source = SearchLocalDataSource(
      apiClient: ApiClient(
        transport: const _StaticTransport(<String, Object?>{
          'products': <Object?>[
            <String, Object?>{'id': 'missing-fields'},
          ],
        }),
      ),
    );

    await expectLater(
      source.searchText(
        SearchQuery(
          text: 'dress',
          filter: CatalogFilter(
            audience: CatalogAudience.all,
            categoryId: 'category-clothing',
          ),
        ),
      ),
      throwsA(
        isA<SearchFailure>().having(
          (failure) => failure.code,
          'code',
          SearchFailureCode.invalidResponse,
        ),
      ),
    );
  });
}

SearchLocalDataSource _fixtureSource() => SearchLocalDataSource(
  apiClient: ApiClient(
    transport: FixtureApiTransport(
      handlers: <FixtureRequestHandler>[SearchFixtureHandler()],
    ),
  ),
);

final class _RecordingTransport implements ApiTransport {
  String? key;
  Object? payload;

  @override
  Future<ApiResponse<Object?>> send(ApiRequest request) async {
    key = request.key;
    payload = request.payload;
    return const ApiResponse<Object?>.success(<String, Object?>{
      'recognizedLabel': 'Floral summer dress',
      'products': <Object?>[],
    });
  }
}

final class _StaticTransport implements ApiTransport {
  const _StaticTransport(this.payload);

  final Object? payload;

  @override
  Future<ApiResponse<Object?>> send(ApiRequest request) async =>
      ApiResponse<Object?>.success(payload);
}
