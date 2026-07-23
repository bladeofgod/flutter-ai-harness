/// Demo Catalog 当前支持的货币。
enum Currency {
  usd(code: 'USD', symbol: r'$');

  const Currency({required this.code, required this.symbol});

  final String code;
  final String symbol;

  static Currency fromCode(String code) => switch (code.toUpperCase()) {
    'USD' => Currency.usd,
    _ => throw FormatException('Unsupported currency code: $code'),
  };
}

/// 以最小货币单位保存金额，避免浮点精度进入 Domain。
final class Money {
  factory Money({required Currency currency, required int minorUnits}) {
    if (minorUnits < 0) {
      throw ArgumentError.value(
        minorUnits,
        'minorUnits',
        'Money must not be negative.',
      );
    }
    return Money._(currency: currency, minorUnits: minorUnits);
  }

  const Money._({required this.currency, required this.minorUnits});

  final Currency currency;
  final int minorUnits;

  String format() {
    final major = minorUnits ~/ 100;
    final fraction = (minorUnits % 100).toString().padLeft(2, '0');
    return '${currency.symbol}$major,$fraction';
  }

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.currency == currency &&
      other.minorUnits == minorUnits;

  @override
  int get hashCode => Object.hash(currency, minorUnits);

  @override
  String toString() => 'Money(${currency.code}, $minorUnits)';
}

/// Catalog 各页面共享的最小商品摘要。
final class ProductSummary {
  factory ProductSummary({
    required String id,
    required String title,
    required String imageAssetKey,
    Money? price,
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
      price: price,
      tag: _optionalText(tag, 'tag'),
      popularityCount: popularityCount,
    );
  }

  const ProductSummary._({
    required this.id,
    required this.title,
    required this.imageAssetKey,
    required this.price,
    required this.tag,
    required this.popularityCount,
  });

  final String id;
  final String title;
  final String imageAssetKey;
  final Money? price;
  final String? tag;
  final int? popularityCount;

  /// 兼容现有 Profile 组件的展示属性，值始终由 [price] 派生。
  String? get displayPrice => price?.format();
}

/// 商品详情 Gallery 中的一张本地图片。
final class ProductImage {
  factory ProductImage({required String id, required String imageAssetKey}) =>
      ProductImage._(
        id: _requiredText(id, 'id'),
        imageAssetKey: _localAssetKey(imageAssetKey),
      );

  const ProductImage._({required this.id, required this.imageAssetKey});

  final String id;
  final String imageAssetKey;
}

/// 商品详情中的一个可选值。
final class ProductOption {
  factory ProductOption({required String id, required String label}) =>
      ProductOption._(
        id: _requiredText(id, 'id'),
        label: _requiredText(label, 'label'),
      );

  const ProductOption._({required this.id, required this.label});

  final String id;
  final String label;
}

/// 商品详情中的规格组，例如 Color 或 Size。
final class ProductOptionGroup {
  factory ProductOptionGroup({
    required String id,
    required String label,
    required List<ProductOption> options,
    bool required = true,
  }) {
    if (options.isEmpty) {
      throw ArgumentError.value(
        options,
        'options',
        'Options must not be empty.',
      );
    }
    return ProductOptionGroup._(
      id: _requiredText(id, 'id'),
      label: _requiredText(label, 'label'),
      options: List<ProductOption>.unmodifiable(options),
      required: required,
    );
  }

  const ProductOptionGroup._({
    required this.id,
    required this.label,
    required this.options,
    required this.required,
  });

  final String id;
  final String label;
  final List<ProductOption> options;
  final bool required;
}

/// 详情页展示的评分汇总，平均分使用百分之一整数避免浮点金额/评分。
final class ProductRatingSummary {
  factory ProductRatingSummary({
    required int averageRatingHundredths,
    required int reviewCount,
    required Map<int, int> distribution,
  }) {
    if (averageRatingHundredths < 0 || averageRatingHundredths > 500) {
      throw ArgumentError.value(
        averageRatingHundredths,
        'averageRatingHundredths',
        'Rating must be between 0 and 5.',
      );
    }
    if (reviewCount < 0) {
      throw ArgumentError.value(
        reviewCount,
        'reviewCount',
        'Review count must not be negative.',
      );
    }
    for (final entry in distribution.entries) {
      if (entry.key < 1 || entry.key > 5 || entry.value < 0) {
        throw ArgumentError.value(
          distribution,
          'distribution',
          'Invalid rating distribution.',
        );
      }
    }
    return ProductRatingSummary._(
      averageRatingHundredths: averageRatingHundredths,
      reviewCount: reviewCount,
      distribution: Map<int, int>.unmodifiable(distribution),
    );
  }

  const ProductRatingSummary._({
    required this.averageRatingHundredths,
    required this.reviewCount,
    required this.distribution,
  });

  final int averageRatingHundredths;
  final int reviewCount;
  final Map<int, int> distribution;

  String get displayRating =>
      '${averageRatingHundredths ~/ 100}.${(averageRatingHundredths % 100) ~/ 10}';
}

/// 详情页评价列表中的只读评价。
final class ProductReview {
  factory ProductReview({
    required String id,
    required String author,
    required String comment,
    required int rating,
    required String publishedLabel,
    String? avatarAssetKey,
  }) {
    if (rating < 1 || rating > 5) {
      throw ArgumentError.value(
        rating,
        'rating',
        'Rating must be between 1 and 5.',
      );
    }
    return ProductReview._(
      id: _requiredText(id, 'id'),
      author: _requiredText(author, 'author'),
      comment: _requiredText(comment, 'comment'),
      rating: rating,
      publishedLabel: _requiredText(publishedLabel, 'publishedLabel'),
      avatarAssetKey: avatarAssetKey == null
          ? null
          : _localAssetKey(avatarAssetKey),
    );
  }

  const ProductReview._({
    required this.id,
    required this.author,
    required this.comment,
    required this.rating,
    required this.publishedLabel,
    required this.avatarAssetKey,
  });

  final String id;
  final String author;
  final String comment;
  final int rating;
  final String publishedLabel;
  final String? avatarAssetKey;
}

/// 商品详情跨层传递的完整只读实体。
final class ProductDetail {
  factory ProductDetail({
    required ProductSummary product,
    required List<ProductImage> gallery,
    required String description,
    required List<ProductOptionGroup> optionGroups,
    required int stockCount,
    required ProductRatingSummary rating,
    required List<ProductReview> reviews,
    Money? originalPrice,
  }) {
    if (gallery.isEmpty) {
      throw ArgumentError.value(
        gallery,
        'gallery',
        'Gallery must not be empty.',
      );
    }
    if (stockCount < 0) {
      throw ArgumentError.value(
        stockCount,
        'stockCount',
        'Stock must not be negative.',
      );
    }
    if (originalPrice != null &&
        (product.price == null ||
            originalPrice.currency != product.price!.currency ||
            originalPrice.minorUnits < product.price!.minorUnits)) {
      throw ArgumentError.value(
        originalPrice,
        'originalPrice',
        'Original price must not be below the current price.',
      );
    }
    return ProductDetail._(
      product: product,
      gallery: List<ProductImage>.unmodifiable(gallery),
      description: _requiredText(description, 'description'),
      optionGroups: List<ProductOptionGroup>.unmodifiable(optionGroups),
      stockCount: stockCount,
      rating: rating,
      reviews: List<ProductReview>.unmodifiable(reviews),
      originalPrice: originalPrice,
    );
  }

  const ProductDetail._({
    required this.product,
    required this.gallery,
    required this.description,
    required this.optionGroups,
    required this.stockCount,
    required this.rating,
    required this.reviews,
    required this.originalPrice,
  });

  final ProductSummary product;
  final List<ProductImage> gallery;
  final String description;
  final List<ProductOptionGroup> optionGroups;
  final int stockCount;
  final ProductRatingSummary rating;
  final List<ProductReview> reviews;
  final Money? originalPrice;

  bool get isOnSale => originalPrice != null;
  String? get displayOriginalPrice => originalPrice?.format();
}

/// Catalog 分类摘要。
final class CategorySummary {
  factory CategorySummary({
    required String id,
    required String name,
    String? imageAssetKey,
    List<String>? previewImageAssetKeys,
    required int itemCount,
  }) {
    if (itemCount < 0) {
      throw ArgumentError.value(
        itemCount,
        'itemCount',
        'Category item count must not be negative.',
      );
    }
    final previewKeys =
        previewImageAssetKeys ??
        (imageAssetKey == null ? const <String>[] : <String>[imageAssetKey]);
    if (previewKeys.isEmpty) {
      throw ArgumentError.value(
        previewImageAssetKeys,
        'previewImageAssetKeys',
        'At least one category preview image is required.',
      );
    }
    return CategorySummary._(
      id: _requiredText(id, 'id'),
      name: _requiredText(name, 'name'),
      previewImageAssetKeys: List<String>.unmodifiable(
        previewKeys.map(_localAssetKey),
      ),
      itemCount: itemCount,
    );
  }

  const CategorySummary._({
    required this.id,
    required this.name,
    required this.previewImageAssetKeys,
    required this.itemCount,
  });

  final String id;
  final String name;
  final List<String> previewImageAssetKeys;
  final int itemCount;

  /// 兼容只消费单张分类图的现有调用方。
  String get imageAssetKey => previewImageAssetKeys.first;
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

/// Shop 页顶部促销区需要的最小信息。
final class ShopPromotion {
  factory ShopPromotion({
    required String id,
    required String title,
    required String subtitle,
    required String badge,
    required String imageAssetKey,
  }) => ShopPromotion._(
    id: _requiredText(id, 'id'),
    title: _requiredText(title, 'title'),
    subtitle: _requiredText(subtitle, 'subtitle'),
    badge: _requiredText(badge, 'badge'),
    imageAssetKey: _localAssetKey(imageAssetKey),
  );

  const ShopPromotion._({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.imageAssetKey,
  });

  final String id;
  final String title;
  final String subtitle;
  final String badge;
  final String imageAssetKey;
}

/// Shop 首页一次加载得到的确定性聚合快照。
final class ShopDashboard {
  factory ShopDashboard({
    required List<ShopPromotion> promotions,
    required List<CategorySummary> categories,
    required List<ProductSummary> topProducts,
    required List<ProductSummary> newItems,
    required FlashSale flashSale,
    required List<ProductSummary> mostPopular,
    required List<ProductSummary> recommendations,
  }) => ShopDashboard._(
    promotions: List<ShopPromotion>.unmodifiable(promotions),
    categories: List<CategorySummary>.unmodifiable(categories),
    topProducts: List<ProductSummary>.unmodifiable(topProducts),
    newItems: List<ProductSummary>.unmodifiable(newItems),
    flashSale: flashSale,
    mostPopular: List<ProductSummary>.unmodifiable(mostPopular),
    recommendations: List<ProductSummary>.unmodifiable(recommendations),
  );

  const ShopDashboard._({
    required this.promotions,
    required this.categories,
    required this.topProducts,
    required this.newItems,
    required this.flashSale,
    required this.mostPopular,
    required this.recommendations,
  });

  final List<ShopPromotion> promotions;
  final List<CategorySummary> categories;
  final List<ProductSummary> topProducts;
  final List<ProductSummary> newItems;
  final FlashSale flashSale;
  final List<ProductSummary> mostPopular;
  final List<ProductSummary> recommendations;
}

/// Catalog 商品列表支持的目标人群。
enum CatalogAudience { all, female, male }

/// Catalog 列表的确定性排序方式。
enum CatalogSortOrder { featured, priceLowToHigh, priceHighToLow }

/// 商品列表已应用的筛选条件。
final class CatalogFilter {
  factory CatalogFilter({
    required CatalogAudience audience,
    required String categoryId,
    String? subcategoryId,
  }) => CatalogFilter._(
    audience: audience,
    categoryId: _requiredText(categoryId, 'categoryId'),
    subcategoryId: _optionalText(subcategoryId, 'subcategoryId'),
  );

  const CatalogFilter._({
    required this.audience,
    required this.categoryId,
    required this.subcategoryId,
  });

  final CatalogAudience audience;
  final String categoryId;
  final String? subcategoryId;

  CatalogFilter copyWith({
    CatalogAudience? audience,
    String? categoryId,
    String? subcategoryId,
    bool clearSubcategory = false,
  }) => CatalogFilter(
    audience: audience ?? this.audience,
    categoryId: categoryId ?? this.categoryId,
    subcategoryId: clearSubcategory
        ? null
        : (subcategoryId ?? this.subcategoryId),
  );

  @override
  bool operator ==(Object other) =>
      other is CatalogFilter &&
      other.audience == audience &&
      other.categoryId == categoryId &&
      other.subcategoryId == subcategoryId;

  @override
  int get hashCode => Object.hash(audience, categoryId, subcategoryId);
}

/// Catalog 查询由筛选条件和排序方式共同组成。
final class CatalogQuery {
  CatalogQuery({
    required this.filter,
    this.sortOrder = CatalogSortOrder.featured,
  });

  factory CatalogQuery.initial() => CatalogQuery(
    filter: CatalogFilter(
      audience: CatalogAudience.female,
      categoryId: 'category-clothing',
    ),
  );

  final CatalogFilter filter;
  final CatalogSortOrder sortOrder;

  CatalogQuery copyWith({CatalogFilter? filter, CatalogSortOrder? sortOrder}) =>
      CatalogQuery(
        filter: filter ?? this.filter,
        sortOrder: sortOrder ?? this.sortOrder,
      );

  @override
  bool operator ==(Object other) =>
      other is CatalogQuery &&
      other.filter == filter &&
      other.sortOrder == sortOrder;

  @override
  int get hashCode => Object.hash(filter, sortOrder);
}

/// 筛选页中的最小子分类选项。
final class CatalogSubcategory {
  factory CatalogSubcategory({
    required String id,
    required String name,
    required String imageAssetKey,
  }) => CatalogSubcategory._(
    id: _requiredText(id, 'id'),
    name: _requiredText(name, 'name'),
    imageAssetKey: _localAssetKey(imageAssetKey),
  );

  const CatalogSubcategory._({
    required this.id,
    required this.name,
    required this.imageAssetKey,
  });

  final String id;
  final String name;
  final String imageAssetKey;
}

/// 筛选页中的分类及其可选子分类。
final class CatalogFilterCategory {
  factory CatalogFilterCategory({
    required String id,
    required String name,
    required String imageAssetKey,
    required List<CatalogSubcategory> subcategories,
  }) => CatalogFilterCategory._(
    id: _requiredText(id, 'id'),
    name: _requiredText(name, 'name'),
    imageAssetKey: _localAssetKey(imageAssetKey),
    subcategories: List<CatalogSubcategory>.unmodifiable(subcategories),
  );

  const CatalogFilterCategory._({
    required this.id,
    required this.name,
    required this.imageAssetKey,
    required this.subcategories,
  });

  final String id;
  final String name;
  final String imageAssetKey;
  final List<CatalogSubcategory> subcategories;
}

/// Catalog 商品列表一次查询得到的不可变快照。
final class CatalogBrowseResult {
  factory CatalogBrowseResult({
    required CatalogQuery query,
    required List<CatalogFilterCategory> categories,
    required List<ProductSummary> products,
  }) => CatalogBrowseResult._(
    query: query,
    categories: List<CatalogFilterCategory>.unmodifiable(categories),
    products: List<ProductSummary>.unmodifiable(products),
  );

  const CatalogBrowseResult._({
    required this.query,
    required this.categories,
    required this.products,
  });

  final CatalogQuery query;
  final List<CatalogFilterCategory> categories;
  final List<ProductSummary> products;

  CatalogFilterCategory? get selectedCategory {
    for (final category in categories) {
      if (category.id == query.filter.categoryId) {
        return category;
      }
    }
    return null;
  }
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
