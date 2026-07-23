import 'package:app_data/app_data.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import '../../shared/catalog/catalog_asset_image.dart';
import '../../shared/catalog/catalog_components.dart';

TextStyle wishlistRaleway({
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

TextStyle wishlistNunito({
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

final class WishlistFailureView extends StatelessWidget {
  const WishlistFailureView({required this.onRetry, super.key});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 40,
            color: Color(0xFF697386),
          ),
          const SizedBox(height: 12),
          Text('Unable to load your items', style: wishlistRaleway(size: 20)),
          const SizedBox(height: 6),
          Text(
            'Please try again.',
            style: wishlistNunito(size: 14, color: const Color(0xFF697386)),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const ValueKey('wishlist-retry'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

final class WishlistRecentlyViewedRail extends StatelessWidget {
  const WishlistRecentlyViewedRail({
    required this.products,
    required this.onOpen,
    super.key,
  });

  final List<ProductSummary> products;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'Recently viewed',
              style: wishlistRaleway(size: 21, height: 30 / 21),
            ),
          ),
          IconButton.filled(
            key: const ValueKey('open-recently-viewed'),
            tooltip: 'Open recently viewed',
            onPressed: onOpen,
            icon: const Icon(Icons.arrow_forward, size: 20),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              fixedSize: const Size.square(30),
              minimumSize: const Size.square(30),
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 66,
        child: ListView.separated(
          key: const ValueKey('wishlist-recently-viewed-rail'),
          scrollDirection: Axis.horizontal,
          itemCount: products.length,
          separatorBuilder: (context, index) => const SizedBox(width: 7),
          itemBuilder: (context, index) =>
              CatalogTopProductCard(product: products[index], showLabel: false),
        ),
      ),
    ],
  );
}

final class WishlistEmptyVisual extends StatelessWidget {
  const WishlistEmptyVisual({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Wishlist is empty',
    child: SizedBox(
      key: const ValueKey('wishlist-empty'),
      height: 270,
      child: Center(
        child: Container(
          width: 134,
          height: 134,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color(0x1F000000),
                blurRadius: 12,
                offset: Offset(0, 7),
              ),
            ],
          ),
          child: const Icon(
            Icons.favorite_border,
            color: AppColors.primary,
            size: 58,
          ),
        ),
      ),
    ),
  );
}

final class WishlistItemCard extends StatelessWidget {
  const WishlistItemCard({
    required this.item,
    required this.onRemove,
    required this.onOpenProduct,
    required this.onAddToCart,
    super.key,
  });

  final WishlistItem item;
  final VoidCallback onRemove;
  final VoidCallback onOpenProduct;
  final VoidCallback onAddToCart;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: 'Wishlist item ${item.product.title}',
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 114),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 126,
            height: 104,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(9),
                    elevation: 2,
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      key: ValueKey<String>('wishlist-open-${item.product.id}'),
                      onTap: onOpenProduct,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: CatalogAssetImage(
                            assetKey: item.product.imageAssetKey,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 8,
                  bottom: 7,
                  child: IconButton.filled(
                    key: ValueKey<String>('wishlist-remove-${item.product.id}'),
                    tooltip: 'Remove from wishlist',
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline, size: 19),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFFFF5777),
                      fixedSize: const Size.square(35),
                      minimumSize: const Size.square(35),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.product.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: wishlistNunito(size: 12, height: 16 / 12),
                  ),
                  const SizedBox(height: 8),
                  _WishlistPrice(item: item),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _OptionChip(label: item.color),
                      _OptionChip(label: item.size),
                    ],
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            key: ValueKey<String>('wishlist-add-${item.product.id}'),
            tooltip: 'Add to cart',
            onPressed: onAddToCart,
            color: AppColors.primary,
            icon: const Icon(Icons.add_shopping_cart_outlined, size: 27),
          ),
        ],
      ),
    ),
  );
}

final class _WishlistPrice extends StatelessWidget {
  const _WishlistPrice({required this.item});

  final WishlistItem item;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      if (item.originalPrice case final originalPrice?)
        Text(
          originalPrice.format(),
          style: wishlistRaleway(
            size: 16,
            weight: FontWeight.w500,
            color: const Color(0xFFF1AEAE),
          ).copyWith(decoration: TextDecoration.lineThrough),
        ),
      Text(item.product.displayPrice ?? '', style: wishlistRaleway(size: 18)),
    ],
  );
}

final class _OptionChip extends StatelessWidget {
  const _OptionChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 50, minHeight: 25),
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.primarySurface,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: wishlistRaleway(size: 14, weight: FontWeight.w500),
    ),
  );
}

final class WishlistDateChip extends StatelessWidget {
  const WishlistDateChip({
    required this.label,
    required this.isSelected,
    required this.onPressed,
    this.showCheck = false,
    super.key,
  });

  final String label;
  final bool isSelected;
  final bool showCheck;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: isSelected,
    label: label,
    child: Material(
      color: isSelected ? AppColors.primarySurface : AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onPressed,
        child: ExcludeSemantics(
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: wishlistRaleway(
                      size: 15,
                      weight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
                if (showCheck && isSelected) ...[
                  const SizedBox(width: 7),
                  const CircleAvatar(
                    radius: 11,
                    backgroundColor: AppColors.primary,
                    child: Icon(Icons.check, color: Colors.white, size: 14),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
