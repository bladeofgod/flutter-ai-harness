import 'package:app_data/promotions.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../shared/catalog/catalog_asset_image.dart';
import '../controllers/promotions_controllers.dart';

final class LivePage extends StatelessWidget {
  const LivePage({
    required this.controller,
    required this.onOpenProduct,
    super.key,
  });

  final LiveController controller;
  final ValueChanged<String> onOpenProduct;

  @override
  Widget build(BuildContext context) => GetBuilder<LiveController>(
    init: controller,
    global: false,
    autoRemove: false,
    dispose: (state) => state.controller.onDelete(),
    builder: (managedController) => Scaffold(
      backgroundColor: const Color(0xFF10131A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF10131A),
        foregroundColor: Colors.white,
        title: const Text('Live Preview'),
      ),
      body: SafeArea(
        top: false,
        child: Obx(
          () => switch (managedController.state) {
            PromotionsLoading<LivePreview>() => const Center(
              child: CircularProgressIndicator(
                key: ValueKey('live-loading'),
                color: Colors.white,
              ),
            ),
            PromotionsData<LivePreview>(:final value) => _LiveContent(
              preview: value,
              controller: managedController,
              onOpenProduct: onOpenProduct,
            ),
            PromotionsError<LivePreview>() => Center(
              child: FilledButton.icon(
                key: const ValueKey('live-retry'),
                onPressed: managedController.retryFromUi,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry preview'),
              ),
            ),
          },
        ),
      ),
    ),
  );
}

final class _LiveContent extends StatelessWidget {
  const _LiveContent({
    required this.preview,
    required this.controller,
    required this.onOpenProduct,
  });

  final LivePreview preview;
  final LiveController controller;
  final ValueChanged<String> onOpenProduct;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final landscape = constraints.maxWidth > constraints.maxHeight;
      final visual = _PreviewVisual(preview: preview, controller: controller);
      final details = _LiveDetails(
        preview: preview,
        controller: controller,
        onOpenProduct: onOpenProduct,
      );
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: landscape
                ? Row(
                    children: [
                      Expanded(child: visual),
                      const SizedBox(width: 24),
                      Expanded(child: SingleChildScrollView(child: details)),
                    ],
                  )
                : Column(
                    children: [
                      Expanded(child: visual),
                      const SizedBox(height: 18),
                      details,
                    ],
                  ),
          ),
        ),
      );
    },
  );
}

final class _PreviewVisual extends StatelessWidget {
  const _PreviewVisual({required this.preview, required this.controller});

  final LivePreview preview;
  final LiveController controller;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: Stack(
      fit: StackFit.expand,
      children: [
        CatalogAssetImage(assetKey: preview.coverAssetKey),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0x18000000), Color(0xB8000000)],
            ),
          ),
        ),
        Positioned(
          left: 14,
          top: 14,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'DEMO LIVE',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
        Center(
          child: Obx(
            () => Icon(
              controller.isDemoPreviewReady.value
                  ? Icons.check_circle
                  : Icons.play_circle_fill,
              key: const ValueKey('live-demo-preview-state'),
              color: Colors.white,
              size: 64,
            ),
          ),
        ),
      ],
    ),
  );
}

final class _LiveDetails extends StatelessWidget {
  const _LiveDetails({
    required this.preview,
    required this.controller,
    required this.onOpenProduct,
  });

  final LivePreview preview;
  final LiveController controller;
  final ValueChanged<String> onOpenProduct;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(preview.title, style: _text(size: 23, weight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text(
        preview.subtitle,
        style: _text(size: 14, color: const Color(0xFFB9C0CE)),
      ),
      const SizedBox(height: 14),
      Semantics(
        button: true,
        label: 'Open ${preview.product.title}',
        child: OutlinedButton.icon(
          key: const ValueKey('live-open-product'),
          onPressed: () => onOpenProduct(preview.product.id),
          icon: const Icon(Icons.shopping_bag_outlined),
          label: Text(
            '${preview.product.title} · ${preview.product.displayPrice}',
            overflow: TextOverflow.ellipsis,
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFF626C7C)),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Obx(
        () => FilledButton.icon(
          key: const ValueKey('live-prepare-preview'),
          onPressed: controller.isDemoPreviewReady.value
              ? null
              : controller.prepareDemoPreview,
          icon: const Icon(Icons.play_arrow),
          label: Text(
            controller.isDemoPreviewReady.value
                ? 'Demo preview ready'
                : 'Prepare demo preview',
          ),
        ),
      ),
    ],
  );
}

TextStyle _text({
  required double size,
  FontWeight weight = FontWeight.w400,
  Color color = Colors.white,
}) => TextStyle(
  fontFamily: weight == FontWeight.w700
      ? AppFonts.raleway
      : AppFonts.nunitoSans,
  package: AppFonts.package,
  fontSize: size,
  fontWeight: weight,
  color: color,
  letterSpacing: 0,
);
