import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app_media_capture_bridge/app_media_capture_bridge.dart';

import '../../api/order_review_media_api.dart';

const int _thumbnailMaxPixelEdge = 512;
const int _draftCleanupAttempts = 3;
const int _disposeReleaseAttempts = 3;

typedef OrderReviewThumbnailDecoder = Future<void> Function(Uint8List bytes);

abstract interface class OrderReviewMediaGateway {
  Future<MediaCaptureFlowOutcome> presentCaptureFlow(MediaCaptureConfig config);

  Future<bool> dismissActivePresentation();

  Future<MediaCaptureCallResult<MediaCaptureThumbnail>> readMediaThumbnail(
    MediaCaptureThumbnailRequest request,
  );

  Future<MediaCaptureCallResult<MediaCaptureMediaReleased>> releaseMedia(
    MediaCaptureMediaHandle mediaHandle,
  );

  /// Settles pending capture calls and owns cleanup for any late confirmed
  /// media before completing successfully.
  Future<void> dispose();
}

final class MediaCaptureClientGateway implements OrderReviewMediaGateway {
  MediaCaptureClientGateway(this._client);

  final MediaCaptureClient _client;

  @override
  Future<MediaCaptureFlowOutcome> presentCaptureFlow(
    MediaCaptureConfig config,
  ) => _client.presentCaptureFlow(config);

  @override
  Future<bool> dismissActivePresentation() =>
      _client.dismissActivePresentation();

  @override
  Future<MediaCaptureCallResult<MediaCaptureThumbnail>> readMediaThumbnail(
    MediaCaptureThumbnailRequest request,
  ) => _client.readMediaThumbnail(request);

  @override
  Future<MediaCaptureCallResult<MediaCaptureMediaReleased>> releaseMedia(
    MediaCaptureMediaHandle mediaHandle,
  ) => _client.releaseMedia(mediaHandle);

  @override
  Future<void> dispose() => _client.dispose();
}

final class NativeOrderReviewMediaApi implements OrderReviewMediaApi {
  NativeOrderReviewMediaApi({MediaCaptureClient? client})
    : this.withGateway(
        MediaCaptureClientGateway(client ?? MediaCaptureClient()),
      );

  NativeOrderReviewMediaApi.withGateway(
    this._gateway, {
    OrderReviewThumbnailDecoder thumbnailDecoder = _decodeThumbnail,
  }) : _thumbnailDecoder = thumbnailDecoder;

  final OrderReviewMediaGateway _gateway;
  final OrderReviewThumbnailDecoder _thumbnailDecoder;
  final Map<OrderReviewMediaAttachment, _LeaseRecord> _leases =
      HashMap<OrderReviewMediaAttachment, _LeaseRecord>.identity();
  final Set<_LeaseRecord> _leaseRecords = HashSet<_LeaseRecord>.identity();

  Future<void>? _disposeFuture;
  Future<OrderReviewMediaCaptureOutcome>? _activeCapture;
  Completer<void>? _presentationSettled;
  bool _disposeRequested = false;
  int _cleanupGeneration = 0;

  @override
  Future<OrderReviewMediaCaptureOutcome> capture() {
    if (_disposeRequested || _activeCapture != null) {
      return const OrderReviewMediaCaptureFailure(
        OrderReviewMediaFailure(
          code: OrderReviewMediaFailureCode.unavailable,
          recoverable: false,
        ),
      ).asFuture();
    }
    late final Future<OrderReviewMediaCaptureOutcome> operation;
    operation = _performCapture().whenComplete(() {
      if (identical(_activeCapture, operation)) {
        _activeCapture = null;
      }
    });
    _activeCapture = operation;
    return operation;
  }

  Future<OrderReviewMediaCaptureOutcome> _performCapture() async {
    if (_leaseRecords.isNotEmpty && !await _clearDrafts(attempts: 1)) {
      return const OrderReviewMediaCaptureFailure(
        OrderReviewMediaFailure(
          code: OrderReviewMediaFailureCode.releaseFailed,
          recoverable: true,
        ),
      );
    }
    final captureGeneration = _cleanupGeneration;
    MediaCaptureConfirmedMedia? confirmedMedia;
    _LeaseRecord? leaseRecord;
    try {
      final presentationSettled = Completer<void>();
      _presentationSettled = presentationSettled;
      late final MediaCaptureFlowOutcome outcome;
      try {
        outcome = await _gateway.presentCaptureFlow(
          MediaCaptureConfig(
            enabledMediaTypes: const {
              MediaCaptureMediaType.photo,
              MediaCaptureMediaType.video,
            },
            preferredCamera: MediaCaptureCamera.rear,
            audioEnabled: true,
            maxVideoDurationMillis: mediaCaptureMaxVideoDurationMillis,
          ),
        );
      } finally {
        if (!presentationSettled.isCompleted) presentationSettled.complete();
        if (identical(_presentationSettled, presentationSettled)) {
          _presentationSettled = null;
        }
      }
      switch (outcome) {
        case MediaCaptureFlowCancelled():
          return const OrderReviewMediaCancelled();
        case MediaCaptureFlowFailure(:final failure):
          return OrderReviewMediaCaptureFailure(_mapFailure(failure));
        case MediaCaptureFlowConfirmed(:final media):
          confirmedMedia = media;
          leaseRecord = _LeaseRecord(media);
          _leaseRecords.add(leaseRecord);
      }

      if (_captureWasInvalidated(captureGeneration, leaseRecord)) {
        return _releaseAfterInvalidation(leaseRecord);
      }

      final thumbnailResult = await _gateway.readMediaThumbnail(
        MediaCaptureThumbnailRequest(
          mediaHandle: confirmedMedia.mediaHandle,
          maxPixelEdge: _thumbnailMaxPixelEdge,
        ),
      );
      final thumbnail = switch (thumbnailResult) {
        MediaCaptureCallSuccess<MediaCaptureThumbnail>(:final value) => value,
        MediaCaptureCallFailure<MediaCaptureThumbnail>() => null,
      };
      if (_captureWasInvalidated(captureGeneration, leaseRecord)) {
        return _releaseAfterInvalidation(leaseRecord);
      }
      if (thumbnail == null || thumbnail.contentType != 'image/jpeg') {
        return _releaseAfterCaptureFailure(
          leaseRecord,
          OrderReviewMediaFailureCode.thumbnailUnavailable,
        );
      }

      final bytes = thumbnail.bytes;
      if (bytes.isEmpty || bytes.length > orderReviewMediaMaxThumbnailBytes) {
        return _releaseAfterCaptureFailure(
          leaseRecord,
          OrderReviewMediaFailureCode.thumbnailUnavailable,
        );
      }
      try {
        await _thumbnailDecoder(bytes);
      } on Object {
        return _releaseAfterCaptureFailure(
          leaseRecord,
          OrderReviewMediaFailureCode.thumbnailUnavailable,
        );
      }
      if (_captureWasInvalidated(captureGeneration, leaseRecord)) {
        return _releaseAfterInvalidation(leaseRecord);
      }

      final attachment = OrderReviewMediaAttachment(
        type: switch (confirmedMedia.mediaType) {
          MediaCaptureMediaType.photo => OrderReviewMediaType.photo,
          MediaCaptureMediaType.video => OrderReviewMediaType.video,
        },
        thumbnailBytes: bytes,
        thumbnailPixelWidth: thumbnail.pixelWidth,
        thumbnailPixelHeight: thumbnail.pixelHeight,
        duration: confirmedMedia.durationMillis == null
            ? null
            : Duration(milliseconds: confirmedMedia.durationMillis!),
      );
      leaseRecord.attachment = attachment;
      _leases[attachment] = leaseRecord;
      return OrderReviewMediaConfirmed(attachment);
    } on Object {
      if (leaseRecord != null) {
        return _releaseAfterCaptureFailure(
          leaseRecord,
          OrderReviewMediaFailureCode.interrupted,
        );
      }
      return const OrderReviewMediaCaptureFailure(
        OrderReviewMediaFailure(
          code: OrderReviewMediaFailureCode.interrupted,
          recoverable: true,
        ),
      );
    }
  }

  @override
  Future<OrderReviewMediaReleaseOutcome> release(
    OrderReviewMediaAttachment attachment,
  ) async {
    final record = _leases[attachment];
    if (record == null) {
      return const OrderReviewMediaReleased();
    }
    if (await _releaseRecord(record)) {
      return const OrderReviewMediaReleased();
    }
    return const OrderReviewMediaReleaseFailure(
      OrderReviewMediaFailure(
        code: OrderReviewMediaFailureCode.releaseFailed,
        recoverable: true,
      ),
    );
  }

  @override
  Future<void> clearDrafts() async {
    if (!await _clearDrafts(attempts: _draftCleanupAttempts)) {
      throw const OrderReviewMediaDisposalException();
    }
  }

  @override
  Future<void> dispose() {
    final existing = _disposeFuture;
    if (existing != null) {
      return existing;
    }
    _disposeRequested = true;
    final future = _performDispose();
    _disposeFuture = future;
    return future;
  }

  Future<void> _performDispose() async {
    if (!await _clearDrafts(attempts: _disposeReleaseAttempts)) {
      _disposeFuture = null;
      throw const OrderReviewMediaDisposalException();
    }
    try {
      await _gateway.dispose();
      await _activeCapture;
      if (_leaseRecords.isNotEmpty) {
        throw const OrderReviewMediaDisposalException();
      }
    } on Object {
      _disposeFuture = null;
      rethrow;
    }
  }

  Future<bool> _clearDrafts({required int attempts}) async {
    _cleanupGeneration += 1;
    _detachBusinessAttachments();
    final presentationSettled = _presentationSettled;
    if (presentationSettled != null) {
      if (!await _gateway.dismissActivePresentation()) return false;
      await presentationSettled.future;
      _detachBusinessAttachments();
    }
    for (var attempt = 0; attempt < attempts; attempt += 1) {
      for (final record in List<_LeaseRecord>.of(_leaseRecords)) {
        await _releaseRecord(record);
      }
      if (_leaseRecords.isEmpty) {
        return true;
      }
    }
    return false;
  }

  void _detachBusinessAttachments() {
    for (final record in _leaseRecords) {
      final attachment = record.attachment;
      if (attachment != null && identical(_leases[attachment], record)) {
        _leases.remove(attachment);
      }
      record.attachment = null;
    }
  }

  Future<bool> _releaseRecord(_LeaseRecord record) {
    if (record.released) {
      final attachment = record.attachment;
      if (attachment != null && identical(_leases[attachment], record)) {
        _leases.remove(attachment);
      }
      record.attachment = null;
      _leaseRecords.remove(record);
      return Future<bool>.value(true);
    }
    final active = record.releaseFuture;
    if (active != null) {
      return active;
    }
    late final Future<bool> operation;
    operation = _releaseConfirmed(record.media)
        .then((released) {
          if (released) {
            record.released = true;
            final attachment = record.attachment;
            if (attachment != null && identical(_leases[attachment], record)) {
              _leases.remove(attachment);
            }
            record.attachment = null;
            _leaseRecords.remove(record);
          }
          return released;
        })
        .whenComplete(() {
          if (identical(record.releaseFuture, operation)) {
            record.releaseFuture = null;
          }
        });
    record.releaseFuture = operation;
    return operation;
  }

  bool _captureWasInvalidated(int generation, _LeaseRecord record) {
    return _disposeRequested ||
        generation != _cleanupGeneration ||
        record.released;
  }

  Future<OrderReviewMediaCaptureOutcome> _releaseAfterInvalidation(
    _LeaseRecord record,
  ) async {
    final released = await _releaseRecord(record);
    return OrderReviewMediaCaptureFailure(
      OrderReviewMediaFailure(
        code: released
            ? _disposeRequested
                  ? OrderReviewMediaFailureCode.unavailable
                  : OrderReviewMediaFailureCode.interrupted
            : OrderReviewMediaFailureCode.releaseFailed,
        recoverable: !_disposeRequested,
      ),
    );
  }

  Future<OrderReviewMediaCaptureOutcome> _releaseAfterCaptureFailure(
    _LeaseRecord record,
    OrderReviewMediaFailureCode fallbackCode,
  ) async {
    final released = await _releaseRecord(record);
    return OrderReviewMediaCaptureFailure(
      OrderReviewMediaFailure(
        code: released
            ? fallbackCode
            : OrderReviewMediaFailureCode.releaseFailed,
        recoverable: true,
      ),
    );
  }

  Future<bool> _releaseConfirmed(MediaCaptureConfirmedMedia media) async {
    try {
      final result = await _gateway.releaseMedia(media.mediaHandle);
      return switch (result) {
        MediaCaptureCallSuccess<MediaCaptureMediaReleased>() => true,
        MediaCaptureCallFailure<MediaCaptureMediaReleased>(:final failure) =>
          failure.code == MediaCaptureFailureCode.mediaInvalid,
      };
    } on Object {
      return false;
    }
  }

  OrderReviewMediaFailure _mapFailure(MediaCaptureFailure failure) {
    return switch (failure.code) {
      MediaCaptureFailureCode.permissionDenied ||
      MediaCaptureFailureCode.permissionRestricted ||
      MediaCaptureFailureCode.permissionPermanentlyDenied =>
        OrderReviewMediaFailure(
          code: OrderReviewMediaFailureCode.permissionDenied,
          recoverable: failure.recoverable,
        ),
      MediaCaptureFailureCode.bridgeUnavailable ||
      MediaCaptureFailureCode.presentationConflict ||
      MediaCaptureFailureCode.resourceInUse => OrderReviewMediaFailure(
        code: OrderReviewMediaFailureCode.unavailable,
        recoverable: failure.recoverable,
      ),
      MediaCaptureFailureCode.thumbnailGenerationFailed ||
      MediaCaptureFailureCode.thumbnailGenerationCancelled ||
      MediaCaptureFailureCode.thumbnailOverloaded => OrderReviewMediaFailure(
        code: OrderReviewMediaFailureCode.thumbnailUnavailable,
        recoverable: failure.recoverable,
      ),
      _ => OrderReviewMediaFailure(
        code: OrderReviewMediaFailureCode.interrupted,
        recoverable: failure.recoverable,
      ),
    };
  }
}

final class _LeaseRecord {
  _LeaseRecord(this.media);

  final MediaCaptureConfirmedMedia media;
  OrderReviewMediaAttachment? attachment;
  Future<bool>? releaseFuture;
  bool released = false;
}

extension on OrderReviewMediaCaptureOutcome {
  Future<OrderReviewMediaCaptureOutcome> asFuture() => Future.value(this);
}

Future<void> _decodeThumbnail(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    frame.image.dispose();
  } finally {
    codec.dispose();
  }
}
