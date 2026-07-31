import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_core/app_core.dart';
import 'package:app_features/api/support_media_picker.dart';
import 'package:app_features/feature_support/api/native_support_media_picker.dart';
import 'package:app_media/app_media.dart';
import 'package:app_media_capture_bridge/app_media_capture_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'support_test_fixtures.dart';

void main() {
  test(
    'gallery JPEG is imported before an owned attachment is returned',
    () async {
      final store = TestSupportMediaResourceStore();
      final picker = _picker(
        store: store,
        file: XFile.fromData(
          Uint8List.fromList(<int>[1, 2, 3]),
          mimeType: 'image/jpeg',
          name: 'damage.jpg',
          path: 'damage.jpg',
          length: 3,
        ),
      );
      addTearDown(picker.dispose);

      final result = await picker.pick(SupportMediaSource.gallery);

      final attachment = (result as SupportMediaPickSuccess).attachment;
      expect(attachment.type, SupportMediaType.image);
      expect(attachment.label, 'damage.jpg');
      expect(attachment.resource.initialLease.isActive, isTrue);
      expect(store.importCount, 1);
    },
  );

  test('gallery imports PNG MP4 and MOV with closed metadata', () async {
    const cases = <({String name, String mimeType, MediaResourceKind kind})>[
      (name: 'photo.png', mimeType: 'image/png', kind: MediaResourceKind.image),
      (name: 'clip.mp4', mimeType: 'video/mp4', kind: MediaResourceKind.video),
      (
        name: 'clip.mov',
        mimeType: 'video/quicktime',
        kind: MediaResourceKind.video,
      ),
    ];

    for (final testCase in cases) {
      final store = TestSupportMediaResourceStore();
      final picker = _picker(
        store: store,
        file: XFile.fromData(
          Uint8List.fromList(<int>[1, 2, 3]),
          mimeType: testCase.mimeType,
          name: testCase.name,
          path: testCase.name,
          length: 3,
        ),
      );

      final result = await picker.pick(SupportMediaSource.gallery);

      final attachment = (result as SupportMediaPickSuccess).attachment;
      expect(attachment.resource.kind, testCase.kind);
      expect(store.lastImportRequest?.declaredContentType, testCase.mimeType);
      await store.release(attachment.resource.initialLease);
      await picker.dispose();
    }
  });

  test('gallery cancellation and size rejection create no resource', () async {
    final canceledStore = TestSupportMediaResourceStore();
    final canceledPicker = _picker(store: canceledStore);
    expect(
      await canceledPicker.pick(SupportMediaSource.gallery),
      isA<SupportMediaPickCanceled>(),
    );
    expect(canceledStore.importCount, 0);
    await canceledPicker.dispose();

    final largeStore = TestSupportMediaResourceStore();
    final largePicker = _picker(
      store: largeStore,
      file: XFile.fromData(
        Uint8List.fromList(<int>[1]),
        mimeType: 'video/mp4',
        name: 'large.mp4',
        path: 'large.mp4',
        length: 50 * 1024 * 1024 + 1,
      ),
    );
    final result = await largePicker.pick(SupportMediaSource.gallery);
    expect(
      (result as SupportMediaPickFailed).failure.code,
      SupportMediaPickFailureCode.tooLarge,
    );
    expect(largeStore.importCount, 0);
    await largePicker.dispose();
  });

  test('gallery rejects formats outside JPEG PNG MP4 and MOV', () async {
    final store = TestSupportMediaResourceStore();
    final picker = _picker(
      store: store,
      file: XFile.fromData(
        Uint8List.fromList(<int>[1]),
        mimeType: 'image/webp',
        name: 'unsupported.webp',
        path: 'unsupported.webp',
        length: 1,
      ),
    );
    addTearDown(picker.dispose);

    final result = await picker.pick(SupportMediaSource.gallery);

    expect(
      (result as SupportMediaPickFailed).failure.code,
      SupportMediaPickFailureCode.invalidMedia,
    );
    expect(store.importCount, 0);
  });

  test('gallery video must pass a real playback probe', () async {
    final store = TestSupportMediaResourceStore();
    final picker = _picker(
      store: store,
      file: XFile.fromData(
        Uint8List.fromList(<int>[1, 2, 3]),
        mimeType: 'video/mp4',
        name: 'proof.mp4',
        path: 'proof.mp4',
        length: 3,
      ),
      probe: _FakePlaybackProbe(
        const MediaResourceError<MediaPlaybackInfo>(
          MediaResourceFailure(
            code: MediaResourceFailureCode.unsupportedMedia,
            isRecoverable: false,
          ),
        ),
      ),
    );
    addTearDown(picker.dispose);

    final result = await picker.pick(SupportMediaSource.gallery);

    expect(result, isA<SupportMediaPickFailed>());
    expect(store.releaseCount, 1);
  });

  test('failed initial lease release is retained for cleanup retry', () async {
    final store = TestSupportMediaResourceStore();
    final picker = _picker(
      store: store,
      file: XFile.fromData(
        Uint8List.fromList(<int>[1, 2, 3]),
        mimeType: 'image/jpeg',
        name: 'retry.jpg',
        path: 'retry.jpg',
        length: 3,
      ),
    );
    addTearDown(picker.dispose);
    final result = await picker.pick(SupportMediaSource.gallery);
    final attachment = (result as SupportMediaPickSuccess).attachment;
    store.releaseFailuresRemaining = 1;

    await picker.release(attachment);

    expect(attachment.resource.initialLease.isActive, isFalse);
    await picker.clearDrafts();
    expect(attachment.resource.initialLease.isActive, isFalse);
    expect(store.releaseCount, 1);
  });

  test('camera imports before releasing export and source leases', () async {
    final events = <String>[];
    final store = TestSupportMediaResourceStore(events: events);
    final gateway = _FakeCameraGateway(
      events: events,
      outcome: MediaCaptureFlowConfirmed(_confirmedVideo()),
    );
    final picker = _picker(store: store, gateway: gateway);
    addTearDown(picker.dispose);

    final result = await picker.pick(SupportMediaSource.camera);

    final attachment = (result as SupportMediaPickSuccess).attachment;
    expect(attachment.type, SupportMediaType.video);
    expect(attachment.duration, const Duration(milliseconds: 4200));
    expect(attachment.poster, isNotNull);
    expect(gateway.config?.maxVideoDurationMillis, 15000);
    expect(events.take(4), <String>[
      'materialize',
      'import',
      'release_export',
      'release_media',
    ]);
  });

  test('poster failure does not discard a playable camera video', () async {
    final store = TestSupportMediaResourceStore();
    final picker = _picker(
      store: store,
      gateway: _FakeCameraGateway(
        events: <String>[],
        outcome: MediaCaptureFlowConfirmed(_confirmedVideo()),
      ),
      poster: const _FakePosterService(
        MediaResourceError<MediaPoster>(
          MediaResourceFailure(
            code: MediaResourceFailureCode.decodeFailed,
            isRecoverable: true,
          ),
        ),
      ),
    );
    addTearDown(picker.dispose);

    final result = await picker.pick(SupportMediaSource.camera);

    final attachment = (result as SupportMediaPickSuccess).attachment;
    expect(attachment.poster, isNull);
    expect(attachment.resource.initialLease.isActive, isTrue);
  });

  test('camera import failure still releases export and source', () async {
    final events = <String>[];
    final store = TestSupportMediaResourceStore(events: events)
      ..nextImportFailure = const MediaResourceFailure(
        code: MediaResourceFailureCode.importFailed,
        isRecoverable: true,
      );
    final picker = _picker(
      store: store,
      gateway: _FakeCameraGateway(
        events: events,
        outcome: MediaCaptureFlowConfirmed(_confirmedVideo()),
      ),
    );
    addTearDown(picker.dispose);

    final result = await picker.pick(SupportMediaSource.camera);

    expect(result, isA<SupportMediaPickFailed>());
    expect(
      events,
      containsAllInOrder(<String>['release_export', 'release_media']),
    );
  });

  test(
    'cleanup failures are retained and converge during clearDrafts',
    () async {
      final store = TestSupportMediaResourceStore();
      final gateway = _FakeCameraGateway(
        events: <String>[],
        outcome: MediaCaptureFlowConfirmed(_confirmedVideo()),
        exportReleaseFailures: 1,
        mediaReleaseFailures: 1,
      );
      final picker = _picker(store: store, gateway: gateway);
      addTearDown(picker.dispose);

      final result = await picker.pick(SupportMediaSource.camera);
      expect(result, isA<SupportMediaPickSuccess>());

      await picker.clearDrafts();
      expect(gateway.exportReleaseCount, 1);
      expect(gateway.mediaReleaseCount, 1);
    },
  );

  test('clearDrafts dismisses an active camera presentation', () async {
    final events = <String>[];
    final pendingFlow = Completer<MediaCaptureFlowOutcome>();
    final gateway = _FakeCameraGateway(
      events: events,
      outcome: const MediaCaptureFlowCancelled(),
    )..pendingFlow = pendingFlow;
    final picker = NativeSupportMediaPicker.withDependencies(
      gateway,
      _FakeImagePicker(null),
      store: TestSupportMediaResourceStore(),
      playbackProbe: const _FakePlaybackProbe(
        MediaResourceError<MediaPlaybackInfo>(
          MediaResourceFailure(
            code: MediaResourceFailureCode.playbackFailed,
            isRecoverable: true,
          ),
        ),
      ),
      posterService: const _FakePosterService(
        MediaResourceError<MediaPoster>(
          MediaResourceFailure(
            code: MediaResourceFailureCode.decodeFailed,
            isRecoverable: true,
          ),
        ),
      ),
    );

    final pick = picker.pick(SupportMediaSource.camera);
    final clear = picker.clearDrafts();

    expect(await pick, isA<SupportMediaPickFailed>());
    await clear;
    expect(gateway.dismissCount, 1);
    await picker.dispose();
  });
}

NativeSupportMediaPicker _picker({
  required TestSupportMediaResourceStore store,
  XFile? file,
  _FakeCameraGateway? gateway,
  MediaPlaybackProbe? probe,
  MediaPosterService? poster,
}) {
  return NativeSupportMediaPicker.withDependencies(
    gateway ??
        _FakeCameraGateway(
          events: <String>[],
          outcome: const MediaCaptureFlowCancelled(),
        ),
    _FakeImagePicker(file),
    store: store,
    playbackProbe:
        probe ??
        const _FakePlaybackProbe(
          MediaResourceSuccess<MediaPlaybackInfo>(
            MediaPlaybackInfo(duration: Duration(milliseconds: 4200)),
          ),
        ),
    posterService:
        poster ??
        _FakePosterService(
          MediaResourceSuccess<MediaPoster>(
            MediaPoster.png(bytes: _onePixelPng(), width: 1, height: 1),
          ),
        ),
  );
}

MediaCaptureConfirmedMedia _confirmedVideo() => MediaCaptureConfirmedMedia(
  mediaHandle: MediaCaptureMediaHandle('support-video'),
  mediaType: MediaCaptureMediaType.video,
  pixelWidth: 1080,
  pixelHeight: 1920,
  durationMillis: 4200,
  orientationDegrees: 0,
  byteLength: 2048,
  leaseExpiresAtMillis: 10000,
);

Uint8List _onePixelPng() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8A'
  'AQUBAScY42YAAAAASUVORK5CYII=',
);

final class _FakeImagePicker extends ImagePicker {
  _FakeImagePicker(this.file);

  final XFile? file;

  @override
  Future<XFile?> pickMedia({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    bool requestFullMetadata = true,
  }) async => file;
}

final class _FakePlaybackProbe implements MediaPlaybackProbe {
  const _FakePlaybackProbe(this.result);

  final MediaResourceResult<MediaPlaybackInfo> result;

  @override
  Future<MediaResourceResult<MediaPlaybackInfo>> probe(
    MediaResourceId resourceId, {
    MediaPreviewCancellation? cancellation,
  }) async => result;
}

final class _FakePosterService implements MediaPosterService {
  const _FakePosterService(this.result);

  final MediaResourceResult<MediaPoster> result;

  @override
  Future<MediaResourceResult<MediaPoster>> generate(
    MediaResourceId resourceId, {
    MediaPreviewCancellation? cancellation,
  }) async => result;
}

final class _FakeCameraGateway implements SupportCameraMediaGateway {
  _FakeCameraGateway({
    required this.events,
    required this.outcome,
    this.exportReleaseFailures = 0,
    this.mediaReleaseFailures = 0,
  });

  final List<String> events;
  final MediaCaptureFlowOutcome outcome;
  int exportReleaseFailures;
  int mediaReleaseFailures;
  int exportReleaseCount = 0;
  int mediaReleaseCount = 0;
  MediaCaptureConfig? config;
  var dismissCount = 0;
  Completer<MediaCaptureFlowOutcome>? pendingFlow;

  @override
  Future<MediaCaptureFlowOutcome> presentCaptureFlow(
    MediaCaptureConfig config,
  ) async {
    this.config = config;
    return pendingFlow?.future ?? outcome;
  }

  @override
  Future<bool> dismissActivePresentation() async {
    dismissCount += 1;
    final pending = pendingFlow;
    if (pending != null && !pending.isCompleted) {
      pending.complete(const MediaCaptureFlowCancelled());
    }
    return true;
  }

  @override
  Future<MediaCaptureCallResult<MediaCaptureMaterializedMedia>>
  materializeMedia(MediaCaptureConfirmedMedia media) async {
    events.add('materialize');
    return MediaCaptureCallResult<MediaCaptureMaterializedMedia>.success(
      MediaCaptureMaterializedMedia(
        exportHandle: MediaCaptureExportHandle(
          'export_00000000000000000000000000000001',
        ),
        fileUri: Uri.file('/temporary/support-video.mp4'),
        mediaType: media.mediaType,
        contentType: 'video/mp4',
        byteLength: media.byteLength,
        durationMillis: media.durationMillis,
        expiresAtMillis: 300000,
        integritySha256: null,
      ),
    );
  }

  @override
  Future<MediaCaptureCallResult<MediaCaptureMaterializedMediaReleased>>
  releaseMaterializedMedia(MediaCaptureExportHandle exportHandle) async {
    if (exportReleaseFailures > 0) {
      exportReleaseFailures -= 1;
      return const MediaCaptureCallResult<
        MediaCaptureMaterializedMediaReleased
      >.failure(
        MediaCaptureFailure(code: MediaCaptureFailureCode.systemInterrupted),
      );
    }
    events.add('release_export');
    exportReleaseCount += 1;
    return const MediaCaptureCallResult<
      MediaCaptureMaterializedMediaReleased
    >.success(MediaCaptureMaterializedMediaReleased());
  }

  @override
  Future<MediaCaptureCallResult<MediaCaptureMediaReleased>> releaseMedia(
    MediaCaptureMediaHandle mediaHandle,
  ) async {
    if (mediaReleaseFailures > 0) {
      mediaReleaseFailures -= 1;
      return const MediaCaptureCallResult<MediaCaptureMediaReleased>.failure(
        MediaCaptureFailure(code: MediaCaptureFailureCode.systemInterrupted),
      );
    }
    events.add('release_media');
    mediaReleaseCount += 1;
    return MediaCaptureCallResult<MediaCaptureMediaReleased>.success(
      MediaCaptureMediaReleased(mediaHandle),
    );
  }

  @override
  Future<void> dispose() async {}
}
