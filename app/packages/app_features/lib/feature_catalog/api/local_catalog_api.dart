import 'package:app_data/app_data.dart';

import '../../api/catalog_api.dart';

/// 通过本地数据源实现 Catalog 能力。
final class LocalCatalogApi
    implements CatalogApi, CatalogBrowseApi, ProductApi {
  const LocalCatalogApi({required CatalogLocalDataSource dataSource})
    : _dataSource = dataSource;

  final CatalogLocalDataSource _dataSource;

  @override
  Future<ShopDashboard> loadShop() => _dataSource.loadShop();

  @override
  Future<CatalogBrowseResult> browse(CatalogQuery query) =>
      _dataSource.browse(query);

  @override
  Future<ProductDetail> loadProductDetail(String productId) =>
      _dataSource.loadProductDetail(productId);
}
