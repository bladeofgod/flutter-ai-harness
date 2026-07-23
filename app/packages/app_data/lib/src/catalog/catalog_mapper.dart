part of 'catalog_local.dart';

abstract final class _CatalogFixtureMapper {
  static ShopDashboard shopDashboard(Object? payload) => _decode(() {
    final values = _map(payload);
    return ShopDashboard(
      promotions: _list(values, 'promotions', _promotion),
      categories: _list(values, 'categories', _category),
      topProducts: _list(values, 'topProducts', _product),
      newItems: _list(values, 'newItems', _product),
      flashSale: _flashSale(values['flashSale']),
      mostPopular: _list(values, 'mostPopular', _product),
      recommendations: _list(values, 'recommendations', _product),
    );
  });

  static CatalogBrowseResult browse(Object? payload, CatalogQuery query) =>
      _decode(() {
        final values = _map(payload);
        return CatalogBrowseResult(
          query: query,
          categories: _list(values, 'categories', _filterCategory),
          products: _list(values, 'products', _product),
        );
      });

  static ProductDetail productDetail(Object? payload) => _decode(() {
    final values = _map(payload);
    return ProductDetail(
      product: _product(values['product']),
      gallery: _list(values, 'gallery', _image),
      description: _string(values, 'description'),
      optionGroups: _list(values, 'optionGroups', _optionGroup),
      stockCount: _integer(values, 'stockCount'),
      rating: _rating(values['rating']),
      reviews: _list(values, 'reviews', _review),
      originalPrice: _optionalOriginalPrice(values),
    );
  });

  static T _decode<T>(T Function() decode) {
    try {
      return decode();
    } on CatalogFailure {
      rethrow;
    } on FormatException catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const CatalogFailure(CatalogFailureCode.invalidResponse),
        stackTrace,
      );
    } on ArgumentError catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const CatalogFailure(CatalogFailureCode.invalidResponse),
        stackTrace,
      );
    }
  }

  static ShopPromotion _promotion(Object? payload) {
    final values = _map(payload);
    return ShopPromotion(
      id: _string(values, 'id'),
      title: _string(values, 'title'),
      subtitle: _string(values, 'subtitle'),
      badge: _string(values, 'badge'),
      imageAssetKey: _string(values, 'imageAssetKey'),
    );
  }

  static ProductSummary _product(Object? payload) {
    final values = _map(payload);
    return ProductSummary(
      id: _string(values, 'id'),
      title: _string(values, 'title'),
      imageAssetKey: _string(values, 'imageAssetKey'),
      price: _optionalMoney(values),
      tag: _optionalString(values, 'tag'),
      popularityCount: _optionalInteger(values, 'popularityCount'),
    );
  }

  static ProductImage _image(Object? payload) {
    final values = _map(payload);
    return ProductImage(
      id: _string(values, 'id'),
      imageAssetKey: _string(values, 'imageAssetKey'),
    );
  }

  static ProductOptionGroup _optionGroup(Object? payload) {
    final values = _map(payload);
    return ProductOptionGroup(
      id: _string(values, 'id'),
      label: _string(values, 'label'),
      required: values['required'] == null
          ? true
          : values['required'] is bool
          ? values['required']! as bool
          : throw const CatalogFailure(CatalogFailureCode.invalidResponse),
      options: _list(values, 'options', _option),
    );
  }

  static ProductOption _option(Object? payload) {
    final values = _map(payload);
    return ProductOption(
      id: _string(values, 'id'),
      label: _string(values, 'label'),
    );
  }

  static ProductRatingSummary _rating(Object? payload) {
    final values = _map(payload);
    final distribution = values['distribution'];
    if (distribution is! Map<String, Object?>) {
      throw const CatalogFailure(CatalogFailureCode.invalidResponse);
    }
    final mappedDistribution = <int, int>{};
    for (final entry in distribution.entries) {
      final rating = int.tryParse(entry.key);
      if (rating == null || entry.value is! int) {
        throw const CatalogFailure(CatalogFailureCode.invalidResponse);
      }
      mappedDistribution[rating] = entry.value! as int;
    }
    return ProductRatingSummary(
      averageRatingHundredths: _integer(values, 'averageRatingHundredths'),
      reviewCount: _integer(values, 'reviewCount'),
      distribution: mappedDistribution,
    );
  }

  static ProductReview _review(Object? payload) {
    final values = _map(payload);
    return ProductReview(
      id: _string(values, 'id'),
      author: _string(values, 'author'),
      comment: _string(values, 'comment'),
      rating: _integer(values, 'rating'),
      publishedLabel: _string(values, 'publishedLabel'),
      avatarAssetKey: _optionalString(values, 'avatarAssetKey'),
    );
  }

  static Money? _optionalOriginalPrice(Map<String, Object?> values) {
    final minorUnits = values['originalPriceMinorUnits'];
    final currency = values['originalPriceCurrency'];
    if (minorUnits == null && currency == null) {
      return null;
    }
    if (minorUnits is! int || currency is! String) {
      throw const CatalogFailure(CatalogFailureCode.invalidResponse);
    }
    return Money(currency: Currency.fromCode(currency), minorUnits: minorUnits);
  }

  static CatalogFilterCategory _filterCategory(Object? payload) {
    final values = _map(payload);
    return CatalogFilterCategory(
      id: _string(values, 'id'),
      name: _string(values, 'name'),
      imageAssetKey: _string(values, 'imageAssetKey'),
      subcategories: _list(values, 'subcategories', _subcategory),
    );
  }

  static CatalogSubcategory _subcategory(Object? payload) {
    final values = _map(payload);
    return CatalogSubcategory(
      id: _string(values, 'id'),
      name: _string(values, 'name'),
      imageAssetKey: _string(values, 'imageAssetKey'),
    );
  }

  static Money? _optionalMoney(Map<String, Object?> values) {
    final minorUnits = values['priceMinorUnits'];
    final currency = values['currency'];
    if (minorUnits == null && currency == null) {
      return null;
    }
    if (minorUnits is! int || currency is! String) {
      throw const CatalogFailure(CatalogFailureCode.invalidResponse);
    }
    return Money(currency: Currency.fromCode(currency), minorUnits: minorUnits);
  }

  static CategorySummary _category(Object? payload) {
    final values = _map(payload);
    return CategorySummary(
      id: _string(values, 'id'),
      name: _string(values, 'name'),
      previewImageAssetKeys: _list(
        values,
        'previewImageAssetKeys',
        (value) => value is String
            ? value
            : throw const CatalogFailure(CatalogFailureCode.invalidResponse),
      ),
      itemCount: _integer(values, 'itemCount'),
    );
  }

  static FlashSale _flashSale(Object? payload) {
    final values = _map(payload);
    return FlashSale(
      hours: _integer(values, 'hours'),
      minutes: _integer(values, 'minutes'),
      seconds: _integer(values, 'seconds'),
      products: _list(values, 'products', _product),
    );
  }

  static List<T> _list<T>(
    Map<String, Object?> values,
    String key,
    T Function(Object?) mapper,
  ) {
    final value = values[key];
    if (value is! List<Object?>) {
      throw const CatalogFailure(CatalogFailureCode.invalidResponse);
    }
    return List<T>.unmodifiable(value.map(mapper));
  }

  static Map<String, Object?> _map(Object? payload) {
    if (payload is! Map<String, Object?>) {
      throw const CatalogFailure(CatalogFailureCode.invalidResponse);
    }
    return payload;
  }

  static String _string(Map<String, Object?> values, String key) {
    final value = values[key];
    if (value is! String || value.isEmpty) {
      throw const CatalogFailure(CatalogFailureCode.invalidResponse);
    }
    return value;
  }

  static String? _optionalString(Map<String, Object?> values, String key) {
    final value = values[key];
    if (value == null) {
      return null;
    }
    return _string(values, key);
  }

  static int _integer(Map<String, Object?> values, String key) {
    final value = values[key];
    if (value is! int) {
      throw const CatalogFailure(CatalogFailureCode.invalidResponse);
    }
    return value;
  }

  static int? _optionalInteger(Map<String, Object?> values, String key) {
    final value = values[key];
    if (value == null) {
      return null;
    }
    return _integer(values, key);
  }
}
