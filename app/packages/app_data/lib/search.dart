/// Search Domain、本地数据源与 Fixture Handler 的公开入口。
library;

export 'src/catalog/catalog_models.dart'
    show CatalogAudience, CatalogFilter, ProductSummary;
export 'src/search/search_failure.dart';
export 'src/search/search_fixture.dart' show SearchFixtureHandler;
export 'src/search/search_local.dart' show SearchLocalDataSource;
export 'src/search/search_models.dart';
