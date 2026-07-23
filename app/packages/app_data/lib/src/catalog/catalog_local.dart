import 'package:app_core/app_core.dart';

import 'catalog_failure.dart';
import 'catalog_fixture.dart';
import 'catalog_models.dart';

part 'catalog_mapper.dart';

/// 通过 [ApiClient] 加载确定性的 Shop Catalog Fixture。
final class CatalogLocalDataSource {
  const CatalogLocalDataSource({required ApiClient apiClient})
    : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<ShopDashboard> loadShop() async {
    final response = await _apiClient.send<Object?>(
      const ApiRequest(key: CatalogFixtureHandler.loadShopKey),
    );
    return switch (response) {
      ApiSuccess<Object?>(:final payload) =>
        _CatalogFixtureMapper.shopDashboard(payload),
      ApiError<Object?>(:final failure) => _throwMappedFailure(failure),
    };
  }

  Future<CatalogBrowseResult> browse(CatalogQuery query) async {
    final response = await _apiClient.send<Object?>(
      ApiRequest(
        key: CatalogFixtureHandler.browseKey,
        payload: <String, Object?>{
          'audience': query.filter.audience.name,
          'categoryId': query.filter.categoryId,
          if (query.filter.subcategoryId case final subcategoryId?)
            'subcategoryId': subcategoryId,
          'sortOrder': query.sortOrder.name,
        },
      ),
    );
    return switch (response) {
      ApiSuccess<Object?>(:final payload) => _CatalogFixtureMapper.browse(
        payload,
        query,
      ),
      ApiError<Object?>(:final failure) => _throwMappedFailure(failure),
    };
  }

  Future<ProductDetail> loadProductDetail(String productId) async {
    final response = await _apiClient.send<Object?>(
      ApiRequest(
        key: CatalogFixtureHandler.productDetailKey,
        payload: <String, Object?>{'productId': productId},
      ),
    );
    return switch (response) {
      ApiSuccess<Object?>(:final payload) =>
        _CatalogFixtureMapper.productDetail(payload),
      ApiError<Object?>(:final failure) => _throwMappedFailure(failure),
    };
  }

  Never _throwMappedFailure(ApiFailure failure) {
    final mappedFailure = CatalogFailure(switch (failure.kind) {
      ApiFailureKind.unknownRequest => CatalogFailureCode.unknownRequest,
      ApiFailureKind.transport => CatalogFailureCode.transportUnavailable,
      ApiFailureKind.invalidResponse => CatalogFailureCode.invalidResponse,
      ApiFailureKind.rejected => switch (failure.code) {
        'catalog.shop_unavailable' => CatalogFailureCode.unavailable,
        'catalog.product_not_found' => CatalogFailureCode.notFound,
        _ => CatalogFailureCode.invalidResponse,
      },
    });
    final stackTrace = failure.stackTrace;
    if (stackTrace != null) {
      Error.throwWithStackTrace(mappedFailure, stackTrace);
    }
    throw mappedFailure;
  }
}
