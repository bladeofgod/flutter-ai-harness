import 'package:app_core/app_core.dart';

import '../catalog/catalog_models.dart';
import 'wishlist_failure.dart';
import 'wishlist_fixture.dart';
import 'wishlist_models.dart';

part 'wishlist_mapper.dart';

/// 通过 [ApiClient] 读写进程内 Wishlist Fixture。
final class WishlistLocalDataSource {
  const WishlistLocalDataSource({required ApiClient apiClient})
    : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<WishlistOverview> loadWishlist() async {
    final response = await _apiClient.send<Object?>(
      const ApiRequest(key: WishlistFixtureHandler.loadWishlistKey),
    );
    return _mapOverviewResponse(response);
  }

  Future<WishlistOverview> addWishlistItem({
    required ProductSummary product,
    required String color,
    required String size,
  }) async {
    final response = await _apiClient.send<Object?>(
      ApiRequest(
        key: WishlistFixtureHandler.addWishlistItemKey,
        payload: <String, Object?>{
          'product': <String, Object?>{
            'id': product.id,
            'title': product.title,
            'imageAssetKey': product.imageAssetKey,
            if (product.price case final price?) ...<String, Object?>{
              'priceMinorUnits': price.minorUnits,
              'currency': price.currency.code,
            },
            if (product.tag case final tag?) 'tag': tag,
            if (product.popularityCount case final count?)
              'popularityCount': count,
          },
          'color': color,
          'size': size,
        },
      ),
    );
    return _mapOverviewResponse(response);
  }

  Future<WishlistOverview> removeWishlistItem(String productId) async {
    final response = await _apiClient.send<Object?>(
      ApiRequest(
        key: WishlistFixtureHandler.removeWishlistItemKey,
        payload: <String, Object?>{'productId': productId},
      ),
    );
    return _mapOverviewResponse(response);
  }

  Future<RecentlyViewedSnapshot> loadRecentlyViewed() async {
    final response = await _apiClient.send<Object?>(
      const ApiRequest(key: WishlistFixtureHandler.loadRecentlyViewedKey),
    );
    return switch (response) {
      ApiSuccess<Object?>(:final payload) =>
        _WishlistFixtureMapper.recentlyViewed(payload),
      ApiError<Object?>(:final failure) => _throwMappedFailure(failure),
    };
  }

  WishlistOverview _mapOverviewResponse(ApiResponse<Object?> response) =>
      switch (response) {
        ApiSuccess<Object?>(:final payload) => _WishlistFixtureMapper.overview(
          payload,
        ),
        ApiError<Object?>(:final failure) => _throwMappedFailure(failure),
      };

  Never _throwMappedFailure(ApiFailure failure) {
    final mappedFailure = WishlistFailure(switch (failure.kind) {
      ApiFailureKind.unknownRequest => WishlistFailureCode.unknownRequest,
      ApiFailureKind.transport => WishlistFailureCode.transportUnavailable,
      ApiFailureKind.invalidResponse => WishlistFailureCode.invalidResponse,
      ApiFailureKind.rejected =>
        failure.code == 'wishlist.invalid_request'
            ? WishlistFailureCode.invalidRequest
            : failure.code == 'wishlist.unavailable'
            ? WishlistFailureCode.unavailable
            : WishlistFailureCode.invalidResponse,
    });
    final stackTrace = failure.stackTrace;
    if (stackTrace != null) {
      Error.throwWithStackTrace(mappedFailure, stackTrace);
    }
    throw mappedFailure;
  }
}
