import 'package:app_data/app_data.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import 'profile_asset_image.dart';

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

final class ProfileSectionHeader extends StatelessWidget {
  const ProfileSectionHeader({
    required this.title,
    this.showSeeAll = false,
    super.key,
  });

  final String title;
  final bool showSeeAll;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: _raleway(size: 21, height: 30 / 21)),
      ),
      if (showSeeAll)
        ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'See All',
                style: _raleway(size: 13, weight: FontWeight.w600),
              ),
              const SizedBox(width: 7),
              const CircleAvatar(
                radius: 12,
                backgroundColor: AppColors.primary,
                child: Icon(
                  Icons.arrow_forward,
                  size: 14,
                  color: AppColors.textOnPrimary,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

final class ProfileEmptySection extends StatelessWidget {
  const ProfileEmptySection({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    height: 72,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      label,
      style: _nunito(size: 13, color: const Color(0xFF697386)),
    ),
  );
}

final class ProfileStoryCard extends StatelessWidget {
  const ProfileStoryCard({required this.story, super.key});

  final Story story;

  @override
  Widget build(BuildContext context) => Semantics(
    label: story.title,
    image: true,
    child: SizedBox(
      width: 104,
      height: 175,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ProfileAssetImage(assetKey: story.imageAssetKey),
            const Align(
              alignment: Alignment.center,
              child: CircleAvatar(
                radius: 15,
                backgroundColor: Color(0xB3FFFFFF),
                child: Icon(
                  Icons.play_arrow_rounded,
                  size: 22,
                  color: Colors.white,
                ),
              ),
            ),
            if (story.isLive)
              Align(
                alignment: Alignment.topLeft,
                child: Container(
                  margin: const EdgeInsets.all(3),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    'Live',
                    style: _raleway(
                      size: 13,
                      weight: FontWeight.w600,
                      color: Colors.white,
                      height: 18 / 13,
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

final class ProfileProductCard extends StatelessWidget {
  const ProfileProductCard({required this.product, super.key});

  final ProductSummary product;

  @override
  Widget build(BuildContext context) => Semantics(
    label: product.title,
    image: true,
    child: SizedBox(
      width: 104,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 104 / 140,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: ProfileAssetImage(assetKey: product.imageAssetKey),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            product.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _nunito(size: 11, height: 14 / 11),
          ),
          if (product.displayPrice case final price?) ...[
            const SizedBox(height: 3),
            Text(price, style: _raleway(size: 13, weight: FontWeight.w700)),
          ],
        ],
      ),
    ),
  );
}

final class ProfilePopularCard extends StatelessWidget {
  const ProfilePopularCard({required this.product, super.key});

  final ProductSummary product;

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
            height: 120,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: ProfileAssetImage(assetKey: product.imageAssetKey),
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
                    style: _raleway(size: 12, weight: FontWeight.w600),
                  ),
                ),
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
                      size: 11,
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

final class ProfileCategoryCard extends StatelessWidget {
  const ProfileCategoryCard({required this.category, super.key});

  final CategorySummary category;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '${category.name}, ${category.itemCount} items',
    image: true,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ProfileAssetImage(assetKey: category.imageAssetKey),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xB3000000)],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _raleway(size: 15, color: Colors.white),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
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
        ],
      ),
    ),
  );
}

final class ProfileSaleCard extends StatelessWidget {
  const ProfileSaleCard({required this.product, super.key});

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
          ProfileAssetImage(assetKey: product.imageAssetKey),
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

final class ProfileTopProductCard extends StatelessWidget {
  const ProfileTopProductCard({required this.product, super.key});

  final ProductSummary product;

  @override
  Widget build(BuildContext context) => Semantics(
    label: product.title,
    image: true,
    child: SizedBox(
      width: 60,
      child: Column(
        children: [
          SizedBox(
            width: 60,
            height: 60,
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
                child: ProfileAssetImage(assetKey: product.imageAssetKey),
              ),
            ),
          ),
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
      ),
    ),
  );
}

final class ProfileRecommendationCard extends StatelessWidget {
  const ProfileRecommendationCard({required this.product, super.key});

  final ProductSummary product;

  @override
  Widget build(BuildContext context) => Semantics(
    label: product.title,
    image: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: ProfileAssetImage(assetKey: product.imageAssetKey),
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
        Text(
          product.displayPrice ?? '',
          style: _raleway(size: 13, weight: FontWeight.w700),
        ),
      ],
    ),
  );
}
