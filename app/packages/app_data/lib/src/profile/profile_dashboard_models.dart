import '../catalog/catalog_models.dart';
import '../orders/orders_models.dart';

export '../orders/orders_models.dart'
    show OrderStatus, OrderStatusSummary, OrderSummary;

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
