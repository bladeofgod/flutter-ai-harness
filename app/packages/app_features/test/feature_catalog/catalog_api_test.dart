import 'package:app_core/app_core.dart';
import 'package:app_data/app_data.dart';
import 'package:app_features/feature_catalog/api/local_catalog_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Local Catalog API exposes Domain data from its data source', () async {
    final api = LocalCatalogApi(
      dataSource: CatalogLocalDataSource(
        apiClient: ApiClient(
          transport: FixtureApiTransport(
            handlers: <FixtureRequestHandler>[CatalogFixtureHandler()],
          ),
        ),
      ),
    );

    final dashboard = await api.loadShop();

    expect(dashboard.promotions.single.title, 'Big Sale');
    expect(dashboard.categories, hasLength(6));
  });
}
