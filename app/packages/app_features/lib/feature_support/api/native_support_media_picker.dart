import 'dart:io';

import 'package:app_media/app_media.dart';
import 'package:app_media_capture_bridge/app_media_capture_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../api/support_media_picker.dart';

const int _galleryImageMaxBytes = 20 * 1024 * 1024;
const int _galleryVideoMaxBytes = 50 * 1024 * 1024;
const int _supportVideoDurationMillis = 15000;
const int _cleanupAttempts = 3;

abstract interface class SupportCameraMediaGateway {
  Future<MediaCaptureFlowOutcome> presentCaptureFlow(MediaCaptureConfig config);

  Future<bool> dismissActivePresentation();

  Future<MediaCaptureCallResult<MediaCaptureMaterializedMedia>>
  materializeMedia(MediaCaptureConfirmedMedia media);

  Future<MediaCaptureCallResult<MediaCaptureMaterializedMediaReleased>>
  releaseMaterializedMedia(MediaCaptureExportHandle exportHandle);

  Future<MediaCaptureCallResult<MediaCaptureMediaReleased>> releaseMedia(
    MediaCaptureMediaHandle mediaHandle,
  );

  Future<void> dispose();
}

final class SupportMediaCaptureClientGateway
    implements SupportCameraMediaGateway {
  SupportMediaCaptureClientGateway(this._client);

  final MediaCaptureClient _client;

  @override
  Future<MediaCaptureFlowOutcome> presentCaptureFlow(
    MediaCaptureConfig config,
  ) => _client.presentCaptureFlow(config);

  @override
  Future<bool> dismissActivePresentation() =>
      _client.dismissActivePresentation();

  @override
  Future<MediaCaptureCallResult<MediaCaptureMaterializedMedia>>
  materializeMedia(MediaCaptureConfirmedMedia media) =>
      _client.materializeMedia(media);

  @override
  Future<MediaCaptureCallResult<MediaCaptureMaterializedMediaReleased>>
  releaseMaterializedMedia(MediaCaptureExportHandle exportHandle) =>
      _client.releaseMaterializedMedia(exportHandle);

  @override
  Future<MediaCaptureCallResult<MediaCaptureMediaReleased>> releaseMedia(
    MediaCaptureMediaHandle mediaHandle,
  ) => _client.releaseMedia(mediaHandle);

  @override
  Future<void> dispose() => _client.dispose();
}

final class NativeSupportMediaPicker implements SupportMediaPicker {
  NativeSupportMediaPicker({
    required MediaResourceStore store,
    MediaCaptureClient? client,
    ImagePicker? imagePicker,
  }) : this.withDependencies(
         SupportMediaCaptureClientGateway(client ?? MediaCaptureClient()),
         imagePicker ?? ImagePicker(),
         store: store,
         playbackProbe: createMediaPlaybackProbe(store: store),
         posterService: createMediaPosterService(store: store),
       );

  NativeSupportMediaPicker.withDependencies(
    this._cameraGateway,
    this._imagePicker, {
    required MediaResourceStore store,
    required MediaPlaybackProbe playbackProbe,
    required MediaPosterService posterService,
  }) : _store = store,
       _playbackProbe = playbackProbe,
       _posterService = posterService;

  static const double galleryImageMaxWidth = 4096;
  static const double galleryImageMaxHeight = 4096;

  final SupportCameraMediaGateway _cameraGateway;
  final ImagePicker _imagePicker;
  final MediaResourceStore _store;
  final MediaPlaybackProbe _playbackProbe;
  final MediaPosterService _posterService;
  final List<MediaCaptureConfirmedMedia> _retainedMedia =
      <MediaCaptureConfirmedMedia>[];
  final List<MediaCaptureExportHandle> _retainedExports =
      <MediaCaptureExportHandle>[];
  final List<MediaResourceLease> _retainedResourceLeases =
      <MediaResourceLease>[];

  Future<SupportMediaPickResult>? _activePick;
  Future<void>? _clearDraftsFuture;
  Future<void>? _disposeFuture;
  var _generation = 0;
  var _disposeRequested = false;

  @override
  Future<SupportMediaPickResult> pick(SupportMediaSource source) {
    if (_disposeRequested ||
        _clearDraftsFuture != null ||
        _activePick != null) {
      _reportPickerUnavailable(
        _SupportMediaPickerStateException(
          disposeRequested: _disposeRequested,
          clearingDrafts: _clearDraftsFuture != null,
          pickActive: _activePick != null,
        ),
        context: 'while starting a Support media pick',
      );
      return Future<SupportMediaPickResult>.value(_unavailableFailure);
    }
    final generation = _generation;
    final operation = switch (source) {
      SupportMediaSource.camera => _capture(generation),
      SupportMediaSource.gallery => _pickFromGallery(generation),
    };
    _activePick = operation;
    return operation.whenComplete(() {
      if (identical(_activePick, operation)) {
        _activePick = null;
      }
    });
  }

  Future<SupportMediaPickResult> _pickFromGallery(int generation) async {
    try {
      final file = await _imagePicker.pickMedia(
        maxWidth: galleryImageMaxWidth,
        maxHeight: galleryImageMaxHeight,
        requestFullMetadata: false,
      );
      if (!_isCurrent(generation)) {
        return _unavailableFailure;
      }
      if (file == null) {
        return const SupportMediaPickCanceled();
      }
      final classification = _classify(file);
      if (classification == null) {
        return _invalidMediaFailure;
      }
      final length = await file.length();
      final maximumBytes = classification.kind == MediaResourceKind.image
          ? _galleryImageMaxBytes
          : _galleryVideoMaxBytes;
      if (length <= 0) {
        return _invalidMediaFailure;
      }
      if (length > maximumBytes) {
        return _tooLargeFailure;
      }
      if (!_isCurrent(generation)) {
        return _unavailableFailure;
      }
      final imported = await _store.importFile(
        MediaImportRequest(
          sourceUri: Uri.file(file.path),
          kind: classification.kind,
          declaredContentType: classification.contentType,
          declaredLength: length,
        ),
      );
      if (imported case MediaResourceError<OwnedMediaResource>(
        :final failure,
      )) {
        return SupportMediaPickFailed(_mapStoreFailure(failure));
      }
      final owned =
          (imported as MediaResourceSuccess<OwnedMediaResource>).value;
      if (!_isCurrent(generation)) {
        await _releaseOrRetainResource(owned.initialLease);
        return _unavailableFailure;
      }
      final prepared = await _prepareAttachment(
        owned,
        label: _displayName(
          file,
          fallback: classification.kind == MediaResourceKind.image
              ? 'Gallery photo'
              : 'Gallery video',
        ),
      );
      if (prepared is! SupportMediaPickSuccess) {
        await _releaseOrRetainResource(owned.initialLease);
      }
      return prepared;
    } on PlatformException catch (error) {
      return SupportMediaPickFailed(
        SupportMediaPickFailure(_mapPickerFailure(error.code)),
      );
    } on IOException {
      return const SupportMediaPickFailed(
        SupportMediaPickFailure(SupportMediaPickFailureCode.readFailed),
      );
    } on Object {
      return _unavailableFailure;
    }
  }

  Future<SupportMediaPickResult> _capture(int generation) async {
    await _retryRetainedCleanup(attempts: 1);
    if (_retainedMedia.isNotEmpty || _retainedExports.isNotEmpty) {
      _reportPickerUnavailable(
        _SupportMediaCleanupPendingException(
          retainedMediaCount: _retainedMedia.length,
          retainedExportCount: _retainedExports.length,
        ),
        context: 'while cleaning up a previous Support capture',
      );
      return _unavailableFailure;
    }
    MediaCaptureConfirmedMedia? confirmed;
    MediaCaptureExportHandle? exportHandle;
    OwnedMediaResource? owned;
    var attachmentTransferred = false;
    var stage = _SupportCaptureStage.presentation;
    try {
      final outcome = await _cameraGateway.presentCaptureFlow(
        MediaCaptureConfig(
          enabledMediaTypes: const <MediaCaptureMediaType>{
            MediaCaptureMediaType.photo,
            MediaCaptureMediaType.video,
          },
          preferredCamera: MediaCaptureCamera.rear,
          audioEnabled: true,
          maxVideoDurationMillis: _supportVideoDurationMillis,
        ),
      );
      switch (outcome) {
        case MediaCaptureFlowCancelled():
          return _isCurrent(generation)
              ? const SupportMediaPickCanceled()
              : _unavailableFailure;
        case MediaCaptureFlowFailure(:final failure):
          if (!_isCurrent(generation)) {
            return _unavailableFailure;
          }
          final mapped = _mapCaptureFailure(failure);
          if (mapped.code == SupportMediaPickFailureCode.unavailable) {
            _reportPickerUnavailable(
              failure,
              context: 'while presenting the native Support capture flow',
            );
          }
          return SupportMediaPickFailed(mapped);
        case MediaCaptureFlowConfirmed(:final media):
          confirmed = media;
      }
      if (!_isCurrent(generation)) {
        return _unavailableFailure;
      }

      stage = _SupportCaptureStage.materialization;
      final materializedResult = await _cameraGateway.materializeMedia(
        confirmed,
      );
      final MediaCaptureMaterializedMedia materialized;
      switch (materializedResult) {
        case MediaCaptureCallFailure<MediaCaptureMaterializedMedia>(
          :final failure,
        ):
          final mapped = _mapCaptureFailure(failure);
          if (mapped.code == SupportMediaPickFailureCode.unavailable) {
            _reportPickerUnavailable(
              failure,
              context: 'while materializing captured Support media',
            );
          }
          return SupportMediaPickFailed(mapped);
        case MediaCaptureCallSuccess<MediaCaptureMaterializedMedia>(
          :final value,
        ):
          materialized = value;
          exportHandle = value.exportHandle;
      }
      if (!_isCurrent(generation)) {
        return _unavailableFailure;
      }
      stage = _SupportCaptureStage.importing;
      final imported = await _store.importFile(
        MediaImportRequest(
          sourceUri: materialized.fileUri,
          kind: materialized.mediaType == MediaCaptureMediaType.photo
              ? MediaResourceKind.image
              : MediaResourceKind.video,
          declaredContentType: materialized.contentType,
          declaredLength: materialized.byteLength,
          duration: materialized.durationMillis == null
              ? null
              : Duration(milliseconds: materialized.durationMillis!),
        ),
      );
      if (imported case MediaResourceError<OwnedMediaResource>(
        :final failure,
      )) {
        return SupportMediaPickFailed(_mapStoreFailure(failure));
      }
      owned = (imported as MediaResourceSuccess<OwnedMediaResource>).value;

      stage = _SupportCaptureStage.releasingNativeMedia;
      await _releaseOrRetainExport(exportHandle);
      exportHandle = null;
      await _releaseOrRetainMedia(confirmed);
      confirmed = null;

      if (!_isCurrent(generation)) {
        return _unavailableFailure;
      }
      stage = _SupportCaptureStage.preparingAttachment;
      final result = await _prepareAttachment(
        owned,
        label: owned.kind == MediaResourceKind.image
            ? 'Camera photo'
            : 'Camera video',
      );
      attachmentTransferred = result is SupportMediaPickSuccess;
      return result;
    } on Object catch (error, stackTrace) {
      _reportPickerUnavailable(
        error,
        stackTrace: stackTrace,
        context: 'during Support capture ${stage.description}',
      );
      return _unavailableFailure;
    } finally {
      if (exportHandle != null) {
        await _releaseOrRetainExport(exportHandle);
      }
      if (confirmed != null) {
        await _releaseOrRetainMedia(confirmed);
      }
      if (owned != null && !attachmentTransferred) {
        await _releaseOrRetainResource(owned.initialLease);
      }
    }
  }

  Future<SupportMediaPickResult> _prepareAttachment(
    OwnedMediaResource owned, {
    required String label,
  }) async {
    if (owned.kind == MediaResourceKind.image) {
      return SupportMediaPickSuccess(
        SupportMediaAttachment(
          resource: owned,
          label: label,
          duration: owned.duration,
        ),
      );
    }
    late final MediaResourceResult<MediaPlaybackInfo> probeResult;
    try {
      probeResult = await _playbackProbe.probe(owned.resourceId);
    } on Object {
      return _invalidMediaFailure;
    }
    if (probeResult case MediaResourceError<MediaPlaybackInfo>()) {
      return _invalidMediaFailure;
    }
    final playbackInfo =
        (probeResult as MediaResourceSuccess<MediaPlaybackInfo>).value;
    MediaResourceResult<MediaPoster>? posterResult;
    try {
      posterResult = await _posterService.generate(owned.resourceId);
    } on Object {
      // A bounded poster is optional after the platform decoder accepts video.
    }
    final poster = switch (posterResult) {
      MediaResourceSuccess<MediaPoster>(:final value) => value,
      MediaResourceError<MediaPoster>() || null => null,
    };
    return SupportMediaPickSuccess(
      SupportMediaAttachment(
        resource: owned,
        label: label,
        duration: playbackInfo.duration,
        poster: poster,
      ),
    );
  }

  @override
  Future<void> release(SupportMediaAttachment attachment) =>
      _releaseOrRetainResource(attachment.resource.initialLease);

  @override
  Future<void> clearDrafts() {
    final existing = _clearDraftsFuture;
    if (existing != null) {
      return existing;
    }
    _generation += 1;
    final clear = _performClearDrafts();
    _clearDraftsFuture = clear;
    return clear.whenComplete(() {
      if (identical(_clearDraftsFuture, clear)) {
        _clearDraftsFuture = null;
      }
    });
  }

  Future<void> _performClearDrafts() async {
    if (_activePick != null &&
        !await _cameraGateway.dismissActivePresentation()) {
      throw const SupportMediaPickerDisposalException();
    }
    await _activePick;
    await _retryRetainedCleanup(attempts: _cleanupAttempts);
    if (_retainedMedia.isNotEmpty ||
        _retainedExports.isNotEmpty ||
        _retainedResourceLeases.isNotEmpty) {
      throw const SupportMediaPickerDisposalException();
    }
  }

  @override
  Future<void> dispose() {
    final existing = _disposeFuture;
    if (existing != null) {
      return existing;
    }
    _disposeRequested = true;
    _generation += 1;
    return _disposeFuture = _performDispose();
  }

  Future<void> _performDispose() async {
    try {
      await _clearDraftsFuture;
    } on Object {
      // Final disposal retries retained cleanup below.
    }
    if (_activePick != null &&
        !await _cameraGateway.dismissActivePresentation()) {
      _disposeFuture = null;
      throw const SupportMediaPickerDisposalException();
    }
    await _activePick;
    await _retryRetainedCleanup(attempts: _cleanupAttempts);
    var gatewayDisposed = true;
    try {
      await _cameraGateway.dispose();
    } on Object {
      gatewayDisposed = false;
    }
    if (_retainedMedia.isNotEmpty ||
        _retainedExports.isNotEmpty ||
        _retainedResourceLeases.isNotEmpty ||
        !gatewayDisposed) {
      _disposeFuture = null;
      throw const SupportMediaPickerDisposalException();
    }
  }

  bool _isCurrent(int generation) =>
      !_disposeRequested && generation == _generation;

  Future<void> _retryRetainedCleanup({required int attempts}) async {
    for (
      var attempt = 0;
      attempt < attempts &&
          (_retainedExports.isNotEmpty ||
              _retainedMedia.isNotEmpty ||
              _retainedResourceLeases.isNotEmpty);
      attempt += 1
    ) {
      for (final handle in List<MediaCaptureExportHandle>.of(
        _retainedExports,
      )) {
        if (await _releaseExport(handle)) {
          _retainedExports.removeWhere((item) => item.value == handle.value);
        }
      }
      for (final media in List<MediaCaptureConfirmedMedia>.of(_retainedMedia)) {
        if (await _releaseMedia(media)) {
          _retainedMedia.removeWhere(
            (item) => item.mediaHandle.value == media.mediaHandle.value,
          );
        }
      }
      for (final lease in List<MediaResourceLease>.of(
        _retainedResourceLeases,
      )) {
        if (await _releaseResource(lease)) {
          _retainedResourceLeases.removeWhere((item) => identical(item, lease));
        }
      }
    }
  }

  Future<void> _releaseOrRetainExport(MediaCaptureExportHandle handle) async {
    if (!await _releaseExport(handle) &&
        !_retainedExports.any((item) => item.value == handle.value)) {
      _retainedExports.add(handle);
    }
  }

  Future<void> _releaseOrRetainMedia(MediaCaptureConfirmedMedia media) async {
    if (!await _releaseMedia(media) &&
        !_retainedMedia.any(
          (item) => item.mediaHandle.value == media.mediaHandle.value,
        )) {
      _retainedMedia.add(media);
    }
  }

  Future<void> _releaseOrRetainResource(MediaResourceLease lease) async {
    if (!await _releaseResource(lease) &&
        !_retainedResourceLeases.any((item) => identical(item, lease))) {
      _retainedResourceLeases.add(lease);
    }
  }

  Future<bool> _releaseResource(MediaResourceLease lease) async {
    try {
      return await _store.release(lease) is MediaResourceSuccess<void>;
    } on Object {
      return false;
    }
  }

  Future<bool> _releaseExport(MediaCaptureExportHandle handle) async {
    try {
      return switch (await _cameraGateway.releaseMaterializedMedia(handle)) {
        MediaCaptureCallSuccess<MediaCaptureMaterializedMediaReleased>() =>
          true,
        MediaCaptureCallFailure<MediaCaptureMaterializedMediaReleased>(
          :final failure,
        ) =>
          failure.code == MediaCaptureFailureCode.materializedMediaInvalid,
      };
    } on Object {
      return false;
    }
  }

  Future<bool> _releaseMedia(MediaCaptureConfirmedMedia media) async {
    try {
      return switch (await _cameraGateway.releaseMedia(media.mediaHandle)) {
        MediaCaptureCallSuccess<MediaCaptureMediaReleased>(:final value) =>
          value.mediaHandle.value == media.mediaHandle.value,
        MediaCaptureCallFailure<MediaCaptureMediaReleased>(:final failure) =>
          failure.code == MediaCaptureFailureCode.mediaInvalid,
      };
    } on Object {
      return false;
    }
  }

  _GalleryMedia? _classify(XFile file) {
    final mimeType = file.mimeType?.toLowerCase();
    if (mimeType != null) {
      return switch (mimeType) {
        'image/jpeg' => const _GalleryMedia(
          MediaResourceKind.image,
          'image/jpeg',
        ),
        'image/png' => const _GalleryMedia(
          MediaResourceKind.image,
          'image/png',
        ),
        'video/mp4' => const _GalleryMedia(
          MediaResourceKind.video,
          'video/mp4',
        ),
        'video/quicktime' => const _GalleryMedia(
          MediaResourceKind.video,
          'video/quicktime',
        ),
        _ => null,
      };
    }
    final name = file.name.toLowerCase();
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) {
      return const _GalleryMedia(MediaResourceKind.image, 'image/jpeg');
    }
    if (name.endsWith('.png')) {
      return const _GalleryMedia(MediaResourceKind.image, 'image/png');
    }
    if (name.endsWith('.mp4')) {
      return const _GalleryMedia(MediaResourceKind.video, 'video/mp4');
    }
    if (name.endsWith('.mov')) {
      return const _GalleryMedia(MediaResourceKind.video, 'video/quicktime');
    }
    return null;
  }

  String _displayName(XFile file, {required String fallback}) {
    final normalized = file.name.trim();
    if (normalized.isEmpty) {
      return fallback;
    }
    return normalized.length <= 80 ? normalized : normalized.substring(0, 80);
  }

  SupportMediaPickFailure _mapStoreFailure(MediaResourceFailure failure) {
    return SupportMediaPickFailure(switch (failure.code) {
      MediaResourceFailureCode.tooLarge => SupportMediaPickFailureCode.tooLarge,
      MediaResourceFailureCode.unsupportedMedia ||
      MediaResourceFailureCode.decodeFailed ||
      MediaResourceFailureCode.playbackFailed =>
        SupportMediaPickFailureCode.invalidMedia,
      _ => SupportMediaPickFailureCode.readFailed,
    });
  }

  SupportMediaPickFailureCode _mapPickerFailure(String code) {
    final normalized = code.toLowerCase();
    if (normalized.contains('denied') || normalized.contains('restricted')) {
      return SupportMediaPickFailureCode.permissionDenied;
    }
    return SupportMediaPickFailureCode.unavailable;
  }

  SupportMediaPickFailure _mapCaptureFailure(MediaCaptureFailure failure) =>
      SupportMediaPickFailure(switch (failure.code) {
        MediaCaptureFailureCode.permissionDenied ||
        MediaCaptureFailureCode.permissionRestricted ||
        MediaCaptureFailureCode.permissionPermanentlyDenied =>
          SupportMediaPickFailureCode.permissionDenied,
        MediaCaptureFailureCode.mediaExportTooLarge =>
          SupportMediaPickFailureCode.tooLarge,
        MediaCaptureFailureCode.mediaInvalid ||
        MediaCaptureFailureCode.materializedMediaInvalid =>
          SupportMediaPickFailureCode.invalidMedia,
        MediaCaptureFailureCode.mediaExportReadFailed ||
        MediaCaptureFailureCode.mediaExportWriteFailed =>
          SupportMediaPickFailureCode.readFailed,
        _ => SupportMediaPickFailureCode.unavailable,
      });

  void _reportPickerUnavailable(
    Object exception, {
    required String context,
    StackTrace? stackTrace,
  }) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: exception,
        stack: stackTrace ?? StackTrace.current,
        library: 'app_features',
        context: ErrorDescription(context),
      ),
    );
  }
}

enum _SupportCaptureStage {
  presentation('presentation'),
  materialization('materialization'),
  importing('import'),
  releasingNativeMedia('native cleanup'),
  preparingAttachment('video preparation');

  const _SupportCaptureStage(this.description);

  final String description;
}

final class _SupportMediaPickerStateException implements Exception {
  const _SupportMediaPickerStateException({
    required this.disposeRequested,
    required this.clearingDrafts,
    required this.pickActive,
  });

  final bool disposeRequested;
  final bool clearingDrafts;
  final bool pickActive;

  @override
  String toString() =>
      'SupportMediaPickerStateException('
      'disposeRequested: $disposeRequested, '
      'clearingDrafts: $clearingDrafts, pickActive: $pickActive)';
}

final class _SupportMediaCleanupPendingException implements Exception {
  const _SupportMediaCleanupPendingException({
    required this.retainedMediaCount,
    required this.retainedExportCount,
  });

  final int retainedMediaCount;
  final int retainedExportCount;

  @override
  String toString() =>
      'SupportMediaCleanupPendingException('
      'retainedMediaCount: $retainedMediaCount, '
      'retainedExportCount: $retainedExportCount)';
}

final class _GalleryMedia {
  const _GalleryMedia(this.kind, this.contentType);

  final MediaResourceKind kind;
  final String contentType;
}

const SupportMediaPickFailed _unavailableFailure = SupportMediaPickFailed(
  SupportMediaPickFailure(SupportMediaPickFailureCode.unavailable),
);

const SupportMediaPickFailed _invalidMediaFailure = SupportMediaPickFailed(
  SupportMediaPickFailure(SupportMediaPickFailureCode.invalidMedia),
);

const SupportMediaPickFailed _tooLargeFailure = SupportMediaPickFailed(
  SupportMediaPickFailure(SupportMediaPickFailureCode.tooLarge),
);
