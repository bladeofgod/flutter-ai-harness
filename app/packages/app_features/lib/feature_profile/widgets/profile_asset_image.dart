import 'dart:typed_data';

import 'package:flutter/material.dart';

/// 固定占位尺寸的 Profile 本地图片。
final class ProfileAssetImage extends StatelessWidget {
  const ProfileAssetImage({
    required this.assetKey,
    this.fit = BoxFit.cover,
    super.key,
  });

  final String assetKey;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const ProfileImagePlaceholder(),
      Image.asset(
        assetKey,
        package: 'app_features',
        fit: fit,
        excludeFromSemantics: true,
        errorBuilder: (context, error, stackTrace) =>
            const ProfileImagePlaceholder(),
      ),
    ],
  );
}

final class ProfileMemoryImage extends StatelessWidget {
  const ProfileMemoryImage({required this.bytes, super.key});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const ProfileImagePlaceholder(),
      Image.memory(
        bytes,
        fit: BoxFit.cover,
        excludeFromSemantics: true,
        errorBuilder: (context, error, stackTrace) =>
            const ProfileImagePlaceholder(),
      ),
    ],
  );
}

final class ProfileImagePlaceholder extends StatelessWidget {
  const ProfileImagePlaceholder({super.key});

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Color(0xFFF1F3F8),
    child: Center(
      child: Icon(Icons.image_outlined, color: Color(0xFF8B95A8), size: 24),
    ),
  );
}
