import 'package:app_data/app_data.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../shared/catalog/catalog_asset_image.dart';
import '../controllers/product_controller.dart';

const _productContentMaxWidth = 420.0;

TextStyle _productRaleway({
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

TextStyle _productNunito({
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

final class ProductDetailPage extends StatelessWidget {
  const ProductDetailPage({
    required this.controller,
    required this.onOpenReviews,
    super.key,
  });

  final ProductController controller;
  final VoidCallback onOpenReviews;

  @override
  Widget build(BuildContext context) => GetBuilder<ProductController>(
    init: controller,
    global: false,
    autoRemove: false,
    dispose: (state) => state.controller.onDelete(),
    builder: (managedController) => Scaffold(
      appBar: AppBar(
        title: const Text('Product'),
        actions: [
          Obx(
            () => IconButton(
              key: const ValueKey('product-favorite'),
              tooltip: managedController.isFavorite.value
                  ? 'Remove from wishlist'
                  : 'Add to wishlist',
              onPressed: managedController.isMutating.value
                  ? null
                  : managedController.toggleFavorite,
              icon: Icon(
                managedController.isFavorite.value
                    ? Icons.favorite
                    : Icons.favorite_border,
                color: managedController.isFavorite.value
                    ? AppColors.primary
                    : AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Obx(() {
          final state = managedController.viewState;
          return switch (state) {
            ProductLoading() => const Center(
              child: CircularProgressIndicator(
                key: ValueKey('product-loading'),
              ),
            ),
            ProductData(:final detail) => _ProductDetailContent(
              detail: detail,
              controller: managedController,
              onOpenReviews: onOpenReviews,
            ),
            ProductError(:final failure) => _ProductError(
              failure: failure,
              onRetry: managedController.retryFromUi,
            ),
          };
        }),
      ),
    ),
  );
}

final class _ProductError extends StatelessWidget {
  const _ProductError({required this.failure, required this.onRetry});

  final CatalogFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            failure.code == CatalogFailureCode.notFound
                ? Icons.search_off_outlined
                : Icons.cloud_off_outlined,
            size: 40,
            color: const Color(0xFF697386),
          ),
          const SizedBox(height: 12),
          Text(
            failure.code == CatalogFailureCode.notFound
                ? 'Product not found'
                : 'Unable to load the product',
            style: _productRaleway(size: 20),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const ValueKey('product-retry'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

final class _ProductDetailContent extends StatelessWidget {
  const _ProductDetailContent({
    required this.detail,
    required this.controller,
    required this.onOpenReviews,
  });

  final ProductDetail detail;
  final ProductController controller;
  final VoidCallback onOpenReviews;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    key: const ValueKey('product-detail-scroll'),
    slivers: [
      SliverToBoxAdapter(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: _productContentMaxWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Gallery(detail: detail, controller: controller),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        detail.product.title,
                        key: const ValueKey('product-title'),
                        style: _productRaleway(size: 22, height: 28 / 22),
                      ),
                      const SizedBox(height: 8),
                      _RatingLine(rating: detail.rating),
                      const SizedBox(height: 12),
                      _PriceLine(detail: detail),
                      const SizedBox(height: 20),
                      Text('Description', style: _productRaleway(size: 18)),
                      const SizedBox(height: 7),
                      Text(
                        detail.description,
                        key: const ValueKey('product-description'),
                        style: _productNunito(
                          size: 14,
                          color: const Color(0xFF697386),
                          height: 21 / 14,
                        ),
                      ),
                      const SizedBox(height: 18),
                      OutlinedButton.icon(
                        key: const ValueKey('product-select-variation'),
                        onPressed: () => _showVariationSheet(context),
                        icon: const Icon(Icons.tune),
                        label: Obx(() {
                          controller.selectionRevision.value;
                          return Text(_selectionButtonLabel(controller));
                        }),
                      ),
                      Obx(() {
                        final error = controller.selectionError.value;
                        if (error == null) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            error,
                            key: const ValueKey('product-selection-error'),
                            style: _productNunito(
                              size: 12,
                              color: AppColors.primary,
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 22),
                      _ReviewsPreview(
                        detail: detail,
                        onOpenReviews: onOpenReviews,
                      ),
                      const SizedBox(height: 24),
                      Obx(
                        () => FilledButton.icon(
                          key: const ValueKey('product-add-to-cart'),
                          onPressed: controller.isMutating.value
                              ? null
                              : () => _addToCart(context),
                          icon: const Icon(Icons.shopping_bag_outlined),
                          label: const Text('Add to Cart'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );

  Future<void> _addToCart(BuildContext context) async {
    if (controller.confirmedSelection.isEmpty) {
      await _showVariationSheet(context);
      if (controller.confirmedSelection.isEmpty) {
        return;
      }
    }
    if (await controller.addToCart() && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Added to cart')));
    }
  }

  Future<void> _showVariationSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _VariationSheet(
        detail: detail,
        initialSelection: controller.confirmedSelection,
        onConfirm: controller.confirmSelection,
      ),
    );
  }
}

final class _Gallery extends StatelessWidget {
  const _Gallery({required this.detail, required this.controller});

  final ProductDetail detail;
  final ProductController controller;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 330,
    child: Stack(
      children: [
        PageView.builder(
          key: const ValueKey('product-gallery'),
          itemCount: detail.gallery.length,
          onPageChanged: controller.setGalleryIndex,
          itemBuilder: (context, index) => CatalogAssetImage(
            assetKey: detail.gallery[index].imageAssetKey,
            fit: BoxFit.contain,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 14,
          child: Obx(
            () => Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var index = 0; index < detail.gallery.length; index += 1)
                  Container(
                    width: index == controller.galleryIndex.value ? 20 : 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: index == controller.galleryIndex.value
                          ? AppColors.primary
                          : AppColors.primarySurface,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

final class _RatingLine extends StatelessWidget {
  const _RatingLine({required this.rating});

  final ProductRatingSummary rating;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.star, color: Color(0xFFF7B84B), size: 18),
      const SizedBox(width: 4),
      Text(rating.displayRating, style: _productRaleway(size: 14)),
      const SizedBox(width: 5),
      Text(
        '(${rating.reviewCount} reviews)',
        style: _productNunito(size: 13, color: const Color(0xFF697386)),
      ),
    ],
  );
}

final class _PriceLine extends StatelessWidget {
  const _PriceLine({required this.detail});

  final ProductDetail detail;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        detail.product.displayPrice ?? 'Price unavailable',
        style: _productRaleway(size: 22, color: AppColors.primary),
      ),
      if (detail.displayOriginalPrice case final original?) ...[
        const SizedBox(width: 9),
        Text(
          original,
          style: _productNunito(
            size: 14,
            color: const Color(0xFF9AA2B1),
          ).copyWith(decoration: TextDecoration.lineThrough),
        ),
        const SizedBox(width: 8),
        const _SaleBadge(),
      ],
    ],
  );
}

final class _SaleBadge extends StatelessWidget {
  const _SaleBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.primarySurface,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      'Sale',
      style: _productRaleway(
        size: 11,
        weight: FontWeight.w600,
        color: AppColors.primary,
      ),
    ),
  );
}

final class _ReviewsPreview extends StatelessWidget {
  const _ReviewsPreview({required this.detail, required this.onOpenReviews});

  final ProductDetail detail;
  final VoidCallback onOpenReviews;

  @override
  Widget build(BuildContext context) => InkWell(
    key: const ValueKey('product-reviews-preview'),
    onTap: onOpenReviews,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text('Reviews', style: _productRaleway(size: 18))),
          Text(
            '${detail.rating.reviewCount}',
            style: _productNunito(size: 13, color: const Color(0xFF697386)),
          ),
          const SizedBox(width: 5),
          const Icon(Icons.chevron_right, size: 22),
        ],
      ),
    ),
  );
}

final class _VariationSheet extends StatefulWidget {
  const _VariationSheet({
    required this.detail,
    required this.initialSelection,
    required this.onConfirm,
  });

  final ProductDetail detail;
  final Map<String, String> initialSelection;
  final bool Function(Map<String, String> selection) onConfirm;

  @override
  State<_VariationSheet> createState() => _VariationSheetState();
}

final class _VariationSheetState extends State<_VariationSheet> {
  late final Map<String, String> _selection = Map<String, String>.from(
    widget.initialSelection,
  );
  String? _error;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Select options', style: _productRaleway(size: 20)),
          const SizedBox(height: 16),
          for (final group in widget.detail.optionGroups) ...[
            Text(group.label, style: _productRaleway(size: 15)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in group.options)
                  ChoiceChip(
                    key: ValueKey<String>(
                      'product-option-${group.id}-${option.id}',
                    ),
                    label: Text(option.label),
                    selected: _selection[group.id] == option.id,
                    onSelected: (_) => setState(() {
                      _selection[group.id] = option.id;
                      _error = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                error,
                style: _productNunito(size: 13, color: AppColors.primary),
              ),
            ),
          FilledButton(
            key: const ValueKey('product-confirm-variation'),
            onPressed: () {
              if (widget.onConfirm(_selection)) {
                Navigator.of(context).pop();
              } else {
                setState(() => _error = 'Please select all required options.');
              }
            },
            child: const Text('Confirm'),
          ),
          TextButton(
            key: const ValueKey('product-cancel-variation'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
  );
}

String _selectionButtonLabel(ProductController controller) {
  final selection = controller.confirmedSelection;
  if (selection.isEmpty) {
    return 'Select Color and Size';
  }
  return 'Options selected';
}

final class ProductReviewsPage extends StatelessWidget {
  const ProductReviewsPage({required this.controller, super.key});

  final ProductController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Reviews')),
    body: SafeArea(
      child: GetBuilder<ProductController>(
        init: controller,
        global: false,
        autoRemove: false,
        dispose: (state) => state.controller.onDelete(),
        builder: (managedController) => Obx(() {
          final state = managedController.viewState;
          return switch (state) {
            ProductLoading() => const Center(
              child: CircularProgressIndicator(
                key: ValueKey('reviews-loading'),
              ),
            ),
            ProductError(:final failure) => _ProductError(
              failure: failure,
              onRetry: managedController.retryFromUi,
            ),
            ProductData(:final detail) => _ReviewsContent(detail: detail),
          };
        }),
      ),
    ),
  );
}

final class _ReviewsContent extends StatelessWidget {
  const _ReviewsContent({required this.detail});

  final ProductDetail detail;

  @override
  Widget build(BuildContext context) {
    if (detail.reviews.isEmpty) {
      return const Center(
        child: Text('No reviews yet', key: ValueKey('reviews-empty')),
      );
    }
    return ListView.separated(
      key: const ValueKey('reviews-list'),
      padding: const EdgeInsets.all(20),
      itemCount: detail.reviews.length + 1,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _RatingSummary(rating: detail.rating);
        }
        return _ReviewCard(review: detail.reviews[index - 1]);
      },
    );
  }
}

final class _RatingSummary extends StatelessWidget {
  const _RatingSummary({required this.rating});

  final ProductRatingSummary rating;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('reviews-summary'),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Text(rating.displayRating, style: _productRaleway(size: 28)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.star, color: Color(0xFFF7B84B), size: 18),
              Text(
                '${rating.reviewCount} reviews',
                style: _productNunito(size: 13),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

final class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});

  final ProductReview review;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey<String>('review-${review.id}'),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      boxShadow: const [BoxShadow(color: Color(0x16000000), blurRadius: 7)],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (review.avatarAssetKey case final avatar?)
              CircleAvatar(
                radius: 18,
                backgroundImage: AssetImage(avatar, package: 'app_features'),
              )
            else
              const CircleAvatar(radius: 18, child: Icon(Icons.person)),
            const SizedBox(width: 9),
            Expanded(
              child: Text(review.author, style: _productRaleway(size: 14)),
            ),
            Text(
              review.publishedLabel,
              style: _productNunito(size: 12, color: const Color(0xFF697386)),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            for (var index = 0; index < 5; index += 1)
              Icon(
                index < review.rating ? Icons.star : Icons.star_border,
                color: const Color(0xFFF7B84B),
                size: 16,
              ),
          ],
        ),
        const SizedBox(height: 7),
        Text(review.comment, style: _productNunito(size: 14, height: 20 / 14)),
      ],
    ),
  );
}
