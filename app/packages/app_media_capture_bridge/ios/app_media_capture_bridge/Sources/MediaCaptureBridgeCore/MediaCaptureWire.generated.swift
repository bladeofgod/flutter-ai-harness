// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generator: media_capture_wire/1
// Source: docs/bridge/contracts/media-capture.wire.json
// Source digest (SHA-256): 76e65a567971ca209e0b4f50412e79002a83eda04869149f21d136a7c6569d27
import Foundation
import CoreFoundation

internal let generatedMediaCaptureWireVersion = 3
internal let generatedCommandsChannel = "com.example.media_capture.commands"
internal let generatedEventsChannel = "com.example.media_capture.events"

internal enum GeneratedMediaCaptureWireMethod: String, CaseIterable, Sendable {
    case cancel = "cancel"
    case confirm = "confirm"
    case dismissCaptureFlow = "dismiss_capture_flow"
    case materializeMediaResource = "materialize_media_resource"
    case presentCaptureFlow = "present_capture_flow"
    case readMediaThumbnail = "read_media_thumbnail"
    case releaseMaterializedMedia = "release_materialized_media"
    case releaseMedia = "release_media"
    case retake = "retake"
    case setFlashMode = "set_flash_mode"
    case setFocusPoint = "set_focus_point"
    case setZoom = "set_zoom"
    case startRecording = "start_recording"
    case startSession = "start_session"
    case stopRecording = "stop_recording"
    case switchCamera = "switch_camera"
    case takePhoto = "take_photo"
}

internal enum GeneratedMediaCaptureWireEvent: String, CaseIterable, Sendable {
    case mediaLeaseExpired = "media_lease_expired"
    case mediaPreviewReady = "media_preview_ready"
    case mediaReadRevoked = "media_read_revoked"
    case sessionFailed = "session_failed"
    case sessionReady = "session_ready"
}

internal enum GeneratedMediaCaptureWireResult: String, CaseIterable, Sendable {
    case captureFlowCancelled = "capture_flow_cancelled"
    case captureFlowConfirmed = "capture_flow_confirmed"
    case captureFlowDismissed = "capture_flow_dismissed"
    case confirmedMedia = "confirmed_media"
    case controlApplied = "control_applied"
    case materializedMediaReleased = "materialized_media_released"
    case materializedMediaResource = "materialized_media_resource"
    case mediaPreview = "media_preview"
    case mediaReleased = "media_released"
    case mediaThumbnail = "media_thumbnail"
    case recordingStarted = "recording_started"
    case retakeReady = "retake_ready"
    case sessionCancelled = "session_cancelled"
    case sessionCreated = "session_created"
}

internal enum GeneratedMediaCaptureWireFailure: String, CaseIterable, Sendable {
    case sessionTimeout = "session_timeout"
}

internal enum GeneratedMediaCaptureWireError: String, CaseIterable, Sendable {
    case bridgeOverloaded = "bridge_overloaded"
    case bridgeUnavailable = "bridge_unavailable"
    case duplicateRequest = "duplicate_request"
    case encodingFailed = "encoding_failed"
    case incompatibleWireVersion = "incompatible_wire_version"
    case invalidArgument = "invalid_argument"
    case invalidState = "invalid_state"
    case invalidWirePayload = "invalid_wire_payload"
    case listenerAlreadyActive = "listener_already_active"
    case materializedMediaInvalid = "materialized_media_invalid"
    case mediaExportCancelled = "media_export_cancelled"
    case mediaExportConflict = "media_export_conflict"
    case mediaExportOverloaded = "media_export_overloaded"
    case mediaExportReadFailed = "media_export_read_failed"
    case mediaExportSinkRejected = "media_export_sink_rejected"
    case mediaExportTimedOut = "media_export_timed_out"
    case mediaExportTooLarge = "media_export_too_large"
    case mediaExportWriteFailed = "media_export_write_failed"
    case mediaInvalid = "media_invalid"
    case permissionDenied = "permission_denied"
    case permissionPermanentlyDenied = "permission_permanently_denied"
    case permissionRestricted = "permission_restricted"
    case presentationConflict = "presentation_conflict"
    case resourceInUse = "resource_in_use"
    case sessionConflict = "session_conflict"
    case sessionInvalid = "session_invalid"
    case sessionTimeout = "session_timeout"
    case storageFull = "storage_full"
    case systemInterrupted = "system_interrupted"
    case thumbnailGenerationCancelled = "thumbnail_generation_cancelled"
    case thumbnailGenerationFailed = "thumbnail_generation_failed"
    case thumbnailOverloaded = "thumbnail_overloaded"
    case transferStoreOverloaded = "transfer_store_overloaded"
    case transferStoreUnavailable = "transfer_store_unavailable"
    case unsupportedCapability = "unsupported_capability"
    case wireEncodingFailed = "wire_encoding_failed"
}

internal struct GeneratedWireFieldDescriptor: Sendable {
    let id: String
    let key: String
    let type: String
    let required: Bool
    let nullable: Bool
    let enumValues: Set<String>
    let minimum: String?
    let maximum: String?
    let allowedIntegers: Set<Int64>
    let minItems: Int?
    let maxItems: Int?
    let finite: Bool
    let format: String
    let boundarySource: String?
    let outOfRangePolicy: String
}

internal let generatedMediaCaptureWireFields: [GeneratedWireFieldDescriptor] = [
    GeneratedWireFieldDescriptor(
        id: "active_camera", key: "activeCamera", type: "string",
        required: true, nullable: false,
        enumValues: ["rear", "front"],
        minimum: nil, maximum: nil,
        allowedIntegers: [],
        minItems: nil, maxItems: nil,
        finite: false, format: "none",
        boundarySource: nil, outOfRangePolicy: "not_applicable"
    ),
    GeneratedWireFieldDescriptor(
        id: "audio_enabled", key: "audioEnabled", type: "bool",
        required: true, nullable: false,
        enumValues: [],
        minimum: nil, maximum: nil,
        allowedIntegers: [],
        minItems: nil, maxItems: nil,
        finite: false, format: "none",
        boundarySource: nil, outOfRangePolicy: "not_applicable"
    ),
    GeneratedWireFieldDescriptor(
        id: "audio_included", key: "audioIncluded", type: "bool",
        required: true, nullable: false,
        enumValues: [],
        minimum: nil, maximum: nil,
        allowedIntegers: [],
        minItems: nil, maxItems: nil,
        finite: false, format: "none",
        boundarySource: nil, outOfRangePolicy: "not_applicable"
    ),
    GeneratedWireFieldDescriptor(
        id: "available_cameras", key: "availableCameras", type: "list_string",
        required: true, nullable: false,
        enumValues: ["rear", "front"],
        minimum: nil, maximum: nil,
        allowedIntegers: [],
        minItems: 1, maxItems: 2,
        finite: false, format: "none",
        boundarySource: nil, outOfRangePolicy: "not_applicable"
    ),
    GeneratedWireFieldDescriptor(
        id: "byte_length", key: "byteLength", type: "int",
        required: true, nullable: false,
        enumValues: [],
        minimum: "1", maximum: nil,
        allowedIntegers: [],
        minItems: nil, maxItems: nil,
        finite: true, format: "byte_length",
        boundarySource: nil, outOfRangePolicy: "reject"
    ),
    GeneratedWireFieldDescriptor(
        id: "content_type", key: "contentType", type: "string",
        required: true, nullable: false,
        enumValues: [],
        minimum: nil, maximum: nil,
        allowedIntegers: [],
        minItems: nil, maxItems: nil,
        finite: false, format: "mime_type",
        boundarySource: nil, outOfRangePolicy: "reject"
    ),
    GeneratedWireFieldDescriptor(
        id: "duration_millis", key: "durationMillis", type: "int",
        required: true, nullable: true,
        enumValues: [],
        minimum: "1", maximum: "60000",
        allowedIntegers: [],
        minItems: nil, maxItems: nil,
        finite: true, format: "duration_millis",
        boundarySource: nil, outOfRangePolicy: "reject"
    ),
    GeneratedWireFieldDescriptor(
        id: "enabled_media_types", key: "enabledMediaTypes", type: "list_string",
        required: true, nullable: false,
        enumValues: ["photo", "video"],
        minimum: nil, maximum: nil,
        allowedIntegers: [],
        minItems: 1, maxItems: 2,
        finite: false, format: "none",
        boundarySource: nil, outOfRangePolicy: "reject"
    ),
    GeneratedWireFieldDescriptor(
        id: "expires_at", key: "expiresAt", type: "int",
        required: true, nullable: false,
        enumValues: [],
        minimum: "0", maximum: nil,
        allowedIntegers: [],
        minItems: nil, maxItems: nil,
        finite: true, format: "unix_epoch_millis",
        boundarySource: nil, outOfRangePolicy: "reject"
    ),
    GeneratedWireFieldDescriptor(
        id: "export_handle", key: "exportHandle", type: "string",
        required: true, nullable: false,
        enumValues: [],
        minimum: nil, maximum: nil,
        allowedIntegers: [],
        minItems: nil, maxItems: nil,
        finite: false, format: "opaque_handle",
        boundarySource: nil, outOfRangePolicy: "not_applicable"
    ),
    GeneratedWireFieldDescriptor(
        id: "file_uri", key: "fileUri", type: "string",
        required: true, nullable: false,
        enumValues: [],
        minimum: nil, maximum: nil,
        allowedIntegers: [],
        minItems: nil, maxItems: nil,
        finite: false, format: "canonical_file_uri",
        boundarySource: nil, outOfRangePolicy: "reject"
    ),
    GeneratedWireFieldDescriptor(
        id: "flash_mode", key: "flashMode", type: "string",
        required: true, nullable: false,
        enumValues: ["off", "on", "auto", "torch"],
        minimum: nil, maximum: nil,
        allowedIntegers: [],
        minItems: nil, maxItems: nil,
        finite: false, format: "none",
        boundarySource: nil, outOfRangePolicy: "reject"
    ),
    GeneratedWireFieldDescriptor(
        id: "focus_point_supported", key: "focusPointSupported", type: "bool",
        required: true, nullable: false,
        enumValues: [],
        minimum: nil, maximum: nil,
        allowedIntegers: [],
        minItems: nil, maxItems: nil,
        finite: false, format: "none",
        boundarySource: nil, outOfRangePolicy: "not_applicable"
    ),
    GeneratedWireFieldDescriptor(
        id: "integrity_sha256", key: "integritySha256", type: "string",
        required: false, nullable: false,
        enumValues: [],
        minimum: nil, maximum: nil,
        allowedIntegers: [],
        minItems: nil, maxItems: nil,
        finite: false, format: "lowercase_sha256_hex",
        boundarySource: nil, outOfRangePolicy: "reject"
    ),
    GeneratedWireFieldDescriptor(
        id: "lease_expires_at", key: "leaseExpiresAt", type: "int",
        required: true, nullable: false,
        enumValues: [],
        minimum: "0", maximum: nil,
        allowedIntegers: [],
        minItems: nil, maxItems: nil,
        finite: true, format: "unix_epoch_millis",
        boundarySource: nil, outOfRangePolicy: "reject"
    ),
    GeneratedWireFieldDescriptor(
        id: "max_pixel_edge", key: "maxPixelEdge", type: "int",
        required: true, nullable: false,
        enumValues: [],
        minimum: "64", maximum: "512",
        allowedIntegers: [],
        minItems: nil, maxItems: nil,
        finite: true, format: "pixel_dimension",
        boundarySource: nil, outOfRangePolicy: "reject"
    ),
    GeneratedWireFieldDescriptor(
        id: "max_video_duration_millis", key: "maxVideoDurationMillis", type: "int",
        required: true, nullable: false,
        enumValues: [],
        minimum: "1", maximum: "60000",
        allowedIntegers: [],
        minItems: nil, maxItems: nil,
        finite: true, format: "duration_millis",
        boundarySource: nil, outOfRangePolicy: "reject"
    ),
    GeneratedWireFieldDescriptor(
        id: "max_zoom_factor", key: "maxZoomFactor", type: "double",
        required: true, nullable: false,
        enumValues: [],
        minimum: "0.01", maximum: nil,
        allowedIntegers: [],
        minItems: nil, maxItems: nil,
        finite: true, format: "zoom_bound",
        boundarySource: nil, outOfRangePolicy: "reject"
    ),
    GeneratedWireFieldDescriptor(
        id: "media_handle", key: "mediaHandle", type: "string",
        required: true, nullable: false,
        enumValues: [],
        minimum: nil, maximum: nil,
        allowedIntegers: [],
        minItems: nil, maxItems: nil,
        finite: false, format: "opaque_handle",
        boundarySource: nil, outOfRangePolicy: "not_applicable"
    ),
    GeneratedWireFieldDescriptor(
        id: "media_type", key: "mediaType", type: "string",
        required: true, nullable: false,
        enumValues: ["photo", "video"],
        minimum: nil, maximum: nil,
        allowedIntegers: [],
        minItems: nil, maxItems: nil,
        finite: false, format: "none",
        boundarySource: nil, outOfRangePolicy: "not_applicable"
    ),
    GeneratedWireFieldDescriptor(
        id: "min_zoom_factor", key: "minZoomFactor", type: "double",
        required: true, nullable: false,
        enumValues: [],
        minimum: "0.01", maximum: nil,
        allowedIntegers: [],
        minItems: nil, maxItems: nil,
        finite: true, format: "zoom_bound",
        boundarySource: nil, outOfRangePolicy: "reject"
    ),
    GeneratedWireFieldDescriptor(
        id: "normalized_x", key: "normalizedX", type: "double",
        required: true, nullable: false,
        enumValues: [],
        minimum: "0", maximum: "1",
        allowedIntegers: [],
        minItems: nil, maxItems: nil,
        finite: true, format: "normalized_coordinate",
        boundarySource: nil, outOfRangePolicy: "reject"
    ),
    GeneratedWireFieldDescriptor(
        id: "normalized_y", key: "normalizedY", type: "double",
        required: true, nullable: false,
        enumValues: [],
        minimum: "0", maximum: "1",
        allowedIntegers: [],
        minItems: nil, maxItems: nil,
        finite: true, format: "normalized_coordinate",
        boundarySource: nil, outOfRangePolicy: "reject"
    ),
    GeneratedWireFieldDescriptor(
        id: "orientation_degrees", key: "orientationDegrees", type: "int",
        required: true, nullable: false,
        enumValues: [],
        minimum: nil, maximum: nil,
        allowedIntegers: [0, 90, 180, 270],
        minItems: nil, maxItems: nil,
        finite: true, format: "orientation_degrees",
        boundarySource: nil, outOfRangePolicy: "reject"
    ),
    GeneratedWireFieldDescriptor(
        id: "pixel_height", key: "pixelHeight", type: "int",
        required: true, nullable: false,
        enumValues: [],
        minimum: "1", maximum: nil,
        allowedIntegers: [],
        minItems: nil, maxItems: nil,
        finite: true, format: "pixel_dimension",
        boundarySource: nil, outOfRangePolicy: "reject"
    ),
    GeneratedWireFieldDescriptor(
        id: "pixel_width", key: "pixelWidth", type: "int",
        required: true, nullable: false,
        enumValues: [],
        minimum: "1", maximum: nil,
        allowedIntegers: [],
        minItems: nil, maxItems: nil,
        finite: true, format: "pixel_dimension",
        boundarySource: nil, outOfRangePolicy: "reject"
    ),
    GeneratedWireFieldDescriptor(
        id: "poster_frame_millis", key: "posterFrameMillis", type: "int",
        required: true, nullable: true,
        enumValues: [],
        minimum: "0", maximum: "60000",
        allowedIntegers: [],
        minItems: nil, maxItems: nil,
        finite: true, format: "duration_millis",
        boundarySource: nil, outOfRangePolicy: "reject"
    ),
    GeneratedWireFieldDescriptor(
        id: "preferred_camera", key: "preferredCamera", type: "string",
        required: true, nullable: false,
        enumValues: ["rear", "front"],
        minimum: nil, maximum: nil,
        allowedIntegers: [],
        minItems: nil, maxItems: nil,
        finite: false, format: "none",
        boundarySource: nil, outOfRangePolicy: "not_applicable"
    ),
    GeneratedWireFieldDescriptor(
        id: "presentation_request_id", key: "presentationRequestId", type: "string",
        required: true, nullable: false,
        enumValues: [],
        minimum: nil, maximum: nil,
        allowedIntegers: [],
        minItems: nil, maxItems: nil,
        finite: false, format: "opaque_request_id",
        boundarySource: nil, outOfRangePolicy: "reject"
    ),
    GeneratedWireFieldDescriptor(
        id: "session_handle", key: "sessionHandle", type: "string",
        required: true, nullable: false,
        enumValues: [],
        minimum: nil, maximum: nil,
        allowedIntegers: [],
        minItems: nil, maxItems: nil,
        finite: false, format: "opaque_handle",
        boundarySource: nil, outOfRangePolicy: "not_applicable"
    ),
    GeneratedWireFieldDescriptor(
        id: "supported_flash_modes", key: "supportedFlashModes", type: "list_string",
        required: true, nullable: false,
        enumValues: ["off", "on", "auto", "torch"],
        minimum: nil, maximum: nil,
        allowedIntegers: [],
        minItems: 1, maxItems: 4,
        finite: false, format: "none",
        boundarySource: nil, outOfRangePolicy: "not_applicable"
    ),
    GeneratedWireFieldDescriptor(
        id: "switch_camera_supported", key: "switchCameraSupported", type: "bool",
        required: true, nullable: false,
        enumValues: [],
        minimum: nil, maximum: nil,
        allowedIntegers: [],
        minItems: nil, maxItems: nil,
        finite: false, format: "none",
        boundarySource: nil, outOfRangePolicy: "not_applicable"
    ),
    GeneratedWireFieldDescriptor(
        id: "terminal_failure_id", key: "terminalFailureId", type: "string",
        required: true, nullable: false,
        enumValues: ["permission_denied", "permission_restricted", "permission_permanently_denied", "resource_in_use", "storage_full", "encoding_failed", "system_interrupted", "session_timeout"],
        minimum: nil, maximum: nil,
        allowedIntegers: [],
        minItems: nil, maxItems: nil,
        finite: false, format: "none",
        boundarySource: nil, outOfRangePolicy: "not_applicable"
    ),
    GeneratedWireFieldDescriptor(
        id: "thumbnail_byte_length", key: "thumbnailByteLength", type: "int",
        required: true, nullable: false,
        enumValues: [],
        minimum: "1", maximum: "524288",
        allowedIntegers: [],
        minItems: nil, maxItems: nil,
        finite: true, format: "byte_length",
        boundarySource: nil, outOfRangePolicy: "reject"
    ),
    GeneratedWireFieldDescriptor(
        id: "thumbnail_content_type", key: "thumbnailContentType", type: "string",
        required: true, nullable: false,
        enumValues: [],
        minimum: nil, maximum: nil,
        allowedIntegers: [],
        minItems: nil, maxItems: nil,
        finite: false, format: "image_jpeg_content_type",
        boundarySource: nil, outOfRangePolicy: "reject"
    ),
    GeneratedWireFieldDescriptor(
        id: "thumbnail_copy", key: "thumbnailCopy", type: "bytes",
        required: true, nullable: false,
        enumValues: [],
        minimum: nil, maximum: nil,
        allowedIntegers: [],
        minItems: nil, maxItems: nil,
        finite: false, format: "caller_owned_bounded_copy",
        boundarySource: nil, outOfRangePolicy: "not_applicable"
    ),
    GeneratedWireFieldDescriptor(
        id: "thumbnail_orientation_degrees", key: "thumbnailOrientationDegrees", type: "int",
        required: true, nullable: false,
        enumValues: [],
        minimum: nil, maximum: nil,
        allowedIntegers: [0],
        minItems: nil, maxItems: nil,
        finite: true, format: "orientation_degrees",
        boundarySource: nil, outOfRangePolicy: "reject"
    ),
    GeneratedWireFieldDescriptor(
        id: "thumbnail_pixel_height", key: "thumbnailPixelHeight", type: "int",
        required: true, nullable: false,
        enumValues: [],
        minimum: "1", maximum: "512",
        allowedIntegers: [],
        minItems: nil, maxItems: nil,
        finite: true, format: "pixel_dimension",
        boundarySource: "max_pixel_edge", outOfRangePolicy: "reject"
    ),
    GeneratedWireFieldDescriptor(
        id: "thumbnail_pixel_width", key: "thumbnailPixelWidth", type: "int",
        required: true, nullable: false,
        enumValues: [],
        minimum: "1", maximum: "512",
        allowedIntegers: [],
        minItems: nil, maxItems: nil,
        finite: true, format: "pixel_dimension",
        boundarySource: "max_pixel_edge", outOfRangePolicy: "reject"
    ),
    GeneratedWireFieldDescriptor(
        id: "zoom_factor", key: "zoomFactor", type: "double",
        required: true, nullable: false,
        enumValues: [],
        minimum: nil, maximum: nil,
        allowedIntegers: [],
        minItems: nil, maxItems: nil,
        finite: true, format: "zoom_factor",
        boundarySource: "session_zoom_range", outOfRangePolicy: "reject"
    ),
]

internal let generatedPayloadFieldIds: [String: Set<String>] = [
    "capture_flow_dismissed_result_payload": [],
    "confirmed_media_result_payload": ["media_handle", "media_type", "pixel_width", "pixel_height", "duration_millis", "orientation_degrees", "byte_length", "lease_expires_at"],
    "control_applied_result_payload": ["session_handle"],
    "dismiss_capture_flow_request_payload": ["presentation_request_id"],
    "flash_mode_request_payload": ["session_handle", "flash_mode"],
    "focus_point_request_payload": ["session_handle", "normalized_x", "normalized_y"],
    "materialize_media_resource_request_payload": ["media_handle"],
    "materialized_media_released_result_payload": [],
    "materialized_media_result_payload": ["export_handle", "file_uri", "media_type", "content_type", "byte_length", "duration_millis", "expires_at", "integrity_sha256"],
    "media_handle_request_payload": ["media_handle"],
    "media_lease_expired_event_payload": ["media_handle"],
    "media_preview_ready_event_payload": ["session_handle", "media_handle", "media_type", "pixel_width", "pixel_height", "duration_millis", "orientation_degrees", "byte_length"],
    "media_preview_result_payload": ["media_handle", "media_type", "pixel_width", "pixel_height", "duration_millis", "orientation_degrees", "byte_length"],
    "media_read_revoked_event_payload": ["media_handle"],
    "media_released_result_payload": ["media_handle"],
    "media_thumbnail_request_payload": ["media_handle", "max_pixel_edge"],
    "media_thumbnail_result_payload": ["media_handle", "thumbnail_copy", "thumbnail_byte_length", "thumbnail_pixel_width", "thumbnail_pixel_height", "thumbnail_content_type", "thumbnail_orientation_degrees", "media_type", "poster_frame_millis"],
    "recording_started_result_payload": ["session_handle", "audio_included"],
    "release_materialized_media_request_payload": ["export_handle"],
    "retake_ready_result_payload": ["session_handle"],
    "session_action_request_payload": ["session_handle"],
    "session_cancelled_result_payload": ["session_handle"],
    "session_created_result_payload": ["session_handle"],
    "session_failed_event_payload": ["session_handle", "terminal_failure_id"],
    "session_ready_event_payload": ["session_handle", "active_camera", "available_cameras", "switch_camera_supported", "supported_flash_modes", "focus_point_supported", "min_zoom_factor", "max_zoom_factor"],
    "session_timeout_failure_payload": ["session_handle"],
    "start_session_request_payload": ["enabled_media_types", "preferred_camera", "audio_enabled", "max_video_duration_millis"],
    "zoom_request_payload": ["session_handle", "zoom_factor"],
]

internal struct GeneratedWirePayloadDescriptor: Sendable {
    let id: String
    let kind: String
    let fieldIds: Set<String>
    let unknownFieldPolicy: String
}
internal let generatedPayloadDescriptors = [
    GeneratedWirePayloadDescriptor(id: "capture_flow_dismissed_result_payload", kind: "result", fieldIds: [], unknownFieldPolicy: "reject"),
    GeneratedWirePayloadDescriptor(id: "confirmed_media_result_payload", kind: "result", fieldIds: ["media_handle", "media_type", "pixel_width", "pixel_height", "duration_millis", "orientation_degrees", "byte_length", "lease_expires_at"], unknownFieldPolicy: "reject"),
    GeneratedWirePayloadDescriptor(id: "control_applied_result_payload", kind: "result", fieldIds: ["session_handle"], unknownFieldPolicy: "reject"),
    GeneratedWirePayloadDescriptor(id: "dismiss_capture_flow_request_payload", kind: "request", fieldIds: ["presentation_request_id"], unknownFieldPolicy: "reject"),
    GeneratedWirePayloadDescriptor(id: "flash_mode_request_payload", kind: "request", fieldIds: ["session_handle", "flash_mode"], unknownFieldPolicy: "reject"),
    GeneratedWirePayloadDescriptor(id: "focus_point_request_payload", kind: "request", fieldIds: ["session_handle", "normalized_x", "normalized_y"], unknownFieldPolicy: "reject"),
    GeneratedWirePayloadDescriptor(id: "materialize_media_resource_request_payload", kind: "request", fieldIds: ["media_handle"], unknownFieldPolicy: "reject"),
    GeneratedWirePayloadDescriptor(id: "materialized_media_released_result_payload", kind: "result", fieldIds: [], unknownFieldPolicy: "reject"),
    GeneratedWirePayloadDescriptor(id: "materialized_media_result_payload", kind: "result", fieldIds: ["export_handle", "file_uri", "media_type", "content_type", "byte_length", "duration_millis", "expires_at", "integrity_sha256"], unknownFieldPolicy: "reject"),
    GeneratedWirePayloadDescriptor(id: "media_handle_request_payload", kind: "request", fieldIds: ["media_handle"], unknownFieldPolicy: "reject"),
    GeneratedWirePayloadDescriptor(id: "media_lease_expired_event_payload", kind: "event", fieldIds: ["media_handle"], unknownFieldPolicy: "reject"),
    GeneratedWirePayloadDescriptor(id: "media_preview_ready_event_payload", kind: "event", fieldIds: ["session_handle", "media_handle", "media_type", "pixel_width", "pixel_height", "duration_millis", "orientation_degrees", "byte_length"], unknownFieldPolicy: "reject"),
    GeneratedWirePayloadDescriptor(id: "media_preview_result_payload", kind: "result", fieldIds: ["media_handle", "media_type", "pixel_width", "pixel_height", "duration_millis", "orientation_degrees", "byte_length"], unknownFieldPolicy: "reject"),
    GeneratedWirePayloadDescriptor(id: "media_read_revoked_event_payload", kind: "event", fieldIds: ["media_handle"], unknownFieldPolicy: "reject"),
    GeneratedWirePayloadDescriptor(id: "media_released_result_payload", kind: "result", fieldIds: ["media_handle"], unknownFieldPolicy: "reject"),
    GeneratedWirePayloadDescriptor(id: "media_thumbnail_request_payload", kind: "request", fieldIds: ["media_handle", "max_pixel_edge"], unknownFieldPolicy: "reject"),
    GeneratedWirePayloadDescriptor(id: "media_thumbnail_result_payload", kind: "result", fieldIds: ["media_handle", "thumbnail_copy", "thumbnail_byte_length", "thumbnail_pixel_width", "thumbnail_pixel_height", "thumbnail_content_type", "thumbnail_orientation_degrees", "media_type", "poster_frame_millis"], unknownFieldPolicy: "reject"),
    GeneratedWirePayloadDescriptor(id: "recording_started_result_payload", kind: "result", fieldIds: ["session_handle", "audio_included"], unknownFieldPolicy: "reject"),
    GeneratedWirePayloadDescriptor(id: "release_materialized_media_request_payload", kind: "request", fieldIds: ["export_handle"], unknownFieldPolicy: "reject"),
    GeneratedWirePayloadDescriptor(id: "retake_ready_result_payload", kind: "result", fieldIds: ["session_handle"], unknownFieldPolicy: "reject"),
    GeneratedWirePayloadDescriptor(id: "session_action_request_payload", kind: "request", fieldIds: ["session_handle"], unknownFieldPolicy: "reject"),
    GeneratedWirePayloadDescriptor(id: "session_cancelled_result_payload", kind: "result", fieldIds: ["session_handle"], unknownFieldPolicy: "reject"),
    GeneratedWirePayloadDescriptor(id: "session_created_result_payload", kind: "result", fieldIds: ["session_handle"], unknownFieldPolicy: "reject"),
    GeneratedWirePayloadDescriptor(id: "session_failed_event_payload", kind: "event", fieldIds: ["session_handle", "terminal_failure_id"], unknownFieldPolicy: "reject"),
    GeneratedWirePayloadDescriptor(id: "session_ready_event_payload", kind: "event", fieldIds: ["session_handle", "active_camera", "available_cameras", "switch_camera_supported", "supported_flash_modes", "focus_point_supported", "min_zoom_factor", "max_zoom_factor"], unknownFieldPolicy: "reject"),
    GeneratedWirePayloadDescriptor(id: "session_timeout_failure_payload", kind: "failure", fieldIds: ["session_handle"], unknownFieldPolicy: "reject"),
    GeneratedWirePayloadDescriptor(id: "start_session_request_payload", kind: "request", fieldIds: ["enabled_media_types", "preferred_camera", "audio_enabled", "max_video_duration_millis"], unknownFieldPolicy: "reject"),
    GeneratedWirePayloadDescriptor(id: "zoom_request_payload", kind: "request", fieldIds: ["session_handle", "zoom_factor"], unknownFieldPolicy: "reject"),
]
internal struct GeneratedWireErrorDescriptor: Sendable {
    let code: String
    let source: String
    let capabilityFailureId: String?
    let recoverable: Bool
    let terminal: Bool
    let messagePolicy: String
    let detailsAllowedKeys: Set<String>
}
internal let generatedErrorDescriptors = [
    GeneratedWireErrorDescriptor(code: "bridge_overloaded", source: "wire_protocol", capabilityFailureId: nil, recoverable: true, terminal: false, messagePolicy: "static_redacted", detailsAllowedKeys: ["operation", "capacity"]),
    GeneratedWireErrorDescriptor(code: "bridge_unavailable", source: "wire_protocol", capabilityFailureId: nil, recoverable: true, terminal: false, messagePolicy: "static_redacted", detailsAllowedKeys: ["operation", "lifecycleReason"]),
    GeneratedWireErrorDescriptor(code: "duplicate_request", source: "wire_protocol", capabilityFailureId: nil, recoverable: true, terminal: false, messagePolicy: "static_redacted", detailsAllowedKeys: ["operation"]),
    GeneratedWireErrorDescriptor(code: "encoding_failed", source: "capability_failure", capabilityFailureId: "encoding_failed", recoverable: true, terminal: true, messagePolicy: "static_redacted", detailsAllowedKeys: ["operation", "capabilityFailureId"]),
    GeneratedWireErrorDescriptor(code: "incompatible_wire_version", source: "wire_protocol", capabilityFailureId: nil, recoverable: false, terminal: false, messagePolicy: "static_redacted", detailsAllowedKeys: ["actualWireVersion", "expectedWireVersion"]),
    GeneratedWireErrorDescriptor(code: "invalid_argument", source: "capability_failure", capabilityFailureId: "invalid_argument", recoverable: true, terminal: false, messagePolicy: "static_redacted", detailsAllowedKeys: ["operation", "capabilityFailureId"]),
    GeneratedWireErrorDescriptor(code: "invalid_state", source: "capability_failure", capabilityFailureId: "invalid_state", recoverable: true, terminal: false, messagePolicy: "static_redacted", detailsAllowedKeys: ["operation", "capabilityFailureId"]),
    GeneratedWireErrorDescriptor(code: "invalid_wire_payload", source: "wire_protocol", capabilityFailureId: nil, recoverable: true, terminal: false, messagePolicy: "static_redacted", detailsAllowedKeys: ["operation", "field", "reason"]),
    GeneratedWireErrorDescriptor(code: "listener_already_active", source: "wire_protocol", capabilityFailureId: nil, recoverable: true, terminal: false, messagePolicy: "static_redacted", detailsAllowedKeys: []),
    GeneratedWireErrorDescriptor(code: "materialized_media_invalid", source: "wire_protocol", capabilityFailureId: nil, recoverable: true, terminal: false, messagePolicy: "static_redacted", detailsAllowedKeys: ["operation"]),
    GeneratedWireErrorDescriptor(code: "media_export_cancelled", source: "capability_failure", capabilityFailureId: "media_export_cancelled", recoverable: true, terminal: false, messagePolicy: "static_redacted", detailsAllowedKeys: ["operation", "capabilityFailureId"]),
    GeneratedWireErrorDescriptor(code: "media_export_conflict", source: "capability_failure", capabilityFailureId: "media_export_conflict", recoverable: true, terminal: false, messagePolicy: "static_redacted", detailsAllowedKeys: ["operation", "capabilityFailureId"]),
    GeneratedWireErrorDescriptor(code: "media_export_overloaded", source: "capability_failure", capabilityFailureId: "media_export_overloaded", recoverable: true, terminal: false, messagePolicy: "static_redacted", detailsAllowedKeys: ["operation", "capabilityFailureId"]),
    GeneratedWireErrorDescriptor(code: "media_export_read_failed", source: "capability_failure", capabilityFailureId: "media_export_read_failed", recoverable: true, terminal: false, messagePolicy: "static_redacted", detailsAllowedKeys: ["operation", "capabilityFailureId"]),
    GeneratedWireErrorDescriptor(code: "media_export_sink_rejected", source: "capability_failure", capabilityFailureId: "media_export_sink_rejected", recoverable: true, terminal: false, messagePolicy: "static_redacted", detailsAllowedKeys: ["operation", "capabilityFailureId"]),
    GeneratedWireErrorDescriptor(code: "media_export_timed_out", source: "capability_failure", capabilityFailureId: "media_export_timed_out", recoverable: true, terminal: false, messagePolicy: "static_redacted", detailsAllowedKeys: ["operation", "capabilityFailureId"]),
    GeneratedWireErrorDescriptor(code: "media_export_too_large", source: "capability_failure", capabilityFailureId: "media_export_too_large", recoverable: true, terminal: false, messagePolicy: "static_redacted", detailsAllowedKeys: ["operation", "capabilityFailureId"]),
    GeneratedWireErrorDescriptor(code: "media_export_write_failed", source: "capability_failure", capabilityFailureId: "media_export_write_failed", recoverable: true, terminal: false, messagePolicy: "static_redacted", detailsAllowedKeys: ["operation", "capabilityFailureId"]),
    GeneratedWireErrorDescriptor(code: "media_invalid", source: "capability_failure", capabilityFailureId: "media_invalid", recoverable: false, terminal: false, messagePolicy: "static_redacted", detailsAllowedKeys: ["operation", "capabilityFailureId"]),
    GeneratedWireErrorDescriptor(code: "permission_denied", source: "capability_failure", capabilityFailureId: "permission_denied", recoverable: true, terminal: true, messagePolicy: "static_redacted", detailsAllowedKeys: ["operation", "capabilityFailureId"]),
    GeneratedWireErrorDescriptor(code: "permission_permanently_denied", source: "capability_failure", capabilityFailureId: "permission_permanently_denied", recoverable: false, terminal: true, messagePolicy: "static_redacted", detailsAllowedKeys: ["operation", "capabilityFailureId"]),
    GeneratedWireErrorDescriptor(code: "permission_restricted", source: "capability_failure", capabilityFailureId: "permission_restricted", recoverable: false, terminal: true, messagePolicy: "static_redacted", detailsAllowedKeys: ["operation", "capabilityFailureId"]),
    GeneratedWireErrorDescriptor(code: "presentation_conflict", source: "wire_protocol", capabilityFailureId: nil, recoverable: true, terminal: false, messagePolicy: "static_redacted", detailsAllowedKeys: ["operation", "capacity"]),
    GeneratedWireErrorDescriptor(code: "resource_in_use", source: "capability_failure", capabilityFailureId: "resource_in_use", recoverable: true, terminal: true, messagePolicy: "static_redacted", detailsAllowedKeys: ["operation", "capabilityFailureId"]),
    GeneratedWireErrorDescriptor(code: "session_conflict", source: "capability_failure", capabilityFailureId: "session_conflict", recoverable: true, terminal: false, messagePolicy: "static_redacted", detailsAllowedKeys: ["operation", "capabilityFailureId"]),
    GeneratedWireErrorDescriptor(code: "session_invalid", source: "capability_failure", capabilityFailureId: "session_invalid", recoverable: false, terminal: false, messagePolicy: "static_redacted", detailsAllowedKeys: ["operation", "capabilityFailureId"]),
    GeneratedWireErrorDescriptor(code: "session_timeout", source: "capability_failure", capabilityFailureId: "session_timeout", recoverable: true, terminal: true, messagePolicy: "static_redacted", detailsAllowedKeys: ["operation", "capabilityFailureId"]),
    GeneratedWireErrorDescriptor(code: "storage_full", source: "capability_failure", capabilityFailureId: "storage_full", recoverable: true, terminal: true, messagePolicy: "static_redacted", detailsAllowedKeys: ["operation", "capabilityFailureId"]),
    GeneratedWireErrorDescriptor(code: "system_interrupted", source: "capability_failure", capabilityFailureId: "system_interrupted", recoverable: true, terminal: true, messagePolicy: "static_redacted", detailsAllowedKeys: ["operation", "capabilityFailureId"]),
    GeneratedWireErrorDescriptor(code: "thumbnail_generation_cancelled", source: "capability_failure", capabilityFailureId: "thumbnail_generation_cancelled", recoverable: true, terminal: false, messagePolicy: "static_redacted", detailsAllowedKeys: ["operation", "capabilityFailureId"]),
    GeneratedWireErrorDescriptor(code: "thumbnail_generation_failed", source: "capability_failure", capabilityFailureId: "thumbnail_generation_failed", recoverable: true, terminal: false, messagePolicy: "static_redacted", detailsAllowedKeys: ["operation", "capabilityFailureId"]),
    GeneratedWireErrorDescriptor(code: "thumbnail_overloaded", source: "capability_failure", capabilityFailureId: "thumbnail_overloaded", recoverable: true, terminal: false, messagePolicy: "static_redacted", detailsAllowedKeys: ["operation", "capabilityFailureId"]),
    GeneratedWireErrorDescriptor(code: "transfer_store_overloaded", source: "wire_protocol", capabilityFailureId: nil, recoverable: true, terminal: false, messagePolicy: "static_redacted", detailsAllowedKeys: ["operation", "capacity"]),
    GeneratedWireErrorDescriptor(code: "transfer_store_unavailable", source: "wire_protocol", capabilityFailureId: nil, recoverable: true, terminal: false, messagePolicy: "static_redacted", detailsAllowedKeys: ["operation", "lifecycleReason"]),
    GeneratedWireErrorDescriptor(code: "unsupported_capability", source: "capability_failure", capabilityFailureId: "unsupported_capability", recoverable: true, terminal: false, messagePolicy: "static_redacted", detailsAllowedKeys: ["operation", "capabilityFailureId"]),
    GeneratedWireErrorDescriptor(code: "wire_encoding_failed", source: "wire_protocol", capabilityFailureId: nil, recoverable: false, terminal: false, messagePolicy: "static_redacted", detailsAllowedKeys: ["operation", "field", "reason"]),
]
internal struct GeneratedWireErrorDetailDescriptor: Sendable {
    let key: String
    let type: String
    let source: String
    let enumValues: Set<String>
    let minLength: Int?
    let maxLength: Int?
    let minimum: String?
    let maximum: String?
    let redaction: String
}
internal let generatedErrorDetailDescriptors = [
    GeneratedWireErrorDetailDescriptor(key: "actualWireVersion", type: "int", source: "request_wire_version", enumValues: [], minLength: nil, maxLength: nil, minimum: "-9223372036854775808", maximum: "9223372036854775807", redaction: "allowlisted_value_only"),
    GeneratedWireErrorDetailDescriptor(key: "capabilityFailureId", type: "string", source: "capability_failure_id", enumValues: ["permission_denied", "permission_restricted", "permission_permanently_denied", "resource_in_use", "storage_full", "encoding_failed", "media_invalid", "session_invalid", "unsupported_capability", "system_interrupted", "session_conflict", "invalid_state", "invalid_argument", "session_timeout", "thumbnail_generation_failed", "thumbnail_generation_cancelled", "thumbnail_overloaded", "attachment_generation_retired", "attachment_target_conflict", "media_export_conflict", "media_export_overloaded", "media_export_too_large", "media_export_sink_rejected", "media_export_read_failed", "media_export_write_failed", "media_export_cancelled", "media_export_timed_out"], minLength: 1, maxLength: 64, minimum: nil, maximum: nil, redaction: "allowlisted_value_only"),
    GeneratedWireErrorDetailDescriptor(key: "capacity", type: "string", source: "closed_capacity_code", enumValues: ["active_export_bytes", "active_exports", "active_presentation", "completed_request_tombstones", "pending_requests", "release_tombstones"], minLength: 1, maxLength: 64, minimum: nil, maximum: nil, redaction: "allowlisted_value_only"),
    GeneratedWireErrorDetailDescriptor(key: "expectedWireVersion", type: "int", source: "contract_wire_version", enumValues: [], minLength: nil, maxLength: nil, minimum: "-9223372036854775808", maximum: "9223372036854775807", redaction: "allowlisted_value_only"),
    GeneratedWireErrorDetailDescriptor(key: "field", type: "string", source: "declared_field_key_or_unknown", enumValues: ["wireVersion", "requestId", "payload", "resultType", "eventType", "failureType", "enabledMediaTypes", "preferredCamera", "audioEnabled", "maxVideoDurationMillis", "sessionHandle", "flashMode", "normalizedX", "normalizedY", "zoomFactor", "mediaHandle", "activeCamera", "availableCameras", "switchCameraSupported", "supportedFlashModes", "focusPointSupported", "minZoomFactor", "maxZoomFactor", "audioIncluded", "mediaType", "pixelWidth", "pixelHeight", "durationMillis", "orientationDegrees", "byteLength", "leaseExpiresAt", "terminalFailureId", "maxPixelEdge", "thumbnailCopy", "thumbnailByteLength", "thumbnailPixelWidth", "thumbnailPixelHeight", "thumbnailContentType", "thumbnailOrientationDegrees", "posterFrameMillis", "unknown_field", "contentType", "exportHandle", "fileUri", "expiresAt", "integritySha256", "presentationRequestId"], minLength: 1, maxLength: 64, minimum: nil, maximum: nil, redaction: "allowlisted_value_only"),
    GeneratedWireErrorDetailDescriptor(key: "lifecycleReason", type: "string", source: "closed_lifecycle_reason", enumValues: ["engine_detached", "activity_destroyed", "view_controller_destroyed", "adapter_disposed"], minLength: 1, maxLength: 64, minimum: nil, maximum: nil, redaction: "allowlisted_value_only"),
    GeneratedWireErrorDetailDescriptor(key: "operation", type: "string", source: "method_id_or_unknown", enumValues: ["start_session", "take_photo", "start_recording", "stop_recording", "switch_camera", "set_flash_mode", "set_focus_point", "set_zoom", "retake", "confirm", "cancel", "release_media", "read_media_thumbnail", "present_capture_flow", "unknown_operation", "materialize_media_resource", "release_materialized_media", "dismiss_capture_flow"], minLength: 1, maxLength: 64, minimum: nil, maximum: nil, redaction: "allowlisted_value_only"),
    GeneratedWireErrorDetailDescriptor(key: "reason", type: "string", source: "closed_reason_code", enumValues: ["missing_required_field", "unknown_field", "type_mismatch", "null_not_allowed", "non_finite", "out_of_range", "invalid_enum", "invalid_format", "integer_overflow", "result_type_mismatch", "native_value_unencodable"], minLength: 1, maxLength: 64, minimum: nil, maximum: nil, redaction: "allowlisted_value_only"),
]
internal let generatedRequestIdWireType = "string"
internal let generatedRequestIdPattern = "^[A-Za-z0-9_-]{1,128}$"
internal let generatedRequestIdFormat = "ascii_token"
internal let generatedRequestIdMinLength = 1
internal let generatedRequestIdMaxLength = 128
internal let generatedEnvelopeRequiredKeys: [String: Set<String>] = [
    "/lifecycle/eventEnvelope": ["wireVersion", "eventType", "payload"],
    "/lifecycle/eventListenEnvelope": ["wireVersion"],
    "/lifecycle/failureEnvelope": ["wireVersion", "failureType", "payload"],
    "/lifecycle/requestEnvelope": ["wireVersion", "requestId", "payload"],
    "/lifecycle/resultEnvelope": ["wireVersion", "requestId", "resultType", "payload"],
]
internal let generatedEnvelopeUnknownFieldPolicies: [String: String] = [
    "/lifecycle/eventEnvelope": "reject",
    "/lifecycle/eventListenEnvelope": "reject",
    "/lifecycle/failureEnvelope": "reject",
    "/lifecycle/requestEnvelope": "reject",
    "/lifecycle/resultEnvelope": "reject",
]
internal let generatedSignedIntegerMinimum: Int64 = Int64.min
internal let generatedSignedIntegerMaximum: Int64 = Int64.max
internal let generatedOpaqueHandleLengths: [String: ClosedRange<Int>] = [
    "export_handle": 22...64,
    "media_handle": 1...128,
    "session_handle": 1...128,
]

internal func generatedHasExactWireKeys(
    _ value: [String: Any], requiredKeys: Set<String>
) -> Bool {
    value.count == requiredKeys.count && Set(value.keys) == requiredKeys
}

internal func generatedIsWireBoolean(_ value: Any) -> Bool {
    guard let number = value as? NSNumber else { return false }
    return CFGetTypeID(number) == CFBooleanGetTypeID()
}

internal func generatedWireDouble(_ value: Any) -> Double? {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID(),
          CFNumberIsFloatType(number as CFNumber) else { return nil }
    return number.doubleValue
}

internal func generatedWireInteger(_ value: Any) -> Int64? {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID(),
          !CFNumberIsFloatType(number as CFNumber) else { return nil }
    return number.int64Value
}

internal func generatedMatchesWireFieldPrimitive(
    _ value: Any?, field: GeneratedWireFieldDescriptor
) -> Bool {
    guard let value else { return field.nullable }
    if let bytes = value as? Data {
        if let minimum = field.minItems, bytes.count < minimum { return false }
        if let maximum = field.maxItems, bytes.count > maximum { return false }
    }
    switch field.type {
    case "bool": return generatedIsWireBoolean(value)
    case "bytes": return value is Data
    case "double":
        guard let number = generatedWireDouble(value) else { return false }
        if field.finite && !number.isFinite { return false }
        if let minimum = field.minimum.flatMap(Double.init), number < minimum { return false }
        if let maximum = field.maximum.flatMap(Double.init), number > maximum { return false }
        return true
    case "int":
        guard let number = generatedWireInteger(value) else { return false }
        if let minimum = field.minimum.flatMap(Int64.init), number < minimum { return false }
        if let maximum = field.maximum.flatMap(Int64.init), number > maximum { return false }
        return field.allowedIntegers.isEmpty || field.allowedIntegers.contains(number)
    case "string":
        guard let string = value as? String else { return false }
        return field.enumValues.isEmpty || field.enumValues.contains(string)
    case "list_bool", "list_double", "list_int", "list_string":
        guard let values = value as? [Any] else { return false }
        if let minimum = field.minItems, values.count < minimum { return false }
        if let maximum = field.maxItems, values.count > maximum { return false }
        switch field.type {
        case "list_bool": return values.allSatisfy(generatedIsWireBoolean)
        case "list_double":
            let numbers = values.compactMap(generatedWireDouble)
            guard numbers.count == values.count else { return false }
            return !field.finite || numbers.allSatisfy(\.isFinite)
        case "list_int": return values.allSatisfy { generatedWireInteger($0) != nil }
        default:
            guard values.allSatisfy({ $0 is String }) else { return false }
            let strings = values.map { $0 as! String }
            guard field.enumValues.isEmpty || strings.allSatisfy(field.enumValues.contains) else { return false }
            return field.enumValues.isEmpty || Set(strings).count == strings.count
        }
    default: return false
    }
}
