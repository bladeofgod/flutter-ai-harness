import 'package:app_data/app_data.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import 'catalog_asset_image.dart';

TextStyle _raleway({
  required double size,
  FontWeight weight = FontWeight.w700,
  Color color = AppColors.textPrimary,
  double? height,
}) => TextStyle(
  fontFamily: AppFonts.raleway,
  package: AppFonts.package,
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
  letterSpacing: 0,
);

TextStyle _nunito({
  required double size,
  FontWeight weight = FontWeight.w400,
  Color color = AppColors.textPrimary,
  double? height,
}) => TextStyle(
  fontFamily: AppFonts.nunitoSans,
  package: AppFonts.package,
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
  letterSpacing: 0,
);

final class CatalogSectionHeader extends StatelessWidget {
  const CatalogSectionHeader({
    required this.title,
    this.showSeeAll = false,
    this.trailing,
    this.actionTextSize = 13,
    this.actionRadius = 12,
    super.key,
  });

  final String title;
  final bool showSeeAll;
  final Widget? trailing;
  final double actionTextSize;
  final double actionRadius;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: _raleway(size: 21, height: 30 / 21)),
      ),
      if (trailing case final trailing?)
        trailing
      else if (showSeeAll)
        ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'See All',
                style: _raleway(size: actionTextSize, weight: FontWeight.w600),
              ),
              const SizedBox(width: 7),
              CircleAvatar(
                radius: actionRadius,
                backgroundColor: AppColors.primary,
                child: Icon(
                  Icons.arrow_forward,
                  size: actionRadius + 2,
                  color: AppColors.textOnPrimary,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

final class CatalogEmptySection extends StatelessWidget {
  const CatalogEmptySection({
    required this.label,
    this.borderRadius = 10,
    super.key,
  });

  final String label;
  final double borderRadius;

  @override
  Widget build(BuildContext context) => Container(
    height: 72,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(borderRadius),
    ),
    child: Text(
      label,
      style: _nunito(size: 13, color: const Color(0xFF697386)),
    ),
  );
}

final class CatalogProductCard extends StatelessWidget {
  const CatalogProductCard({
    required this.product,
    this.width = 104,
    this.imageAspectRatio = 104 / 140,
    this.imagePadding = EdgeInsets.zero,
    this.frameImage = false,
    this.borderRadius = 9,
    this.titleSize = 11,
    this.priceSize = 13,
    super.key,
  });

  final ProductSummary product;
  final double width;
  final double imageAspectRatio;
  final EdgeInsets imagePadding;
  final bool frameImage;
  final double borderRadius;
  final double titleSize;
  final double priceSize;

  @override
  Widget build(BuildContext context) => Semantics(
    label: product.title,
    image: true,
    child: SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: imageAspectRatio,
            child: Container(
              padding: imagePadding,
              decoration: frameImage
                  ? BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(borderRadius),
                      boxShadow: const [
                        BoxShadow(color: Color(0x18000000), blurRadius: 7),
                      ],
                    )
                  : null,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(borderRadius),
                child: CatalogAssetImage(assetKey: product.imageAssetKey),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            product.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _nunito(size: titleSize, height: 14 / 11),
          ),
          if (product.displayPrice case final price?) ...[
            const SizedBox(height: 3),
            Text(price, style: _raleway(size: priceSize)),
          ],
        ],
      ),
    ),
  );
}

final class CatalogPopularCard extends StatelessWidget {
  const CatalogPopularCard({
    required this.product,
    this.countSize = 12,
    this.tagSize = 11,
    this.borderRadius = 9,
    this.imageHeight = 120,
    this.imagePadding = EdgeInsets.zero,
    this.frameImage = false,
    this.showFavorite = false,
    super.key,
  });

  final ProductSummary product;
  final double countSize;
  final double tagSize;
  final double borderRadius;
  final double imageHeight;
  final EdgeInsets imagePadding;
  final bool frameImage;
  final bool showFavorite;

  @override
  Widget build(BuildContext context) => Semantics(
    label: product.title,
    image: true,
    child: SizedBox(
      width: 104,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            height: imageHeight,
            child: Container(
              padding: imagePadding,
              decoration: frameImage
                  ? BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(borderRadius),
                      boxShadow: const [
                        BoxShadow(color: Color(0x18000000), blurRadius: 7),
                      ],
                    )
                  : null,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(borderRadius),
                child: CatalogAssetImage(assetKey: product.imageAssetKey),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              if (product.popularityCount case final count?)
                Expanded(
                  child: Text(
                    '$count',
                    overflow: TextOverflow.ellipsis,
                    style: _raleway(size: countSize, weight: FontWeight.w700),
                  ),
                ),
              if (showFavorite && product.popularityCount != null) ...[
                const SizedBox(width: 2),
                const Icon(Icons.favorite, size: 12, color: AppColors.primary),
                const SizedBox(width: 5),
              ],
              if (product.tag case final tag?)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    tag,
                    style: _raleway(
                      size: tagSize,
                      weight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

final class CatalogCategoryCard extends StatelessWidget {
  const CatalogCategoryCard({required this.category, super.key});

  final CategorySummary category;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '${category.name}, ${category.itemCount} items',
    image: true,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Color(0x18000000), blurRadius: 7)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Wrap(
                      spacing: 2,
                      runSpacing: 2,
                      children: [
                        for (final assetKey
                            in category.previewImageAssetKeys.take(4))
                          SizedBox(
                            width: (constraints.maxWidth - 2) / 2,
                            height: (constraints.maxHeight - 2) / 2,
                            child: CatalogAssetImage(assetKey: assetKey),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 38),
              ],
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: ColoredBox(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          category.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _raleway(size: 15),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primarySurface,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          '${category.itemCount}',
                          style: _nunito(size: 10, weight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

final class CatalogSaleCard extends StatelessWidget {
  const CatalogSaleCard({required this.product, super.key});

  final ProductSummary product;

  @override
  Widget build(BuildContext context) => Semantics(
    label: product.title,
    image: true,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CatalogAssetImage(assetKey: product.imageAssetKey),
          if (product.tag case final tag?)
            Align(
              alignment: Alignment.topRight,
              child: Container(
                margin: const EdgeInsets.all(4),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFE84868),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  tag,
                  style: _raleway(size: 10, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

final class CatalogTopProductCard extends StatelessWidget {
  const CatalogTopProductCard({
    required this.product,
    this.showLabel = true,
    super.key,
  });

  final ProductSummary product;
  final bool showLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    label: product.title,
    image: true,
    child: SizedBox(
      width: 60,
      child: Column(
        children: [
          SizedBox.square(
            dimension: 60,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x1A000000),
                    blurRadius: 10,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: ClipOval(
                child: CatalogAssetImage(assetKey: product.imageAssetKey),
              ),
            ),
          ),
          if (showLabel) ...[
            const SizedBox(height: 7),
            SizedBox(
              height: 21,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  product.title,
                  maxLines: 1,
                  style: _raleway(size: 13, weight: FontWeight.w500),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

final class CatalogRecommendationCard extends StatelessWidget {
  const CatalogRecommendationCard({
    required this.product,
    this.borderRadius = 9,
    super.key,
  });

  final ProductSummary product;
  final double borderRadius;

  @override
  Widget build(BuildContext context) => Semantics(
    label: product.title,
    image: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: CatalogAssetImage(assetKey: product.imageAssetKey),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          product.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: _nunito(size: 11, height: 14 / 11),
        ),
        const SizedBox(height: 4),
        Text(product.displayPrice ?? '', style: _raleway(size: 13)),
      ],
    ),
  );
}
