import 'dart:typed_data';

import 'package:flutter/foundation.dart' show internal;

const int mediaCaptureMaxHandleLength = 128;
const int mediaCaptureMinVideoDurationMillis = 1;
const int mediaCaptureMaxVideoDurationMillis = 60000;
const int mediaCaptureMinThumbnailEdge = 64;
const int mediaCaptureMaxThumbnailEdge = 512;
const int mediaCaptureMaxThumbnailBytes = 524288;
const int mediaCaptureMinExportHandleLength = 22;
const int mediaCaptureMaxExportHandleLength = 64;
const int mediaCaptureMaxFileUriLength = 4096;
const int mediaCaptureMaxMaterializedBytes = 52428800;
const int mediaCaptureMaterializedTtlMillis = 300000;

enum MediaCaptureMediaType {
  photo('photo'),
  video('video');

  const MediaCaptureMediaType(this.wireName);

  final String wireName;
}

enum MediaCaptureCamera {
  rear('rear'),
  front('front');

  const MediaCaptureCamera(this.wireName);

  final String wireName;
}

enum MediaCaptureFlashMode {
  off('off'),
  on('on'),
  auto('auto'),
  torch('torch');

  const MediaCaptureFlashMode(this.wireName);

  final String wireName;
}

enum MediaCaptureOperation {
  startSession('start_session'),
  takePhoto('take_photo'),
  startRecording('start_recording'),
  stopRecording('stop_recording'),
  switchCamera('switch_camera'),
  setFlashMode('set_flash_mode'),
  setFocusPoint('set_focus_point'),
  setZoom('set_zoom'),
  retake('retake'),
  confirm('confirm'),
  cancel('cancel'),
  releaseMedia('release_media'),
  readMediaThumbnail('read_media_thumbnail'),
  presentCaptureFlow('present_capture_flow'),
  dismissCaptureFlow('dismiss_capture_flow'),
  materializeMediaResource('materialize_media_resource'),
  releaseMaterializedMedia('release_materialized_media'),
  unknownOperation('unknown_operation');

  const MediaCaptureOperation(this.wireName);

  final String wireName;
}

enum MediaCaptureFailureCode {
  permissionDenied('permission_denied', recoverable: true, terminal: true),
  permissionRestricted(
    'permission_restricted',
    recoverable: false,
    terminal: true,
  ),
  permissionPermanentlyDenied(
    'permission_permanently_denied',
    recoverable: false,
    terminal: true,
  ),
  resourceInUse('resource_in_use', recoverable: true, terminal: true),
  storageFull('storage_full', recoverable: true, terminal: true),
  encodingFailed('encoding_failed', recoverable: true, terminal: true),
  mediaInvalid('media_invalid', recoverable: false, terminal: false),
  sessionInvalid('session_invalid', recoverable: false, terminal: false),
  unsupportedCapability(
    'unsupported_capability',
    recoverable: true,
    terminal: false,
  ),
  systemInterrupted('system_interrupted', recoverable: true, terminal: true),
  sessionConflict('session_conflict', recoverable: true, terminal: false),
  invalidState('invalid_state', recoverable: true, terminal: false),
  invalidArgument('invalid_argument', recoverable: true, terminal: false),
  sessionTimeout('session_timeout', recoverable: true, terminal: true),
  thumbnailGenerationFailed(
    'thumbnail_generation_failed',
    recoverable: true,
    terminal: false,
  ),
  thumbnailGenerationCancelled(
    'thumbnail_generation_cancelled',
    recoverable: true,
    terminal: false,
  ),
  thumbnailOverloaded(
    'thumbnail_overloaded',
    recoverable: true,
    terminal: false,
  ),
  incompatibleWireVersion(
    'incompatible_wire_version',
    recoverable: false,
    terminal: false,
  ),
  invalidWirePayload(
    'invalid_wire_payload',
    recoverable: true,
    terminal: false,
  ),
  duplicateRequest('duplicate_request', recoverable: true, terminal: false),
  bridgeUnavailable('bridge_unavailable', recoverable: true, terminal: false),
  bridgeOverloaded('bridge_overloaded', recoverable: true, terminal: false),
  wireEncodingFailed(
    'wire_encoding_failed',
    recoverable: false,
    terminal: false,
  ),
  listenerAlreadyActive(
    'listener_already_active',
    recoverable: true,
    terminal: false,
  ),
  presentationConflict(
    'presentation_conflict',
    recoverable: true,
    terminal: false,
  ),
  mediaExportConflict(
    'media_export_conflict',
    recoverable: true,
    terminal: false,
  ),
  mediaExportOverloaded(
    'media_export_overloaded',
    recoverable: true,
    terminal: false,
  ),
  mediaExportTooLarge(
    'media_export_too_large',
    recoverable: true,
    terminal: false,
  ),
  mediaExportSinkRejected(
    'media_export_sink_rejected',
    recoverable: true,
    terminal: false,
  ),
  mediaExportReadFailed(
    'media_export_read_failed',
    recoverable: true,
    terminal: false,
  ),
  mediaExportWriteFailed(
    'media_export_write_failed',
    recoverable: true,
    terminal: false,
  ),
  mediaExportCancelled(
    'media_export_cancelled',
    recoverable: true,
    terminal: false,
  ),
  mediaExportTimedOut(
    'media_export_timed_out',
    recoverable: true,
    terminal: false,
  ),
  transferStoreOverloaded(
    'transfer_store_overloaded',
    recoverable: true,
    terminal: false,
  ),
  transferStoreUnavailable(
    'transfer_store_unavailable',
    recoverable: true,
    terminal: false,
  ),
  materializedMediaInvalid(
    'materialized_media_invalid',
    recoverable: true,
    terminal: false,
  );

  const MediaCaptureFailureCode(
    this.wireName, {
    required this.recoverable,
    required this.terminal,
  });

  final String wireName;
  final bool recoverable;
  final bool terminal;
}

enum MediaCaptureCapabilityFailure {
  permissionDenied('permission_denied'),
  permissionRestricted('permission_restricted'),
  permissionPermanentlyDenied('permission_permanently_denied'),
  resourceInUse('resource_in_use'),
  storageFull('storage_full'),
  encodingFailed('encoding_failed'),
  mediaInvalid('media_invalid'),
  sessionInvalid('session_invalid'),
  unsupportedCapability('unsupported_capability'),
  systemInterrupted('system_interrupted'),
  sessionConflict('session_conflict'),
  invalidState('invalid_state'),
  invalidArgument('invalid_argument'),
  sessionTimeout('session_timeout'),
  thumbnailGenerationFailed('thumbnail_generation_failed'),
  thumbnailGenerationCancelled('thumbnail_generation_cancelled'),
  thumbnailOverloaded('thumbnail_overloaded'),
  mediaExportConflict('media_export_conflict'),
  mediaExportOverloaded('media_export_overloaded'),
  mediaExportTooLarge('media_export_too_large'),
  mediaExportSinkRejected('media_export_sink_rejected'),
  mediaExportReadFailed('media_export_read_failed'),
  mediaExportWriteFailed('media_export_write_failed'),
  mediaExportCancelled('media_export_cancelled'),
  mediaExportTimedOut('media_export_timed_out'),
  attachmentGenerationRetired('attachment_generation_retired'),
  attachmentTargetConflict('attachment_target_conflict');

  const MediaCaptureCapabilityFailure(this.wireName);

  final String wireName;
}

enum MediaCaptureFailureField {
  wireVersion('wireVersion'),
  requestId('requestId'),
  payload('payload'),
  resultType('resultType'),
  eventType('eventType'),
  failureType('failureType'),
  enabledMediaTypes('enabledMediaTypes'),
  preferredCamera('preferredCamera'),
  audioEnabled('audioEnabled'),
  maxVideoDurationMillis('maxVideoDurationMillis'),
  sessionHandle('sessionHandle'),
  flashMode('flashMode'),
  normalizedX('normalizedX'),
  normalizedY('normalizedY'),
  zoomFactor('zoomFactor'),
  mediaHandle('mediaHandle'),
  activeCamera('activeCamera'),
  availableCameras('availableCameras'),
  switchCameraSupported('switchCameraSupported'),
  supportedFlashModes('supportedFlashModes'),
  focusPointSupported('focusPointSupported'),
  minZoomFactor('minZoomFactor'),
  maxZoomFactor('maxZoomFactor'),
  audioIncluded('audioIncluded'),
  mediaType('mediaType'),
  pixelWidth('pixelWidth'),
  pixelHeight('pixelHeight'),
  durationMillis('durationMillis'),
  orientationDegrees('orientationDegrees'),
  byteLength('byteLength'),
  leaseExpiresAt('leaseExpiresAt'),
  terminalFailureId('terminalFailureId'),
  maxPixelEdge('maxPixelEdge'),
  thumbnailCopy('thumbnailCopy'),
  thumbnailByteLength('thumbnailByteLength'),
  thumbnailPixelWidth('thumbnailPixelWidth'),
  thumbnailPixelHeight('thumbnailPixelHeight'),
  thumbnailContentType('thumbnailContentType'),
  thumbnailOrientationDegrees('thumbnailOrientationDegrees'),
  posterFrameMillis('posterFrameMillis'),
  exportHandle('exportHandle'),
  fileUri('fileUri'),
  contentType('contentType'),
  expiresAt('expiresAt'),
  integritySha256('integritySha256'),
  unknownField('unknown_field');

  const MediaCaptureFailureField(this.wireName);

  final String wireName;
}

enum MediaCaptureFailureReason {
  missingRequiredField('missing_required_field'),
  unknownField('unknown_field'),
  typeMismatch('type_mismatch'),
  nullNotAllowed('null_not_allowed'),
  nonFinite('non_finite'),
  outOfRange('out_of_range'),
  invalidEnum('invalid_enum'),
  invalidFormat('invalid_format'),
  integerOverflow('integer_overflow'),
  resultTypeMismatch('result_type_mismatch'),
  nativeValueUnencodable('native_value_unencodable');

  const MediaCaptureFailureReason(this.wireName);

  final String wireName;
}

enum MediaCaptureLifecycleReason {
  engineDetached('engine_detached'),
  activityDestroyed('activity_destroyed'),
  viewControllerDestroyed('view_controller_destroyed'),
  adapterDisposed('adapter_disposed');

  const MediaCaptureLifecycleReason(this.wireName);

  final String wireName;
}

enum MediaCaptureCapacity {
  pendingRequests('pending_requests'),
  completedRequestTombstones('completed_request_tombstones'),
  activePresentation('active_presentation'),
  activeExports('active_exports'),
  activeExportBytes('active_export_bytes'),
  releaseTombstones('release_tombstones');

  const MediaCaptureCapacity(this.wireName);

  final String wireName;
}

enum MediaCaptureTerminalFailure {
  permissionDenied('permission_denied'),
  permissionRestricted('permission_restricted'),
  permissionPermanentlyDenied('permission_permanently_denied'),
  resourceInUse('resource_in_use'),
  storageFull('storage_full'),
  encodingFailed('encoding_failed'),
  systemInterrupted('system_interrupted'),
  sessionTimeout('session_timeout');

  const MediaCaptureTerminalFailure(this.wireName);

  final String wireName;
}

final class MediaCaptureFailureDiagnostics {
  const MediaCaptureFailureDiagnostics({
    this.operation,
    this.capabilityFailure,
    this.actualWireVersion,
    this.expectedWireVersion,
    this.field,
    this.reason,
    this.lifecycleReason,
    this.capacity,
  });

  final MediaCaptureOperation? operation;
  final MediaCaptureCapabilityFailure? capabilityFailure;
  final int? actualWireVersion;
  final int? expectedWireVersion;
  final MediaCaptureFailureField? field;
  final MediaCaptureFailureReason? reason;
  final MediaCaptureLifecycleReason? lifecycleReason;
  final MediaCaptureCapacity? capacity;
}

final class MediaCaptureFailure {
  const MediaCaptureFailure({
    required this.code,
    this.diagnostics = const MediaCaptureFailureDiagnostics(),
  });

  final MediaCaptureFailureCode code;
  final MediaCaptureFailureDiagnostics diagnostics;

  bool get recoverable => code.recoverable;
  bool get terminal => code.terminal;

  @override
  String toString() => 'MediaCaptureFailure(${code.wireName}, <redacted>)';
}

final class MediaCaptureDisposalException implements Exception {
  const MediaCaptureDisposalException();

  @override
  String toString() =>
      'MediaCaptureDisposalException(cleanup_incomplete, <redacted>)';
}

sealed class MediaCaptureCallResult<T> {
  const MediaCaptureCallResult();

  const factory MediaCaptureCallResult.success(T value) =
      MediaCaptureCallSuccess<T>;

  const factory MediaCaptureCallResult.failure(MediaCaptureFailure failure) =
      MediaCaptureCallFailure<T>;
}

final class MediaCaptureCallSuccess<T> extends MediaCaptureCallResult<T> {
  const MediaCaptureCallSuccess(this.value);

  final T value;
}

final class MediaCaptureCallFailure<T> extends MediaCaptureCallResult<T> {
  const MediaCaptureCallFailure(this.failure);

  final MediaCaptureFailure failure;
}

sealed class MediaCaptureFlowOutcome {
  const MediaCaptureFlowOutcome();
}

final class MediaCaptureFlowConfirmed extends MediaCaptureFlowOutcome {
  const MediaCaptureFlowConfirmed(this.media);

  final MediaCaptureConfirmedMedia media;
}

final class MediaCaptureFlowCancelled extends MediaCaptureFlowOutcome {
  const MediaCaptureFlowCancelled();
}

final class MediaCaptureFlowFailure extends MediaCaptureFlowOutcome {
  const MediaCaptureFlowFailure(this.failure);

  final MediaCaptureFailure failure;
}

final class MediaCaptureConfig {
  MediaCaptureConfig({
    required Set<MediaCaptureMediaType> enabledMediaTypes,
    required this.preferredCamera,
    required this.audioEnabled,
    required this.maxVideoDurationMillis,
  }) : enabledMediaTypes = Set<MediaCaptureMediaType>.unmodifiable(
         enabledMediaTypes,
       ) {
    if (enabledMediaTypes.isEmpty || enabledMediaTypes.length > 2) {
      throw ArgumentError.value(
        enabledMediaTypes.length,
        'enabledMediaTypes',
        'must contain one or two media types',
      );
    }
    if (maxVideoDurationMillis < mediaCaptureMinVideoDurationMillis ||
        maxVideoDurationMillis > mediaCaptureMaxVideoDurationMillis) {
      throw RangeError.range(
        maxVideoDurationMillis,
        mediaCaptureMinVideoDurationMillis,
        mediaCaptureMaxVideoDurationMillis,
        'maxVideoDurationMillis',
      );
    }
  }

  final Set<MediaCaptureMediaType> enabledMediaTypes;
  final MediaCaptureCamera preferredCamera;
  final bool audioEnabled;
  final int maxVideoDurationMillis;
}

final class MediaCaptureSession {
  MediaCaptureSession(this.handle) {
    _checkHandle(handle, 'handle');
  }

  final String handle;
}

final class MediaCaptureMediaHandle {
  MediaCaptureMediaHandle(this.value) {
    _checkHandle(value, 'value');
  }

  final String value;
}

final class MediaCaptureControlApplied {
  const MediaCaptureControlApplied(this.session);

  final MediaCaptureSession session;
}

final class MediaCaptureRecordingStarted {
  const MediaCaptureRecordingStarted({
    required this.session,
    required this.audioIncluded,
  });

  final MediaCaptureSession session;
  final bool audioIncluded;
}

final class MediaCapturePreview {
  const MediaCapturePreview({
    required this.mediaHandle,
    required this.mediaType,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.durationMillis,
    required this.orientationDegrees,
    required this.byteLength,
  });

  final MediaCaptureMediaHandle mediaHandle;
  final MediaCaptureMediaType mediaType;
  final int pixelWidth;
  final int pixelHeight;
  final int? durationMillis;
  final int orientationDegrees;
  final int byteLength;
}

final class MediaCaptureRetakeReady {
  const MediaCaptureRetakeReady(this.session);

  final MediaCaptureSession session;
}

final class MediaCaptureSessionCancelled {
  const MediaCaptureSessionCancelled(this.session);

  final MediaCaptureSession session;
}

final class MediaCaptureMediaReleased {
  const MediaCaptureMediaReleased(this.mediaHandle);

  final MediaCaptureMediaHandle mediaHandle;
}

final class MediaCaptureConfirmedMedia {
  const MediaCaptureConfirmedMedia({
    required this.mediaHandle,
    required this.mediaType,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.durationMillis,
    required this.orientationDegrees,
    required this.byteLength,
    required this.leaseExpiresAtMillis,
  });

  final MediaCaptureMediaHandle mediaHandle;
  final MediaCaptureMediaType mediaType;
  final int pixelWidth;
  final int pixelHeight;
  final int? durationMillis;
  final int orientationDegrees;
  final int byteLength;
  final int leaseExpiresAtMillis;
}

final class MediaCaptureExportHandle {
  MediaCaptureExportHandle(this.value) {
    if (!_exportHandlePattern.hasMatch(value)) {
      throw ArgumentError.value('<redacted>', 'value', 'invalid export handle');
    }
  }

  final String value;

  @override
  String toString() => 'MediaCaptureExportHandle(<redacted>)';
}

final class MediaCaptureMaterializedMedia {
  MediaCaptureMaterializedMedia({
    required this.exportHandle,
    required this.fileUri,
    required this.mediaType,
    required this.contentType,
    required this.byteLength,
    required this.durationMillis,
    required this.expiresAtMillis,
    required this.integritySha256,
  }) {
    final expectedContentType = mediaType == MediaCaptureMediaType.photo
        ? 'image/jpeg'
        : 'video/mp4';
    if (contentType != expectedContentType ||
        byteLength < 1 ||
        byteLength > mediaCaptureMaxMaterializedBytes ||
        expiresAtMillis < 0 ||
        (mediaType == MediaCaptureMediaType.photo && durationMillis != null) ||
        (mediaType == MediaCaptureMediaType.video &&
            (durationMillis == null ||
                durationMillis! < mediaCaptureMinVideoDurationMillis ||
                durationMillis! > mediaCaptureMaxVideoDurationMillis)) ||
        (integritySha256 != null &&
            !_sha256Pattern.hasMatch(integritySha256!))) {
      throw ArgumentError('Invalid materialized media metadata');
    }
  }

  final MediaCaptureExportHandle exportHandle;

  /// A short-lived infrastructure locator. Import it immediately and do not
  /// persist it in domain models, routes, fixtures, analytics, or logs.
  final Uri fileUri;
  final MediaCaptureMediaType mediaType;
  final String contentType;
  final int byteLength;
  final int? durationMillis;
  final int expiresAtMillis;
  final String? integritySha256;

  @override
  String toString() => 'MediaCaptureMaterializedMedia(<redacted>)';
}

final class MediaCaptureMaterializedMediaReleased {
  const MediaCaptureMaterializedMediaReleased();
}

final class MediaCaptureThumbnailRequest {
  MediaCaptureThumbnailRequest({
    required this.mediaHandle,
    required this.maxPixelEdge,
  }) {
    if (maxPixelEdge < mediaCaptureMinThumbnailEdge ||
        maxPixelEdge > mediaCaptureMaxThumbnailEdge) {
      throw RangeError.range(
        maxPixelEdge,
        mediaCaptureMinThumbnailEdge,
        mediaCaptureMaxThumbnailEdge,
        'maxPixelEdge',
      );
    }
  }

  final MediaCaptureMediaHandle mediaHandle;
  final int maxPixelEdge;
}

final class MediaCaptureThumbnail {
  MediaCaptureThumbnail({
    required this.mediaHandle,
    required Uint8List bytes,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.contentType,
    required this.orientationDegrees,
    required this.mediaType,
    required this.posterFrameMillis,
  }) : _bytes = Uint8List.fromList(bytes) {
    if (_bytes.isEmpty || _bytes.length > mediaCaptureMaxThumbnailBytes) {
      throw RangeError.range(
        _bytes.length,
        1,
        mediaCaptureMaxThumbnailBytes,
        'bytes.length',
      );
    }
  }

  final MediaCaptureMediaHandle mediaHandle;
  final Uint8List _bytes;
  final int pixelWidth;
  final int pixelHeight;
  final String contentType;
  final int orientationDegrees;
  final MediaCaptureMediaType mediaType;
  final int? posterFrameMillis;

  int get byteLength => _bytes.length;
  Uint8List get bytes => Uint8List.fromList(_bytes);
}

@internal
void clearMediaCaptureThumbnailForDisposal(MediaCaptureThumbnail thumbnail) {
  thumbnail._bytes.fillRange(0, thumbnail._bytes.length, 0);
}

sealed class MediaCaptureEvent {
  const MediaCaptureEvent();
}

final class MediaCaptureSessionReady extends MediaCaptureEvent {
  MediaCaptureSessionReady({
    required this.session,
    required this.activeCamera,
    required Set<MediaCaptureCamera> availableCameras,
    required this.switchCameraSupported,
    required Set<MediaCaptureFlashMode> supportedFlashModes,
    required this.focusPointSupported,
    required this.minZoomFactor,
    required this.maxZoomFactor,
  }) : availableCameras = Set<MediaCaptureCamera>.unmodifiable(
         Set<MediaCaptureCamera>.of(availableCameras),
       ),
       supportedFlashModes = Set<MediaCaptureFlashMode>.unmodifiable(
         Set<MediaCaptureFlashMode>.of(supportedFlashModes),
       );

  final MediaCaptureSession session;
  final MediaCaptureCamera activeCamera;
  final Set<MediaCaptureCamera> availableCameras;
  final bool switchCameraSupported;
  final Set<MediaCaptureFlashMode> supportedFlashModes;
  final bool focusPointSupported;
  final double minZoomFactor;
  final double maxZoomFactor;
}

final class MediaCaptureSessionFailed extends MediaCaptureEvent {
  const MediaCaptureSessionFailed({
    required this.session,
    required this.terminalFailure,
  });

  final MediaCaptureSession session;
  final MediaCaptureTerminalFailure terminalFailure;
}

final class MediaCapturePreviewReady extends MediaCaptureEvent {
  const MediaCapturePreviewReady({
    required this.session,
    required this.preview,
  });

  final MediaCaptureSession session;
  final MediaCapturePreview preview;
}

final class MediaCaptureLeaseExpired extends MediaCaptureEvent {
  const MediaCaptureLeaseExpired(this.mediaHandle);

  final MediaCaptureMediaHandle mediaHandle;
}

final class MediaCaptureReadRevoked extends MediaCaptureEvent {
  const MediaCaptureReadRevoked(this.mediaHandle);

  final MediaCaptureMediaHandle mediaHandle;
}

final class MediaCaptureAsyncFailure extends MediaCaptureEvent {
  const MediaCaptureAsyncFailure({
    required this.failure,
    required this.session,
  });

  final MediaCaptureFailure failure;
  final MediaCaptureSession session;
}

final class MediaCaptureBridgeFailureEvent extends MediaCaptureEvent {
  const MediaCaptureBridgeFailureEvent(this.failure);

  final MediaCaptureFailure failure;
}

void _checkHandle(String value, String name) {
  if (value.isEmpty || value.length > mediaCaptureMaxHandleLength) {
    throw RangeError.range(value.length, 1, mediaCaptureMaxHandleLength, name);
  }
}

final RegExp _exportHandlePattern = RegExp(
  '^[A-Za-z0-9_-]{$mediaCaptureMinExportHandleLength,'
  '$mediaCaptureMaxExportHandleLength}\$',
);
final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
