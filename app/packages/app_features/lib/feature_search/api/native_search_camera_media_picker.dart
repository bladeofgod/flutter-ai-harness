import 'dart:async' show Future;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app_media_capture_bridge/app_media_capture_bridge.dart';

import '../../api/search_image_picker.dart';
import 'shared_media_search_image_picker.dart';

const int _thumbnailMaxPixelEdge = 512;
const int _cleanupAttempts = 3;

typedef SearchThumbnailDecoder = Future<void> Function(Uint8List bytes);

abstract interface class SearchCameraMediaGateway {
  Future<MediaCaptureFlowOutcome> presentCaptureFlow(MediaCaptureConfig config);

  Future<bool> dismissActivePresentation();

  Future<MediaCaptureCallResult<MediaCaptureThumbnail>> readMediaThumbnail(
    MediaCaptureThumbnailRequest request,
  );

  Future<MediaCaptureCallResult<MediaCaptureMediaReleased>> releaseMedia(
    MediaCaptureMediaHandle mediaHandle,
  );

  Future<void> dispose();
}

final class SearchMediaCaptureClientGateway
    implements SearchCameraMediaGateway {
  SearchMediaCaptureClientGateway(this._client);

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

final class NativeSearchCameraMediaPicker implements SearchCameraMediaPicker {
  NativeSearchCameraMediaPicker({MediaCaptureClient? client})
    : this.withGateway(
        SearchMediaCaptureClientGateway(client ?? MediaCaptureClient()),
      );

  NativeSearchCameraMediaPicker.withGateway(
    this._gateway, {
    SearchThumbnailDecoder thumbnailDecoder = _decodeThumbnail,
  }) : _thumbnailDecoder = thumbnailDecoder;

  final SearchCameraMediaGateway _gateway;
  final SearchThumbnailDecoder _thumbnailDecoder;
  final List<MediaCaptureConfirmedMedia> _retainedLeases =
      <MediaCaptureConfirmedMedia>[];

  Future<SearchImagePickResult>? _activeCapture;
  Future<void>? _clearDraftsFuture;
  Future<void>? _disposeFuture;
  bool _disposeRequested = false;
  var _sessionGeneration = 0;

  @override
  Future<SearchImagePickResult> capturePhoto() {
    if (_disposeRequested ||
        _clearDraftsFuture != null ||
        _activeCapture != null) {
      return Future<SearchImagePickResult>.value(_unavailableFailure);
    }
    final capture = _performCapture(_sessionGeneration);
    _activeCapture = capture;
    return capture.whenComplete(() {
      if (identical(_activeCapture, capture)) {
        _activeCapture = null;
      }
    });
  }

  Future<SearchImagePickResult> _performCapture(int sessionGeneration) async {
    await _releaseRetained(attempts: 1);
    if (_retainedLeases.isNotEmpty) {
      return _unavailableFailure;
    }
    MediaCaptureConfirmedMedia? confirmed;
    try {
      final outcome = await _gateway.presentCaptureFlow(
        MediaCaptureConfig(
          enabledMediaTypes: const <MediaCaptureMediaType>{
            MediaCaptureMediaType.photo,
          },
          preferredCamera: MediaCaptureCamera.rear,
          audioEnabled: false,
          maxVideoDurationMillis: mediaCaptureMaxVideoDurationMillis,
        ),
      );
      switch (outcome) {
        case MediaCaptureFlowCancelled():
          return sessionGeneration == _sessionGeneration
              ? const SearchImagePickCanceled()
              : _unavailableFailure;
        case MediaCaptureFlowFailure(:final failure):
          return sessionGeneration == _sessionGeneration
              ? SearchImagePickFailed(_mapFailure(failure))
              : _unavailableFailure;
        case MediaCaptureFlowConfirmed(:final media):
          confirmed = media;
      }

      if (_disposeRequested ||
          sessionGeneration != _sessionGeneration ||
          confirmed.mediaType != MediaCaptureMediaType.photo) {
        await _releaseOrRetain(confirmed);
        return _unavailableFailure;
      }

      final thumbnailResult = await _gateway.readMediaThumbnail(
        MediaCaptureThumbnailRequest(
          mediaHandle: confirmed.mediaHandle,
          maxPixelEdge: _thumbnailMaxPixelEdge,
        ),
      );
      if (_disposeRequested || sessionGeneration != _sessionGeneration) {
        await _releaseOrRetain(confirmed);
        return _unavailableFailure;
      }
      final thumbnail = switch (thumbnailResult) {
        MediaCaptureCallSuccess<MediaCaptureThumbnail>(:final value) => value,
        MediaCaptureCallFailure<MediaCaptureThumbnail>() => null,
      };
      if (thumbnail == null ||
          thumbnail.mediaHandle.value != confirmed.mediaHandle.value ||
          thumbnail.mediaType != MediaCaptureMediaType.photo ||
          thumbnail.contentType != 'image/jpeg' ||
          thumbnail.byteLength > mediaCaptureMaxThumbnailBytes ||
          thumbnail.pixelWidth < 1 ||
          thumbnail.pixelWidth > _thumbnailMaxPixelEdge ||
          thumbnail.pixelHeight < 1 ||
          thumbnail.pixelHeight > _thumbnailMaxPixelEdge) {
        await _releaseOrRetain(confirmed);
        return SearchImagePickFailed(
          thumbnailResult is MediaCaptureCallFailure<MediaCaptureThumbnail>
              ? _mapFailure(thumbnailResult.failure)
              : const SearchImagePickFailure(
                  SearchImagePickFailureCode.invalidImage,
                ),
        );
      }

      final bytes = thumbnail.bytes;
      try {
        await _thumbnailDecoder(bytes);
      } on Object {
        bytes.fillRange(0, bytes.length, 0);
        await _releaseOrRetain(confirmed);
        return const SearchImagePickFailed(
          SearchImagePickFailure(SearchImagePickFailureCode.invalidImage),
        );
      }

      if (!await _releaseOrRetain(confirmed)) {
        bytes.fillRange(0, bytes.length, 0);
        return _unavailableFailure;
      }
      if (_disposeRequested || sessionGeneration != _sessionGeneration) {
        bytes.fillRange(0, bytes.length, 0);
        return _unavailableFailure;
      }
      final result = SearchImagePickSuccess(bytes);
      bytes.fillRange(0, bytes.length, 0);
      return result;
    } on Object {
      if (confirmed != null) {
        await _releaseOrRetain(confirmed);
      }
      return _unavailableFailure;
    }
  }

  @override
  Future<void> clearDrafts() {
    final existing = _clearDraftsFuture;
    if (existing != null) {
      return existing;
    }
    _sessionGeneration += 1;
    final clear = _performClearDrafts();
    _clearDraftsFuture = clear;
    return clear.whenComplete(() {
      if (identical(_clearDraftsFuture, clear)) {
        _clearDraftsFuture = null;
      }
    });
  }

  Future<void> _performClearDrafts() async {
    if (_activeCapture != null && !await _gateway.dismissActivePresentation()) {
      throw const SearchImagePickerDisposalException();
    }
    await _activeCapture;
    await _releaseRetained(attempts: _cleanupAttempts);
    if (_retainedLeases.isNotEmpty) {
      throw const SearchImagePickerDisposalException();
    }
  }

  @override
  Future<void> dispose() {
    final existing = _disposeFuture;
    if (existing != null) {
      return existing;
    }
    _disposeRequested = true;
    _sessionGeneration += 1;
    return _disposeFuture = _performDispose();
  }

  Future<void> _performDispose() async {
    try {
      await _clearDraftsFuture;
    } on Object {
      // Final disposal retries retained leases below.
    }
    if (_activeCapture != null && !await _gateway.dismissActivePresentation()) {
      _disposeFuture = null;
      throw const SearchImagePickerDisposalException();
    }
    await _activeCapture;
    await _releaseRetained(attempts: _cleanupAttempts);
    Object? disposalFailure;
    try {
      await _gateway.dispose();
    } on Object catch (error) {
      disposalFailure = error;
    }
    if (_retainedLeases.isNotEmpty || disposalFailure != null) {
      _disposeFuture = null;
      throw const SearchImagePickerDisposalException();
    }
  }

  Future<bool> _releaseOrRetain(MediaCaptureConfirmedMedia media) async {
    final released = await _release(media);
    if (!released &&
        !_retainedLeases.any(
          (retained) => retained.mediaHandle.value == media.mediaHandle.value,
        )) {
      _retainedLeases.add(media);
    }
    return released;
  }

  Future<void> _releaseRetained({required int attempts}) async {
    for (
      var attempt = 0;
      attempt < attempts && _retainedLeases.isNotEmpty;
      attempt += 1
    ) {
      final pending = List<MediaCaptureConfirmedMedia>.of(_retainedLeases);
      for (final media in pending) {
        if (await _release(media)) {
          _retainedLeases.removeWhere(
            (retained) => retained.mediaHandle.value == media.mediaHandle.value,
          );
        }
      }
    }
  }

  Future<bool> _release(MediaCaptureConfirmedMedia media) async {
    try {
      return switch (await _gateway.releaseMedia(media.mediaHandle)) {
        MediaCaptureCallSuccess<MediaCaptureMediaReleased>(:final value) =>
          value.mediaHandle.value == media.mediaHandle.value,
        MediaCaptureCallFailure<MediaCaptureMediaReleased>(:final failure) =>
          failure.code == MediaCaptureFailureCode.mediaInvalid,
      };
    } on Object {
      return false;
    }
  }

  SearchImagePickFailure _mapFailure(MediaCaptureFailure failure) =>
      switch (failure.code) {
        MediaCaptureFailureCode.permissionDenied ||
        MediaCaptureFailureCode.permissionRestricted ||
        MediaCaptureFailureCode.permissionPermanentlyDenied =>
          const SearchImagePickFailure(
            SearchImagePickFailureCode.permissionDenied,
          ),
        MediaCaptureFailureCode.thumbnailGenerationFailed ||
        MediaCaptureFailureCode.thumbnailGenerationCancelled ||
        MediaCaptureFailureCode.thumbnailOverloaded =>
          const SearchImagePickFailure(SearchImagePickFailureCode.invalidImage),
        _ => const SearchImagePickFailure(
          SearchImagePickFailureCode.pickerUnavailable,
        ),
      };
}

const SearchImagePickFailed _unavailableFailure = SearchImagePickFailed(
  SearchImagePickFailure(SearchImagePickFailureCode.pickerUnavailable),
);

Future<void> _decodeThumbnail(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    frame.image.dispose();
  } finally {
    codec.dispose();
  }
}
