import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:app_media/app_media.dart';
import 'package:app_media/src/preview/media_playback_driver.dart';
import 'package:flutter/widgets.dart';

final class FakeMediaResourceStore implements MediaResourceStore {
  FakeMediaResourceStore(this.resources);

  final Map<MediaResourceId, ResolvedMediaResource> resources;
  Completer<void>? retainGate;
  Completer<void>? resolveGate;
  int retainCalls = 0;
  int resolveCalls = 0;
  int releaseCalls = 0;
  int releaseAttempts = 0;
  final List<FakeMediaResourceLease> leases = <FakeMediaResourceLease>[];

  @override
  Future<MediaImportResult> importFile(MediaImportRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<MediaResourceResult<MediaResourceLease>> retain(
    MediaResourceId resourceId,
  ) async {
    retainCalls += 1;
    await retainGate?.future;
    if (!resources.containsKey(resourceId)) {
      return failure(MediaResourceFailureCode.missing);
    }
    final lease = FakeMediaResourceLease(resourceId);
    leases.add(lease);
    return MediaResourceResult<MediaResourceLease>.success(lease);
  }

  @override
  Future<MediaResourceResult<ResolvedMediaResource>> resolve(
    MediaResourceId resourceId,
    MediaResourceLease lease,
  ) async {
    resolveCalls += 1;
    await resolveGate?.future;
    final resource = resources[resourceId];
    if (resource == null) {
      return failure(MediaResourceFailureCode.missing);
    }
    if (!lease.isActive || lease.resourceId != resourceId) {
      return failure(MediaResourceFailureCode.invalidArgument);
    }
    return MediaResourceResult<ResolvedMediaResource>.success(resource);
  }

  @override
  Future<MediaResourceResult<void>> release(MediaResourceLease lease) async {
    releaseAttempts += 1;
    if (lease is FakeMediaResourceLease && lease.isActive) {
      lease.release();
      releaseCalls += 1;
    }
    return const MediaResourceResult<void>.success(null);
  }

  @override
  Future<void> dispose() async {}
}

final class FakeMediaResourceLease implements MediaResourceLease {
  FakeMediaResourceLease(this.resourceId);

  @override
  final MediaResourceId resourceId;
  bool _active = true;

  @override
  bool get isActive => _active;

  void release() => _active = false;
}

final class FakeMediaPlaybackDriverFactory
    implements MediaPlaybackDriverFactory {
  FakeMediaPlaybackDriverFactory(this.createDriver);

  final FakeMediaPlaybackDriver Function() createDriver;
  final List<Uri> requestedUris = <Uri>[];
  final List<FakeMediaPlaybackDriver> drivers = <FakeMediaPlaybackDriver>[];

  @override
  MediaPlaybackDriver create(Uri fileUri) {
    requestedUris.add(fileUri);
    final driver = createDriver();
    drivers.add(driver);
    return driver;
  }
}

final class FakeMediaPlaybackDriver implements MediaPlaybackDriver {
  FakeMediaPlaybackDriver({
    MediaPlaybackSnapshot snapshot =
        const MediaPlaybackSnapshot.uninitialized(),
    this.initializeGate,
    this.initializeError,
    this.disposeGate,
    this.disposeError,
  }) : _snapshot = snapshot;

  MediaPlaybackSnapshot _snapshot;
  final Completer<void>? initializeGate;
  final Object? initializeError;
  final Completer<void>? disposeGate;
  final Object? disposeError;
  final Set<VoidCallback> _listeners = <VoidCallback>{};
  int initializeCalls = 0;
  int playCalls = 0;
  int pauseCalls = 0;
  int seekCalls = 0;
  int disposeCalls = 0;

  @override
  MediaPlaybackSnapshot get snapshot => _snapshot;

  set snapshot(MediaPlaybackSnapshot value) {
    _snapshot = value;
    for (final listener in _listeners.toList()) {
      listener();
    }
  }

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
    await initializeGate?.future;
    final error = initializeError;
    if (error != null) {
      throw error;
    }
    snapshot = MediaPlaybackSnapshot(
      isInitialized: true,
      isPlaying: false,
      isCompleted: false,
      position: Duration.zero,
      duration: const Duration(minutes: 2),
      aspectRatio: 16 / 9,
      hasError: false,
    );
  }

  @override
  Future<void> play() async {
    playCalls += 1;
    snapshot = _copy(isPlaying: true, isCompleted: false);
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
    snapshot = _copy(isPlaying: false);
  }

  @override
  Future<void> seekTo(Duration position) async {
    seekCalls += 1;
    snapshot = _copy(position: position, isCompleted: false);
  }

  @override
  Widget buildSurface() => const ColoredBox(
    key: Key('fake-video-surface'),
    color: Color(0xff123456),
  );

  @override
  Future<void> dispose() async {
    if (disposeCalls == 0) {
      disposeCalls += 1;
      _listeners.clear();
      await disposeGate?.future;
      final error = disposeError;
      if (error != null) {
        throw error;
      }
    }
  }

  MediaPlaybackSnapshot _copy({
    bool? isPlaying,
    bool? isCompleted,
    Duration? position,
  }) {
    return MediaPlaybackSnapshot(
      isInitialized: _snapshot.isInitialized,
      isPlaying: isPlaying ?? _snapshot.isPlaying,
      isCompleted: isCompleted ?? _snapshot.isCompleted,
      position: position ?? _snapshot.position,
      duration: _snapshot.duration,
      aspectRatio: _snapshot.aspectRatio,
      hasError: _snapshot.hasError,
    );
  }
}

final class FakeMediaPreviewImageInspector
    implements MediaPreviewImageInspector {
  FakeMediaPreviewImageInspector({
    this.descriptor = const MediaPreviewImageDescriptor(width: 1, height: 1),
    this.gate,
  });

  final MediaPreviewImageDescriptor? descriptor;
  final Completer<void>? gate;
  int inspectCalls = 0;

  @override
  Future<MediaPreviewImageDescriptor?> inspect(Uri fileUri) async {
    inspectCalls += 1;
    await gate?.future;
    return descriptor;
  }
}

MediaResourceId testResourceId([String suffix = '0']) {
  return MediaResourceId('mr_${suffix.padLeft(32, '0')}');
}

ResolvedMediaResource testResource({
  required MediaResourceId id,
  required MediaResourceKind kind,
  required Uri fileUri,
}) {
  return ResolvedMediaResource(
    resourceId: id,
    kind: kind,
    contentType: kind == MediaResourceKind.image ? 'image/png' : 'video/mp4',
    length: 128,
    fileUri: fileUri,
    duration: kind == MediaResourceKind.video
        ? const Duration(minutes: 2)
        : null,
  );
}

MediaResourceError<T> failure<T>(MediaResourceFailureCode code) {
  return MediaResourceError<T>(
    MediaResourceFailure(code: code, isRecoverable: false),
  );
}
