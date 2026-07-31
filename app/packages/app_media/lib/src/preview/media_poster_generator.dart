import 'dart:typed_data';

abstract interface class MediaPosterGenerator {
  Future<Uint8List?> generateJpeg(
    Uri fileUri, {
    required int maximumDimension,
    required int quality,
  });
}
