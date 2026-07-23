part of 'wishlist_local.dart';

abstract final class _WishlistFixtureMapper {
  static WishlistOverview overview(Object? payload) => _decode(() {
    final values = _map(payload);
    return WishlistOverview(
      items: _list(values, 'items', _wishlistItem),
      recentlyViewed: _list(values, 'recentlyViewed', _product),
      recommendations: _list(values, 'recommendations', _product),
    );
  });

  static RecentlyViewedSnapshot recentlyViewed(Object? payload) => _decode(() {
    final values = _map(payload);
    return RecentlyViewedSnapshot(
      referenceDate: _date(values['referenceDate']),
      items: _list(values, 'items', _recentlyViewedItem),
    );
  });

  static T _decode<T>(T Function() decode) {
    try {
      return decode();
    } on WishlistFailure {
      rethrow;
    } on FormatException catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const WishlistFailure(WishlistFailureCode.invalidResponse),
        stackTrace,
      );
    } on ArgumentError catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const WishlistFailure(WishlistFailureCode.invalidResponse),
        stackTrace,
      );
    }
  }

  static WishlistItem _wishlistItem(Object? payload) {
    final values = _map(payload);
    return WishlistItem(
      product: _product(values['product']),
      color: _string(values, 'color'),
      size: _string(values, 'size'),
      originalPrice: _optionalMoney(
        values,
        unitsKey: 'originalPriceMinorUnits',
        currencyKey: 'originalPriceCurrency',
      ),
    );
  }

  static RecentlyViewedItem _recentlyViewedItem(Object? payload) {
    final values = _map(payload);
    return RecentlyViewedItem(
      id: _string(values, 'id'),
      product: _product(values['product']),
      viewedOn: _date(values['viewedOn']),
    );
  }

  static ProductSummary _product(Object? payload) {
    final values = _map(payload);
    return ProductSummary(
      id: _string(values, 'id'),
      title: _string(values, 'title'),
      imageAssetKey: _string(values, 'imageAssetKey'),
      price: _optionalMoney(
        values,
        unitsKey: 'priceMinorUnits',
        currencyKey: 'currency',
      ),
      tag: _optionalString(values, 'tag'),
      popularityCount: _optionalInteger(values, 'popularityCount'),
    );
  }

  static Money? _optionalMoney(
    Map<String, Object?> values, {
    required String unitsKey,
    required String currencyKey,
  }) {
    final minorUnits = values[unitsKey];
    final currency = values[currencyKey];
    if (minorUnits == null && currency == null) {
      return null;
    }
    if (minorUnits is! int || currency is! String) {
      throw const WishlistFailure(WishlistFailureCode.invalidResponse);
    }
    return Money(currency: Currency.fromCode(currency), minorUnits: minorUnits);
  }

  static WishlistDate _date(Object? payload) {
    final values = _map(payload);
    return WishlistDate(
      year: _integer(values, 'year'),
      month: _integer(values, 'month'),
      day: _integer(values, 'day'),
    );
  }

  static List<T> _list<T>(
    Map<String, Object?> values,
    String key,
    T Function(Object?) mapper,
  ) {
    final value = values[key];
    if (value is! List<Object?>) {
      throw const WishlistFailure(WishlistFailureCode.invalidResponse);
    }
    return List<T>.unmodifiable(value.map(mapper));
  }

  static Map<String, Object?> _map(Object? payload) {
    if (payload is! Map<String, Object?>) {
      throw const WishlistFailure(WishlistFailureCode.invalidResponse);
    }
    return payload;
  }

  static String _string(Map<String, Object?> values, String key) {
    final value = values[key];
    if (value is! String || value.trim().isEmpty) {
      throw const WishlistFailure(WishlistFailureCode.invalidResponse);
    }
    return value;
  }

  static String? _optionalString(Map<String, Object?> values, String key) {
    if (values[key] == null) {
      return null;
    }
    return _string(values, key);
  }

  static int _integer(Map<String, Object?> values, String key) {
    final value = values[key];
    if (value is! int) {
      throw const WishlistFailure(WishlistFailureCode.invalidResponse);
    }
    return value;
  }

  static int? _optionalInteger(Map<String, Object?> values, String key) {
    if (values[key] == null) {
      return null;
    }
    return _integer(values, key);
  }
}
