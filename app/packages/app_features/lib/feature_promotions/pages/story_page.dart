import 'package:app_data/promotions.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../shared/catalog/catalog_asset_image.dart';
import '../controllers/promotions_controllers.dart';

final class StoryPage extends StatelessWidget {
  const StoryPage({
    required this.controller,
    required this.onClose,
    required this.onOpenProduct,
    super.key,
  });

  final StoryController controller;
  final VoidCallback onClose;
  final ValueChanged<String> onOpenProduct;

  @override
  Widget build(BuildContext context) => GetBuilder<StoryController>(
    init: controller,
    global: false,
    autoRemove: false,
    dispose: (state) => state.controller.onDelete(),
    builder: (managedController) => Scaffold(
      backgroundColor: const Color(0xFF11141B),
      body: SafeArea(
        child: Obx(
          () => switch (managedController.state) {
            PromotionsLoading<StorySequence>() => const Center(
              child: CircularProgressIndicator(
                key: ValueKey('story-loading'),
                color: Colors.white,
              ),
            ),
            PromotionsData<StorySequence>(:final value) => Obx(
              () => _StoryContent(
                sequence: value,
                currentIndex: managedController.currentIndex.value,
                controller: managedController,
                onClose: onClose,
                onOpenProduct: onOpenProduct,
              ),
            ),
            PromotionsError<StorySequence>(:final failure) => _StoryError(
              failure: failure,
              onRetry: managedController.retryFromUi,
              onClose: onClose,
            ),
          },
        ),
      ),
    ),
  );
}

final class _StoryContent extends StatelessWidget {
  const _StoryContent({
    required this.sequence,
    required this.currentIndex,
    required this.controller,
    required this.onClose,
    required this.onOpenProduct,
  });

  final StorySequence sequence;
  final int currentIndex;
  final StoryController controller;
  final VoidCallback onClose;
  final ValueChanged<String> onOpenProduct;

  @override
  Widget build(BuildContext context) {
    final index = currentIndex;
    final item = sequence.items[index];
    return LayoutBuilder(
      builder: (context, constraints) {
        final landscape = constraints.maxWidth > constraints.maxHeight;
        final media = _StoryMedia(item: item);
        final caption = _StoryCaption(item: item, onOpenProduct: onOpenProduct);
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Progress(sequence: sequence, currentIndex: index),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          sequence.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _storyText(size: 16, weight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('story-close'),
                        tooltip: 'Close story',
                        onPressed: onClose,
                        color: Colors.white,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: landscape
                        ? Row(
                            children: [
                              Expanded(flex: 3, child: media),
                              const SizedBox(width: 18),
                              Expanded(flex: 2, child: caption),
                            ],
                          )
                        : Column(
                            children: [
                              Expanded(child: media),
                              const SizedBox(height: 14),
                              caption,
                            ],
                          ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const ValueKey('story-previous'),
                          onPressed: index == 0 ? null : controller.previous,
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Previous'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFF747D8C)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          key: const ValueKey('story-next'),
                          onPressed: controller.next,
                          icon: Icon(
                            index == sequence.items.length - 1
                                ? Icons.close
                                : Icons.arrow_forward,
                          ),
                          label: Text(
                            index == sequence.items.length - 1
                                ? 'Finish'
                                : 'Next',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

final class _Progress extends StatelessWidget {
  const _Progress({required this.sequence, required this.currentIndex});

  final StorySequence sequence;
  final int currentIndex;

  @override
  Widget build(BuildContext context) => Semantics(
    key: const ValueKey('story-progress'),
    label: 'Story ${currentIndex + 1} of ${sequence.items.length}',
    child: Row(
      children: [
        for (var index = 0; index < sequence.items.length; index += 1)
          Expanded(
            child: Container(
              height: 3,
              margin: EdgeInsets.only(
                right: index == sequence.items.length - 1 ? 0 : 4,
              ),
              decoration: BoxDecoration(
                color: index <= currentIndex
                    ? Colors.white
                    : const Color(0xFF596171),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
      ],
    ),
  );
}

final class _StoryMedia extends StatelessWidget {
  const _StoryMedia({required this.item});

  final StoryItem item;

  @override
  Widget build(BuildContext context) => ClipRRect(
    key: ValueKey('story-item-${item.id}'),
    borderRadius: BorderRadius.circular(8),
    child: CatalogAssetImage(assetKey: item.imageAssetKey),
  );
}

final class _StoryCaption extends StatelessWidget {
  const _StoryCaption({required this.item, required this.onOpenProduct});

  final StoryItem item;
  final ValueChanged<String> onOpenProduct;

  @override
  Widget build(BuildContext context) => switch (item) {
    ProductStoryItem(:final product) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(item.title, style: _storyText(size: 23, weight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          '${product.title} · ${product.displayPrice}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: _storyText(size: 14, color: const Color(0xFFD0D5DE)),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const ValueKey('story-open-product'),
          onPressed: () => onOpenProduct(product.id),
          icon: const Icon(Icons.shopping_bag_outlined),
          label: const Text('View product'),
        ),
      ],
    ),
    BannerStoryItem(:final body) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(item.title, style: _storyText(size: 23, weight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          body,
          style: _storyText(
            size: 14,
            color: const Color(0xFFD0D5DE),
            height: 20 / 14,
          ),
        ),
      ],
    ),
  };
}

final class _StoryError extends StatelessWidget {
  const _StoryError({
    required this.failure,
    required this.onRetry,
    required this.onClose,
  });

  final PromotionsFailure failure;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            failure.code == PromotionsFailureCode.notFound
                ? 'Story not found'
                : 'Unable to load this story',
            textAlign: TextAlign.center,
            style: _storyText(size: 20, weight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('story-retry'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
          TextButton(onPressed: onClose, child: const Text('Close')),
        ],
      ),
    ),
  );
}

TextStyle _storyText({
  required double size,
  FontWeight weight = FontWeight.w400,
  Color color = Colors.white,
  double? height,
}) => TextStyle(
  fontFamily: weight == FontWeight.w700
      ? AppFonts.raleway
      : AppFonts.nunitoSans,
  package: AppFonts.package,
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
  letterSpacing: 0,
);
