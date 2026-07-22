/// Profile 顶部只读公告。
final class Announcement {
  factory Announcement({required String title, required String message}) =>
      Announcement._(
        title: _requiredText(title, 'title'),
        message: _requiredText(message, 'message'),
      );

  const Announcement._({required this.title, required this.message});

  final String title;
  final String message;
}

/// 最近浏览的本地图片摘要。
final class RecentlyViewed {
  factory RecentlyViewed({required String id, required String imageAssetKey}) =>
      RecentlyViewed._(
        id: _requiredText(id, 'id'),
        imageAssetKey: _localAssetKey(imageAssetKey),
      );

  const RecentlyViewed._({required this.id, required this.imageAssetKey});

  final String id;
  final String imageAssetKey;
}

enum OrderStatus { toPay, toReceive, toReview }

/// 单个订单状态入口当前需要的只读信息。
final class OrderStatusSummary {
  const OrderStatusSummary({
    required this.status,
    this.hasNotification = false,
  });

  final OrderStatus status;
  final bool hasNotification;
}

/// 保留设计中订单状态的固定展示顺序。
final class OrderSummary {
  factory OrderSummary({required List<OrderStatusSummary> items}) =>
      OrderSummary._(List<OrderStatusSummary>.unmodifiable(items));

  const OrderSummary._(this.items);

  final List<OrderStatusSummary> items;
}

/// Profile 横向 Story 卡片摘要。
final class Story {
  factory Story({
    required String id,
    required String title,
    required String imageAssetKey,
    required bool isLive,
  }) => Story._(
    id: _requiredText(id, 'id'),
    title: _requiredText(title, 'title'),
    imageAssetKey: _localAssetKey(imageAssetKey),
    isLive: isLive,
  );

  const Story._({
    required this.id,
    required this.title,
    required this.imageAssetKey,
    required this.isLive,
  });

  final String id;
  final String title;
  final String imageAssetKey;
  final bool isLive;
}

/// 多个 Profile 商品区段共享的最小展示摘要。
final class ProductSummary {
  factory ProductSummary({
    required String id,
    required String title,
    required String imageAssetKey,
    String? displayPrice,
    String? tag,
    int? popularityCount,
  }) {
    if (popularityCount != null && popularityCount < 0) {
      throw ArgumentError.value(
        popularityCount,
        'popularityCount',
        'Popularity count must not be negative.',
      );
    }
    return ProductSummary._(
      id: _requiredText(id, 'id'),
      title: _requiredText(title, 'title'),
      imageAssetKey: _localAssetKey(imageAssetKey),
      displayPrice: _optionalText(displayPrice, 'displayPrice'),
      tag: _optionalText(tag, 'tag'),
      popularityCount: popularityCount,
    );
  }

  const ProductSummary._({
    required this.id,
    required this.title,
    required this.imageAssetKey,
    required this.displayPrice,
    required this.tag,
    required this.popularityCount,
  });

  final String id;
  final String title;
  final String imageAssetKey;
  final String? displayPrice;
  final String? tag;
  final int? popularityCount;
}

/// Categories 区段当前使用的分类摘要。
final class CategorySummary {
  factory CategorySummary({
    required String id,
    required String name,
    required String imageAssetKey,
    required int itemCount,
  }) {
    if (itemCount < 0) {
      throw ArgumentError.value(
        itemCount,
        'itemCount',
        'Category item count must not be negative.',
      );
    }
    return CategorySummary._(
      id: _requiredText(id, 'id'),
      name: _requiredText(name, 'name'),
      imageAssetKey: _localAssetKey(imageAssetKey),
      itemCount: itemCount,
    );
  }

  const CategorySummary._({
    required this.id,
    required this.name,
    required this.imageAssetKey,
    required this.itemCount,
  });

  final String id;
  final String name;
  final String imageAssetKey;
  final int itemCount;
}

/// 不依赖墙钟的静态 Flash Sale 展示数据。
final class FlashSale {
  factory FlashSale({
    required int hours,
    required int minutes,
    required int seconds,
    required List<ProductSummary> products,
  }) {
    if (hours < 0 ||
        hours > 99 ||
        minutes < 0 ||
        minutes > 59 ||
        seconds < 0 ||
        seconds > 59) {
      throw ArgumentError('Invalid static Flash Sale countdown.');
    }
    return FlashSale._(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      products: List<ProductSummary>.unmodifiable(products),
    );
  }

  const FlashSale._({
    required this.hours,
    required this.minutes,
    required this.seconds,
    required this.products,
  });

  final int hours;
  final int minutes;
  final int seconds;
  final List<ProductSummary> products;

  String get displayCountdown =>
      '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

/// Profile 页面一次加载得到的确定性聚合快照。
final class ProfileDashboard {
  factory ProfileDashboard({
    required Announcement? announcement,
    required List<RecentlyViewed> recentlyViewed,
    required OrderSummary orders,
    required List<Story> stories,
    required List<ProductSummary> newItems,
    required List<ProductSummary> mostPopular,
    required List<CategorySummary> categories,
    required FlashSale flashSale,
    required List<ProductSummary> topProducts,
    required List<ProductSummary> recommendations,
  }) => ProfileDashboard._(
    announcement: announcement,
    recentlyViewed: List<RecentlyViewed>.unmodifiable(recentlyViewed),
    orders: orders,
    stories: List<Story>.unmodifiable(stories),
    newItems: List<ProductSummary>.unmodifiable(newItems),
    mostPopular: List<ProductSummary>.unmodifiable(mostPopular),
    categories: List<CategorySummary>.unmodifiable(categories),
    flashSale: flashSale,
    topProducts: List<ProductSummary>.unmodifiable(topProducts),
    recommendations: List<ProductSummary>.unmodifiable(recommendations),
  );

  const ProfileDashboard._({
    required this.announcement,
    required this.recentlyViewed,
    required this.orders,
    required this.stories,
    required this.newItems,
    required this.mostPopular,
    required this.categories,
    required this.flashSale,
    required this.topProducts,
    required this.recommendations,
  });

  final Announcement? announcement;
  final List<RecentlyViewed> recentlyViewed;
  final OrderSummary orders;
  final List<Story> stories;
  final List<ProductSummary> newItems;
  final List<ProductSummary> mostPopular;
  final List<CategorySummary> categories;
  final FlashSale flashSale;
  final List<ProductSummary> topProducts;
  final List<ProductSummary> recommendations;
}

String _requiredText(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, 'Value must not be empty.');
  }
  return normalized;
}

String? _optionalText(String? value, String name) {
  if (value == null) {
    return null;
  }
  return _requiredText(value, name);
}

String _localAssetKey(String value) {
  final normalized = _requiredText(value, 'imageAssetKey');
  final uri = Uri.tryParse(normalized);
  if (normalized.startsWith('/') ||
      normalized.contains('\\') ||
      normalized.split('/').contains('..') ||
      (uri?.hasScheme ?? false)) {
    throw ArgumentError.value(
      value,
      'imageAssetKey',
      'Image asset key must be a relative, platform-neutral identifier.',
    );
  }
  return normalized;
}
