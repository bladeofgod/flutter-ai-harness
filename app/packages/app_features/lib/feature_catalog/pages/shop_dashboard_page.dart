import 'package:app_data/app_data.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../shared/catalog/catalog_asset_image.dart';
import '../../shared/catalog/catalog_components.dart';
import '../controllers/shop_dashboard_controller.dart';

const _contentMaxWidth = 420.0;

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

final class ShopDashboardPage extends StatelessWidget {
  const ShopDashboardPage({
    required this.controller,
    this.onOpenProduct,
    this.onOpenSearch,
    this.onOpenFlashSale,
    this.onOpenLive,
    this.onOpenStory,
    super.key,
  });

  final ShopDashboardController controller;
  final ValueChanged<String>? onOpenProduct;
  final VoidCallback? onOpenSearch;
  final VoidCallback? onOpenFlashSale;
  final VoidCallback? onOpenLive;
  final VoidCallback? onOpenStory;

  @override
  Widget build(BuildContext context) => GetBuilder<ShopDashboardController>(
    init: controller,
    global: false,
    autoRemove: false,
    dispose: (state) => state.controller.onDelete(),
    builder: (managedController) => Scaffold(
      body: SafeArea(
        bottom: false,
        child: Obx(() {
          final viewState = managedController.viewState;
          return switch (viewState) {
            ShopDashboardLoading() => const Center(
              child: CircularProgressIndicator(key: ValueKey('shop-loading')),
            ),
            ShopDashboardData(:final dashboard) => _ShopDashboardContent(
              dashboard: dashboard,
              onOpenProduct: onOpenProduct,
              onOpenSearch: onOpenSearch,
              onOpenFlashSale: onOpenFlashSale,
              onOpenLive: onOpenLive,
              onOpenStory: onOpenStory,
            ),
            ShopDashboardError() => _ShopError(
              onRetry: managedController.retryFromUi,
            ),
          };
        }),
      ),
    ),
  );
}

final class _ShopError extends StatelessWidget {
  const _ShopError({required this.onRetry});

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
          Text('Unable to load the shop', style: _raleway(size: 20)),
          const SizedBox(height: 6),
          Text(
            'Please try again.',
            style: _nunito(size: 14, color: const Color(0xFF697386)),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const ValueKey('shop-retry'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

final class _ShopDashboardContent extends StatelessWidget {
  const _ShopDashboardContent({
    required this.dashboard,
    this.onOpenProduct,
    this.onOpenSearch,
    this.onOpenFlashSale,
    this.onOpenLive,
    this.onOpenStory,
  });

  final ShopDashboard dashboard;
  final ValueChanged<String>? onOpenProduct;
  final VoidCallback? onOpenSearch;
  final VoidCallback? onOpenFlashSale;
  final VoidCallback? onOpenLive;
  final VoidCallback? onOpenStory;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    key: const ValueKey('shop-dashboard-scroll'),
    slivers: [
      _ShopSliver(
        padding: EdgeInsets.fromLTRB(20, 10, 20, 0),
        child: _ShopHeader(onOpenSearch: onOpenSearch),
      ),
      _ShopSliver(
        key: const ValueKey('shop-section-big-sale'),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        child: _PromotionSection(
          promotions: dashboard.promotions,
          onOpenFlashSale: onOpenFlashSale,
          onOpenLive: onOpenLive,
          onOpenStory: onOpenStory,
        ),
      ),
      _ShopSliver(
        key: const ValueKey('shop-section-categories'),
        padding: const EdgeInsets.fromLTRB(16, 20, 24, 0),
        child: _CategoriesSection(categories: dashboard.categories),
      ),
      _ShopSliver(
        key: const ValueKey('shop-section-top-products'),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
        child: _TopProductsSection(
          products: dashboard.topProducts,
          onOpenProduct: onOpenProduct,
        ),
      ),
      _ShopSliver(
        key: const ValueKey('shop-section-new-items'),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: _NewItemsSection(
          products: dashboard.newItems,
          onOpenProduct: onOpenProduct,
        ),
      ),
      _ShopSliver(
        key: const ValueKey('shop-section-flash-sale'),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
        child: _FlashSaleSection(
          flashSale: dashboard.flashSale,
          onOpenProduct: onOpenProduct,
        ),
      ),
      _ShopSliver(
        key: const ValueKey('shop-section-most-popular'),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: _MostPopularSection(
          products: dashboard.mostPopular,
          onOpenProduct: onOpenProduct,
        ),
      ),
      _ShopSliver(
        padding: const EdgeInsets.fromLTRB(20, 25, 20, 9),
        child: const CatalogSectionHeader(title: 'Just for You'),
      ),
      if (dashboard.recommendations.isEmpty)
        const _ShopSliver(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: CatalogEmptySection(label: 'No recommendations available.'),
        )
      else
        SliverPadding(
          key: const ValueKey('shop-section-recommendations'),
          padding: EdgeInsets.fromLTRB(
            _responsiveSidePadding(context),
            0,
            _responsiveSidePadding(context),
            28,
          ),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _ShopProductCard(
                product: dashboard.recommendations[index],
                onOpenProduct: onOpenProduct,
              ),
              childCount: dashboard.recommendations.length,
            ),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 14,
              childAspectRatio: 0.69,
            ),
          ),
        ),
    ],
  );
}

final class _ShopProductCard extends StatelessWidget {
  const _ShopProductCard({required this.product, this.onOpenProduct});

  final ProductSummary product;
  final ValueChanged<String>? onOpenProduct;

  @override
  Widget build(BuildContext context) {
    final card = CatalogRecommendationCard(
      key: ValueKey<String>('shop-recommendation-${product.id}'),
      product: product,
      borderRadius: 8,
    );
    if (onOpenProduct == null) {
      return card;
    }
    return InkWell(
      key: ValueKey<String>('shop-open-product-${product.id}'),
      borderRadius: BorderRadius.circular(8),
      onTap: () => onOpenProduct!(product.id),
      child: card,
    );
  }
}

double _responsiveSidePadding(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  return width > _contentMaxWidth ? (width - _contentMaxWidth) / 2 + 20 : 20;
}

final class _ShopSliver extends StatelessWidget {
  const _ShopSliver({required this.child, required this.padding, super.key});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}

final class _ShopHeader extends StatelessWidget {
  const _ShopHeader({this.onOpenSearch});

  final VoidCallback? onOpenSearch;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text('Shop', style: _raleway(size: 28, height: 36 / 28)),
      const SizedBox(width: 20),
      Expanded(
        child: InkWell(
          key: const ValueKey('shop-search'),
          onTap: onOpenSearch,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Search',
                    style: _raleway(
                      size: 16,
                      weight: FontWeight.w500,
                      color: const Color(0xFFC7C7C7),
                    ),
                  ),
                ),
                const Icon(
                  Icons.image_search_outlined,
                  size: 21,
                  color: AppColors.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

final class _PromotionSection extends StatelessWidget {
  const _PromotionSection({
    required this.promotions,
    this.onOpenFlashSale,
    this.onOpenLive,
    this.onOpenStory,
  });

  final List<ShopPromotion> promotions;
  final VoidCallback? onOpenFlashSale;
  final VoidCallback? onOpenLive;
  final VoidCallback? onOpenStory;

  @override
  Widget build(BuildContext context) {
    if (promotions.isEmpty) {
      return const CatalogEmptySection(label: 'No promotions available.');
    }
    final promotion = promotions.first;
    return Column(
      children: [
        SizedBox(
          key: const ValueKey('shop-big-sale-banner'),
          height: 130,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CatalogAssetImage(assetKey: promotion.imageAssetKey),
                Positioned(
                  left: 18,
                  top: 11,
                  right: 150,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          promotion.title,
                          maxLines: 1,
                          style: _raleway(size: 29, color: Colors.white),
                        ),
                      ),
                      Text(
                        promotion.subtitle,
                        maxLines: 1,
                        style: _nunito(
                          size: 12,
                          weight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 18,
                  bottom: 12,
                  child: Text(
                    promotion.badge.replaceFirst(' ', '\n'),
                    maxLines: 2,
                    style: _raleway(size: 11, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 9),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('shop-flash-sale'),
              onPressed: onOpenFlashSale,
              icon: const Icon(Icons.local_offer_outlined),
              label: const Text('Flash Sale'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('shop-live'),
              onPressed: onOpenLive,
              icon: const Icon(Icons.live_tv_outlined),
              label: const Text('Live'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('shop-story'),
              onPressed: onOpenStory,
              icon: const Icon(Icons.auto_stories_outlined),
              label: const Text('Stories'),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var index = 0; index < 5; index += 1)
              Container(
                width: index == 0 ? 20 : 8,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: index == 0
                      ? AppColors.primary
                      : AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

final class _CategoriesSection extends StatelessWidget {
  const _CategoriesSection({required this.categories});

  final List<CategorySummary> categories;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const CatalogSectionHeader(
        title: 'Categories',
        showSeeAll: true,
        actionTextSize: 15,
        actionRadius: 15,
      ),
      const SizedBox(height: 9),
      if (categories.isEmpty)
        const CatalogEmptySection(label: 'No categories available.')
      else
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 6.0;
            final width = (constraints.maxWidth - spacing) / 2;
            return Wrap(
              spacing: spacing,
              runSpacing: 6,
              children: [
                for (final category in categories)
                  SizedBox(
                    width: width,
                    height: 192,
                    child: CatalogCategoryCard(category: category),
                  ),
              ],
            );
          },
        ),
    ],
  );
}

final class _TopProductsSection extends StatelessWidget {
  const _TopProductsSection({required this.products, this.onOpenProduct});

  final List<ProductSummary> products;
  final ValueChanged<String>? onOpenProduct;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const CatalogSectionHeader(title: 'Top Products'),
      const SizedBox(height: 9),
      if (products.isEmpty)
        const CatalogEmptySection(label: 'No top products available.')
      else
        SizedBox(
          height: 60,
          child: ListView.separated(
            key: const ValueKey('shop-top-products-list'),
            scrollDirection: Axis.horizontal,
            itemCount: products.length,
            separatorBuilder: (context, index) => const SizedBox(width: 9),
            itemBuilder: (context, index) => _ShopProductTapTarget(
              product: products[index],
              onOpenProduct: onOpenProduct,
              child: CatalogTopProductCard(
                product: products[index],
                showLabel: false,
              ),
            ),
          ),
        ),
    ],
  );
}

final class _NewItemsSection extends StatelessWidget {
  const _NewItemsSection({required this.products, this.onOpenProduct});

  final List<ProductSummary> products;
  final ValueChanged<String>? onOpenProduct;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const CatalogSectionHeader(
        title: 'New Items',
        showSeeAll: true,
        actionTextSize: 15,
        actionRadius: 15,
      ),
      const SizedBox(height: 9),
      if (products.isEmpty)
        const CatalogEmptySection(label: 'No new items available.')
      else
        SizedBox(
          height: 232,
          child: ListView.separated(
            key: const ValueKey('shop-new-items-list'),
            scrollDirection: Axis.horizontal,
            itemCount: products.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) => _ShopProductTapTarget(
              product: products[index],
              onOpenProduct: onOpenProduct,
              child: CatalogProductCard(
                product: products[index],
                width: 140,
                imageAspectRatio: 1,
                imagePadding: const EdgeInsets.all(5),
                frameImage: true,
                borderRadius: 8,
                titleSize: 12,
                priceSize: 17,
              ),
            ),
          ),
        ),
    ],
  );
}

final class _FlashSaleSection extends StatelessWidget {
  const _FlashSaleSection({required this.flashSale, this.onOpenProduct});

  final FlashSale flashSale;
  final ValueChanged<String>? onOpenProduct;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      CatalogSectionHeader(
        title: 'Flash Sale',
        trailing: _FlashCountdown(flashSale: flashSale),
      ),
      const SizedBox(height: 9),
      if (flashSale.products.isEmpty)
        const CatalogEmptySection(label: 'No Flash Sale items available.')
      else
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 8.0;
            final width = (constraints.maxWidth - spacing * 2) / 3;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final product in flashSale.products)
                  Container(
                    width: width,
                    height: width + 5,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: const [
                        BoxShadow(color: Color(0x18000000), blurRadius: 7),
                      ],
                    ),
                    child: _ShopProductTapTarget(
                      product: product,
                      onOpenProduct: onOpenProduct,
                      child: CatalogSaleCard(product: product),
                    ),
                  ),
              ],
            );
          },
        ),
    ],
  );
}

final class _MostPopularSection extends StatelessWidget {
  const _MostPopularSection({required this.products, this.onOpenProduct});

  final List<ProductSummary> products;
  final ValueChanged<String>? onOpenProduct;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const CatalogSectionHeader(
        title: 'Most Popular',
        showSeeAll: true,
        actionTextSize: 15,
        actionRadius: 15,
      ),
      const SizedBox(height: 9),
      if (products.isEmpty)
        const CatalogEmptySection(label: 'No popular items available.')
      else
        SizedBox(
          height: 162,
          child: ListView.separated(
            key: const ValueKey('shop-most-popular-list'),
            scrollDirection: Axis.horizontal,
            itemCount: products.length,
            separatorBuilder: (context, index) => const SizedBox(width: 7),
            itemBuilder: (context, index) => _ShopProductTapTarget(
              product: products[index],
              onOpenProduct: onOpenProduct,
              child: CatalogPopularCard(
                product: products[index],
                countSize: 15,
                tagSize: 15,
                borderRadius: 8,
                imageHeight: 112,
                imagePadding: const EdgeInsets.all(5),
                frameImage: true,
                showFavorite: true,
              ),
            ),
          ),
        ),
    ],
  );
}

final class _ShopProductTapTarget extends StatelessWidget {
  const _ShopProductTapTarget({
    required this.product,
    required this.child,
    this.onOpenProduct,
  });

  final ProductSummary product;
  final Widget child;
  final ValueChanged<String>? onOpenProduct;

  @override
  Widget build(BuildContext context) {
    if (onOpenProduct == null) {
      return child;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey<String>('shop-open-product-${product.id}'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => onOpenProduct!(product.id),
        child: child,
      ),
    );
  }
}

final class _FlashCountdown extends StatelessWidget {
  const _FlashCountdown({required this.flashSale});

  final FlashSale flashSale;

  @override
  Widget build(BuildContext context) => Row(
    key: const ValueKey('shop-flash-countdown'),
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.timer_outlined, size: 20, color: AppColors.primary),
      const SizedBox(width: 7),
      for (final value in <int>[
        flashSale.hours,
        flashSale.minutes,
        flashSale.seconds,
      ]) ...[
        Container(
          width: 28,
          height: 27,
          alignment: Alignment.center,
          margin: const EdgeInsets.only(left: 3),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(6),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value.toString().padLeft(2, '0'),
              style: _raleway(size: 17),
            ),
          ),
        ),
      ],
    ],
  );
}
