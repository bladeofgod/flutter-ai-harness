import 'package:app_core/app_core.dart';
import 'package:app_data/app_data.dart';
import 'package:app_features/api/catalog_api.dart';
import 'package:app_features/feature_catalog/api/local_catalog_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Local Catalog Browse API exposes typed Category results', () async {
    final CatalogBrowseApi api = LocalCatalogApi(
      dataSource: CatalogLocalDataSource(
        apiClient: ApiClient(
          transport: FixtureApiTransport(
            handlers: <FixtureRequestHandler>[CatalogFixtureHandler()],
          ),
        ),
      ),
    );

    final result = await api.browse(CatalogQuery.initial());

    expect(result.selectedCategory?.name, 'Clothing');
    expect(result.products, isNotEmpty);
  });
}
