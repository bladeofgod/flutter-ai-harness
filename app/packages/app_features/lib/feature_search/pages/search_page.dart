import 'dart:async';
import 'dart:typed_data';

import 'package:app_data/search.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../api/search_image_picker.dart';
import '../../shared/catalog/catalog_asset_image.dart';
import '../../shared/catalog/catalog_components.dart';
import '../controllers/search_controller.dart';

typedef SearchProductSelected = void Function(String productId);

final class SearchPage extends StatelessWidget {
  const SearchPage({
    required this.controller,
    required this.onProductSelected,
    super.key,
  });

  final SearchFlowController controller;
  final SearchProductSelected onProductSelected;

  @override
  Widget build(BuildContext context) => GetBuilder<SearchFlowController>(
    init: controller,
    global: false,
    autoRemove: false,
    dispose: (state) => state.controller.onDelete(),
    builder: (managedController) => Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            _SearchHeader(controller: managedController),
            Expanded(
              child: _SearchBody(
                controller: managedController,
                onProductSelected: onProductSelected,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

final class _SearchHeader extends StatelessWidget {
  const _SearchHeader({required this.controller});

  final SearchFlowController controller;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Search',
          style: const TextStyle(
            fontFamily: AppFonts.raleway,
            package: AppFonts.package,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 13),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('search-input'),
                controller: controller.queryController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => controller.submit(),
                decoration: InputDecoration(
                  hintText: 'What are you looking for?',
                  filled: true,
                  fillColor: AppColors.formBackground,
                  prefixIcon: const Icon(Icons.search, size: 21),
                  suffixIcon: IconButton(
                    key: const ValueKey('search-image-entry'),
                    tooltip: 'Search with a photo',
                    onPressed: controller.isPickingImage
                        ? null
                        : () => unawaited(
                            _chooseSearchImageSource(context, controller),
                          ),
                    icon: controller.isPickingImage
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.image_search_outlined, size: 22),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              key: const ValueKey('search-filter'),
              tooltip: 'Filter search results',
              onPressed: () => _openFilter(context),
              icon: const Icon(Icons.tune, size: 20),
            ),
          ],
        ),
      ],
    ),
  );

  Future<void> _openFilter(BuildContext context) async {
    FocusScope.of(context).unfocus();
    controller.beginFilter();
    final apply = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _SearchFilterSheet(controller: controller),
    );
    if (apply ?? false) {
      await controller.applyFilter();
    } else {
      controller.cancelFilter();
    }
  }
}

final class _SearchBody extends StatelessWidget {
  const _SearchBody({
    required this.controller,
    required this.onProductSelected,
  });

  final SearchFlowController controller;
  final SearchProductSelected onProductSelected;

  @override
  Widget build(BuildContext context) {
    final imageFailure = controller.imagePickFailure;
    return Column(
      children: [
        if (imageFailure != null)
          _InlineMessage(
            key: const ValueKey('search-image-error'),
            message: _imageFailureMessage(imageFailure.code),
          ),
        Expanded(
          child: switch (controller.state) {
            SearchViewState.initial => _InitialSearch(
              onImageSearch: () =>
                  unawaited(_chooseSearchImageSource(context, controller)),
            ),
            SearchViewState.searching => const Center(
              child: CircularProgressIndicator(key: ValueKey('search-loading')),
            ),
            SearchViewState.results => _ProductResults(
              title: 'Search results',
              products: controller.textResult?.products ?? const [],
              onProductSelected: onProductSelected,
            ),
            SearchViewState.empty => const _EmptySearch(),
            SearchViewState.error => _SearchError(onRetry: controller.retry),
            SearchViewState.imageRecognizing => _ImageRecognition(
              bytes: controller.selectedImageBytes,
              recognizing: true,
            ),
            SearchViewState.imageRecognized => _ImageRecognition(
              bytes: controller.selectedImageBytes,
              recognizing: false,
              label: controller.imageResult?.recognizedLabel,
              onShowResults: controller.showImageResults,
            ),
            SearchViewState.imageResults => _ProductResults(
              title: controller.imageResult?.recognizedLabel ?? 'Similar items',
              subtitle: 'Demo visual match',
              products: controller.imageResult?.products ?? const [],
              onProductSelected: onProductSelected,
            ),
          },
        ),
      ],
    );
  }
}

enum _SearchImageSource { camera, gallery }

Future<void> _chooseSearchImageSource(
  BuildContext context,
  SearchFlowController controller,
) async {
  if (controller.isPickingImage) {
    return;
  }
  FocusScope.of(context).unfocus();
  final source = await showModalBottomSheet<_SearchImageSource>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => const _SearchImageSourceSheet(),
  );
  if (!context.mounted) {
    return;
  }
  switch (source) {
    case _SearchImageSource.camera:
      await controller.capturePhoto();
      return;
    case _SearchImageSource.gallery:
      await controller.pickImage();
      return;
    case null:
      return;
  }
}

final class _SearchImageSourceSheet extends StatelessWidget {
  const _SearchImageSourceSheet();

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      key: const ValueKey('search-image-source-sheet'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Add a photo',
            style: TextStyle(
              fontFamily: AppFonts.raleway,
              package: AppFonts.package,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            key: const ValueKey('search-image-source-camera'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.of(context).pop(_SearchImageSource.camera),
          ),
          ListTile(
            key: const ValueKey('search-image-source-gallery'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.of(context).pop(_SearchImageSource.gallery),
          ),
          TextButton(
            key: const ValueKey('search-image-source-cancel'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
  );
}

final class _InitialSearch extends StatelessWidget {
  const _InitialSearch({required this.onImageSearch});

  final VoidCallback onImageSearch;

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('search-initial'),
    padding: const EdgeInsets.fromLTRB(28, 56, 28, 32),
    children: [
      const Icon(Icons.search_rounded, size: 80, color: AppColors.primary),
      const SizedBox(height: 18),
      const Text(
        'Find your next favorite',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: AppFonts.raleway,
          package: AppFonts.package,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
      const SizedBox(height: 9),
      const Text(
        'Search by product name or add a photo.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: AppFonts.nunitoSans,
          package: AppFonts.package,
          fontSize: 14,
          height: 1.4,
          letterSpacing: 0,
        ),
      ),
      const SizedBox(height: 24),
      FilledButton.icon(
        key: const ValueKey('search-image-button'),
        onPressed: onImageSearch,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('Choose a photo'),
      ),
    ],
  );
}

final class _ProductResults extends StatelessWidget {
  const _ProductResults({
    required this.title,
    required this.products,
    required this.onProductSelected,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<ProductSummary> products;
  final SearchProductSelected onProductSelected;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    key: const ValueKey('search-results-scroll'),
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        sliver: SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontFamily: AppFonts.raleway,
                  package: AppFonts.package,
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: const TextStyle(
                    fontFamily: AppFonts.nunitoSans,
                    package: AppFonts.package,
                    fontSize: 13,
                    letterSpacing: 0,
                  ),
                ),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        sliver: SliverGrid.builder(
          itemCount: products.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 12,
            childAspectRatio: 0.62,
          ),
          itemBuilder: (context, index) {
            final product = products[index];
            return Semantics(
              button: true,
              child: InkWell(
                key: ValueKey('search-product-${product.id}'),
                onTap: () => onProductSelected(product.id),
                borderRadius: BorderRadius.circular(9),
                child: CatalogProductCard(
                  product: product,
                  width: double.infinity,
                  imageAspectRatio: 0.82,
                ),
              ),
            );
          },
        ),
      ),
    ],
  );
}

final class _EmptySearch extends StatelessWidget {
  const _EmptySearch();

  @override
  Widget build(BuildContext context) => const Center(
    key: ValueKey('search-empty'),
    child: Padding(
      padding: EdgeInsets.all(28),
      child: CatalogEmptySection(label: 'No items match this search.'),
    ),
  );
}

final class _SearchError extends StatelessWidget {
  const _SearchError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    key: const ValueKey('search-error'),
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Search is unavailable right now.'),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}

final class _ImageRecognition extends StatelessWidget {
  const _ImageRecognition({
    required this.bytes,
    required this.recognizing,
    this.label,
    this.onShowResults,
  });

  final Uint8List? bytes;
  final bool recognizing;
  final String? label;
  final VoidCallback? onShowResults;

  @override
  Widget build(BuildContext context) => ListView(
    key: ValueKey(recognizing ? 'search-recognizing' : 'search-recognized'),
    padding: const EdgeInsets.fromLTRB(28, 22, 28, 32),
    children: [
      Center(child: _ImagePreview(bytes: bytes)),
      const SizedBox(height: 24),
      if (recognizing) ...[
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 15),
        const Text(
          'Recognizing image...',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppFonts.raleway,
            package: AppFonts.package,
            fontSize: 21,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Demo recognition runs locally with a fixed result.',
          textAlign: TextAlign.center,
        ),
      ] else ...[
        const Text(
          'Image recognized',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppFonts.raleway,
            package: AppFonts.package,
            fontSize: 21,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label ?? 'Similar style',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, letterSpacing: 0),
        ),
        const SizedBox(height: 24),
        FilledButton(
          key: const ValueKey('search-show-image-results'),
          onPressed: onShowResults,
          child: const Text('Show similar items'),
        ),
      ],
    ],
  );
}

final class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.bytes});

  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey('search-image-preview'),
    width: 210,
    height: 240,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: bytes == null
          ? const CatalogImagePlaceholder()
          : Image.memory(
              bytes!,
              fit: BoxFit.cover,
              excludeFromSemantics: true,
              errorBuilder: (context, error, stackTrace) =>
                  const CatalogImagePlaceholder(),
            ),
    ),
  );
}

final class _InlineMessage extends StatelessWidget {
  const _InlineMessage({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF2F3),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(message),
  );
}

final class _SearchFilterSheet extends StatefulWidget {
  const _SearchFilterSheet({required this.controller});

  final SearchFlowController controller;

  @override
  State<_SearchFilterSheet> createState() => _SearchFilterSheetState();
}

final class _SearchFilterSheetState extends State<_SearchFilterSheet> {
  static const Map<String, String> _categories = <String, String>{
    'category-clothing': 'Clothing',
    'category-shoes': 'Shoes',
    'category-bags': 'Bags',
  };

  @override
  Widget build(BuildContext context) {
    final draft = widget.controller.draftFilter;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        key: const ValueKey('search-filter-sheet'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Filter',
                    style: TextStyle(
                      fontFamily: AppFonts.raleway,
                      package: AppFonts.package,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('search-filter-cancel'),
                  tooltip: 'Cancel filter',
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Shopping for'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final audience in CatalogAudience.values)
                  ChoiceChip(
                    label: Text(_audienceLabel(audience)),
                    selected: draft.audience == audience,
                    onSelected: (_) => setState(
                      () => widget.controller.selectDraftAudience(audience),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            const Text('Category'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in _categories.entries)
                  ChoiceChip(
                    key: ValueKey('search-filter-${category.key}'),
                    label: Text(category.value),
                    selected: draft.categoryId == category.key,
                    onSelected: (_) => setState(
                      () => widget.controller.selectDraftCategory(category.key),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 26),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('search-filter-apply'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Apply'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _audienceLabel(CatalogAudience audience) => switch (audience) {
  CatalogAudience.all => 'All',
  CatalogAudience.female => 'Women',
  CatalogAudience.male => 'Men',
};

String _imageFailureMessage(SearchImagePickFailureCode code) => switch (code) {
  SearchImagePickFailureCode.permissionDenied =>
    'Photo access was not granted.',
  SearchImagePickFailureCode.pickerUnavailable =>
    'The photo picker is unavailable.',
  SearchImagePickFailureCode.readFailed =>
    'The selected photo could not be read.',
  SearchImagePickFailureCode.tooLarge => 'Choose a photo smaller than 2 MB.',
  SearchImagePickFailureCode.invalidImage => 'Choose a valid image file.',
};
