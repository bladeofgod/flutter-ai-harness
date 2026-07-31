import 'package:flutter/widgets.dart';

final class MediaPlaybackSnapshot {
  const MediaPlaybackSnapshot({
    required this.isInitialized,
    required this.isPlaying,
    required this.isCompleted,
    required this.position,
    required this.duration,
    required this.aspectRatio,
    required this.hasError,
  });

  const MediaPlaybackSnapshot.uninitialized()
    : isInitialized = false,
      isPlaying = false,
      isCompleted = false,
      position = Duration.zero,
      duration = Duration.zero,
      aspectRatio = 1,
      hasError = false;

  final bool isInitialized;
  final bool isPlaying;
  final bool isCompleted;
  final Duration position;
  final Duration duration;
  final double aspectRatio;
  final bool hasError;
}

abstract interface class MediaPlaybackDriver implements Listenable {
  MediaPlaybackSnapshot get snapshot;

  Future<void> initialize();

  Future<void> play();

  Future<void> pause();

  Future<void> seekTo(Duration position);

  Widget buildSurface();

  Future<void> dispose();
}

abstract interface class MediaPlaybackDriverFactory {
  MediaPlaybackDriver create(Uri fileUri);
}

final class UnsupportedMediaPlaybackException implements Exception {
  const UnsupportedMediaPlaybackException();

  @override
  String toString() => 'UnsupportedMediaPlaybackException(<redacted>)';
}
