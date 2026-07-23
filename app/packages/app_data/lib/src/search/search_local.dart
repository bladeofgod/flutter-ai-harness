import 'package:app_core/app_core.dart';

import '../catalog/catalog_models.dart';
import 'search_failure.dart';
import 'search_fixture.dart';
import 'search_models.dart';

/// 通过 [ApiClient] 访问确定性的 Search Fixture。
final class SearchLocalDataSource {
  const SearchLocalDataSource({required ApiClient apiClient})
    : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<SearchResult> searchText(SearchQuery query) async {
    final response = await _apiClient.send<Object?>(
      ApiRequest(
        key: SearchFixtureHandler.textSearchKey,
        payload: <String, Object?>{
          'text': query.normalizedText,
          'audience': query.filter.audience.name,
          'categoryId': query.filter.categoryId,
          if (query.filter.subcategoryId case final subcategoryId?)
            'subcategoryId': subcategoryId,
        },
      ),
    );
    return switch (response) {
      ApiSuccess<Object?>(:final payload) => SearchResult(
        query: query,
        products: _SearchFixtureMapper.products(payload),
      ),
      ApiError<Object?>(:final failure) => _throwMappedFailure(failure),
    };
  }

  Future<SearchImageResult> searchImage(SearchImageInput input) async {
    final response = await _apiClient.send<Object?>(
      ApiRequest(
        key: SearchFixtureHandler.imageSearchKey,
        payload: <String, Object?>{
          'fixtureInput': 'selected_gallery_image',
          'byteLength': input.byteLength,
        },
      ),
    );
    return switch (response) {
      ApiSuccess<Object?>(:final payload) => _SearchFixtureMapper.imageResult(
        payload,
      ),
      ApiError<Object?>(:final failure) => _throwMappedFailure(failure),
    };
  }

  Never _throwMappedFailure(ApiFailure failure) {
    final mapped = SearchFailure(switch (failure.kind) {
      ApiFailureKind.unknownRequest => SearchFailureCode.unknownRequest,
      ApiFailureKind.transport => SearchFailureCode.transportUnavailable,
      ApiFailureKind.invalidResponse => SearchFailureCode.invalidResponse,
      ApiFailureKind.rejected => switch (failure.code) {
        'search.invalid_query' => SearchFailureCode.invalidQuery,
        'search.unavailable' => SearchFailureCode.unavailable,
        _ => SearchFailureCode.invalidResponse,
      },
    });
    final stackTrace = failure.stackTrace;
    if (stackTrace != null) {
      Error.throwWithStackTrace(mapped, stackTrace);
    }
    throw mapped;
  }
}

abstract final class _SearchFixtureMapper {
  static List<ProductSummary> products(Object? payload) => _decode(() {
    final values = _map(payload);
    final products = values['products'];
    if (products is! List<Object?>) {
      throw const SearchFailure(SearchFailureCode.invalidResponse);
    }
    return List<ProductSummary>.unmodifiable(products.map(_product));
  });

  static SearchImageResult imageResult(Object? payload) => _decode(() {
    final values = _map(payload);
    final label = values['recognizedLabel'];
    if (label is! String || label.isEmpty) {
      throw const SearchFailure(SearchFailureCode.invalidResponse);
    }
    return SearchImageResult(
      recognizedLabel: label,
      products: products(payload),
    );
  });

  static ProductSummary _product(Object? payload) {
    final values = _map(payload);
    final id = values['id'];
    final title = values['title'];
    final imageAssetKey = values['imageAssetKey'];
    final priceMinorUnits = values['priceMinorUnits'];
    final currency = values['currency'];
    if (id is! String ||
        title is! String ||
        imageAssetKey is! String ||
        priceMinorUnits is! int ||
        currency is! String) {
      throw const SearchFailure(SearchFailureCode.invalidResponse);
    }
    return ProductSummary(
      id: id,
      title: title,
      imageAssetKey: imageAssetKey,
      price: Money(
        currency: Currency.fromCode(currency),
        minorUnits: priceMinorUnits,
      ),
    );
  }

  static Map<String, Object?> _map(Object? payload) {
    if (payload is! Map<String, Object?>) {
      throw const SearchFailure(SearchFailureCode.invalidResponse);
    }
    return payload;
  }

  static T _decode<T>(T Function() decode) {
    try {
      return decode();
    } on SearchFailure {
      rethrow;
    } on FormatException catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const SearchFailure(SearchFailureCode.invalidResponse),
        stackTrace,
      );
    } on ArgumentError catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const SearchFailure(SearchFailureCode.invalidResponse),
        stackTrace,
      );
    }
  }
}
