import 'dart:async';

import 'package:app_features/api/order_review_media_api.dart';
import 'package:app_features/feature_orders/api/native_order_review_media_api.dart';
import 'package:app_media_capture_bridge/app_media_capture_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

import 'orders_test_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('maps confirmed media to a decoded business attachment', () async {
    final gateway = FakeOrderReviewMediaGateway();
    final api = NativeOrderReviewMediaApi.withGateway(gateway);

    final result = await api.capture();

    final attachment = (result as OrderReviewMediaConfirmed).attachment;
    expect(attachment.type, OrderReviewMediaType.photo);
    expect(attachment.thumbnailBytes, validOrderReviewJpeg());
    expect(attachment.duration, isNull);

    expect(await api.release(attachment), isA<OrderReviewMediaReleased>());
    expect(await api.release(attachment), isA<OrderReviewMediaReleased>());
    expect(gateway.releaseCount, 1);
  });

  test('keeps cancellation normal and does not request a thumbnail', () async {
    final gateway = FakeOrderReviewMediaGateway()
      ..flowOutcome = const MediaCaptureFlowCancelled();
    final api = NativeOrderReviewMediaApi.withGateway(
      gateway,
      thumbnailDecoder: (_) async {},
    );

    expect(await api.capture(), isA<OrderReviewMediaCancelled>());
    expect(gateway.thumbnailCount, 0);
    expect(gateway.releaseCount, 0);
  });

  test('releases confirmed media when thumbnail generation fails', () async {
    final gateway = FakeOrderReviewMediaGateway()
      ..thumbnailResult = const MediaCaptureCallResult.failure(
        MediaCaptureFailure(
          code: MediaCaptureFailureCode.thumbnailGenerationFailed,
        ),
      );
    final api = NativeOrderReviewMediaApi.withGateway(
      gateway,
      thumbnailDecoder: (_) async {},
    );

    final result = await api.capture();

    expect(result, isA<OrderReviewMediaCaptureFailure>());
    expect(gateway.releaseCount, 1);
  });

  test('releases confirmed media when thumbnail decoding fails', () async {
    final gateway = FakeOrderReviewMediaGateway();
    final api = NativeOrderReviewMediaApi.withGateway(
      gateway,
      thumbnailDecoder: (_) async => throw const FormatException(),
    );

    final result = await api.capture();

    expect(result, isA<OrderReviewMediaCaptureFailure>());
    expect(gateway.releaseCount, 1);
  });

  test(
    'retains a failed release for retry and dispose is idempotent',
    () async {
      final gateway = FakeOrderReviewMediaGateway()
        ..releaseResults.addAll(<bool>[false, true]);
      final api = NativeOrderReviewMediaApi.withGateway(
        gateway,
        thumbnailDecoder: (_) async {},
      );
      final attachment =
          (await api.capture() as OrderReviewMediaConfirmed).attachment;

      expect(
        await api.release(attachment),
        isA<OrderReviewMediaReleaseFailure>(),
      );
      await api.dispose();
      await api.dispose();

      expect(gateway.releaseCount, 2);
      expect(gateway.disposeCount, 1);
    },
  );

  test('shares one native release across route and global cleanup', () async {
    final gateway = FakeOrderReviewMediaGateway();
    final api = NativeOrderReviewMediaApi.withGateway(
      gateway,
      thumbnailDecoder: (_) async {},
    );
    final attachment =
        (await api.capture() as OrderReviewMediaConfirmed).attachment;
    final releaseCompleter = Completer<bool>();
    gateway.pendingRelease = releaseCompleter.future;

    final routeRelease = api.release(attachment);
    await Future<void>.delayed(Duration.zero);
    final globalCleanup = api.clearDrafts();
    await Future<void>.delayed(Duration.zero);

    expect(gateway.releaseCount, 1);
    releaseCompleter.complete(true);
    expect(await routeRelease, isA<OrderReviewMediaReleased>());
    await globalCleanup;
    expect(gateway.releaseCount, 1);
  });

  test(
    'clearDrafts detaches thumbnail bytes before bounded release retry',
    () async {
      final gateway = FakeOrderReviewMediaGateway()..releaseResults.add(true);
      final api = NativeOrderReviewMediaApi.withGateway(
        gateway,
        thumbnailDecoder: (_) async {},
      );
      final attachment =
          (await api.capture() as OrderReviewMediaConfirmed).attachment;
      final firstRelease = Completer<bool>();
      gateway.pendingRelease = firstRelease.future;

      final cleanup = api.clearDrafts();
      await Future<void>.delayed(Duration.zero);

      expect(gateway.releaseCount, 1);
      expect(await api.release(attachment), isA<OrderReviewMediaReleased>());
      expect(gateway.releaseCount, 1);

      firstRelease.complete(false);
      await cleanup;
      expect(gateway.releaseCount, 2);
      expect(await api.release(attachment), isA<OrderReviewMediaReleased>());
      expect(gateway.releaseCount, 2);
    },
  );

  test(
    'dispose releases a confirmed lease while thumbnail is pending',
    () async {
      final gateway = FakeOrderReviewMediaGateway();
      final thumbnailCompleter =
          Completer<MediaCaptureCallResult<MediaCaptureThumbnail>>();
      gateway.pendingThumbnail = thumbnailCompleter.future;
      final api = NativeOrderReviewMediaApi.withGateway(
        gateway,
        thumbnailDecoder: (_) async {},
      );

      final capture = api.capture();
      await Future<void>.delayed(Duration.zero);
      expect(gateway.thumbnailCount, 1);
      final dispose = api.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(gateway.releaseCount, 1);
      expect(gateway.disposeCount, 1);

      thumbnailCompleter.complete(gateway.thumbnailResult);
      expect(await capture, isA<OrderReviewMediaCaptureFailure>());
      await dispose;
      expect(gateway.releaseCount, 1);
      expect(gateway.disposeCount, 1);
    },
  );

  test(
    'dispose settles a pending presentation without external completion',
    () async {
      final gateway = FakeOrderReviewMediaGateway()
        ..pendingFlow = Completer<MediaCaptureFlowOutcome>();
      final api = NativeOrderReviewMediaApi.withGateway(
        gateway,
        thumbnailDecoder: (_) async {},
      );

      final capture = api.capture();
      await Future<void>.delayed(Duration.zero);

      await api.dispose();

      expect(await capture, isA<OrderReviewMediaCancelled>());
      expect(gateway.releaseCount, 0);
      expect(gateway.dismissCount, 1);
      expect(gateway.disposeCount, 1);
    },
  );

  test(
    'clearDrafts prevents a pending thumbnail from publishing ready media',
    () async {
      final gateway = FakeOrderReviewMediaGateway();
      final thumbnailCompleter =
          Completer<MediaCaptureCallResult<MediaCaptureThumbnail>>();
      gateway.pendingThumbnail = thumbnailCompleter.future;
      final api = NativeOrderReviewMediaApi.withGateway(
        gateway,
        thumbnailDecoder: (_) async {},
      );

      final capture = api.capture();
      await Future<void>.delayed(Duration.zero);
      await api.clearDrafts();
      thumbnailCompleter.complete(gateway.thumbnailResult);

      expect(await capture, isA<OrderReviewMediaCaptureFailure>());
      expect(gateway.releaseCount, 1);
      await api.clearDrafts();
      expect(gateway.releaseCount, 1);
    },
  );

  test('failed thumbnail cleanup is retried before another capture', () async {
    final gateway = FakeOrderReviewMediaGateway()
      ..releaseResults.addAll(<bool>[false, true]);
    var decoderFails = true;
    final api = NativeOrderReviewMediaApi.withGateway(
      gateway,
      thumbnailDecoder: (_) async {
        if (decoderFails) throw const FormatException();
      },
    );

    final first = await api.capture() as OrderReviewMediaCaptureFailure;
    expect(first.failure.code, OrderReviewMediaFailureCode.releaseFailed);
    expect(gateway.releaseCount, 1);

    decoderFails = false;
    final second = await api.capture();
    expect(second, isA<OrderReviewMediaConfirmed>());
    expect(gateway.releaseCount, 2);
    expect(gateway.flowCount, 2);
  });

  test('dispose keeps the gateway alive until retained leases clear', () async {
    final gateway = FakeOrderReviewMediaGateway()
      ..releaseResults.addAll(<bool>[false, false, false, true]);
    final api = NativeOrderReviewMediaApi.withGateway(
      gateway,
      thumbnailDecoder: (_) async {},
    );
    await api.capture();

    await expectLater(
      api.dispose(),
      throwsA(isA<OrderReviewMediaDisposalException>()),
    );
    expect(gateway.disposeCount, 0);
    await api.dispose();
    expect(gateway.releaseCount, 4);
    expect(gateway.disposeCount, 1);
  });
}

final class FakeOrderReviewMediaGateway implements OrderReviewMediaGateway {
  FakeOrderReviewMediaGateway() {
    final media = _confirmedMedia();
    flowOutcome = MediaCaptureFlowConfirmed(media);
    thumbnailResult = MediaCaptureCallResult.success(
      MediaCaptureThumbnail(
        mediaHandle: media.mediaHandle,
        bytes: validOrderReviewJpeg(),
        pixelWidth: 1,
        pixelHeight: 1,
        contentType: 'image/jpeg',
        orientationDegrees: 0,
        mediaType: MediaCaptureMediaType.photo,
        posterFrameMillis: null,
      ),
    );
  }

  late MediaCaptureFlowOutcome flowOutcome;
  late MediaCaptureCallResult<MediaCaptureThumbnail> thumbnailResult;
  Completer<MediaCaptureFlowOutcome>? pendingFlow;
  Future<MediaCaptureCallResult<MediaCaptureThumbnail>>? pendingThumbnail;
  Future<bool>? pendingRelease;
  final List<bool> releaseResults = <bool>[];
  var thumbnailCount = 0;
  var flowCount = 0;
  var releaseCount = 0;
  var disposeCount = 0;
  var dismissCount = 0;

  @override
  Future<MediaCaptureFlowOutcome> presentCaptureFlow(
    MediaCaptureConfig config,
  ) async {
    flowCount += 1;
    return pendingFlow?.future ?? flowOutcome;
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
    thumbnailCount += 1;
    return pendingThumbnail ?? thumbnailResult;
  }

  @override
  Future<MediaCaptureCallResult<MediaCaptureMediaReleased>> releaseMedia(
    MediaCaptureMediaHandle mediaHandle,
  ) async {
    releaseCount += 1;
    final pending = pendingRelease;
    final succeeds = pending == null
        ? releaseResults.isEmpty
              ? true
              : releaseResults.removeAt(0)
        : await pending;
    if (identical(pendingRelease, pending)) {
      pendingRelease = null;
    }
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
    final pending = pendingFlow;
    if (pending != null && !pending.isCompleted) {
      pending.complete(
        const MediaCaptureFlowFailure(
          MediaCaptureFailure(code: MediaCaptureFailureCode.bridgeUnavailable),
        ),
      );
    }
  }
}

MediaCaptureConfirmedMedia _confirmedMedia() => MediaCaptureConfirmedMedia(
  mediaHandle: MediaCaptureMediaHandle('media-1'),
  mediaType: MediaCaptureMediaType.photo,
  pixelWidth: 1,
  pixelHeight: 1,
  durationMillis: null,
  orientationDegrees: 0,
  byteLength: validOrderReviewJpeg().length,
  leaseExpiresAtMillis: DateTime.utc(2026, 7, 30).millisecondsSinceEpoch,
);
