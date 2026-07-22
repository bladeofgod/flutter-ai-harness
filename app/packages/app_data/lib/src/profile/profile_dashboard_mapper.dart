part of 'profile_dashboard_local.dart';

abstract final class _ProfileDashboardFixtureMapper {
  static ProfileDashboard dashboard(Object? payload) => _decode(() {
    final values = _map(payload);
    return ProfileDashboard(
      announcement: _announcement(values['announcement']),
      recentlyViewed: _list(values, 'recentlyViewed', _recentlyViewed),
      orders: _orders(values['orders']),
      stories: _list(values, 'stories', _story),
      newItems: _list(values, 'newItems', _product),
      mostPopular: _list(values, 'mostPopular', _product),
      categories: _list(values, 'categories', _category),
      flashSale: _flashSale(values['flashSale']),
      topProducts: _list(values, 'topProducts', _product),
      recommendations: _list(values, 'recommendations', _product),
    );
  });

  static T _decode<T>(T Function() decode) {
    try {
      return decode();
    } on ProfileDashboardFailure {
      rethrow;
    } on FormatException catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const ProfileDashboardFailure(
          ProfileDashboardFailureCode.invalidResponse,
        ),
        stackTrace,
      );
    } on ArgumentError catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const ProfileDashboardFailure(
          ProfileDashboardFailureCode.invalidResponse,
        ),
        stackTrace,
      );
    }
  }

  static Announcement? _announcement(Object? payload) {
    if (payload == null) {
      return null;
    }
    final values = _map(payload);
    return Announcement(
      title: _string(values, 'title'),
      message: _string(values, 'message'),
    );
  }

  static RecentlyViewed _recentlyViewed(Object? payload) {
    final values = _map(payload);
    return RecentlyViewed(
      id: _string(values, 'id'),
      imageAssetKey: _string(values, 'imageAssetKey'),
    );
  }

  static OrderSummary _orders(Object? payload) {
    final values = _map(payload);
    return OrderSummary(
      items: _list(values, 'items', (item) {
        final itemValues = _map(item);
        return OrderStatusSummary(
          status: switch (_string(itemValues, 'status')) {
            'to_pay' => OrderStatus.toPay,
            'to_receive' => OrderStatus.toReceive,
            'to_review' => OrderStatus.toReview,
            _ => throw const ProfileDashboardFailure(
              ProfileDashboardFailureCode.invalidResponse,
            ),
          },
          hasNotification: _boolean(itemValues, 'hasNotification'),
        );
      }),
    );
  }

  static Story _story(Object? payload) {
    final values = _map(payload);
    return Story(
      id: _string(values, 'id'),
      title: _string(values, 'title'),
      imageAssetKey: _string(values, 'imageAssetKey'),
      isLive: _boolean(values, 'isLive'),
    );
  }

  static ProductSummary _product(Object? payload) {
    final values = _map(payload);
    return ProductSummary(
      id: _string(values, 'id'),
      title: _string(values, 'title'),
      imageAssetKey: _string(values, 'imageAssetKey'),
      displayPrice: _optionalString(values, 'displayPrice'),
      tag: _optionalString(values, 'tag'),
      popularityCount: _optionalInteger(values, 'popularityCount'),
    );
  }

  static CategorySummary _category(Object? payload) {
    final values = _map(payload);
    return CategorySummary(
      id: _string(values, 'id'),
      name: _string(values, 'name'),
      imageAssetKey: _string(values, 'imageAssetKey'),
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
      throw const ProfileDashboardFailure(
        ProfileDashboardFailureCode.invalidResponse,
      );
    }
    return List<T>.unmodifiable(value.map(mapper));
  }

  static Map<String, Object?> _map(Object? payload) {
    if (payload is! Map<String, Object?>) {
      throw const ProfileDashboardFailure(
        ProfileDashboardFailureCode.invalidResponse,
      );
    }
    return payload;
  }

  static String _string(Map<String, Object?> values, String key) {
    final value = values[key];
    if (value is! String || value.isEmpty) {
      throw const ProfileDashboardFailure(
        ProfileDashboardFailureCode.invalidResponse,
      );
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
      throw const ProfileDashboardFailure(
        ProfileDashboardFailureCode.invalidResponse,
      );
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

  static bool _boolean(Map<String, Object?> values, String key) {
    final value = values[key];
    if (value is! bool) {
      throw const ProfileDashboardFailure(
        ProfileDashboardFailureCode.invalidResponse,
      );
    }
    return value;
  }
}
