import 'dart:typed_data';

import 'package:app_data/search.dart';
import 'package:test/test.dart';

void main() {
  test('normalizes text and combines it with the typed Catalog filter', () {
    final query = SearchQuery(
      text: '  Floral   DRESS ',
      filter: CatalogFilter(
        audience: CatalogAudience.female,
        categoryId: 'category-clothing',
      ),
    );

    expect(query.text, 'Floral DRESS');
    expect(query.normalizedText, 'floral dress');
    expect(
      query,
      SearchQuery(
        text: 'floral dress',
        filter: CatalogFilter(
          audience: CatalogAudience.female,
          categoryId: 'category-clothing',
        ),
      ),
    );
  });

  test('rejects an empty text query', () {
    expect(
      () => SearchQuery(
        text: '  ',
        filter: CatalogFilter(
          audience: CatalogAudience.all,
          categoryId: 'category-clothing',
        ),
      ),
      throwsArgumentError,
    );
  });

  test('image input is defensive and diagnostics stay redacted', () {
    final source = Uint8List.fromList(<int>[1, 2, 3]);
    final input = SearchImageInput(source);
    source[0] = 9;
    final firstRead = input.bytes;
    firstRead[1] = 9;

    expect(input.bytes, <int>[1, 2, 3]);
    expect(input.byteLength, 3);
    expect(input.toString(), 'SearchImageInput(<redacted>)');
    expect(input.toString(), isNot(contains('[1, 2, 3]')));
  });
}
