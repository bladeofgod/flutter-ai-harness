import 'package:app_data/app_data.dart';

/// Shop 首页需要的只读 Catalog 边界。
abstract interface class CatalogApi {
  Future<ShopDashboard> loadShop();
}

/// Categories 商品列表使用的窄查询边界。
abstract interface class CatalogBrowseApi {
  Future<CatalogBrowseResult> browse(CatalogQuery query);
}

/// 商品详情页使用的窄只读边界。
abstract interface class ProductApi {
  Future<ProductDetail> loadProductDetail(String productId);
}
