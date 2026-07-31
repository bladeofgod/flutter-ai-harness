import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../resource/flutter_image_canonicalizer.dart';

final class MediaPreviewImageDescriptor {
  const MediaPreviewImageDescriptor({
    required this.width,
    required this.height,
  });

  final int width;
  final int height;
}

abstract interface class MediaPreviewImageInspector {
  Future<MediaPreviewImageDescriptor?> inspect(Uri fileUri);
}

final class FlutterMediaPreviewImageInspector
    implements MediaPreviewImageInspector {
  const FlutterMediaPreviewImageInspector();

  @override
  Future<MediaPreviewImageDescriptor?> inspect(Uri fileUri) async {
    if (!fileUri.isScheme('file')) return null;
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      buffer = await ui.ImmutableBuffer.fromFilePath(fileUri.toFilePath());
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (!FlutterMediaImageCanonicalizer.acceptsDimensions(
        descriptor.width,
        descriptor.height,
      )) {
        return null;
      }
      return MediaPreviewImageDescriptor(
        width: descriptor.width,
        height: descriptor.height,
      );
    } on Object {
      return null;
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}

final class MediaPreviewImagePolicy {
  const MediaPreviewImagePolicy._();

  static const double maximumViewerScale = 4;
  static const int maximumDecodeDimension = 4096;
  static const int maximumDecodePixels = 16 * 1024 * 1024;

  static bool acceptsSource(MediaPreviewImageDescriptor source) {
    return FlutterMediaImageCanonicalizer.acceptsDimensions(
      source.width,
      source.height,
    );
  }

  static (int, int) viewerDecodeSize({
    required MediaPreviewImageDescriptor source,
    required Size viewport,
    required double devicePixelRatio,
  }) {
    final widthScale = viewport.width / source.width;
    final heightScale = viewport.height / source.height;
    final containScale = widthScale < heightScale ? widthScale : heightScale;
    final requestedScale = containScale * devicePixelRatio * maximumViewerScale;
    var targetScale = requestedScale.clamp(0.0, 1.0);
    targetScale = _boundedScale(source, targetScale);
    return (
      (source.width * targetScale).ceil().clamp(1, source.width),
      (source.height * targetScale).ceil().clamp(1, source.height),
    );
  }

  static (int, int) thumbnailDecodeSize({
    required MediaPreviewImageDescriptor source,
    required Size logicalSize,
    required double devicePixelRatio,
  }) {
    final requestedScale = <double>[
      logicalSize.width * devicePixelRatio / source.width,
      logicalSize.height * devicePixelRatio / source.height,
    ].reduce((left, right) => left > right ? left : right);
    final targetScale = _boundedScale(source, requestedScale.clamp(0.0, 1.0));
    return (
      (source.width * targetScale).ceil().clamp(1, source.width),
      (source.height * targetScale).ceil().clamp(1, source.height),
    );
  }

  static double _boundedScale(
    MediaPreviewImageDescriptor source,
    double requestedScale,
  ) {
    final dimensionScale =
        maximumDecodeDimension /
        (source.width > source.height ? source.width : source.height);
    final pixelScale = math.sqrt(
      maximumDecodePixels / (source.width * source.height),
    );
    return <double>[
      requestedScale,
      dimensionScale,
      pixelScale,
    ].reduce((left, right) => left < right ? left : right).clamp(0.0, 1.0);
  }
}
