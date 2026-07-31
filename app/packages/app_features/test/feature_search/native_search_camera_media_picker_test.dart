import 'dart:async';

import 'package:app_features/api/search_image_picker.dart';
import 'package:app_features/feature_search/api/native_search_camera_media_picker.dart';
import 'package:app_media_capture_bridge/app_media_capture_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

import 'search_test_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'captures photo-only media, validates thumbnail and releases first',
    () async {
      final gateway = _FakeSearchCameraGateway();
      final picker = NativeSearchCameraMediaPicker.withGateway(gateway);

      final result = await picker.capturePhoto();

      final success = result as SearchImagePickSuccess;
      expect(success.bytes, validSearchJpeg());
      expect(gateway.operations, <String>['present', 'thumbnail', 'release']);
      expect(gateway.configs.single.enabledMediaTypes, <MediaCaptureMediaType>{
        MediaCaptureMediaType.photo,
      });
      expect(gateway.configs.single.audioEnabled, isFalse);
      expect(gateway.thumbnailRequests.single.maxPixelEdge, 512);
    },
  );

  test('keeps cancellation normal without thumbnail or release work', () async {
    final gateway = _FakeSearchCameraGateway()
      ..flowOutcome = const MediaCaptureFlowCancelled();
    final picker = NativeSearchCameraMediaPicker.withGateway(gateway);

    expect(await picker.capturePhoto(), isA<SearchImagePickCanceled>());
    expect(gateway.operations, <String>['present']);
  });

  test('maps thumbnail failure and releases confirmed media', () async {
    final gateway = _FakeSearchCameraGateway()
      ..thumbnailResult = const MediaCaptureCallResult.failure(
        MediaCaptureFailure(
          code: MediaCaptureFailureCode.thumbnailGenerationFailed,
        ),
      );
    final picker = NativeSearchCameraMediaPicker.withGateway(
      gateway,
      thumbnailDecoder: (_) async {},
    );

    final result = await picker.capturePhoto() as SearchImagePickFailed;

    expect(result.failure.code, SearchImagePickFailureCode.invalidImage);
    expect(gateway.operations, <String>['present', 'thumbnail', 'release']);
  });

  test('maps permission and generic flow failures to stable codes', () async {
    for (final testCase
        in <
          ({
            MediaCaptureFailureCode native,
            SearchImagePickFailureCode expected,
          })
        >[
          (
            native: MediaCaptureFailureCode.permissionDenied,
            expected: SearchImagePickFailureCode.permissionDenied,
          ),
          (
            native: MediaCaptureFailureCode.permissionRestricted,
            expected: SearchImagePickFailureCode.permissionDenied,
          ),
          (
            native: MediaCaptureFailureCode.systemInterrupted,
            expected: SearchImagePickFailureCode.pickerUnavailable,
          ),
        ]) {
      final gateway = _FakeSearchCameraGateway()
        ..flowOutcome = MediaCaptureFlowFailure(
          MediaCaptureFailure(code: testCase.native),
        );
      final picker = NativeSearchCameraMediaPicker.withGateway(gateway);

      final result = await picker.capturePhoto() as SearchImagePickFailed;

      expect(result.failure.code, testCase.expected);
      expect(gateway.releaseCount, 0);
    }
  });

  test('rejects a non-photo confirmation and mismatched thumbnail', () async {
    final videoGateway = _FakeSearchCameraGateway()
      ..flowOutcome = MediaCaptureFlowConfirmed(
        _confirmedMedia(
          handle: 'search-video-1',
          mediaType: MediaCaptureMediaType.video,
        ),
      );
    final videoPicker = NativeSearchCameraMediaPicker.withGateway(videoGateway);

    expect(await videoPicker.capturePhoto(), isA<SearchImagePickFailed>());
    expect(videoGateway.releaseCount, 1);
    expect(videoGateway.thumbnailRequests, isEmpty);

    final thumbnailGateway = _FakeSearchCameraGateway();
    thumbnailGateway.thumbnailResult = MediaCaptureCallResult.success(
      MediaCaptureThumbnail(
        mediaHandle: MediaCaptureMediaHandle('other-media'),
        bytes: validSearchJpeg(),
        pixelWidth: 1,
        pixelHeight: 1,
        contentType: 'image/jpeg',
        orientationDegrees: 0,
        mediaType: MediaCaptureMediaType.photo,
        posterFrameMillis: null,
      ),
    );
    final thumbnailPicker = NativeSearchCameraMediaPicker.withGateway(
      thumbnailGateway,
    );

    final result =
        await thumbnailPicker.capturePhoto() as SearchImagePickFailed;
    expect(result.failure.code, SearchImagePickFailureCode.invalidImage);
    expect(thumbnailGateway.releaseCount, 1);
  });

  test(
    'invalid decoded image releases media and returns stable failure',
    () async {
      final gateway = _FakeSearchCameraGateway();
      final picker = NativeSearchCameraMediaPicker.withGateway(
        gateway,
        thumbnailDecoder: (_) async => throw const FormatException(),
      );

      final result = await picker.capturePhoto() as SearchImagePickFailed;

      expect(result.failure.code, SearchImagePickFailureCode.invalidImage);
      expect(gateway.releaseCount, 1);
    },
  );

  test('default decoder rejects a corrupt JPEG frame', () async {
    final gateway = _FakeSearchCameraGateway();
    final corrupt = validSearchJpeg();
    corrupt.fillRange(64, corrupt.length, 0);
    gateway.thumbnailResult = MediaCaptureCallResult.success(
      MediaCaptureThumbnail(
        mediaHandle: gateway.confirmedMedia.mediaHandle,
        bytes: corrupt,
        pixelWidth: 1,
        pixelHeight: 1,
        contentType: 'image/jpeg',
        orientationDegrees: 0,
        mediaType: MediaCaptureMediaType.photo,
        posterFrameMillis: null,
      ),
    );
    final picker = NativeSearchCameraMediaPicker.withGateway(gateway);

    final result = await picker.capturePhoto() as SearchImagePickFailed;

    expect(result.failure.code, SearchImagePickFailureCode.invalidImage);
    expect(gateway.releaseCount, 1);
  });

  test('retains a failed release for clearDrafts retry', () async {
    final gateway = _FakeSearchCameraGateway()
      ..releaseResults.addAll(<bool>[false, true]);
    final picker = NativeSearchCameraMediaPicker.withGateway(
      gateway,
      thumbnailDecoder: (_) async {},
    );

    final result = await picker.capturePhoto() as SearchImagePickFailed;
    expect(result.failure.code, SearchImagePickFailureCode.pickerUnavailable);

    await picker.clearDrafts();
    expect(gateway.releaseCount, 2);
  });

  test('dispose waits for an active flow and remains idempotent', () async {
    final gateway = _FakeSearchCameraGateway();
    final flow = Completer<MediaCaptureFlowOutcome>();
    gateway.pendingFlow = flow;
    final picker = NativeSearchCameraMediaPicker.withGateway(
      gateway,
      thumbnailDecoder: (_) async {},
    );

    final capture = picker.capturePhoto();
    final dispose = picker.dispose();

    expect(await capture, isA<SearchImagePickFailed>());
    await dispose;
    await picker.dispose();
    expect(gateway.releaseCount, 0);
    expect(gateway.dismissCount, 1);
    expect(gateway.disposeCount, 1);
  });

  test('dispose retries a failed gateway cleanup', () async {
    final gateway = _FakeSearchCameraGateway()
      ..disposeResults.addAll(<bool>[false, true]);
    final picker = NativeSearchCameraMediaPicker.withGateway(gateway);

    await expectLater(
      picker.dispose(),
      throwsA(isA<SearchImagePickerDisposalException>()),
    );
    await picker.dispose();

    expect(gateway.disposeCount, 2);
  });

  test(
    'session reset dismisses pending media and blocks a new capture',
    () async {
      final gateway = _FakeSearchCameraGateway();
      final flow = Completer<MediaCaptureFlowOutcome>();
      gateway.pendingFlow = flow;
      final picker = NativeSearchCameraMediaPicker.withGateway(
        gateway,
        thumbnailDecoder: (_) async {},
      );

      final staleCapture = picker.capturePhoto();
      final clear = picker.clearDrafts();
      expect(await picker.capturePhoto(), isA<SearchImagePickFailed>());
      expect(gateway.configs, hasLength(1));

      expect(await staleCapture, isA<SearchImagePickFailed>());
      await clear;

      expect(gateway.releaseCount, 0);
      expect(gateway.dismissCount, 1);
      expect(await picker.capturePhoto(), isA<SearchImagePickSuccess>());
      expect(gateway.configs, hasLength(2));
    },
  );
}

final class _FakeSearchCameraGateway implements SearchCameraMediaGateway {
  _FakeSearchCameraGateway() {
    flowOutcome = MediaCaptureFlowConfirmed(confirmedMedia);
    thumbnailResult = MediaCaptureCallResult.success(
      MediaCaptureThumbnail(
        mediaHandle: confirmedMedia.mediaHandle,
        bytes: validSearchJpeg(),
        pixelWidth: 1,
        pixelHeight: 1,
        contentType: 'image/jpeg',
        orientationDegrees: 0,
        mediaType: MediaCaptureMediaType.photo,
        posterFrameMillis: null,
      ),
    );
  }

  final MediaCaptureConfirmedMedia confirmedMedia = _confirmedMedia();
  late MediaCaptureFlowOutcome flowOutcome;
  late MediaCaptureCallResult<MediaCaptureThumbnail> thumbnailResult;
  Completer<MediaCaptureFlowOutcome>? pendingFlow;
  final List<bool> releaseResults = <bool>[];
  final List<bool> disposeResults = <bool>[];
  final List<String> operations = <String>[];
  final List<MediaCaptureConfig> configs = <MediaCaptureConfig>[];
  final List<MediaCaptureThumbnailRequest> thumbnailRequests =
      <MediaCaptureThumbnailRequest>[];
  var releaseCount = 0;
  var disposeCount = 0;
  var dismissCount = 0;

  @override
  Future<MediaCaptureFlowOutcome> presentCaptureFlow(
    MediaCaptureConfig config,
  ) async {
    operations.add('present');
    configs.add(config);
    final pending = pendingFlow;
    if (pending == null) return flowOutcome;
    try {
      return await pending.future;
    } finally {
      if (identical(pendingFlow, pending)) pendingFlow = null;
    }
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
  Future<MediaCaptureCallResult<MediaCaptureThumbnail>> readMediaThumbnail(
    MediaCaptureThumbnailRequest request,
  ) async {
    operations.add('thumbnail');
    thumbnailRequests.add(request);
    return thumbnailResult;
  }

  @override
  Future<MediaCaptureCallResult<MediaCaptureMediaReleased>> releaseMedia(
    MediaCaptureMediaHandle mediaHandle,
  ) async {
    operations.add('release');
    releaseCount += 1;
    final succeeds = releaseResults.isEmpty ? true : releaseResults.removeAt(0);
    return succeeds
        ? MediaCaptureCallResult.success(MediaCaptureMediaReleased(mediaHandle))
        : const MediaCaptureCallResult.failure(
            MediaCaptureFailure(
              code: MediaCaptureFailureCode.systemInterrupted,
            ),
          );
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
    final succeeds = disposeResults.isEmpty ? true : disposeResults.removeAt(0);
    if (!succeeds) {
      throw const MediaCaptureDisposalException();
    }
  }
}

MediaCaptureConfirmedMedia _confirmedMedia({
  String handle = 'search-media-1',
  MediaCaptureMediaType mediaType = MediaCaptureMediaType.photo,
}) => MediaCaptureConfirmedMedia(
  mediaHandle: MediaCaptureMediaHandle(handle),
  mediaType: mediaType,
  pixelWidth: 1,
  pixelHeight: 1,
  durationMillis: mediaType == MediaCaptureMediaType.video ? 1000 : null,
  orientationDegrees: 0,
  byteLength: 1,
  leaseExpiresAtMillis: DateTime.utc(2026, 7, 30).millisecondsSinceEpoch,
);
