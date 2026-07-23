import '../catalog/catalog_models.dart';

/// 不依赖系统时钟的日历日期值对象。
final class WishlistDate implements Comparable<WishlistDate> {
  factory WishlistDate({
    required int year,
    required int month,
    required int day,
  }) {
    final normalized = DateTime.utc(year, month, day);
    if (normalized.year != year ||
        normalized.month != month ||
        normalized.day != day) {
      throw ArgumentError('Invalid Wishlist date: $year-$month-$day.');
    }
    return WishlistDate._(year: year, month: month, day: day);
  }

  const WishlistDate._({
    required this.year,
    required this.month,
    required this.day,
  });

  final int year;
  final int month;
  final int day;

  WishlistDate addDays(int days) {
    final value = DateTime.utc(year, month, day).add(Duration(days: days));
    return WishlistDate(year: value.year, month: value.month, day: value.day);
  }

  @override
  int compareTo(WishlistDate other) => DateTime.utc(
    year,
    month,
    day,
  ).compareTo(DateTime.utc(other.year, other.month, other.day));

  @override
  bool operator ==(Object other) =>
      other is WishlistDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() =>
      'WishlistDate($year-${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')})';
}

/// 收藏关系附带的商品选择，不复制 Catalog 商品字段。
final class WishlistItem {
  factory WishlistItem({
    required ProductSummary product,
    required String color,
    required String size,
    Money? originalPrice,
  }) {
    final price = product.price;
    if (price == null) {
      throw ArgumentError.value(
        product,
        'product',
        'Wishlist products must have a price.',
      );
    }
    if (originalPrice != null &&
        (originalPrice.currency != price.currency ||
            originalPrice.minorUnits < price.minorUnits)) {
      throw ArgumentError.value(
        originalPrice,
        'originalPrice',
        'Original price must use the same currency and not be lower.',
      );
    }
    return WishlistItem._(
      product: product,
      color: _requiredText(color, 'color'),
      size: _requiredText(size, 'size'),
      originalPrice: originalPrice,
    );
  }

  const WishlistItem._({
    required this.product,
    required this.color,
    required this.size,
    required this.originalPrice,
  });

  final ProductSummary product;
  final String color;
  final String size;
  final Money? originalPrice;
}

/// 一条确定日期的最近浏览记录。
final class RecentlyViewedItem {
  factory RecentlyViewedItem({
    required String id,
    required ProductSummary product,
    required WishlistDate viewedOn,
  }) => RecentlyViewedItem._(
    id: _requiredText(id, 'id'),
    product: product,
    viewedOn: viewedOn,
  );

  const RecentlyViewedItem._({
    required this.id,
    required this.product,
    required this.viewedOn,
  });

  final String id;
  final ProductSummary product;
  final WishlistDate viewedOn;
}

/// Wishlist 页面一次加载得到的快照。
final class WishlistOverview {
  WishlistOverview({
    required List<WishlistItem> items,
    required List<ProductSummary> recentlyViewed,
    required List<ProductSummary> recommendations,
  }) : items = List<WishlistItem>.unmodifiable(items),
       recentlyViewed = List<ProductSummary>.unmodifiable(recentlyViewed),
       recommendations = List<ProductSummary>.unmodifiable(recommendations);

  final List<WishlistItem> items;
  final List<ProductSummary> recentlyViewed;
  final List<ProductSummary> recommendations;
}

/// Recently Viewed 页面使用的确定性日期快照。
final class RecentlyViewedSnapshot {
  RecentlyViewedSnapshot({
    required this.referenceDate,
    required List<RecentlyViewedItem> items,
  }) : items = List<RecentlyViewedItem>.unmodifiable(items);

  final WishlistDate referenceDate;
  final List<RecentlyViewedItem> items;
}

String _requiredText(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, 'Value must not be empty.');
  }
  return normalized;
}
