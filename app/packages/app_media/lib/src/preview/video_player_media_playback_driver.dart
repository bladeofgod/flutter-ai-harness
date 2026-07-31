import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import 'media_playback_driver.dart';

final class VideoPlayerMediaPlaybackDriverFactory
    implements MediaPlaybackDriverFactory {
  const VideoPlayerMediaPlaybackDriverFactory();

  @override
  MediaPlaybackDriver create(Uri fileUri) {
    return _VideoPlayerMediaPlaybackDriver(
      VideoPlayerController.file(
        File.fromUri(fileUri),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      ),
    );
  }
}

final class _VideoPlayerMediaPlaybackDriver extends ChangeNotifier
    implements MediaPlaybackDriver {
  _VideoPlayerMediaPlaybackDriver(this._controller) {
    _controller.addListener(_onValueChanged);
  }

  final VideoPlayerController _controller;
  bool _disposed = false;

  @override
  MediaPlaybackSnapshot get snapshot {
    final value = _controller.value;
    final ratio = value.aspectRatio.isFinite && value.aspectRatio > 0
        ? value.aspectRatio
        : 1.0;
    return MediaPlaybackSnapshot(
      isInitialized: value.isInitialized,
      isPlaying: value.isPlaying,
      isCompleted: value.isCompleted,
      position: value.position,
      duration: value.duration,
      aspectRatio: ratio,
      hasError: value.hasError,
    );
  }

  @override
  Future<void> initialize() async {
    try {
      await _controller.initialize();
      if (!_controller.value.isInitialized ||
          _controller.value.duration <= Duration.zero) {
        throw const UnsupportedMediaPlaybackException();
      }
      await _controller.pause();
    } on UnsupportedMediaPlaybackException {
      rethrow;
    } on Object {
      throw const UnsupportedMediaPlaybackException();
    }
  }

  @override
  Future<void> play() => _controller.play();

  @override
  Future<void> pause() => _controller.pause();

  @override
  Future<void> seekTo(Duration position) => _controller.seekTo(position);

  @override
  Widget buildSurface() => VideoPlayer(_controller);

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _controller.removeListener(_onValueChanged);
    await _controller.dispose();
    super.dispose();
  }

  void _onValueChanged() {
    if (!_disposed) {
      notifyListeners();
    }
  }
}
