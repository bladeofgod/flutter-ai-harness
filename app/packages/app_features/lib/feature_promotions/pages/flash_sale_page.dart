import 'package:app_data/promotions.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../shared/catalog/catalog_asset_image.dart';
import '../../shared/catalog/catalog_components.dart';
import '../controllers/promotions_controllers.dart';

final class FlashSalePage extends StatelessWidget {
  const FlashSalePage({
    required this.controller,
    required this.onOpenProduct,
    super.key,
  });

  final FlashSaleController controller;
  final ValueChanged<String> onOpenProduct;

  @override
  Widget build(BuildContext context) => GetBuilder<FlashSaleController>(
    init: controller,
    global: false,
    autoRemove: false,
    dispose: (state) => state.controller.onDelete(),
    builder: (managedController) => Scaffold(
      appBar: AppBar(title: const Text('Flash Sale')),
      body: SafeArea(
        top: false,
        child: Obx(
          () => switch (managedController.state) {
            PromotionsLoading<Promotion>() => const Center(
              child: CircularProgressIndicator(
                key: ValueKey('flash-sale-loading'),
              ),
            ),
            PromotionsData<Promotion>(:final value) => _FlashSaleContent(
              promotion: value,
              onOpenProduct: onOpenProduct,
            ),
            PromotionsError<Promotion>(:final failure) => _PromotionsError(
              failure: failure,
              onRetry: managedController.retryFromUi,
            ),
          },
        ),
      ),
    ),
  );
}

final class _FlashSaleContent extends StatelessWidget {
  const _FlashSaleContent({
    required this.promotion,
    required this.onOpenProduct,
  });

  final Promotion promotion;
  final ValueChanged<String> onOpenProduct;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    key: const ValueKey('flash-sale-scroll'),
    slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
        sliver: SliverToBoxAdapter(
          child: AspectRatio(
            aspectRatio: 335 / 130,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CatalogAssetImage(assetKey: promotion.imageAssetKey),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: <Color>[Color(0xA6000000), Color(0x12000000)],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          promotion.title,
                          style: _raleway(
                            size: 26,
                            color: Colors.white,
                            height: 30 / 26,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          promotion.subtitle,
                          style: _nunito(size: 14, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        sliver: SliverToBoxAdapter(
          child: Row(
            children: [
              Expanded(child: Text('Deals for you', style: _raleway(size: 22))),
              _Countdown(value: promotion.flashSale.displayCountdown),
            ],
          ),
        ),
      ),
      if (promotion.flashSale.products.isEmpty)
        const SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverToBoxAdapter(
            child: CatalogEmptySection(label: 'No sale items available.'),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 190,
              mainAxisExtent: 252,
              crossAxisSpacing: 12,
              mainAxisSpacing: 18,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final product = promotion.flashSale.products[index];
              return Semantics(
                button: true,
                label: 'Open ${product.title}',
                child: InkWell(
                  key: ValueKey('flash-sale-product-${product.id}'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onOpenProduct(product.id),
                  child: CatalogProductCard(
                    product: product,
                    width: double.infinity,
                    imageAspectRatio: 1,
                    titleSize: 13,
                    priceSize: 15,
                  ),
                ),
              );
            }, childCount: promotion.flashSale.products.length),
          ),
        ),
    ],
  );
}

final class _Countdown extends StatelessWidget {
  const _Countdown({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Fixed sale countdown $value',
    child: Container(
      key: const ValueKey('flash-sale-countdown'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(value, style: _raleway(size: 13, color: AppColors.primary)),
    ),
  );
}

final class _PromotionsError extends StatelessWidget {
  const _PromotionsError({required this.failure, required this.onRetry});

  final PromotionsFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 40),
          const SizedBox(height: 12),
          Text(
            failure.code == PromotionsFailureCode.notFound
                ? 'Promotion not found'
                : 'Unable to load promotions',
            textAlign: TextAlign.center,
            style: _raleway(size: 20),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('promotions-retry'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

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

TextStyle _nunito({required double size, required Color color}) => TextStyle(
  fontFamily: AppFonts.nunitoSans,
  package: AppFonts.package,
  fontSize: size,
  color: color,
  letterSpacing: 0,
);
