import 'package:app_data/app_data.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../shared/catalog/catalog_asset_image.dart';
import '../controllers/categories_controller.dart';

TextStyle _filterRaleway({
  required double size,
  FontWeight weight = FontWeight.w700,
  Color color = AppColors.textPrimary,
}) => TextStyle(
  fontFamily: AppFonts.raleway,
  package: AppFonts.package,
  fontSize: size,
  fontWeight: weight,
  color: color,
  letterSpacing: 0,
);

final class CategoriesFilterPage extends StatelessWidget {
  const CategoriesFilterPage({
    required this.controller,
    required this.onCancel,
    required this.onApply,
    super.key,
  });

  final CategoriesFilterController controller;
  final VoidCallback onCancel;
  final ValueChanged<CatalogFilter> onApply;

  @override
  Widget build(BuildContext context) => GetBuilder<CategoriesFilterController>(
    init: controller,
    global: false,
    autoRemove: false,
    dispose: (state) => state.controller.onDelete(),
    builder: (managedController) => Scaffold(
      body: SafeArea(
        bottom: false,
        child: Obx(() {
          final draft = managedController.draft;
          final expandedCategoryId = managedController.expandedCategoryId;
          return CustomScrollView(
            key: const ValueKey('categories-filter-scroll'),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 12, 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'All Categories',
                          style: _filterRaleway(size: 28),
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('categories-filter-close'),
                        tooltip: 'Cancel',
                        onPressed: onCancel,
                        icon: const Icon(Icons.close, size: 25),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 25),
                  child: _AudienceSelector(
                    selectedAudience: draft.audience,
                    onSelected: managedController.selectAudience,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                sliver: SliverList.builder(
                  itemCount: managedController.categories.length,
                  itemBuilder: (context, index) {
                    final category = managedController.categories[index];
                    final expanded = expandedCategoryId == category.id;
                    return _FilterCategoryPanel(
                      category: category,
                      expanded: expanded,
                      selectedSubcategoryId: draft.subcategoryId,
                      onToggle: () =>
                          managedController.toggleCategory(category.id),
                      onSelectSubcategory: (subcategoryId) => managedController
                          .selectSubcategory(category.id, subcategoryId),
                    );
                  },
                ),
              ),
            ],
          );
        }),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('categories-filter-reset'),
                  onPressed: managedController.reset,
                  child: const Text('Reset'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('categories-filter-apply'),
                  onPressed: () => onApply(managedController.draft),
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

final class _AudienceSelector extends StatelessWidget {
  const _AudienceSelector({
    required this.selectedAudience,
    required this.onSelected,
  });

  final CatalogAudience selectedAudience;
  final ValueChanged<CatalogAudience> onSelected;

  @override
  Widget build(BuildContext context) => Row(
    key: const ValueKey('categories-audience-selector'),
    children: [
      for (final audience in CatalogAudience.values) ...[
        if (audience != CatalogAudience.all) const SizedBox(width: 7),
        Expanded(
          child: _AudienceButton(
            audience: audience,
            selected: selectedAudience == audience,
            onTap: () => onSelected(audience),
          ),
        ),
      ],
    ],
  );
}

final class _AudienceButton extends StatelessWidget {
  const _AudienceButton({
    required this.audience,
    required this.selected,
    required this.onTap,
  });

  final CatalogAudience audience;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: InkWell(
      key: ValueKey<String>('audience-${audience.name}'),
      borderRadius: BorderRadius.circular(9),
      onTap: onTap,
      child: Container(
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySurface : AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(9),
          border: selected ? Border.all(color: AppColors.primary) : null,
        ),
        child: Text(
          switch (audience) {
            CatalogAudience.all => 'All',
            CatalogAudience.female => 'Female',
            CatalogAudience.male => 'Male',
          },
          style: _filterRaleway(
            size: selected ? 18 : 17,
            weight: FontWeight.w500,
            color: selected ? AppColors.primary : AppColors.textPrimary,
          ),
        ),
      ),
    ),
  );
}

final class _FilterCategoryPanel extends StatelessWidget {
  const _FilterCategoryPanel({
    required this.category,
    required this.expanded,
    required this.selectedSubcategoryId,
    required this.onToggle,
    required this.onSelectSubcategory,
  });

  final CatalogFilterCategory category;
  final bool expanded;
  final String? selectedSubcategoryId;
  final VoidCallback onToggle;
  final ValueChanged<String> onSelectSubcategory;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Column(
      children: [
        Material(
          color: Colors.white,
          elevation: 3,
          shadowColor: const Color(0x26000000),
          borderRadius: BorderRadius.circular(7),
          child: InkWell(
            key: ValueKey<String>('filter-category-${category.id}'),
            borderRadius: BorderRadius.circular(7),
            onTap: onToggle,
            child: SizedBox(
              height: 50,
              child: Row(
                children: [
                  const SizedBox(width: 3),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: SizedBox.square(
                      dimension: 44,
                      child: CatalogAssetImage(
                        assetKey: category.imageAssetKey,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(category.name, style: _filterRaleway(size: 17)),
                  ),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: expanded ? AppColors.primary : AppColors.textPrimary,
                  ),
                  const SizedBox(width: 10),
                ],
              ),
            ),
          ),
        ),
        if (expanded && category.subcategories.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 14),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: category.subcategories.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 9,
                mainAxisExtent: 41,
              ),
              itemBuilder: (context, index) {
                final subcategory = category.subcategories[index];
                final selected = selectedSubcategoryId == subcategory.id;
                return OutlinedButton(
                  key: ValueKey<String>('filter-subcategory-${subcategory.id}'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: selected
                        ? AppColors.primary
                        : AppColors.textPrimary,
                    side: BorderSide(
                      color: selected
                          ? AppColors.primary
                          : const Color(0xFFFFE0E0),
                      width: selected ? 2 : 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7),
                    ),
                    textStyle: _filterRaleway(size: 15),
                  ),
                  onPressed: () => onSelectSubcategory(subcategory.id),
                  child: Text(
                    subcategory.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
          ),
      ],
    ),
  );
}
