import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../shared/catalog/catalog_asset_image.dart';

/// Profile 用户头像专属的内存图片边界。
final class ProfileMemoryImage extends StatelessWidget {
  const ProfileMemoryImage({required this.bytes, super.key});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const CatalogImagePlaceholder(),
      Image.memory(
        bytes,
        fit: BoxFit.cover,
        excludeFromSemantics: true,
        errorBuilder: (context, error, stackTrace) =>
            const CatalogImagePlaceholder(),
      ),
    ],
  );
}
