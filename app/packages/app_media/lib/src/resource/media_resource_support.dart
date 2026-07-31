import 'dart:math';
import 'dart:typed_data';

abstract interface class MediaResourceClock {
  DateTime now();
}

final class SystemMediaResourceClock implements MediaResourceClock {
  const SystemMediaResourceClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}

abstract interface class MediaResourceRandom {
  Uint8List nextBytes(int length);
}

final class SecureMediaResourceRandom implements MediaResourceRandom {
  SecureMediaResourceRandom() : _random = Random.secure();

  final Random _random;

  @override
  Uint8List nextBytes(int length) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => _random.nextInt(256)),
    );
  }
}

abstract interface class MediaImageCanonicalizer {
  Future<CanonicalImage> canonicalize(Uint8List encodedBytes);
}

final class CanonicalImage {
  const CanonicalImage({required this.bytes, required this.contentType});

  final Uint8List bytes;
  final String contentType;
}

final class UnsupportedMediaException implements Exception {
  const UnsupportedMediaException();

  @override
  String toString() => 'UnsupportedMediaException(details: <redacted>)';
}
