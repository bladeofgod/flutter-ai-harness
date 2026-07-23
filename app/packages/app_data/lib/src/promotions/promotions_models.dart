import '../catalog/catalog_models.dart';

/// Flash Sale 页面当前消费的确定性促销内容。
final class Promotion {
  factory Promotion({
    required String id,
    required String title,
    required String subtitle,
    required String imageAssetKey,
    required FlashSale flashSale,
  }) => Promotion._(
    id: _requiredText(id, 'id'),
    title: _requiredText(title, 'title'),
    subtitle: _requiredText(subtitle, 'subtitle'),
    imageAssetKey: _localAssetKey(imageAssetKey),
    flashSale: flashSale,
  );

  const Promotion._({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageAssetKey,
    required this.flashSale,
  });

  final String id;
  final String title;
  final String subtitle;
  final String imageAssetKey;
  final FlashSale flashSale;
}

/// Live 页展示的本地静态预览，不代表真实直播连接。
final class LivePreview {
  factory LivePreview({
    required String id,
    required String title,
    required String subtitle,
    required String coverAssetKey,
    required ProductSummary product,
  }) => LivePreview._(
    id: _requiredText(id, 'id'),
    title: _requiredText(title, 'title'),
    subtitle: _requiredText(subtitle, 'subtitle'),
    coverAssetKey: _localAssetKey(coverAssetKey),
    product: product,
  );

  const LivePreview._({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.coverAssetKey,
    required this.product,
  });

  final String id;
  final String title;
  final String subtitle;
  final String coverAssetKey;
  final ProductSummary product;
}

/// Story 内容的公共基类；页面通过具体类型选择展示 Variant。
sealed class StoryItem {
  const StoryItem({
    required this.id,
    required this.title,
    required this.imageAssetKey,
  });

  final String id;
  final String title;
  final String imageAssetKey;
}

/// 展示并可打开商品详情的 Story Variant。
final class ProductStoryItem extends StoryItem {
  factory ProductStoryItem({
    required String id,
    required String title,
    required String imageAssetKey,
    required ProductSummary product,
  }) => ProductStoryItem._(
    id: _requiredText(id, 'id'),
    title: _requiredText(title, 'title'),
    imageAssetKey: _localAssetKey(imageAssetKey),
    product: product,
  );

  const ProductStoryItem._({
    required super.id,
    required super.title,
    required super.imageAssetKey,
    required this.product,
  });

  final ProductSummary product;
}

/// 只有文案和视觉内容的 Story Variant。
final class BannerStoryItem extends StoryItem {
  factory BannerStoryItem({
    required String id,
    required String title,
    required String imageAssetKey,
    required String body,
  }) => BannerStoryItem._(
    id: _requiredText(id, 'id'),
    title: _requiredText(title, 'title'),
    imageAssetKey: _localAssetKey(imageAssetKey),
    body: _requiredText(body, 'body'),
  );

  const BannerStoryItem._({
    required super.id,
    required super.title,
    required super.imageAssetKey,
    required this.body,
  });

  final String body;
}

/// 一条可手动浏览的 Story 序列。
final class StorySequence {
  factory StorySequence({
    required String id,
    required String title,
    required String coverAssetKey,
    required List<StoryItem> items,
  }) {
    if (items.isEmpty) {
      throw ArgumentError.value(
        items,
        'items',
        'Story items must not be empty.',
      );
    }
    return StorySequence._(
      id: _requiredText(id, 'id'),
      title: _requiredText(title, 'title'),
      coverAssetKey: _localAssetKey(coverAssetKey),
      items: List<StoryItem>.unmodifiable(items),
    );
  }

  const StorySequence._({
    required this.id,
    required this.title,
    required this.coverAssetKey,
    required this.items,
  });

  final String id;
  final String title;
  final String coverAssetKey;
  final List<StoryItem> items;
}

/// Promotions 入口一次加载得到的固定排序快照。
final class PromotionsOverview {
  factory PromotionsOverview({
    required Promotion flashSale,
    required List<LivePreview> livePreviews,
    required List<StorySequence> stories,
  }) => PromotionsOverview._(
    flashSale: flashSale,
    livePreviews: List<LivePreview>.unmodifiable(livePreviews),
    stories: List<StorySequence>.unmodifiable(stories),
  );

  const PromotionsOverview._({
    required this.flashSale,
    required this.livePreviews,
    required this.stories,
  });

  final Promotion flashSale;
  final List<LivePreview> livePreviews;
  final List<StorySequence> stories;
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
      'Image asset key must be a relative identifier.',
    );
  }
  return normalized;
}
