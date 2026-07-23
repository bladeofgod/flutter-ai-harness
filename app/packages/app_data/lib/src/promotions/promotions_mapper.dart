part of 'promotions_local.dart';

abstract final class _PromotionsFixtureMapper {
  static PromotionsOverview overview(Object? payload) => _decode(() {
    final values = _map(payload, 'overview');
    return PromotionsOverview(
      flashSale: _promotion(values['flashSale']),
      livePreviews: _list(values, 'livePreviews', _live),
      stories: _list(values, 'stories', story),
    );
  });

  static Promotion _promotion(Object? payload) {
    final values = _map(payload, 'flashSale');
    return Promotion(
      id: _string(values, 'id'),
      title: _string(values, 'title'),
      subtitle: _string(values, 'subtitle'),
      imageAssetKey: _string(values, 'imageAssetKey'),
      flashSale: FlashSale(
        hours: _int(values, 'hours'),
        minutes: _int(values, 'minutes'),
        seconds: _int(values, 'seconds'),
        products: _list(values, 'products', _product),
      ),
    );
  }

  static LivePreview _live(Object? payload) {
    final values = _map(payload, 'livePreview');
    return LivePreview(
      id: _string(values, 'id'),
      title: _string(values, 'title'),
      subtitle: _string(values, 'subtitle'),
      coverAssetKey: _string(values, 'coverAssetKey'),
      product: _product(values['product']),
    );
  }

  static StorySequence story(Object? payload) => _decode(() {
    final values = _map(payload, 'story');
    return StorySequence(
      id: _string(values, 'id'),
      title: _string(values, 'title'),
      coverAssetKey: _string(values, 'coverAssetKey'),
      items: _list(values, 'items', _storyItem),
    );
  });

  static T _decode<T>(T Function() decode) {
    try {
      return decode();
    } on PromotionsFailure {
      rethrow;
    } on FormatException catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const PromotionsFailure(PromotionsFailureCode.invalidResponse),
        stackTrace,
      );
    } on ArgumentError catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const PromotionsFailure(PromotionsFailureCode.invalidResponse),
        stackTrace,
      );
    }
  }

  static StoryItem _storyItem(Object? payload) {
    final values = _map(payload, 'storyItem');
    return switch (_string(values, 'type')) {
      'product' => ProductStoryItem(
        id: _string(values, 'id'),
        title: _string(values, 'title'),
        imageAssetKey: _string(values, 'imageAssetKey'),
        product: _product(values['product']),
      ),
      'banner' => BannerStoryItem(
        id: _string(values, 'id'),
        title: _string(values, 'title'),
        imageAssetKey: _string(values, 'imageAssetKey'),
        body: _string(values, 'body'),
      ),
      final type => throw FormatException('Unsupported Story item type: $type'),
    };
  }

  static ProductSummary _product(Object? payload) {
    final values = _map(payload, 'product');
    return ProductSummary(
      id: _string(values, 'id'),
      title: _string(values, 'title'),
      imageAssetKey: _string(values, 'imageAssetKey'),
      price: Money(
        currency: Currency.fromCode(_string(values, 'currency')),
        minorUnits: _int(values, 'priceMinorUnits'),
      ),
    );
  }

  static Map<String, Object?> _map(Object? value, String name) {
    if (value is! Map<Object?, Object?>) {
      throw FormatException('$name must be a map.');
    }
    return value.map((key, item) {
      if (key is! String) {
        throw FormatException('$name contains a non-string key.');
      }
      return MapEntry(key, item);
    });
  }

  static List<T> _list<T>(
    Map<String, Object?> values,
    String key,
    T Function(Object?) mapper,
  ) {
    final value = values[key];
    if (value is! List<Object?>) {
      throw FormatException('$key must be a list.');
    }
    return value.map(mapper).toList(growable: false);
  }

  static String _string(Map<String, Object?> values, String key) {
    final value = values[key];
    if (value is! String) {
      throw FormatException('$key must be a string.');
    }
    return value;
  }

  static int _int(Map<String, Object?> values, String key) {
    final value = values[key];
    if (value is! int) {
      throw FormatException('$key must be an int.');
    }
    return value;
  }
}
