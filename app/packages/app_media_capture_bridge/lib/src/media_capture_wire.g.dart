// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generator: media_capture_wire/1
// Source: docs/bridge/contracts/media-capture.wire.json
// Source digest (SHA-256): 76e65a567971ca209e0b4f50412e79002a83eda04869149f21d136a7c6569d27
part of 'media_capture_wire_codec.dart';

const int _generatedMediaCaptureWireVersion = 3;
const String _generatedCommandsChannel = 'com.example.media_capture.commands';
const String _generatedEventsChannel = 'com.example.media_capture.events';

const String _generatedMediaCaptureWireMethodCancel = 'cancel';
const String _generatedMediaCaptureWireMethodConfirm = 'confirm';
const String _generatedMediaCaptureWireMethodDismissCaptureFlow =
    'dismiss_capture_flow';
const String _generatedMediaCaptureWireMethodMaterializeMediaResource =
    'materialize_media_resource';
const String _generatedMediaCaptureWireMethodPresentCaptureFlow =
    'present_capture_flow';
const String _generatedMediaCaptureWireMethodReadMediaThumbnail =
    'read_media_thumbnail';
const String _generatedMediaCaptureWireMethodReleaseMaterializedMedia =
    'release_materialized_media';
const String _generatedMediaCaptureWireMethodReleaseMedia = 'release_media';
const String _generatedMediaCaptureWireMethodRetake = 'retake';
const String _generatedMediaCaptureWireMethodSetFlashMode = 'set_flash_mode';
const String _generatedMediaCaptureWireMethodSetFocusPoint = 'set_focus_point';
const String _generatedMediaCaptureWireMethodSetZoom = 'set_zoom';
const String _generatedMediaCaptureWireMethodStartRecording = 'start_recording';
const String _generatedMediaCaptureWireMethodStartSession = 'start_session';
const String _generatedMediaCaptureWireMethodStopRecording = 'stop_recording';
const String _generatedMediaCaptureWireMethodSwitchCamera = 'switch_camera';
const String _generatedMediaCaptureWireMethodTakePhoto = 'take_photo';

enum _GeneratedMediaCaptureWireMethod {
  cancel(_generatedMediaCaptureWireMethodCancel),
  confirm(_generatedMediaCaptureWireMethodConfirm),
  dismissCaptureFlow(_generatedMediaCaptureWireMethodDismissCaptureFlow),
  materializeMediaResource(
    _generatedMediaCaptureWireMethodMaterializeMediaResource,
  ),
  presentCaptureFlow(_generatedMediaCaptureWireMethodPresentCaptureFlow),
  readMediaThumbnail(_generatedMediaCaptureWireMethodReadMediaThumbnail),
  releaseMaterializedMedia(
    _generatedMediaCaptureWireMethodReleaseMaterializedMedia,
  ),
  releaseMedia(_generatedMediaCaptureWireMethodReleaseMedia),
  retake(_generatedMediaCaptureWireMethodRetake),
  setFlashMode(_generatedMediaCaptureWireMethodSetFlashMode),
  setFocusPoint(_generatedMediaCaptureWireMethodSetFocusPoint),
  setZoom(_generatedMediaCaptureWireMethodSetZoom),
  startRecording(_generatedMediaCaptureWireMethodStartRecording),
  startSession(_generatedMediaCaptureWireMethodStartSession),
  stopRecording(_generatedMediaCaptureWireMethodStopRecording),
  switchCamera(_generatedMediaCaptureWireMethodSwitchCamera),
  takePhoto(_generatedMediaCaptureWireMethodTakePhoto);

  const _GeneratedMediaCaptureWireMethod(this.wireValue);
  final String wireValue;
}

const String _generatedMediaCaptureWireEventMediaLeaseExpired =
    'media_lease_expired';
const String _generatedMediaCaptureWireEventMediaPreviewReady =
    'media_preview_ready';
const String _generatedMediaCaptureWireEventMediaReadRevoked =
    'media_read_revoked';
const String _generatedMediaCaptureWireEventSessionFailed = 'session_failed';
const String _generatedMediaCaptureWireEventSessionReady = 'session_ready';

enum _GeneratedMediaCaptureWireEvent {
  mediaLeaseExpired(_generatedMediaCaptureWireEventMediaLeaseExpired),
  mediaPreviewReady(_generatedMediaCaptureWireEventMediaPreviewReady),
  mediaReadRevoked(_generatedMediaCaptureWireEventMediaReadRevoked),
  sessionFailed(_generatedMediaCaptureWireEventSessionFailed),
  sessionReady(_generatedMediaCaptureWireEventSessionReady);

  const _GeneratedMediaCaptureWireEvent(this.wireValue);
  final String wireValue;
}

const String _generatedMediaCaptureWireResultCaptureFlowCancelled =
    'capture_flow_cancelled';
const String _generatedMediaCaptureWireResultCaptureFlowConfirmed =
    'capture_flow_confirmed';
const String _generatedMediaCaptureWireResultCaptureFlowDismissed =
    'capture_flow_dismissed';
const String _generatedMediaCaptureWireResultConfirmedMedia = 'confirmed_media';
const String _generatedMediaCaptureWireResultControlApplied = 'control_applied';
const String _generatedMediaCaptureWireResultMaterializedMediaReleased =
    'materialized_media_released';
const String _generatedMediaCaptureWireResultMaterializedMediaResource =
    'materialized_media_resource';
const String _generatedMediaCaptureWireResultMediaPreview = 'media_preview';
const String _generatedMediaCaptureWireResultMediaReleased = 'media_released';
const String _generatedMediaCaptureWireResultMediaThumbnail = 'media_thumbnail';
const String _generatedMediaCaptureWireResultRecordingStarted =
    'recording_started';
const String _generatedMediaCaptureWireResultRetakeReady = 'retake_ready';
const String _generatedMediaCaptureWireResultSessionCancelled =
    'session_cancelled';
const String _generatedMediaCaptureWireResultSessionCreated = 'session_created';

enum _GeneratedMediaCaptureWireResult {
  captureFlowCancelled(_generatedMediaCaptureWireResultCaptureFlowCancelled),
  captureFlowConfirmed(_generatedMediaCaptureWireResultCaptureFlowConfirmed),
  captureFlowDismissed(_generatedMediaCaptureWireResultCaptureFlowDismissed),
  confirmedMedia(_generatedMediaCaptureWireResultConfirmedMedia),
  controlApplied(_generatedMediaCaptureWireResultControlApplied),
  materializedMediaReleased(
    _generatedMediaCaptureWireResultMaterializedMediaReleased,
  ),
  materializedMediaResource(
    _generatedMediaCaptureWireResultMaterializedMediaResource,
  ),
  mediaPreview(_generatedMediaCaptureWireResultMediaPreview),
  mediaReleased(_generatedMediaCaptureWireResultMediaReleased),
  mediaThumbnail(_generatedMediaCaptureWireResultMediaThumbnail),
  recordingStarted(_generatedMediaCaptureWireResultRecordingStarted),
  retakeReady(_generatedMediaCaptureWireResultRetakeReady),
  sessionCancelled(_generatedMediaCaptureWireResultSessionCancelled),
  sessionCreated(_generatedMediaCaptureWireResultSessionCreated);

  const _GeneratedMediaCaptureWireResult(this.wireValue);
  final String wireValue;
}

const String _generatedMediaCaptureWireFailureSessionTimeout =
    'session_timeout';

enum _GeneratedMediaCaptureWireFailure {
  sessionTimeout(_generatedMediaCaptureWireFailureSessionTimeout);

  const _GeneratedMediaCaptureWireFailure(this.wireValue);
  final String wireValue;
}

const String _generatedMediaCaptureWireErrorBridgeOverloaded =
    'bridge_overloaded';
const String _generatedMediaCaptureWireErrorBridgeUnavailable =
    'bridge_unavailable';
const String _generatedMediaCaptureWireErrorDuplicateRequest =
    'duplicate_request';
const String _generatedMediaCaptureWireErrorEncodingFailed = 'encoding_failed';
const String _generatedMediaCaptureWireErrorIncompatibleWireVersion =
    'incompatible_wire_version';
const String _generatedMediaCaptureWireErrorInvalidArgument =
    'invalid_argument';
const String _generatedMediaCaptureWireErrorInvalidState = 'invalid_state';
const String _generatedMediaCaptureWireErrorInvalidWirePayload =
    'invalid_wire_payload';
const String _generatedMediaCaptureWireErrorListenerAlreadyActive =
    'listener_already_active';
const String _generatedMediaCaptureWireErrorMaterializedMediaInvalid =
    'materialized_media_invalid';
const String _generatedMediaCaptureWireErrorMediaExportCancelled =
    'media_export_cancelled';
const String _generatedMediaCaptureWireErrorMediaExportConflict =
    'media_export_conflict';
const String _generatedMediaCaptureWireErrorMediaExportOverloaded =
    'media_export_overloaded';
const String _generatedMediaCaptureWireErrorMediaExportReadFailed =
    'media_export_read_failed';
const String _generatedMediaCaptureWireErrorMediaExportSinkRejected =
    'media_export_sink_rejected';
const String _generatedMediaCaptureWireErrorMediaExportTimedOut =
    'media_export_timed_out';
const String _generatedMediaCaptureWireErrorMediaExportTooLarge =
    'media_export_too_large';
const String _generatedMediaCaptureWireErrorMediaExportWriteFailed =
    'media_export_write_failed';
const String _generatedMediaCaptureWireErrorMediaInvalid = 'media_invalid';
const String _generatedMediaCaptureWireErrorPermissionDenied =
    'permission_denied';
const String _generatedMediaCaptureWireErrorPermissionPermanentlyDenied =
    'permission_permanently_denied';
const String _generatedMediaCaptureWireErrorPermissionRestricted =
    'permission_restricted';
const String _generatedMediaCaptureWireErrorPresentationConflict =
    'presentation_conflict';
const String _generatedMediaCaptureWireErrorResourceInUse = 'resource_in_use';
const String _generatedMediaCaptureWireErrorSessionConflict =
    'session_conflict';
const String _generatedMediaCaptureWireErrorSessionInvalid = 'session_invalid';
const String _generatedMediaCaptureWireErrorSessionTimeout = 'session_timeout';
const String _generatedMediaCaptureWireErrorStorageFull = 'storage_full';
const String _generatedMediaCaptureWireErrorSystemInterrupted =
    'system_interrupted';
const String _generatedMediaCaptureWireErrorThumbnailGenerationCancelled =
    'thumbnail_generation_cancelled';
const String _generatedMediaCaptureWireErrorThumbnailGenerationFailed =
    'thumbnail_generation_failed';
const String _generatedMediaCaptureWireErrorThumbnailOverloaded =
    'thumbnail_overloaded';
const String _generatedMediaCaptureWireErrorTransferStoreOverloaded =
    'transfer_store_overloaded';
const String _generatedMediaCaptureWireErrorTransferStoreUnavailable =
    'transfer_store_unavailable';
const String _generatedMediaCaptureWireErrorUnsupportedCapability =
    'unsupported_capability';
const String _generatedMediaCaptureWireErrorWireEncodingFailed =
    'wire_encoding_failed';

enum _GeneratedMediaCaptureWireError {
  bridgeOverloaded(_generatedMediaCaptureWireErrorBridgeOverloaded),
  bridgeUnavailable(_generatedMediaCaptureWireErrorBridgeUnavailable),
  duplicateRequest(_generatedMediaCaptureWireErrorDuplicateRequest),
  encodingFailed(_generatedMediaCaptureWireErrorEncodingFailed),
  incompatibleWireVersion(
    _generatedMediaCaptureWireErrorIncompatibleWireVersion,
  ),
  invalidArgument(_generatedMediaCaptureWireErrorInvalidArgument),
  invalidState(_generatedMediaCaptureWireErrorInvalidState),
  invalidWirePayload(_generatedMediaCaptureWireErrorInvalidWirePayload),
  listenerAlreadyActive(_generatedMediaCaptureWireErrorListenerAlreadyActive),
  materializedMediaInvalid(
    _generatedMediaCaptureWireErrorMaterializedMediaInvalid,
  ),
  mediaExportCancelled(_generatedMediaCaptureWireErrorMediaExportCancelled),
  mediaExportConflict(_generatedMediaCaptureWireErrorMediaExportConflict),
  mediaExportOverloaded(_generatedMediaCaptureWireErrorMediaExportOverloaded),
  mediaExportReadFailed(_generatedMediaCaptureWireErrorMediaExportReadFailed),
  mediaExportSinkRejected(
    _generatedMediaCaptureWireErrorMediaExportSinkRejected,
  ),
  mediaExportTimedOut(_generatedMediaCaptureWireErrorMediaExportTimedOut),
  mediaExportTooLarge(_generatedMediaCaptureWireErrorMediaExportTooLarge),
  mediaExportWriteFailed(_generatedMediaCaptureWireErrorMediaExportWriteFailed),
  mediaInvalid(_generatedMediaCaptureWireErrorMediaInvalid),
  permissionDenied(_generatedMediaCaptureWireErrorPermissionDenied),
  permissionPermanentlyDenied(
    _generatedMediaCaptureWireErrorPermissionPermanentlyDenied,
  ),
  permissionRestricted(_generatedMediaCaptureWireErrorPermissionRestricted),
  presentationConflict(_generatedMediaCaptureWireErrorPresentationConflict),
  resourceInUse(_generatedMediaCaptureWireErrorResourceInUse),
  sessionConflict(_generatedMediaCaptureWireErrorSessionConflict),
  sessionInvalid(_generatedMediaCaptureWireErrorSessionInvalid),
  sessionTimeout(_generatedMediaCaptureWireErrorSessionTimeout),
  storageFull(_generatedMediaCaptureWireErrorStorageFull),
  systemInterrupted(_generatedMediaCaptureWireErrorSystemInterrupted),
  thumbnailGenerationCancelled(
    _generatedMediaCaptureWireErrorThumbnailGenerationCancelled,
  ),
  thumbnailGenerationFailed(
    _generatedMediaCaptureWireErrorThumbnailGenerationFailed,
  ),
  thumbnailOverloaded(_generatedMediaCaptureWireErrorThumbnailOverloaded),
  transferStoreOverloaded(
    _generatedMediaCaptureWireErrorTransferStoreOverloaded,
  ),
  transferStoreUnavailable(
    _generatedMediaCaptureWireErrorTransferStoreUnavailable,
  ),
  unsupportedCapability(_generatedMediaCaptureWireErrorUnsupportedCapability),
  wireEncodingFailed(_generatedMediaCaptureWireErrorWireEncodingFailed);

  const _GeneratedMediaCaptureWireError(this.wireValue);
  final String wireValue;
}

final class _GeneratedWireFieldDescriptor {
  const _GeneratedWireFieldDescriptor({
    required this.id,
    required this.key,
    required this.type,
    required this.required,
    required this.nullable,
    required this.enumValues,
    required this.minimum,
    required this.maximum,
    required this.allowedIntegers,
    required this.minItems,
    required this.maxItems,
    required this.finite,
    required this.format,
    required this.boundarySource,
    required this.outOfRangePolicy,
  });
  final String id;
  final String key;
  final String type;
  final bool required;
  final bool nullable;
  final List<String> enumValues;
  final num? minimum;
  final num? maximum;
  final List<int> allowedIntegers;
  final int? minItems;
  final int? maxItems;
  final bool finite;
  final String format;
  final String? boundarySource;
  final String outOfRangePolicy;
}

const List<_GeneratedWireFieldDescriptor> _generatedMediaCaptureWireFields =
    <_GeneratedWireFieldDescriptor>[
      _GeneratedWireFieldDescriptor(
        id: 'active_camera',
        key: 'activeCamera',
        type: 'string',
        required: true,
        nullable: false,
        enumValues: const <String>['rear', 'front'],
        minimum: null,
        maximum: null,
        allowedIntegers: const <int>[],
        minItems: null,
        maxItems: null,
        finite: false,
        format: 'none',
        boundarySource: null,
        outOfRangePolicy: 'not_applicable',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'audio_enabled',
        key: 'audioEnabled',
        type: 'bool',
        required: true,
        nullable: false,
        enumValues: const <String>[],
        minimum: null,
        maximum: null,
        allowedIntegers: const <int>[],
        minItems: null,
        maxItems: null,
        finite: false,
        format: 'none',
        boundarySource: null,
        outOfRangePolicy: 'not_applicable',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'audio_included',
        key: 'audioIncluded',
        type: 'bool',
        required: true,
        nullable: false,
        enumValues: const <String>[],
        minimum: null,
        maximum: null,
        allowedIntegers: const <int>[],
        minItems: null,
        maxItems: null,
        finite: false,
        format: 'none',
        boundarySource: null,
        outOfRangePolicy: 'not_applicable',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'available_cameras',
        key: 'availableCameras',
        type: 'list_string',
        required: true,
        nullable: false,
        enumValues: const <String>['rear', 'front'],
        minimum: null,
        maximum: null,
        allowedIntegers: const <int>[],
        minItems: 1,
        maxItems: 2,
        finite: false,
        format: 'none',
        boundarySource: null,
        outOfRangePolicy: 'not_applicable',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'byte_length',
        key: 'byteLength',
        type: 'int',
        required: true,
        nullable: false,
        enumValues: const <String>[],
        minimum: 1,
        maximum: null,
        allowedIntegers: const <int>[],
        minItems: null,
        maxItems: null,
        finite: true,
        format: 'byte_length',
        boundarySource: null,
        outOfRangePolicy: 'reject',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'content_type',
        key: 'contentType',
        type: 'string',
        required: true,
        nullable: false,
        enumValues: const <String>[],
        minimum: null,
        maximum: null,
        allowedIntegers: const <int>[],
        minItems: null,
        maxItems: null,
        finite: false,
        format: 'mime_type',
        boundarySource: null,
        outOfRangePolicy: 'reject',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'duration_millis',
        key: 'durationMillis',
        type: 'int',
        required: true,
        nullable: true,
        enumValues: const <String>[],
        minimum: 1,
        maximum: 60000,
        allowedIntegers: const <int>[],
        minItems: null,
        maxItems: null,
        finite: true,
        format: 'duration_millis',
        boundarySource: null,
        outOfRangePolicy: 'reject',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'enabled_media_types',
        key: 'enabledMediaTypes',
        type: 'list_string',
        required: true,
        nullable: false,
        enumValues: const <String>['photo', 'video'],
        minimum: null,
        maximum: null,
        allowedIntegers: const <int>[],
        minItems: 1,
        maxItems: 2,
        finite: false,
        format: 'none',
        boundarySource: null,
        outOfRangePolicy: 'reject',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'expires_at',
        key: 'expiresAt',
        type: 'int',
        required: true,
        nullable: false,
        enumValues: const <String>[],
        minimum: 0,
        maximum: null,
        allowedIntegers: const <int>[],
        minItems: null,
        maxItems: null,
        finite: true,
        format: 'unix_epoch_millis',
        boundarySource: null,
        outOfRangePolicy: 'reject',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'export_handle',
        key: 'exportHandle',
        type: 'string',
        required: true,
        nullable: false,
        enumValues: const <String>[],
        minimum: null,
        maximum: null,
        allowedIntegers: const <int>[],
        minItems: null,
        maxItems: null,
        finite: false,
        format: 'opaque_handle',
        boundarySource: null,
        outOfRangePolicy: 'not_applicable',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'file_uri',
        key: 'fileUri',
        type: 'string',
        required: true,
        nullable: false,
        enumValues: const <String>[],
        minimum: null,
        maximum: null,
        allowedIntegers: const <int>[],
        minItems: null,
        maxItems: null,
        finite: false,
        format: 'canonical_file_uri',
        boundarySource: null,
        outOfRangePolicy: 'reject',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'flash_mode',
        key: 'flashMode',
        type: 'string',
        required: true,
        nullable: false,
        enumValues: const <String>['off', 'on', 'auto', 'torch'],
        minimum: null,
        maximum: null,
        allowedIntegers: const <int>[],
        minItems: null,
        maxItems: null,
        finite: false,
        format: 'none',
        boundarySource: null,
        outOfRangePolicy: 'reject',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'focus_point_supported',
        key: 'focusPointSupported',
        type: 'bool',
        required: true,
        nullable: false,
        enumValues: const <String>[],
        minimum: null,
        maximum: null,
        allowedIntegers: const <int>[],
        minItems: null,
        maxItems: null,
        finite: false,
        format: 'none',
        boundarySource: null,
        outOfRangePolicy: 'not_applicable',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'integrity_sha256',
        key: 'integritySha256',
        type: 'string',
        required: false,
        nullable: false,
        enumValues: const <String>[],
        minimum: null,
        maximum: null,
        allowedIntegers: const <int>[],
        minItems: null,
        maxItems: null,
        finite: false,
        format: 'lowercase_sha256_hex',
        boundarySource: null,
        outOfRangePolicy: 'reject',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'lease_expires_at',
        key: 'leaseExpiresAt',
        type: 'int',
        required: true,
        nullable: false,
        enumValues: const <String>[],
        minimum: 0,
        maximum: null,
        allowedIntegers: const <int>[],
        minItems: null,
        maxItems: null,
        finite: true,
        format: 'unix_epoch_millis',
        boundarySource: null,
        outOfRangePolicy: 'reject',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'max_pixel_edge',
        key: 'maxPixelEdge',
        type: 'int',
        required: true,
        nullable: false,
        enumValues: const <String>[],
        minimum: 64,
        maximum: 512,
        allowedIntegers: const <int>[],
        minItems: null,
        maxItems: null,
        finite: true,
        format: 'pixel_dimension',
        boundarySource: null,
        outOfRangePolicy: 'reject',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'max_video_duration_millis',
        key: 'maxVideoDurationMillis',
        type: 'int',
        required: true,
        nullable: false,
        enumValues: const <String>[],
        minimum: 1,
        maximum: 60000,
        allowedIntegers: const <int>[],
        minItems: null,
        maxItems: null,
        finite: true,
        format: 'duration_millis',
        boundarySource: null,
        outOfRangePolicy: 'reject',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'max_zoom_factor',
        key: 'maxZoomFactor',
        type: 'double',
        required: true,
        nullable: false,
        enumValues: const <String>[],
        minimum: 0.01,
        maximum: null,
        allowedIntegers: const <int>[],
        minItems: null,
        maxItems: null,
        finite: true,
        format: 'zoom_bound',
        boundarySource: null,
        outOfRangePolicy: 'reject',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'media_handle',
        key: 'mediaHandle',
        type: 'string',
        required: true,
        nullable: false,
        enumValues: const <String>[],
        minimum: null,
        maximum: null,
        allowedIntegers: const <int>[],
        minItems: null,
        maxItems: null,
        finite: false,
        format: 'opaque_handle',
        boundarySource: null,
        outOfRangePolicy: 'not_applicable',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'media_type',
        key: 'mediaType',
        type: 'string',
        required: true,
        nullable: false,
        enumValues: const <String>['photo', 'video'],
        minimum: null,
        maximum: null,
        allowedIntegers: const <int>[],
        minItems: null,
        maxItems: null,
        finite: false,
        format: 'none',
        boundarySource: null,
        outOfRangePolicy: 'not_applicable',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'min_zoom_factor',
        key: 'minZoomFactor',
        type: 'double',
        required: true,
        nullable: false,
        enumValues: const <String>[],
        minimum: 0.01,
        maximum: null,
        allowedIntegers: const <int>[],
        minItems: null,
        maxItems: null,
        finite: true,
        format: 'zoom_bound',
        boundarySource: null,
        outOfRangePolicy: 'reject',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'normalized_x',
        key: 'normalizedX',
        type: 'double',
        required: true,
        nullable: false,
        enumValues: const <String>[],
        minimum: 0,
        maximum: 1,
        allowedIntegers: const <int>[],
        minItems: null,
        maxItems: null,
        finite: true,
        format: 'normalized_coordinate',
        boundarySource: null,
        outOfRangePolicy: 'reject',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'normalized_y',
        key: 'normalizedY',
        type: 'double',
        required: true,
        nullable: false,
        enumValues: const <String>[],
        minimum: 0,
        maximum: 1,
        allowedIntegers: const <int>[],
        minItems: null,
        maxItems: null,
        finite: true,
        format: 'normalized_coordinate',
        boundarySource: null,
        outOfRangePolicy: 'reject',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'orientation_degrees',
        key: 'orientationDegrees',
        type: 'int',
        required: true,
        nullable: false,
        enumValues: const <String>[],
        minimum: null,
        maximum: null,
        allowedIntegers: const <int>[0, 90, 180, 270],
        minItems: null,
        maxItems: null,
        finite: true,
        format: 'orientation_degrees',
        boundarySource: null,
        outOfRangePolicy: 'reject',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'pixel_height',
        key: 'pixelHeight',
        type: 'int',
        required: true,
        nullable: false,
        enumValues: const <String>[],
        minimum: 1,
        maximum: null,
        allowedIntegers: const <int>[],
        minItems: null,
        maxItems: null,
        finite: true,
        format: 'pixel_dimension',
        boundarySource: null,
        outOfRangePolicy: 'reject',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'pixel_width',
        key: 'pixelWidth',
        type: 'int',
        required: true,
        nullable: false,
        enumValues: const <String>[],
        minimum: 1,
        maximum: null,
        allowedIntegers: const <int>[],
        minItems: null,
        maxItems: null,
        finite: true,
        format: 'pixel_dimension',
        boundarySource: null,
        outOfRangePolicy: 'reject',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'poster_frame_millis',
        key: 'posterFrameMillis',
        type: 'int',
        required: true,
        nullable: true,
        enumValues: const <String>[],
        minimum: 0,
        maximum: 60000,
        allowedIntegers: const <int>[],
        minItems: null,
        maxItems: null,
        finite: true,
        format: 'duration_millis',
        boundarySource: null,
        outOfRangePolicy: 'reject',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'preferred_camera',
        key: 'preferredCamera',
        type: 'string',
        required: true,
        nullable: false,
        enumValues: const <String>['rear', 'front'],
        minimum: null,
        maximum: null,
        allowedIntegers: const <int>[],
        minItems: null,
        maxItems: null,
        finite: false,
        format: 'none',
        boundarySource: null,
        outOfRangePolicy: 'not_applicable',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'presentation_request_id',
        key: 'presentationRequestId',
        type: 'string',
        required: true,
        nullable: false,
        enumValues: const <String>[],
        minimum: null,
        maximum: null,
        allowedIntegers: const <int>[],
        minItems: null,
        maxItems: null,
        finite: false,
        format: 'opaque_request_id',
        boundarySource: null,
        outOfRangePolicy: 'reject',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'session_handle',
        key: 'sessionHandle',
        type: 'string',
        required: true,
        nullable: false,
        enumValues: const <String>[],
        minimum: null,
        maximum: null,
        allowedIntegers: const <int>[],
        minItems: null,
        maxItems: null,
        finite: false,
        format: 'opaque_handle',
        boundarySource: null,
        outOfRangePolicy: 'not_applicable',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'supported_flash_modes',
        key: 'supportedFlashModes',
        type: 'list_string',
        required: true,
        nullable: false,
        enumValues: const <String>['off', 'on', 'auto', 'torch'],
        minimum: null,
        maximum: null,
        allowedIntegers: const <int>[],
        minItems: 1,
        maxItems: 4,
        finite: false,
        format: 'none',
        boundarySource: null,
        outOfRangePolicy: 'not_applicable',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'switch_camera_supported',
        key: 'switchCameraSupported',
        type: 'bool',
        required: true,
        nullable: false,
        enumValues: const <String>[],
        minimum: null,
        maximum: null,
        allowedIntegers: const <int>[],
        minItems: null,
        maxItems: null,
        finite: false,
        format: 'none',
        boundarySource: null,
        outOfRangePolicy: 'not_applicable',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'terminal_failure_id',
        key: 'terminalFailureId',
        type: 'string',
        required: true,
        nullable: false,
        enumValues: const <String>[
          'permission_denied',
          'permission_restricted',
          'permission_permanently_denied',
          'resource_in_use',
          'storage_full',
          'encoding_failed',
          'system_interrupted',
          'session_timeout',
        ],
        minimum: null,
        maximum: null,
        allowedIntegers: const <int>[],
        minItems: null,
        maxItems: null,
        finite: false,
        format: 'none',
        boundarySource: null,
        outOfRangePolicy: 'not_applicable',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'thumbnail_byte_length',
        key: 'thumbnailByteLength',
        type: 'int',
        required: true,
        nullable: false,
        enumValues: const <String>[],
        minimum: 1,
        maximum: 524288,
        allowedIntegers: const <int>[],
        minItems: null,
        maxItems: null,
        finite: true,
        format: 'byte_length',
        boundarySource: null,
        outOfRangePolicy: 'reject',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'thumbnail_content_type',
        key: 'thumbnailContentType',
        type: 'string',
        required: true,
        nullable: false,
        enumValues: const <String>[],
        minimum: null,
        maximum: null,
        allowedIntegers: const <int>[],
        minItems: null,
        maxItems: null,
        finite: false,
        format: 'image_jpeg_content_type',
        boundarySource: null,
        outOfRangePolicy: 'reject',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'thumbnail_copy',
        key: 'thumbnailCopy',
        type: 'bytes',
        required: true,
        nullable: false,
        enumValues: const <String>[],
        minimum: null,
        maximum: null,
        allowedIntegers: const <int>[],
        minItems: null,
        maxItems: null,
        finite: false,
        format: 'caller_owned_bounded_copy',
        boundarySource: null,
        outOfRangePolicy: 'not_applicable',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'thumbnail_orientation_degrees',
        key: 'thumbnailOrientationDegrees',
        type: 'int',
        required: true,
        nullable: false,
        enumValues: const <String>[],
        minimum: null,
        maximum: null,
        allowedIntegers: const <int>[0],
        minItems: null,
        maxItems: null,
        finite: true,
        format: 'orientation_degrees',
        boundarySource: null,
        outOfRangePolicy: 'reject',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'thumbnail_pixel_height',
        key: 'thumbnailPixelHeight',
        type: 'int',
        required: true,
        nullable: false,
        enumValues: const <String>[],
        minimum: 1,
        maximum: 512,
        allowedIntegers: const <int>[],
        minItems: null,
        maxItems: null,
        finite: true,
        format: 'pixel_dimension',
        boundarySource: 'max_pixel_edge',
        outOfRangePolicy: 'reject',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'thumbnail_pixel_width',
        key: 'thumbnailPixelWidth',
        type: 'int',
        required: true,
        nullable: false,
        enumValues: const <String>[],
        minimum: 1,
        maximum: 512,
        allowedIntegers: const <int>[],
        minItems: null,
        maxItems: null,
        finite: true,
        format: 'pixel_dimension',
        boundarySource: 'max_pixel_edge',
        outOfRangePolicy: 'reject',
      ),
      _GeneratedWireFieldDescriptor(
        id: 'zoom_factor',
        key: 'zoomFactor',
        type: 'double',
        required: true,
        nullable: false,
        enumValues: const <String>[],
        minimum: null,
        maximum: null,
        allowedIntegers: const <int>[],
        minItems: null,
        maxItems: null,
        finite: true,
        format: 'zoom_factor',
        boundarySource: 'session_zoom_range',
        outOfRangePolicy: 'reject',
      ),
    ];

const Map<String, List<String>>
_generatedPayloadFieldIds = <String, List<String>>{
  'capture_flow_dismissed_result_payload': const <String>[],
  'confirmed_media_result_payload': const <String>[
    'media_handle',
    'media_type',
    'pixel_width',
    'pixel_height',
    'duration_millis',
    'orientation_degrees',
    'byte_length',
    'lease_expires_at',
  ],
  'control_applied_result_payload': const <String>['session_handle'],
  'dismiss_capture_flow_request_payload': const <String>[
    'presentation_request_id',
  ],
  'flash_mode_request_payload': const <String>['session_handle', 'flash_mode'],
  'focus_point_request_payload': const <String>[
    'session_handle',
    'normalized_x',
    'normalized_y',
  ],
  'materialize_media_resource_request_payload': const <String>['media_handle'],
  'materialized_media_released_result_payload': const <String>[],
  'materialized_media_result_payload': const <String>[
    'export_handle',
    'file_uri',
    'media_type',
    'content_type',
    'byte_length',
    'duration_millis',
    'expires_at',
    'integrity_sha256',
  ],
  'media_handle_request_payload': const <String>['media_handle'],
  'media_lease_expired_event_payload': const <String>['media_handle'],
  'media_preview_ready_event_payload': const <String>[
    'session_handle',
    'media_handle',
    'media_type',
    'pixel_width',
    'pixel_height',
    'duration_millis',
    'orientation_degrees',
    'byte_length',
  ],
  'media_preview_result_payload': const <String>[
    'media_handle',
    'media_type',
    'pixel_width',
    'pixel_height',
    'duration_millis',
    'orientation_degrees',
    'byte_length',
  ],
  'media_read_revoked_event_payload': const <String>['media_handle'],
  'media_released_result_payload': const <String>['media_handle'],
  'media_thumbnail_request_payload': const <String>[
    'media_handle',
    'max_pixel_edge',
  ],
  'media_thumbnail_result_payload': const <String>[
    'media_handle',
    'thumbnail_copy',
    'thumbnail_byte_length',
    'thumbnail_pixel_width',
    'thumbnail_pixel_height',
    'thumbnail_content_type',
    'thumbnail_orientation_degrees',
    'media_type',
    'poster_frame_millis',
  ],
  'recording_started_result_payload': const <String>[
    'session_handle',
    'audio_included',
  ],
  'release_materialized_media_request_payload': const <String>['export_handle'],
  'retake_ready_result_payload': const <String>['session_handle'],
  'session_action_request_payload': const <String>['session_handle'],
  'session_cancelled_result_payload': const <String>['session_handle'],
  'session_created_result_payload': const <String>['session_handle'],
  'session_failed_event_payload': const <String>[
    'session_handle',
    'terminal_failure_id',
  ],
  'session_ready_event_payload': const <String>[
    'session_handle',
    'active_camera',
    'available_cameras',
    'switch_camera_supported',
    'supported_flash_modes',
    'focus_point_supported',
    'min_zoom_factor',
    'max_zoom_factor',
  ],
  'session_timeout_failure_payload': const <String>['session_handle'],
  'start_session_request_payload': const <String>[
    'enabled_media_types',
    'preferred_camera',
    'audio_enabled',
    'max_video_duration_millis',
  ],
  'zoom_request_payload': const <String>['session_handle', 'zoom_factor'],
};

final class _GeneratedWirePayloadDescriptor {
  const _GeneratedWirePayloadDescriptor(
    this.id,
    this.kind,
    this.fieldIds,
    this.unknownFieldPolicy,
  );
  final String id;
  final String kind;
  final List<String> fieldIds;
  final String unknownFieldPolicy;
}

const List<_GeneratedWirePayloadDescriptor> _generatedPayloadDescriptors =
    <_GeneratedWirePayloadDescriptor>[
      _GeneratedWirePayloadDescriptor(
        'capture_flow_dismissed_result_payload',
        'result',
        const <String>[],
        'reject',
      ),
      _GeneratedWirePayloadDescriptor(
        'confirmed_media_result_payload',
        'result',
        const <String>[
          'media_handle',
          'media_type',
          'pixel_width',
          'pixel_height',
          'duration_millis',
          'orientation_degrees',
          'byte_length',
          'lease_expires_at',
        ],
        'reject',
      ),
      _GeneratedWirePayloadDescriptor(
        'control_applied_result_payload',
        'result',
        const <String>['session_handle'],
        'reject',
      ),
      _GeneratedWirePayloadDescriptor(
        'dismiss_capture_flow_request_payload',
        'request',
        const <String>['presentation_request_id'],
        'reject',
      ),
      _GeneratedWirePayloadDescriptor(
        'flash_mode_request_payload',
        'request',
        const <String>['session_handle', 'flash_mode'],
        'reject',
      ),
      _GeneratedWirePayloadDescriptor(
        'focus_point_request_payload',
        'request',
        const <String>['session_handle', 'normalized_x', 'normalized_y'],
        'reject',
      ),
      _GeneratedWirePayloadDescriptor(
        'materialize_media_resource_request_payload',
        'request',
        const <String>['media_handle'],
        'reject',
      ),
      _GeneratedWirePayloadDescriptor(
        'materialized_media_released_result_payload',
        'result',
        const <String>[],
        'reject',
      ),
      _GeneratedWirePayloadDescriptor(
        'materialized_media_result_payload',
        'result',
        const <String>[
          'export_handle',
          'file_uri',
          'media_type',
          'content_type',
          'byte_length',
          'duration_millis',
          'expires_at',
          'integrity_sha256',
        ],
        'reject',
      ),
      _GeneratedWirePayloadDescriptor(
        'media_handle_request_payload',
        'request',
        const <String>['media_handle'],
        'reject',
      ),
      _GeneratedWirePayloadDescriptor(
        'media_lease_expired_event_payload',
        'event',
        const <String>['media_handle'],
        'reject',
      ),
      _GeneratedWirePayloadDescriptor(
        'media_preview_ready_event_payload',
        'event',
        const <String>[
          'session_handle',
          'media_handle',
          'media_type',
          'pixel_width',
          'pixel_height',
          'duration_millis',
          'orientation_degrees',
          'byte_length',
        ],
        'reject',
      ),
      _GeneratedWirePayloadDescriptor(
        'media_preview_result_payload',
        'result',
        const <String>[
          'media_handle',
          'media_type',
          'pixel_width',
          'pixel_height',
          'duration_millis',
          'orientation_degrees',
          'byte_length',
        ],
        'reject',
      ),
      _GeneratedWirePayloadDescriptor(
        'media_read_revoked_event_payload',
        'event',
        const <String>['media_handle'],
        'reject',
      ),
      _GeneratedWirePayloadDescriptor(
        'media_released_result_payload',
        'result',
        const <String>['media_handle'],
        'reject',
      ),
      _GeneratedWirePayloadDescriptor(
        'media_thumbnail_request_payload',
        'request',
        const <String>['media_handle', 'max_pixel_edge'],
        'reject',
      ),
      _GeneratedWirePayloadDescriptor(
        'media_thumbnail_result_payload',
        'result',
        const <String>[
          'media_handle',
          'thumbnail_copy',
          'thumbnail_byte_length',
          'thumbnail_pixel_width',
          'thumbnail_pixel_height',
          'thumbnail_content_type',
          'thumbnail_orientation_degrees',
          'media_type',
          'poster_frame_millis',
        ],
        'reject',
      ),
      _GeneratedWirePayloadDescriptor(
        'recording_started_result_payload',
        'result',
        const <String>['session_handle', 'audio_included'],
        'reject',
      ),
      _GeneratedWirePayloadDescriptor(
        'release_materialized_media_request_payload',
        'request',
        const <String>['export_handle'],
        'reject',
      ),
      _GeneratedWirePayloadDescriptor(
        'retake_ready_result_payload',
        'result',
        const <String>['session_handle'],
        'reject',
      ),
      _GeneratedWirePayloadDescriptor(
        'session_action_request_payload',
        'request',
        const <String>['session_handle'],
        'reject',
      ),
      _GeneratedWirePayloadDescriptor(
        'session_cancelled_result_payload',
        'result',
        const <String>['session_handle'],
        'reject',
      ),
      _GeneratedWirePayloadDescriptor(
        'session_created_result_payload',
        'result',
        const <String>['session_handle'],
        'reject',
      ),
      _GeneratedWirePayloadDescriptor(
        'session_failed_event_payload',
        'event',
        const <String>['session_handle', 'terminal_failure_id'],
        'reject',
      ),
      _GeneratedWirePayloadDescriptor(
        'session_ready_event_payload',
        'event',
        const <String>[
          'session_handle',
          'active_camera',
          'available_cameras',
          'switch_camera_supported',
          'supported_flash_modes',
          'focus_point_supported',
          'min_zoom_factor',
          'max_zoom_factor',
        ],
        'reject',
      ),
      _GeneratedWirePayloadDescriptor(
        'session_timeout_failure_payload',
        'failure',
        const <String>['session_handle'],
        'reject',
      ),
      _GeneratedWirePayloadDescriptor(
        'start_session_request_payload',
        'request',
        const <String>[
          'enabled_media_types',
          'preferred_camera',
          'audio_enabled',
          'max_video_duration_millis',
        ],
        'reject',
      ),
      _GeneratedWirePayloadDescriptor(
        'zoom_request_payload',
        'request',
        const <String>['session_handle', 'zoom_factor'],
        'reject',
      ),
    ];

final class _GeneratedWireErrorDescriptor {
  const _GeneratedWireErrorDescriptor(
    this.code,
    this.source,
    this.capabilityFailureId,
    this.recoverable,
    this.terminal,
    this.messagePolicy,
    this.detailsAllowedKeys,
  );
  final String code;
  final String source;
  final String? capabilityFailureId;
  final bool recoverable;
  final bool terminal;
  final String messagePolicy;
  final List<String> detailsAllowedKeys;
}

const List<_GeneratedWireErrorDescriptor> _generatedErrorDescriptors =
    <_GeneratedWireErrorDescriptor>[
      _GeneratedWireErrorDescriptor(
        'bridge_overloaded',
        'wire_protocol',
        null,
        true,
        false,
        'static_redacted',
        const <String>['operation', 'capacity'],
      ),
      _GeneratedWireErrorDescriptor(
        'bridge_unavailable',
        'wire_protocol',
        null,
        true,
        false,
        'static_redacted',
        const <String>['operation', 'lifecycleReason'],
      ),
      _GeneratedWireErrorDescriptor(
        'duplicate_request',
        'wire_protocol',
        null,
        true,
        false,
        'static_redacted',
        const <String>['operation'],
      ),
      _GeneratedWireErrorDescriptor(
        'encoding_failed',
        'capability_failure',
        'encoding_failed',
        true,
        true,
        'static_redacted',
        const <String>['operation', 'capabilityFailureId'],
      ),
      _GeneratedWireErrorDescriptor(
        'incompatible_wire_version',
        'wire_protocol',
        null,
        false,
        false,
        'static_redacted',
        const <String>['actualWireVersion', 'expectedWireVersion'],
      ),
      _GeneratedWireErrorDescriptor(
        'invalid_argument',
        'capability_failure',
        'invalid_argument',
        true,
        false,
        'static_redacted',
        const <String>['operation', 'capabilityFailureId'],
      ),
      _GeneratedWireErrorDescriptor(
        'invalid_state',
        'capability_failure',
        'invalid_state',
        true,
        false,
        'static_redacted',
        const <String>['operation', 'capabilityFailureId'],
      ),
      _GeneratedWireErrorDescriptor(
        'invalid_wire_payload',
        'wire_protocol',
        null,
        true,
        false,
        'static_redacted',
        const <String>['operation', 'field', 'reason'],
      ),
      _GeneratedWireErrorDescriptor(
        'listener_already_active',
        'wire_protocol',
        null,
        true,
        false,
        'static_redacted',
        const <String>[],
      ),
      _GeneratedWireErrorDescriptor(
        'materialized_media_invalid',
        'wire_protocol',
        null,
        true,
        false,
        'static_redacted',
        const <String>['operation'],
      ),
      _GeneratedWireErrorDescriptor(
        'media_export_cancelled',
        'capability_failure',
        'media_export_cancelled',
        true,
        false,
        'static_redacted',
        const <String>['operation', 'capabilityFailureId'],
      ),
      _GeneratedWireErrorDescriptor(
        'media_export_conflict',
        'capability_failure',
        'media_export_conflict',
        true,
        false,
        'static_redacted',
        const <String>['operation', 'capabilityFailureId'],
      ),
      _GeneratedWireErrorDescriptor(
        'media_export_overloaded',
        'capability_failure',
        'media_export_overloaded',
        true,
        false,
        'static_redacted',
        const <String>['operation', 'capabilityFailureId'],
      ),
      _GeneratedWireErrorDescriptor(
        'media_export_read_failed',
        'capability_failure',
        'media_export_read_failed',
        true,
        false,
        'static_redacted',
        const <String>['operation', 'capabilityFailureId'],
      ),
      _GeneratedWireErrorDescriptor(
        'media_export_sink_rejected',
        'capability_failure',
        'media_export_sink_rejected',
        true,
        false,
        'static_redacted',
        const <String>['operation', 'capabilityFailureId'],
      ),
      _GeneratedWireErrorDescriptor(
        'media_export_timed_out',
        'capability_failure',
        'media_export_timed_out',
        true,
        false,
        'static_redacted',
        const <String>['operation', 'capabilityFailureId'],
      ),
      _GeneratedWireErrorDescriptor(
        'media_export_too_large',
        'capability_failure',
        'media_export_too_large',
        true,
        false,
        'static_redacted',
        const <String>['operation', 'capabilityFailureId'],
      ),
      _GeneratedWireErrorDescriptor(
        'media_export_write_failed',
        'capability_failure',
        'media_export_write_failed',
        true,
        false,
        'static_redacted',
        const <String>['operation', 'capabilityFailureId'],
      ),
      _GeneratedWireErrorDescriptor(
        'media_invalid',
        'capability_failure',
        'media_invalid',
        false,
        false,
        'static_redacted',
        const <String>['operation', 'capabilityFailureId'],
      ),
      _GeneratedWireErrorDescriptor(
        'permission_denied',
        'capability_failure',
        'permission_denied',
        true,
        true,
        'static_redacted',
        const <String>['operation', 'capabilityFailureId'],
      ),
      _GeneratedWireErrorDescriptor(
        'permission_permanently_denied',
        'capability_failure',
        'permission_permanently_denied',
        false,
        true,
        'static_redacted',
        const <String>['operation', 'capabilityFailureId'],
      ),
      _GeneratedWireErrorDescriptor(
        'permission_restricted',
        'capability_failure',
        'permission_restricted',
        false,
        true,
        'static_redacted',
        const <String>['operation', 'capabilityFailureId'],
      ),
      _GeneratedWireErrorDescriptor(
        'presentation_conflict',
        'wire_protocol',
        null,
        true,
        false,
        'static_redacted',
        const <String>['operation', 'capacity'],
      ),
      _GeneratedWireErrorDescriptor(
        'resource_in_use',
        'capability_failure',
        'resource_in_use',
        true,
        true,
        'static_redacted',
        const <String>['operation', 'capabilityFailureId'],
      ),
      _GeneratedWireErrorDescriptor(
        'session_conflict',
        'capability_failure',
        'session_conflict',
        true,
        false,
        'static_redacted',
        const <String>['operation', 'capabilityFailureId'],
      ),
      _GeneratedWireErrorDescriptor(
        'session_invalid',
        'capability_failure',
        'session_invalid',
        false,
        false,
        'static_redacted',
        const <String>['operation', 'capabilityFailureId'],
      ),
      _GeneratedWireErrorDescriptor(
        'session_timeout',
        'capability_failure',
        'session_timeout',
        true,
        true,
        'static_redacted',
        const <String>['operation', 'capabilityFailureId'],
      ),
      _GeneratedWireErrorDescriptor(
        'storage_full',
        'capability_failure',
        'storage_full',
        true,
        true,
        'static_redacted',
        const <String>['operation', 'capabilityFailureId'],
      ),
      _GeneratedWireErrorDescriptor(
        'system_interrupted',
        'capability_failure',
        'system_interrupted',
        true,
        true,
        'static_redacted',
        const <String>['operation', 'capabilityFailureId'],
      ),
      _GeneratedWireErrorDescriptor(
        'thumbnail_generation_cancelled',
        'capability_failure',
        'thumbnail_generation_cancelled',
        true,
        false,
        'static_redacted',
        const <String>['operation', 'capabilityFailureId'],
      ),
      _GeneratedWireErrorDescriptor(
        'thumbnail_generation_failed',
        'capability_failure',
        'thumbnail_generation_failed',
        true,
        false,
        'static_redacted',
        const <String>['operation', 'capabilityFailureId'],
      ),
      _GeneratedWireErrorDescriptor(
        'thumbnail_overloaded',
        'capability_failure',
        'thumbnail_overloaded',
        true,
        false,
        'static_redacted',
        const <String>['operation', 'capabilityFailureId'],
      ),
      _GeneratedWireErrorDescriptor(
        'transfer_store_overloaded',
        'wire_protocol',
        null,
        true,
        false,
        'static_redacted',
        const <String>['operation', 'capacity'],
      ),
      _GeneratedWireErrorDescriptor(
        'transfer_store_unavailable',
        'wire_protocol',
        null,
        true,
        false,
        'static_redacted',
        const <String>['operation', 'lifecycleReason'],
      ),
      _GeneratedWireErrorDescriptor(
        'unsupported_capability',
        'capability_failure',
        'unsupported_capability',
        true,
        false,
        'static_redacted',
        const <String>['operation', 'capabilityFailureId'],
      ),
      _GeneratedWireErrorDescriptor(
        'wire_encoding_failed',
        'wire_protocol',
        null,
        false,
        false,
        'static_redacted',
        const <String>['operation', 'field', 'reason'],
      ),
    ];

final class _GeneratedWireErrorDetailDescriptor {
  const _GeneratedWireErrorDetailDescriptor(
    this.key,
    this.type,
    this.source,
    this.enumValues,
    this.minLength,
    this.maxLength,
    this.minimum,
    this.maximum,
    this.redaction,
  );
  final String key;
  final String type;
  final String source;
  final List<String> enumValues;
  final int? minLength;
  final int? maxLength;
  final int? minimum;
  final int? maximum;
  final String redaction;
}

const List<_GeneratedWireErrorDetailDescriptor>
_generatedErrorDetailDescriptors = <_GeneratedWireErrorDetailDescriptor>[
  _GeneratedWireErrorDetailDescriptor(
    'actualWireVersion',
    'int',
    'request_wire_version',
    const <String>[],
    null,
    null,
    -9223372036854775808,
    9223372036854775807,
    'allowlisted_value_only',
  ),
  _GeneratedWireErrorDetailDescriptor(
    'capabilityFailureId',
    'string',
    'capability_failure_id',
    const <String>[
      'permission_denied',
      'permission_restricted',
      'permission_permanently_denied',
      'resource_in_use',
      'storage_full',
      'encoding_failed',
      'media_invalid',
      'session_invalid',
      'unsupported_capability',
      'system_interrupted',
      'session_conflict',
      'invalid_state',
      'invalid_argument',
      'session_timeout',
      'thumbnail_generation_failed',
      'thumbnail_generation_cancelled',
      'thumbnail_overloaded',
      'attachment_generation_retired',
      'attachment_target_conflict',
      'media_export_conflict',
      'media_export_overloaded',
      'media_export_too_large',
      'media_export_sink_rejected',
      'media_export_read_failed',
      'media_export_write_failed',
      'media_export_cancelled',
      'media_export_timed_out',
    ],
    1,
    64,
    null,
    null,
    'allowlisted_value_only',
  ),
  _GeneratedWireErrorDetailDescriptor(
    'capacity',
    'string',
    'closed_capacity_code',
    const <String>[
      'active_export_bytes',
      'active_exports',
      'active_presentation',
      'completed_request_tombstones',
      'pending_requests',
      'release_tombstones',
    ],
    1,
    64,
    null,
    null,
    'allowlisted_value_only',
  ),
  _GeneratedWireErrorDetailDescriptor(
    'expectedWireVersion',
    'int',
    'contract_wire_version',
    const <String>[],
    null,
    null,
    -9223372036854775808,
    9223372036854775807,
    'allowlisted_value_only',
  ),
  _GeneratedWireErrorDetailDescriptor(
    'field',
    'string',
    'declared_field_key_or_unknown',
    const <String>[
      'wireVersion',
      'requestId',
      'payload',
      'resultType',
      'eventType',
      'failureType',
      'enabledMediaTypes',
      'preferredCamera',
      'audioEnabled',
      'maxVideoDurationMillis',
      'sessionHandle',
      'flashMode',
      'normalizedX',
      'normalizedY',
      'zoomFactor',
      'mediaHandle',
      'activeCamera',
      'availableCameras',
      'switchCameraSupported',
      'supportedFlashModes',
      'focusPointSupported',
      'minZoomFactor',
      'maxZoomFactor',
      'audioIncluded',
      'mediaType',
      'pixelWidth',
      'pixelHeight',
      'durationMillis',
      'orientationDegrees',
      'byteLength',
      'leaseExpiresAt',
      'terminalFailureId',
      'maxPixelEdge',
      'thumbnailCopy',
      'thumbnailByteLength',
      'thumbnailPixelWidth',
      'thumbnailPixelHeight',
      'thumbnailContentType',
      'thumbnailOrientationDegrees',
      'posterFrameMillis',
      'unknown_field',
      'contentType',
      'exportHandle',
      'fileUri',
      'expiresAt',
      'integritySha256',
      'presentationRequestId',
    ],
    1,
    64,
    null,
    null,
    'allowlisted_value_only',
  ),
  _GeneratedWireErrorDetailDescriptor(
    'lifecycleReason',
    'string',
    'closed_lifecycle_reason',
    const <String>[
      'engine_detached',
      'activity_destroyed',
      'view_controller_destroyed',
      'adapter_disposed',
    ],
    1,
    64,
    null,
    null,
    'allowlisted_value_only',
  ),
  _GeneratedWireErrorDetailDescriptor(
    'operation',
    'string',
    'method_id_or_unknown',
    const <String>[
      'start_session',
      'take_photo',
      'start_recording',
      'stop_recording',
      'switch_camera',
      'set_flash_mode',
      'set_focus_point',
      'set_zoom',
      'retake',
      'confirm',
      'cancel',
      'release_media',
      'read_media_thumbnail',
      'present_capture_flow',
      'unknown_operation',
      'materialize_media_resource',
      'release_materialized_media',
      'dismiss_capture_flow',
    ],
    1,
    64,
    null,
    null,
    'allowlisted_value_only',
  ),
  _GeneratedWireErrorDetailDescriptor(
    'reason',
    'string',
    'closed_reason_code',
    const <String>[
      'missing_required_field',
      'unknown_field',
      'type_mismatch',
      'null_not_allowed',
      'non_finite',
      'out_of_range',
      'invalid_enum',
      'invalid_format',
      'integer_overflow',
      'result_type_mismatch',
      'native_value_unencodable',
    ],
    1,
    64,
    null,
    null,
    'allowlisted_value_only',
  ),
];

const String _generatedRequestIdWireType = 'string';
const String _generatedRequestIdPattern = '^[A-Za-z0-9_-]{1,128}\$';
const String _generatedRequestIdFormat = 'ascii_token';
const int _generatedRequestIdMinLength = 1;
const int _generatedRequestIdMaxLength = 128;
const Map<String, List<String>> _generatedEnvelopeRequiredKeys =
    <String, List<String>>{
      '/lifecycle/eventEnvelope': const <String>[
        'wireVersion',
        'eventType',
        'payload',
      ],
      '/lifecycle/eventListenEnvelope': const <String>['wireVersion'],
      '/lifecycle/failureEnvelope': const <String>[
        'wireVersion',
        'failureType',
        'payload',
      ],
      '/lifecycle/requestEnvelope': const <String>[
        'wireVersion',
        'requestId',
        'payload',
      ],
      '/lifecycle/resultEnvelope': const <String>[
        'wireVersion',
        'requestId',
        'resultType',
        'payload',
      ],
    };
const Map<String, String> _generatedEnvelopeUnknownFieldPolicies =
    <String, String>{
      '/lifecycle/eventEnvelope': 'reject',
      '/lifecycle/eventListenEnvelope': 'reject',
      '/lifecycle/failureEnvelope': 'reject',
      '/lifecycle/requestEnvelope': 'reject',
      '/lifecycle/resultEnvelope': 'reject',
    };
const int _generatedSignedIntegerMinimum = -9223372036854775808;
const int _generatedSignedIntegerMaximum = 9223372036854775807;
const Map<String, List<int>> _generatedOpaqueHandleLengths =
    <String, List<int>>{
      'export_handle': <int>[22, 64],
      'media_handle': <int>[1, 128],
      'session_handle': <int>[1, 128],
    };

bool _generatedHasExactWireKeys(
  Map<Object?, Object?> value,
  List<String> requiredKeys,
) =>
    value.length == requiredKeys.length &&
    value.keys.every(requiredKeys.contains);

bool _generatedMatchesWireFieldPrimitive(
  Object? value,
  _GeneratedWireFieldDescriptor field,
) {
  if (value == null) return field.nullable;
  final validType = switch (field.type) {
    'bool' => value is bool,
    'bytes' => value is Uint8List,
    'double' => value is double,
    'int' => value is int,
    'string' => value is String,
    'list_bool' => value is List && value.every((item) => item is bool),
    'list_double' => value is List && value.every((item) => item is double),
    'list_int' => value is List && value.every((item) => item is int),
    'list_string' => value is List && value.every((item) => item is String),
    _ => false,
  };
  if (!validType) return false;
  if (value is double && field.finite && !value.isFinite) return false;
  if (value is int &&
      (value < _generatedSignedIntegerMinimum ||
          value > _generatedSignedIntegerMaximum))
    return false;
  if (value is num && field.minimum != null && value < field.minimum!)
    return false;
  if (value is num && field.maximum != null && value > field.maximum!)
    return false;
  if (value is int &&
      field.allowedIntegers.isNotEmpty &&
      !field.allowedIntegers.contains(value))
    return false;
  final collectionLength = switch (value) {
    Uint8List() => value.length,
    List() => value.length,
    _ => null,
  };
  if (collectionLength != null &&
      field.minItems != null &&
      collectionLength < field.minItems!)
    return false;
  if (collectionLength != null &&
      field.maxItems != null &&
      collectionLength > field.maxItems!)
    return false;
  if (value is String &&
      field.enumValues.isNotEmpty &&
      !field.enumValues.contains(value))
    return false;
  if (value is List &&
      field.type == 'list_string' &&
      field.enumValues.isNotEmpty &&
      !value.every(field.enumValues.contains))
    return false;
  if (value is List &&
      field.type == 'list_string' &&
      field.enumValues.isNotEmpty &&
      value.toSet().length != value.length)
    return false;
  if (value is List &&
      field.type == 'list_double' &&
      field.finite &&
      value.any((item) => !(item as double).isFinite))
    return false;
  if (value is List &&
      field.type == 'list_int' &&
      value.any(
        (item) =>
            item < _generatedSignedIntegerMinimum ||
            item > _generatedSignedIntegerMaximum,
      ))
    return false;
  return true;
}
