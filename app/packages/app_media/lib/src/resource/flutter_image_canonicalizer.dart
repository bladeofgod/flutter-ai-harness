import 'dart:typed_data';
import 'dart:ui' as ui;

import 'media_resource_support.dart';

final class FlutterMediaImageCanonicalizer implements MediaImageCanonicalizer {
  const FlutterMediaImageCanonicalizer();

  static const int maximumDimension = 8192;
  static const int maximumDecodedBytes = 64 * 1024 * 1024;
  static const int _decodedBytesPerPixel = 4;

  static bool acceptsDimensions(int width, int height) {
    return width > 0 &&
        height > 0 &&
        width <= maximumDimension &&
        height <= maximumDimension &&
        width * height <= maximumDecodedBytes ~/ _decodedBytesPerPixel;
  }

  @override
  Future<CanonicalImage> canonicalize(Uint8List encodedBytes) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(encodedBytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (!acceptsDimensions(descriptor.width, descriptor.height)) {
        throw const UnsupportedMediaException();
      }

      codec = await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();
      image = frame.image;
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw const UnsupportedMediaException();
      }
      return CanonicalImage(
        bytes: byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        ),
        contentType: 'image/png',
      );
    } on UnsupportedMediaException {
      rethrow;
    } on Object {
      throw const UnsupportedMediaException();
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}
