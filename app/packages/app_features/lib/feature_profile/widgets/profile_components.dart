import 'package:app_data/app_data.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import '../../shared/catalog/catalog_asset_image.dart';

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
}) => TextStyle(
  fontFamily: AppFonts.nunitoSans,
  package: AppFonts.package,
  fontSize: size,
  fontWeight: weight,
  color: color,
  letterSpacing: 0,
);

/// Profile 专属 Story 展示，不下沉到 Catalog 共享组件。
final class ProfileStoryCard extends StatelessWidget {
  const ProfileStoryCard({required this.story, this.onTap, super.key});

  final Story story;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Semantics(
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
              CatalogAssetImage(assetKey: story.imageAssetKey),
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
    if (onTap == null) {
      return card;
    }
    return InkWell(
      key: ValueKey<String>('profile-open-story-${story.id}'),
      borderRadius: BorderRadius.circular(9),
      onTap: onTap,
      child: card,
    );
  }
}

/// Profile 设计专属的单图渐变分类卡，不与 Shop 四图拼贴卡混用。
final class ProfileCategoryCard extends StatelessWidget {
  const ProfileCategoryCard({required this.category, this.onTap, super.key});

  final CategorySummary category;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Semantics(
      label: '${category.name}, ${category.itemCount} items',
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CatalogAssetImage(
              key: ValueKey<String>('profile-category-image-${category.id}'),
              assetKey: category.imageAssetKey,
            ),
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
          ],
        ),
      ),
    );
    if (onTap == null) {
      return card;
    }
    return InkWell(
      key: ValueKey<String>('profile-open-category-${category.id}'),
      borderRadius: BorderRadius.circular(9),
      onTap: onTap,
      child: card,
    );
  }
}
