import 'package:flutter/foundation.dart';

final class MediaPlaybackInfo {
  const MediaPlaybackInfo({required this.duration});

  final Duration duration;

  @override
  String toString() => 'MediaPlaybackInfo(metadata: <redacted>)';
}

final class MediaPoster {
  static const int maximumBytes = 524288;
  static const int maximumDimension = 512;

  MediaPoster._({
    required Uint8List bytes,
    required this.contentType,
    required this.width,
    required this.height,
  }) : _bytes = Uint8List.fromList(bytes);

  factory MediaPoster.png({
    required Uint8List bytes,
    required int width,
    required int height,
  }) {
    if (bytes.isEmpty ||
        bytes.length > maximumBytes ||
        width <= 0 ||
        height <= 0 ||
        width > maximumDimension ||
        height > maximumDimension ||
        !_isMetadataFreePng(bytes, width: width, height: height)) {
      throw ArgumentError('Invalid bounded media poster');
    }
    return MediaPoster._(
      bytes: bytes,
      contentType: 'image/png',
      width: width,
      height: height,
    );
  }

  final Uint8List _bytes;
  final String contentType;
  final int width;
  final int height;

  Uint8List get bytes => Uint8List.fromList(_bytes);

  @override
  String toString() => 'MediaPoster(bytes: <redacted>, metadata: <redacted>)';
}

final class MediaPreviewCancellation implements Listenable {
  bool _isCancelled = false;
  final Set<VoidCallback> _listeners = <VoidCallback>{};

  bool get isCancelled => _isCancelled;

  void cancel() {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    for (final listener in _listeners.toList()) {
      listener();
    }
  }

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  @override
  String toString() => 'MediaPreviewCancellation(<redacted>)';
}

bool _isMetadataFreePng(
  Uint8List bytes, {
  required int width,
  required int height,
}) {
  const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length < 8 ||
      !listEquals(bytes.sublist(0, signature.length), signature)) {
    return false;
  }
  var offset = signature.length;
  var sawHeader = false;
  var sawPalette = false;
  var sawImageData = false;
  var imageDataEnded = false;
  while (offset + 12 <= bytes.length) {
    final length = _readUint32(bytes, offset);
    final chunkEnd = offset + 12 + length;
    if (chunkEnd > bytes.length) return false;
    final typeOffset = offset + 4;
    final dataOffset = offset + 8;
    final storedCrc = _readUint32(bytes, dataOffset + length);
    if (_crc32(bytes, typeOffset, dataOffset + length) != storedCrc) {
      return false;
    }
    final isHeader = _matchesChunk(bytes, typeOffset, 73, 72, 68, 82);
    final isPalette = _matchesChunk(bytes, typeOffset, 80, 76, 84, 69);
    final isImageData = _matchesChunk(bytes, typeOffset, 73, 68, 65, 84);
    final isEnd = _matchesChunk(bytes, typeOffset, 73, 69, 78, 68);
    if (isHeader) {
      if (sawHeader || offset != signature.length || length != 13) return false;
      if (_readUint32(bytes, dataOffset) != width ||
          _readUint32(bytes, dataOffset + 4) != height) {
        return false;
      }
      sawHeader = true;
    } else if (isPalette) {
      if (!sawHeader || sawPalette || sawImageData || length == 0) return false;
      sawPalette = true;
    } else if (isImageData) {
      if (!sawHeader || imageDataEnded || length == 0) return false;
      sawImageData = true;
    } else if (isEnd) {
      return sawHeader &&
          sawImageData &&
          length == 0 &&
          chunkEnd == bytes.length;
    } else {
      return false;
    }
    if (sawImageData && !isImageData) imageDataEnded = true;
    offset = chunkEnd;
  }
  return false;
}

bool _matchesChunk(
  Uint8List bytes,
  int offset,
  int first,
  int second,
  int third,
  int fourth,
) {
  return bytes[offset] == first &&
      bytes[offset + 1] == second &&
      bytes[offset + 2] == third &&
      bytes[offset + 3] == fourth;
}

int _readUint32(Uint8List bytes, int offset) {
  return bytes[offset] << 24 |
      bytes[offset + 1] << 16 |
      bytes[offset + 2] << 8 |
      bytes[offset + 3];
}

int _crc32(Uint8List bytes, int start, int end) {
  var crc = 0xffffffff;
  for (var index = start; index < end; index += 1) {
    crc ^= bytes[index];
    for (var bit = 0; bit < 8; bit += 1) {
      crc = (crc & 1) == 1 ? 0xedb88320 ^ (crc >>> 1) : crc >>> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
