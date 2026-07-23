import 'package:flutter/material.dart';

/// 为 Catalog 相关页面提供固定占位和错误降级的本地图片。
final class CatalogAssetImage extends StatelessWidget {
  const CatalogAssetImage({
    required this.assetKey,
    this.fit = BoxFit.cover,
    super.key,
  });

  final String assetKey;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final logicalWidth = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : 0;
      final cacheWidth = logicalWidth > 0
          ? (logicalWidth * MediaQuery.devicePixelRatioOf(context))
                .round()
                .clamp(1, 1600)
          : null;
      return Stack(
        fit: StackFit.expand,
        children: [
          const CatalogImagePlaceholder(),
          Image.asset(
            assetKey,
            package: 'app_features',
            fit: fit,
            cacheWidth: cacheWidth,
            excludeFromSemantics: true,
            errorBuilder: (context, error, stackTrace) =>
                const CatalogImagePlaceholder(),
          ),
        ],
      );
    },
  );
}

final class CatalogImagePlaceholder extends StatelessWidget {
  const CatalogImagePlaceholder({super.key});

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Color(0xFFF1F3F8),
    child: Center(
      child: Icon(Icons.image_outlined, color: Color(0xFF8B95A8), size: 24),
    ),
  );
}
