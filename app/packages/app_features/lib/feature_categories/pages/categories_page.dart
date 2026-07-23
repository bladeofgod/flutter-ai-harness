import 'dart:async';

import 'package:app_data/app_data.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../shared/catalog/catalog_asset_image.dart';
import '../../shared/catalog/catalog_components.dart';
import '../controllers/categories_controller.dart';

typedef OpenCategoriesFilter =
    Future<CatalogFilter?> Function(
      CatalogFilter initialFilter,
      List<CatalogFilterCategory> categories,
    );

const _contentMaxWidth = 420.0;
const _headerHeight = 51.0;

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

final class CategoriesPage extends StatelessWidget {
  const CategoriesPage({
    required this.controller,
    required this.openFilter,
    required this.onProductSelected,
    super.key,
  });

  final CategoriesController controller;
  final OpenCategoriesFilter openFilter;
  final ValueChanged<String> onProductSelected;

  @override
  Widget build(BuildContext context) => GetBuilder<CategoriesController>(
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
            CategoriesLoading() => const Center(
              child: CircularProgressIndicator(
                key: ValueKey('categories-loading'),
              ),
            ),
            CategoriesData(:final result) ||
            CategoriesEmpty(:final result) => _CategoriesContent(
              controller: managedController,
              result: result,
              openFilter: openFilter,
              onProductSelected: onProductSelected,
            ),
            CategoriesError() => _CategoriesError(
              onRetry: managedController.retryFromUi,
            ),
          };
        }),
      ),
    ),
  );
}

final class _CategoriesContent extends StatelessWidget {
  const _CategoriesContent({
    required this.controller,
    required this.result,
    required this.openFilter,
    required this.onProductSelected,
  });

  final CategoriesController controller;
  final CatalogBrowseResult result;
  final OpenCategoriesFilter openFilter;
  final ValueChanged<String> onProductSelected;

  @override
  Widget build(BuildContext context) {
    final category = result.selectedCategory;
    final subcategories =
        category?.subcategories ?? const <CatalogSubcategory>[];
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.axis == Axis.vertical) {
          controller.setScrolled(notification.metrics.pixels > 190);
        }
        return false;
      },
      child: CustomScrollView(
        key: const ValueKey('categories-scroll'),
        slivers: [
          SliverAppBar(
            key: const ValueKey('categories-pinned-header'),
            pinned: true,
            automaticallyImplyLeading: false,
            backgroundColor: AppColors.background,
            surfaceTintColor: Colors.transparent,
            toolbarHeight: _headerHeight,
            collapsedHeight: _headerHeight,
            expandedHeight: _headerHeight,
            titleSpacing: 0,
            title: _CenteredContent(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _CategoriesHeader(
                  controller: controller,
                  categoryName: category?.name ?? 'Categories',
                  onFilter: () => unawaited(_openFilter(result.categories)),
                ),
              ),
            ),
          ),
          if (subcategories.isNotEmpty)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                _responsiveSidePadding(context),
                20,
                _responsiveSidePadding(context),
                17,
              ),
              sliver: SliverGrid(
                key: const ValueKey('categories-subcategory-grid'),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _SubcategoryItem(
                    subcategory: subcategories[index],
                    selected:
                        result.query.filter.subcategoryId ==
                        subcategories[index].id,
                    onTap: () => unawaited(
                      controller.selectSubcategory(subcategories[index].id),
                    ),
                  ),
                  childCount: subcategories.length,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 9,
                  mainAxisExtent: 85,
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: _CenteredContent(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 9),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        result.query.filter.subcategoryId == null
                            ? 'All Items'
                            : _selectedSubcategoryName(result) ?? 'All Items',
                        style: _raleway(size: 21, height: 30 / 21),
                      ),
                    ),
                    Obx(
                      () => controller.isScrolled
                          ? const SizedBox.square(dimension: 25)
                          : _FilterButton(
                              buttonKey: const ValueKey(
                                'categories-list-filter',
                              ),
                              onPressed: () =>
                                  unawaited(_openFilter(result.categories)),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (result.products.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  'No items match these filters.',
                  key: ValueKey('categories-empty'),
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                _responsiveSidePadding(context),
                0,
                _responsiveSidePadding(context),
                28,
              ),
              sliver: SliverGrid(
                key: const ValueKey('categories-product-grid'),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _CategoriesProductCard(
                    product: result.products[index],
                    onTap: () => onProductSelected(result.products[index].id),
                  ),
                  childCount: result.products.length,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 14,
                  childAspectRatio: 0.62,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openFilter(List<CatalogFilterCategory> categories) async {
    final filter = await openFilter(controller.appliedFilter, categories);
    if (filter != null) {
      await controller.applyFilter(filter);
    }
  }
}

final class _CategoriesHeader extends StatelessWidget {
  const _CategoriesHeader({
    required this.controller,
    required this.categoryName,
    required this.onFilter,
  });

  final CategoriesController controller;
  final String categoryName;
  final VoidCallback onFilter;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text('Shop', style: _raleway(size: 28, height: 36 / 28)),
      const SizedBox(width: 19),
      Expanded(
        child: Container(
          key: const ValueKey('categories-query-chip'),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.primarySurface,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  categoryName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _raleway(
                    size: 16,
                    weight: FontWeight.w500,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.close, size: 14, color: Color(0xFF7D9BF0)),
              const Spacer(),
              const Icon(
                Icons.photo_camera_outlined,
                size: 21,
                color: AppColors.primary,
              ),
            ],
          ),
        ),
      ),
      Obx(
        () => controller.isScrolled
            ? Padding(
                padding: const EdgeInsets.only(left: 12),
                child: _FilterButton(
                  buttonKey: const ValueKey('categories-header-filter'),
                  onPressed: onFilter,
                ),
              )
            : const SizedBox.shrink(),
      ),
    ],
  );
}

final class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.onPressed, this.buttonKey});

  final VoidCallback onPressed;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) => IconButton(
    key: buttonKey,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 25, height: 25),
    tooltip: 'Filter categories',
    onPressed: onPressed,
    icon: const Icon(Icons.tune, size: 22, color: AppColors.textPrimary),
  );
}

final class _SubcategoryItem extends StatelessWidget {
  const _SubcategoryItem({
    required this.subcategory,
    required this.selected,
    required this.onTap,
  });

  final CatalogSubcategory subcategory;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    label: subcategory.name,
    child: InkWell(
      key: ValueKey<String>('subcategory-${subcategory.id}'),
      borderRadius: BorderRadius.circular(32),
      onTap: onTap,
      child: Column(
        children: [
          SizedBox(
            height: 60,
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: selected
                        ? Border.all(color: AppColors.primary, width: 2)
                        : null,
                    boxShadow: const [
                      BoxShadow(color: Color(0x26000000), blurRadius: 8),
                    ],
                  ),
                  child: ClipOval(
                    child: CatalogAssetImage(
                      assetKey: subcategory.imageAssetKey,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(subcategory.name, style: _raleway(size: 13)),
            ),
          ),
        ],
      ),
    ),
  );
}

final class _CategoriesProductCard extends StatelessWidget {
  const _CategoriesProductCard({required this.product, required this.onTap});

  final ProductSummary product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      key: ValueKey<String>('categories-product-${product.id}'),
      borderRadius: BorderRadius.circular(9),
      onTap: onTap,
      child: CatalogProductCard(
        product: product,
        width: double.infinity,
        imageAspectRatio: 165 / 181,
        imagePadding: const EdgeInsets.all(5),
        frameImage: true,
        titleSize: 12,
        priceSize: 17,
      ),
    ),
  );
}

final class _CategoriesError extends StatelessWidget {
  const _CategoriesError({required this.onRetry});

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
          Text('Unable to load categories', style: _raleway(size: 20)),
          const SizedBox(height: 6),
          Text('Please try again.', style: _nunito(size: 14)),
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const ValueKey('categories-retry'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

final class _CenteredContent extends StatelessWidget {
  const _CenteredContent({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
      child: child,
    ),
  );
}

double _responsiveSidePadding(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  return width > _contentMaxWidth ? (width - _contentMaxWidth) / 2 + 20 : 20;
}

String? _selectedSubcategoryName(CatalogBrowseResult result) {
  final selectedId = result.query.filter.subcategoryId;
  for (final category in result.categories) {
    for (final subcategory in category.subcategories) {
      if (subcategory.id == selectedId) {
        return subcategory.name;
      }
    }
  }
  return null;
}
