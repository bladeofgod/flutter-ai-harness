import CoreFoundation
import Foundation
import MediaCapture

package enum MediaCaptureWireCodec {
    package static let methods: Set<String> = [
        "start_session",
        "take_photo",
        "start_recording",
        "stop_recording",
        "switch_camera",
        "set_flash_mode",
        "set_focus_point",
        "set_zoom",
        "retake",
        "confirm",
        "cancel",
        "release_media",
        "read_media_thumbnail",
        "present_capture_flow",
        "dismiss_capture_flow",
        "materialize_media_resource",
        "release_materialized_media",
    ]

    package static func decodeRequest(
        operation: String,
        arguments: Any?
    ) throws -> MediaCaptureWireRequest {
        guard methods.contains(operation) else {
            throw invalidPayload(operation: "unknown_operation", field: "payload", reason: "invalid_enum")
        }
        let envelope = try WireObject(arguments, operation: operation, field: "payload")
        try envelope.requireKeys(["wireVersion", "requestId", "payload"], operation: operation)
        let version = try envelope.integer("wireVersion", operation: operation)
        guard version == Int64(mediaCaptureWireVersion) else {
            throw MediaCaptureWireFailure(
                code: "incompatible_wire_version",
                details: [
                    "actualWireVersion": String(version),
                    "expectedWireVersion": String(mediaCaptureWireVersion),
                ]
            )
        }
        let requestId = try envelope.string("requestId", operation: operation)
        guard isRequestId(requestId) else {
            throw invalidPayload(operation: operation, field: "requestId", reason: "invalid_format")
        }
        let payload = try WireObject(
            envelope.value("payload", operation: operation),
            operation: operation,
            field: "payload"
        )
        return MediaCaptureWireRequest(
            requestId: requestId,
            operation: operation,
            payload: try decodePayload(operation: operation, payload: payload)
        )
    }

    package static func decodeListenArguments(_ arguments: Any?) throws {
        let envelope = try WireObject(arguments, operation: "unknown_operation", field: "payload")
        try envelope.requireKeys(["wireVersion"], operation: "unknown_operation")
        let version = try envelope.integer("wireVersion", operation: "unknown_operation")
        guard version == Int64(mediaCaptureWireVersion) else {
            throw MediaCaptureWireFailure(
                code: "incompatible_wire_version",
                details: [
                    "actualWireVersion": String(version),
                    "expectedWireVersion": String(mediaCaptureWireVersion),
                ]
            )
        }
    }

    package static func sessionCreated(
        requestId: String,
        handle: SessionHandle
    ) throws -> [String: Any] {
        try result(
            requestId: requestId,
            resultType: "session_created",
            payload: ["sessionHandle": outputHandle(handle.rawValue)]
        )
    }

    package static func controlApplied(
        requestId: String,
        handle: SessionHandle
    ) throws -> [String: Any] {
        try result(
            requestId: requestId,
            resultType: "control_applied",
            payload: ["sessionHandle": outputHandle(handle.rawValue)]
        )
    }

    package static func recordingStarted(
        requestId: String,
        value: MediaCaptureRecordingValue
    ) throws -> [String: Any] {
        try result(
            requestId: requestId,
            resultType: "recording_started",
            payload: [
                "sessionHandle": outputHandle(value.sessionHandle.rawValue),
                "audioIncluded": value.audioIncluded,
            ]
        )
    }

    package static func mediaPreview(
        requestId: String,
        metadata: MediaMetadata
    ) throws -> [String: Any] {
        try result(
            requestId: requestId,
            resultType: "media_preview",
            payload: try mediaPayload(metadata)
        )
    }

    package static func retakeReady(
        requestId: String,
        handle: SessionHandle
    ) throws -> [String: Any] {
        try result(
            requestId: requestId,
            resultType: "retake_ready",
            payload: ["sessionHandle": outputHandle(handle.rawValue)]
        )
    }

    package static func confirmedMedia(
        requestId: String,
        value: MediaCaptureConfirmedValue,
        resultType: String = "confirmed_media"
    ) throws -> [String: Any] {
        var payload = try mediaPayload(value.metadata)
        payload["leaseExpiresAt"] = try epochMilliseconds(value.leaseExpiresAt)
        return try result(requestId: requestId, resultType: resultType, payload: payload)
    }

    package static func sessionCancelled(
        requestId: String,
        handle: SessionHandle
    ) throws -> [String: Any] {
        try result(
            requestId: requestId,
            resultType: "session_cancelled",
            payload: ["sessionHandle": outputHandle(handle.rawValue)]
        )
    }

    package static func mediaReleased(
        requestId: String,
        handle: MediaHandle
    ) throws -> [String: Any] {
        try result(
            requestId: requestId,
            resultType: "media_released",
            payload: ["mediaHandle": outputHandle(handle.rawValue)]
        )
    }

    package static func materializedMedia(
        requestId: String,
        exportHandle: String,
        fileURI: String,
        metadata: MediaMetadata,
        expiresAtEpochMilliseconds: Int64
    ) throws -> [String: Any] {
        guard isExportHandle(exportHandle),
              (1 ... MediaCaptureTransferStore.maximumFileBytes).contains(metadata.byteLength),
              expiresAtEpochMilliseconds >= 0,
              (metadata.mediaType == .photo && metadata.durationMilliseconds == nil) ||
              (metadata.mediaType == .video && metadata.durationMilliseconds.map {
                  (1 ... 60_000).contains($0)
              } == true)
        else {
            throw wireEncodingFailure(operation: "materialize_media_resource")
        }
        try requireCanonicalFileURI(fileURI)
        return try result(
            requestId: requestId,
            resultType: "materialized_media_resource",
            payload: [
                "exportHandle": exportHandle,
                "fileUri": fileURI,
                "mediaType": metadata.mediaType.rawValue,
                "contentType": metadata.mediaType == .photo ? "image/jpeg" : "video/mp4",
                "byteLength": Int64(metadata.byteLength),
                "durationMillis": metadata.durationMilliseconds.map { Int64($0) as Any } ?? NSNull(),
                "expiresAt": expiresAtEpochMilliseconds,
            ]
        )
    }

    package static func materializedMediaReleased(requestId: String) throws -> [String: Any] {
        try result(requestId: requestId, resultType: "materialized_media_released", payload: [:])
    }

    package static func thumbnail(
        requestId: String,
        value: MediaCaptureThumbnailValue,
        maxPixelEdge: Int
    ) throws -> [String: Any] {
        try thumbnail(
            requestId: requestId,
            encoded: encodeThumbnail(value: value, maxPixelEdge: maxPixelEdge)
        )
    }

    package static func encodeThumbnail(
        value: MediaCaptureThumbnailValue,
        maxPixelEdge: Int
    ) throws -> MediaCaptureEncodedThumbnail {
        var data = value.copyData()
        defer {
            data.resetBytes(in: 0 ..< data.count)
            data.removeAll(keepingCapacity: false)
        }
        guard (64 ... 512).contains(maxPixelEdge),
              !data.isEmpty,
              data.count <= 524_288,
              (1 ... maxPixelEdge).contains(value.pixelWidth),
              (1 ... maxPixelEdge).contains(value.pixelHeight),
              value.contentType == "image/jpeg",
              value.orientationDegrees == 0,
              (value.mediaType == .photo && value.posterFrameMilliseconds == nil) ||
              (value.mediaType == .video && value.posterFrameMilliseconds.map { (0 ... 60_000).contains($0) } == true),
              SanitizedJpegValidator.isValid(
                  data,
                  expectedWidth: value.pixelWidth,
                  expectedHeight: value.pixelHeight
              )
        else {
            throw wireEncodingFailure(operation: "read_media_thumbnail")
        }
        return MediaCaptureEncodedThumbnail(
            mediaHandle: value.mediaHandle,
            bytes: MediaCaptureWireBytes(data),
            byteLength: data.count,
            pixelWidth: value.pixelWidth,
            pixelHeight: value.pixelHeight,
            mediaType: value.mediaType,
            posterFrameMilliseconds: value.posterFrameMilliseconds,
            contentType: value.contentType,
            orientationDegrees: value.orientationDegrees
        )
    }

    package static func thumbnail(
        requestId: String,
        encoded: MediaCaptureEncodedThumbnail
    ) throws -> [String: Any] {
        return try result(
            requestId: requestId,
            resultType: "media_thumbnail",
            payload: [
                "mediaHandle": try outputHandle(encoded.mediaHandle.rawValue),
                "thumbnailCopy": encoded.bytes,
                "thumbnailByteLength": Int64(encoded.byteLength),
                "thumbnailPixelWidth": Int64(encoded.pixelWidth),
                "thumbnailPixelHeight": Int64(encoded.pixelHeight),
                "thumbnailContentType": encoded.contentType,
                "thumbnailOrientationDegrees": Int64(encoded.orientationDegrees),
                "mediaType": encoded.mediaType.rawValue,
                "posterFrameMillis": encoded.posterFrameMilliseconds.map { Int64($0) as Any } ?? NSNull(),
            ]
        )
    }

    package static func captureFlowCancelled(requestId: String) throws -> [String: Any] {
        try result(requestId: requestId, resultType: "capture_flow_cancelled", payload: [:])
    }

    package static func captureFlowDismissed(requestId: String) throws -> [String: Any] {
        try result(requestId: requestId, resultType: "capture_flow_dismissed", payload: [:])
    }

    package static func event(_ event: MediaCaptureEvent) throws -> [String: Any]? {
        switch event {
        case let .sessionReady(snapshot):
            return eventEnvelope(type: "session_ready", payload: try readyPayload(snapshot))
        case let .sessionFailed(sessionHandle, failure):
            if failure.id == .sessionTimeout {
                return failureEnvelope(
                    type: "session_timeout",
                    payload: ["sessionHandle": try outputHandle(sessionHandle.rawValue)]
                )
            }
            let terminalIds: Set<MediaCaptureFailure.ID> = [
                .permissionDenied,
                .permissionRestricted,
                .permissionPermanentlyDenied,
                .resourceInUse,
                .storageFull,
                .encodingFailed,
                .systemInterrupted,
            ]
            guard terminalIds.contains(failure.id) else {
                throw wireEncodingFailure(operation: "unknown_operation")
            }
            return eventEnvelope(
                type: "session_failed",
                payload: [
                    "sessionHandle": try outputHandle(sessionHandle.rawValue),
                    "terminalFailureId": failure.id.rawValue,
                ]
            )
        case let .mediaPreviewReady(sessionHandle, metadata):
            var payload = try mediaPayload(metadata)
            payload["sessionHandle"] = try outputHandle(sessionHandle.rawValue)
            return eventEnvelope(type: "media_preview_ready", payload: payload)
        case let .mediaLeaseExpired(handle):
            return eventEnvelope(
                type: "media_lease_expired",
                payload: ["mediaHandle": try outputHandle(handle.rawValue)]
            )
        case let .mediaReadRevoked(handle):
            return eventEnvelope(
                type: "media_read_revoked",
                payload: ["mediaHandle": try outputHandle(handle.rawValue)]
            )
        case .renderAttachmentRevoked:
            return nil
        }
    }

    package static func capabilityFailure(
        operation: String,
        failure: MediaCaptureFailure
    ) -> MediaCaptureWireFailure {
        guard allowedFailures[operation]?.contains(failure.id) == true else {
            return wireEncodingFailure(operation: operation)
        }
        return MediaCaptureWireFailure(
            code: failure.id.rawValue,
            details: [
                "operation": safeOperation(operation),
                "capabilityFailureId": failure.id.rawValue,
            ]
        )
    }

    package static func invalidPayload(
        operation: String,
        field: String,
        reason: String
    ) -> MediaCaptureWireFailure {
        MediaCaptureWireFailure(
            code: "invalid_wire_payload",
            details: [
                "operation": safeOperation(operation),
                "field": allowedFields.contains(field) ? field : "unknown_field",
                "reason": allowedReasons.contains(reason) ? reason : "invalid_format",
            ]
        )
    }

    package static func bridgeUnavailable(
        operation: String,
        reason: String
    ) -> MediaCaptureWireFailure {
        let safeReason = lifecycleReasons.contains(reason) ? reason : "adapter_disposed"
        return MediaCaptureWireFailure(
            code: "bridge_unavailable",
            details: ["operation": safeOperation(operation), "lifecycleReason": safeReason]
        )
    }

    package static func bridgeOverloaded(
        operation: String,
        capacity: String
    ) -> MediaCaptureWireFailure {
        let safeCapacity = capacities.contains(capacity) ? capacity : "pending_requests"
        return MediaCaptureWireFailure(
            code: "bridge_overloaded",
            details: ["operation": safeOperation(operation), "capacity": safeCapacity]
        )
    }

    package static func duplicateRequest(operation: String) -> MediaCaptureWireFailure {
        MediaCaptureWireFailure(
            code: "duplicate_request",
            details: ["operation": safeOperation(operation)]
        )
    }

    package static func listenerAlreadyActive() -> MediaCaptureWireFailure {
        MediaCaptureWireFailure(code: "listener_already_active", details: [:])
    }

    package static func presentationConflict() -> MediaCaptureWireFailure {
        MediaCaptureWireFailure(
            code: "presentation_conflict",
            details: ["operation": "present_capture_flow", "capacity": "active_presentation"]
        )
    }

    package static func wireEncodingFailure(operation: String) -> MediaCaptureWireFailure {
        MediaCaptureWireFailure(
            code: "wire_encoding_failed",
            details: [
                "operation": safeOperation(operation),
                "field": "unknown_field",
                "reason": "native_value_unencodable",
            ]
        )
    }

    package static func transferStoreOverloaded(
        operation: String,
        capacity: String
    ) -> MediaCaptureWireFailure {
        MediaCaptureWireFailure(
            code: "transfer_store_overloaded",
            details: ["operation": safeOperation(operation), "capacity": capacity]
        )
    }

    package static func transferStoreUnavailable(operation: String) -> MediaCaptureWireFailure {
        MediaCaptureWireFailure(
            code: "transfer_store_unavailable",
            details: [
                "operation": safeOperation(operation),
                "lifecycleReason": "adapter_disposed",
            ]
        )
    }

    package static func materializedMediaInvalid() -> MediaCaptureWireFailure {
        MediaCaptureWireFailure(
            code: "materialized_media_invalid",
            details: ["operation": "release_materialized_media"]
        )
    }

    private static func decodePayload(
        operation: String,
        payload: WireObject
    ) throws -> MediaCaptureWirePayload {
        switch operation {
        case "start_session", "present_capture_flow":
            try payload.requireKeys(
                ["enabledMediaTypes", "preferredCamera", "audioEnabled", "maxVideoDurationMillis"],
                operation: operation
            )
            let mediaTypeValues = try payload.enumList(
                "enabledMediaTypes",
                operation: operation,
                allowed: ["photo", "video"]
            )
            let preferredCamera = try payload.enumValue(
                "preferredCamera",
                operation: operation,
                allowed: ["rear", "front"]
            )
            let duration = try payload.integer("maxVideoDurationMillis", operation: operation)
            guard (1 ... 60_000).contains(duration) else {
                throw invalidPayload(
                    operation: operation,
                    field: "maxVideoDurationMillis",
                    reason: "out_of_range"
                )
            }
            let types = Set(mediaTypeValues.compactMap(MediaType.init(rawValue:)))
            guard types.count == mediaTypeValues.count,
                  let camera = CameraPosition(rawValue: preferredCamera)
            else {
                throw invalidPayload(operation: operation, field: "payload", reason: "invalid_enum")
            }
            do {
                return .startSession(
                    try SessionOptions(
                        enabledMediaTypes: types,
                        preferredCamera: camera,
                        audioEnabled: payload.boolean("audioEnabled", operation: operation),
                        maxVideoDurationMilliseconds: Int(duration)
                    )
                )
            } catch {
                throw invalidPayload(operation: operation, field: "payload", reason: "out_of_range")
            }
        case "take_photo", "start_recording", "stop_recording", "switch_camera", "cancel":
            try payload.requireKeys(["sessionHandle"], operation: operation)
            return .sessionAction(try payload.sessionHandle(operation: operation))
        case "set_flash_mode":
            try payload.requireKeys(["sessionHandle", "flashMode"], operation: operation)
            let value = try payload.enumValue(
                "flashMode",
                operation: operation,
                allowed: ["off", "on", "auto", "torch"]
            )
            guard let mode = FlashMode(rawValue: value) else {
                throw invalidPayload(operation: operation, field: "flashMode", reason: "invalid_enum")
            }
            return .flash(sessionHandle: try payload.sessionHandle(operation: operation), mode: mode)
        case "set_focus_point":
            try payload.requireKeys(
                ["sessionHandle", "normalizedX", "normalizedY"],
                operation: operation
            )
            return .focus(
                sessionHandle: try payload.sessionHandle(operation: operation),
                normalizedX: try payload.finiteDouble(
                    "normalizedX",
                    operation: operation,
                    range: 0 ... 1
                ),
                normalizedY: try payload.finiteDouble(
                    "normalizedY",
                    operation: operation,
                    range: 0 ... 1
                )
            )
        case "set_zoom":
            try payload.requireKeys(["sessionHandle", "zoomFactor"], operation: operation)
            let factor = try payload.finiteDouble(
                "zoomFactor",
                operation: operation,
                minimum: 0.01
            )
            return .zoom(sessionHandle: try payload.sessionHandle(operation: operation), factor: factor)
        case "retake", "confirm", "release_media":
            try payload.requireKeys(["mediaHandle"], operation: operation)
            return .mediaAction(try payload.mediaHandle(operation: operation))
        case "materialize_media_resource":
            try payload.requireKeys(["mediaHandle"], operation: operation)
            return .materialize(try payload.mediaHandle(operation: operation))
        case "release_materialized_media":
            try payload.requireKeys(["exportHandle"], operation: operation)
            let exportHandle = try payload.string("exportHandle", operation: operation)
            guard isExportHandle(exportHandle) else {
                throw invalidPayload(
                    operation: operation,
                    field: "exportHandle",
                    reason: "invalid_format"
                )
            }
            return .releaseMaterialized(exportHandle: exportHandle)
        case "read_media_thumbnail":
            try payload.requireKeys(["mediaHandle", "maxPixelEdge"], operation: operation)
            let edge = try payload.integer("maxPixelEdge", operation: operation)
            guard (64 ... 512).contains(edge) else {
                throw invalidPayload(operation: operation, field: "maxPixelEdge", reason: "out_of_range")
            }
            return .thumbnail(
                mediaHandle: try payload.mediaHandle(operation: operation),
                maxPixelEdge: Int(edge)
            )
        case "dismiss_capture_flow":
            try payload.requireKeys(["presentationRequestId"], operation: operation)
            let requestId = try payload.string("presentationRequestId", operation: operation)
            guard isRequestId(requestId) else {
                throw invalidPayload(
                    operation: operation,
                    field: "presentationRequestId",
                    reason: "invalid_format"
                )
            }
            return .dismissPresentation(presentationRequestId: requestId)
        default:
            throw invalidPayload(operation: "unknown_operation", field: "payload", reason: "invalid_enum")
        }
    }

    private static func result(
        requestId: String,
        resultType: String,
        payload: [String: Any]
    ) throws -> [String: Any] {
        guard isRequestId(requestId) else {
            throw wireEncodingFailure(operation: "unknown_operation")
        }
        return [
            "wireVersion": Int64(mediaCaptureWireVersion),
            "requestId": requestId,
            "resultType": resultType,
            "payload": payload,
        ]
    }

    private static func readyPayload(_ value: SessionReadySnapshot) throws -> [String: Any] {
        guard !value.availableCameras.isEmpty,
              value.availableCameras.count <= 2,
              value.availableCameras.contains(value.activeCamera),
              !value.supportedFlashModes.isEmpty,
              value.supportedFlashModes.count <= 4,
              value.minimumZoomFactor.isFinite,
              value.minimumZoomFactor >= 0.01,
              value.maximumZoomFactor.isFinite,
              value.maximumZoomFactor >= value.minimumZoomFactor
        else {
            throw wireEncodingFailure(operation: "unknown_operation")
        }
        return [
            "sessionHandle": try outputHandle(value.sessionHandle.rawValue),
            "activeCamera": value.activeCamera.rawValue,
            "availableCameras": value.availableCameras.map(\.rawValue),
            "switchCameraSupported": value.switchCameraSupported,
            "supportedFlashModes": value.supportedFlashModes.map(\.rawValue),
            "focusPointSupported": value.focusPointSupported,
            "minZoomFactor": value.minimumZoomFactor,
            "maxZoomFactor": value.maximumZoomFactor,
        ]
    }

    private static func mediaPayload(_ value: MediaMetadata) throws -> [String: Any] {
        guard value.pixelWidth > 0,
              value.pixelHeight > 0,
              value.byteLength > 0,
              [0, 90, 180, 270].contains(value.orientationDegrees),
              (value.mediaType == .photo && value.durationMilliseconds == nil) ||
              (value.mediaType == .video && value.durationMilliseconds.map { (1 ... 60_000).contains($0) } == true)
        else {
            throw wireEncodingFailure(operation: "unknown_operation")
        }
        return [
            "mediaHandle": try outputHandle(value.mediaHandle.rawValue),
            "mediaType": value.mediaType.rawValue,
            "pixelWidth": Int64(value.pixelWidth),
            "pixelHeight": Int64(value.pixelHeight),
            "durationMillis": value.durationMilliseconds.map { Int64($0) as Any } ?? NSNull(),
            "orientationDegrees": Int64(value.orientationDegrees),
            "byteLength": Int64(value.byteLength),
        ]
    }

    private static func eventEnvelope(type: String, payload: [String: Any]) -> [String: Any] {
        ["wireVersion": Int64(mediaCaptureWireVersion), "eventType": type, "payload": payload]
    }

    private static func failureEnvelope(type: String, payload: [String: Any]) -> [String: Any] {
        ["wireVersion": Int64(mediaCaptureWireVersion), "failureType": type, "payload": payload]
    }

    private static func epochMilliseconds(_ date: Date) throws -> Int64 {
        let milliseconds = date.timeIntervalSince1970 * 1_000
        guard milliseconds.isFinite,
              milliseconds >= 0,
              milliseconds <= Double(Int64.max)
        else {
            throw wireEncodingFailure(operation: "unknown_operation")
        }
        return Int64(milliseconds.rounded(.towardZero))
    }

    private static func outputHandle(_ value: String) throws -> String {
        guard isOpaqueHandle(value) else {
            throw wireEncodingFailure(operation: "unknown_operation")
        }
        return value
    }

    package static func requireCanonicalFileURI(_ value: String) throws {
        guard value.utf8.count <= 4_096,
              value.hasPrefix("file:///"),
              value.unicodeScalars.allSatisfy({ (0x21 ... 0x7e).contains($0.value) })
        else {
            throw wireEncodingFailure(operation: "materialize_media_resource")
        }
        let characters = Array(value.utf8)
        for index in characters.indices where characters[index] == 0x25 {
            guard index + 2 < characters.count,
                  isUpperHex(characters[index + 1]),
                  isUpperHex(characters[index + 2])
            else {
                throw wireEncodingFailure(operation: "materialize_media_resource")
            }
        }
        guard let components = URLComponents(string: value),
              components.scheme == "file",
              components.user == nil,
              components.password == nil,
              components.host == nil || components.host == "",
              components.port == nil,
              components.query == nil,
              components.fragment == nil,
              components.string == value
        else {
            throw wireEncodingFailure(operation: "materialize_media_resource")
        }
        let path = components.percentEncodedPath
        guard path.hasPrefix("/"), path.count > 1, !path.hasSuffix("/"),
              !String(path.dropFirst()).contains("//")
        else {
            throw wireEncodingFailure(operation: "materialize_media_resource")
        }
        for rawSegment in path.dropFirst().split(separator: "/", omittingEmptySubsequences: false) {
            let segment = String(rawSegment)
            guard !segment.isEmpty,
                  let decoded = segment.removingPercentEncoding,
                  !decoded.isEmpty,
                  decoded != ".", decoded != "..",
                  !decoded.contains("/"), !decoded.contains("\\"),
                  decoded.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7f })
            else {
                throw wireEncodingFailure(operation: "materialize_media_resource")
            }
        }
    }

    private static func isExportHandle(_ value: String) -> Bool {
        (22 ... 64).contains(value.utf8.count) && value.utf8.allSatisfy {
            ($0 >= 0x41 && $0 <= 0x5a) ||
                ($0 >= 0x61 && $0 <= 0x7a) ||
                ($0 >= 0x30 && $0 <= 0x39) ||
                $0 == 0x2d || $0 == 0x5f
        }
    }

    private static func isUpperHex(_ value: UInt8) -> Bool {
        (value >= 0x30 && value <= 0x39) || (value >= 0x41 && value <= 0x46)
    }

    private static func safeOperation(_ operation: String) -> String {
        methods.contains(operation) ? operation : "unknown_operation"
    }

    private static func isRequestId(_ value: String) -> Bool {
        isAsciiIdentifier(value, minimumLength: 1, maximumLength: 128)
    }

    package static func isOpaqueHandle(_ value: String) -> Bool {
        (1 ... 128).contains(value.utf8.count)
    }

    private static func isAsciiIdentifier(
        _ value: String,
        minimumLength: Int,
        maximumLength: Int
    ) -> Bool {
        let bytes = Array(value.utf8)
        guard (minimumLength ... maximumLength).contains(bytes.count) else { return false }
        return bytes.allSatisfy {
            (48 ... 57).contains($0) || (65 ... 90).contains($0) ||
                (97 ... 122).contains($0) || $0 == 45 || $0 == 95
        }
    }

    private static let allowedFields: Set<String> = [
        "wireVersion", "requestId", "payload", "enabledMediaTypes", "preferredCamera",
        "audioEnabled", "maxVideoDurationMillis", "sessionHandle", "flashMode",
        "normalizedX", "normalizedY", "zoomFactor", "mediaHandle", "maxPixelEdge",
        "presentationRequestId", "exportHandle", "unknown_field",
    ]

    private static let allowedReasons: Set<String> = [
        "missing_required_field", "unknown_field", "type_mismatch", "null_not_allowed",
        "non_finite", "out_of_range", "invalid_enum", "invalid_format", "integer_overflow",
        "result_type_mismatch", "native_value_unencodable",
    ]

    private static let lifecycleReasons: Set<String> = [
        "engine_detached", "activity_destroyed", "view_controller_destroyed", "adapter_disposed",
    ]

    private static let capacities: Set<String> = [
        "active_presentation", "active_exports", "active_export_bytes",
        "release_tombstones", "completed_request_tombstones", "pending_requests",
    ]

    private static let allowedFailures: [String: Set<MediaCaptureFailure.ID>] = [
        "start_session": [.invalidArgument, .unsupportedCapability, .sessionConflict],
        "take_photo": [
            .sessionInvalid, .invalidState, .invalidArgument, .storageFull, .encodingFailed,
            .unsupportedCapability, .systemInterrupted,
        ],
        "start_recording": [
            .sessionInvalid, .invalidState, .invalidArgument, .permissionDenied,
            .permissionRestricted, .permissionPermanentlyDenied, .resourceInUse, .storageFull,
            .encodingFailed, .unsupportedCapability, .systemInterrupted,
        ],
        "stop_recording": [
            .sessionInvalid, .invalidState, .invalidArgument, .encodingFailed, .systemInterrupted,
        ],
        "switch_camera": [
            .sessionInvalid, .invalidState, .invalidArgument, .resourceInUse,
            .unsupportedCapability, .systemInterrupted,
        ],
        "set_flash_mode": [
            .sessionInvalid, .invalidState, .invalidArgument, .unsupportedCapability,
            .systemInterrupted,
        ],
        "set_focus_point": [
            .sessionInvalid, .invalidState, .invalidArgument, .unsupportedCapability,
            .systemInterrupted,
        ],
        "set_zoom": [
            .sessionInvalid, .invalidState, .invalidArgument, .unsupportedCapability,
            .systemInterrupted,
        ],
        "retake": [.sessionInvalid, .mediaInvalid, .invalidState, .invalidArgument],
        "confirm": [.sessionInvalid, .mediaInvalid, .invalidState, .invalidArgument],
        "cancel": [.sessionInvalid, .invalidState, .invalidArgument],
        "release_media": [.mediaInvalid, .invalidState, .invalidArgument],
        "read_media_thumbnail": [
            .mediaInvalid, .invalidState, .invalidArgument, .thumbnailGenerationFailed,
            .thumbnailGenerationCancelled, .thumbnailOverloaded,
        ],
        "materialize_media_resource": [
            .mediaInvalid, .invalidState, .invalidArgument,
            .mediaExportConflict, .mediaExportOverloaded, .mediaExportTooLarge,
            .mediaExportSinkRejected, .mediaExportReadFailed, .mediaExportWriteFailed,
            .mediaExportCancelled, .mediaExportTimedOut,
        ],
        "present_capture_flow": [
            .permissionDenied, .permissionRestricted, .permissionPermanentlyDenied, .resourceInUse,
            .storageFull, .encodingFailed, .mediaInvalid, .sessionInvalid, .unsupportedCapability,
            .systemInterrupted, .sessionConflict, .invalidState, .invalidArgument, .sessionTimeout,
        ],
    ]
}

private struct WireObject {
    private let storage: [String: Any]

    init(_ value: Any?, operation: String, field: String) throws {
        guard let dictionary = value as? [AnyHashable: Any] else {
            throw MediaCaptureWireCodec.invalidPayload(
                operation: operation,
                field: field,
                reason: value == nil || value is NSNull ? "null_not_allowed" : "type_mismatch"
            )
        }
        var decoded: [String: Any] = [:]
        decoded.reserveCapacity(dictionary.count)
        for (key, item) in dictionary {
            guard let key = key as? String else {
                throw MediaCaptureWireCodec.invalidPayload(
                    operation: operation,
                    field: field,
                    reason: "type_mismatch"
                )
            }
            decoded[key] = item
        }
        storage = decoded
    }

    func requireKeys(_ expected: Set<String>, operation: String) throws {
        if let missing = expected.first(where: { storage[$0] == nil }) {
            throw MediaCaptureWireCodec.invalidPayload(
                operation: operation,
                field: missing,
                reason: "missing_required_field"
            )
        }
        if storage.keys.contains(where: { !expected.contains($0) }) {
            throw MediaCaptureWireCodec.invalidPayload(
                operation: operation,
                field: "unknown_field",
                reason: "unknown_field"
            )
        }
    }

    func value(_ key: String, operation: String) throws -> Any {
        guard let value = storage[key] else {
            throw MediaCaptureWireCodec.invalidPayload(
                operation: operation,
                field: key,
                reason: "missing_required_field"
            )
        }
        guard !(value is NSNull) else {
            throw MediaCaptureWireCodec.invalidPayload(
                operation: operation,
                field: key,
                reason: "null_not_allowed"
            )
        }
        return value
    }

    func string(_ key: String, operation: String) throws -> String {
        let value = try value(key, operation: operation)
        guard let string = value as? String else {
            throw MediaCaptureWireCodec.invalidPayload(
                operation: operation,
                field: key,
                reason: "type_mismatch"
            )
        }
        return string
    }

    func boolean(_ key: String, operation: String) throws -> Bool {
        let value = try value(key, operation: operation)
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID()
        else {
            throw MediaCaptureWireCodec.invalidPayload(
                operation: operation,
                field: key,
                reason: "type_mismatch"
            )
        }
        return number.boolValue
    }

    func integer(_ key: String, operation: String) throws -> Int64 {
        let value = try value(key, operation: operation)
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              !CFNumberIsFloatType(number)
        else {
            throw MediaCaptureWireCodec.invalidPayload(
                operation: operation,
                field: key,
                reason: "type_mismatch"
            )
        }
        return number.int64Value
    }

    func finiteDouble(
        _ key: String,
        operation: String,
        range: ClosedRange<Double>? = nil,
        minimum: Double? = nil
    ) throws -> Double {
        let value = try value(key, operation: operation)
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              CFNumberIsFloatType(number)
        else {
            throw MediaCaptureWireCodec.invalidPayload(
                operation: operation,
                field: key,
                reason: "type_mismatch"
            )
        }
        let result = number.doubleValue
        guard result.isFinite else {
            throw MediaCaptureWireCodec.invalidPayload(
                operation: operation,
                field: key,
                reason: "non_finite"
            )
        }
        guard range?.contains(result) != false, minimum.map({ result >= $0 }) != false else {
            throw MediaCaptureWireCodec.invalidPayload(
                operation: operation,
                field: key,
                reason: "out_of_range"
            )
        }
        return result
    }

    func enumValue(
        _ key: String,
        operation: String,
        allowed: Set<String>
    ) throws -> String {
        let result = try string(key, operation: operation)
        guard allowed.contains(result) else {
            throw MediaCaptureWireCodec.invalidPayload(
                operation: operation,
                field: key,
                reason: "invalid_enum"
            )
        }
        return result
    }

    func enumList(
        _ key: String,
        operation: String,
        allowed: Set<String>
    ) throws -> [String] {
        let value = try value(key, operation: operation)
        guard let list = value as? [Any],
              !list.isEmpty,
              list.count <= allowed.count
        else {
            throw MediaCaptureWireCodec.invalidPayload(
                operation: operation,
                field: key,
                reason: value is [Any] ? "out_of_range" : "type_mismatch"
            )
        }
        var result: [String] = []
        result.reserveCapacity(list.count)
        for item in list {
            guard let item = item as? String else {
                throw MediaCaptureWireCodec.invalidPayload(
                    operation: operation,
                    field: key,
                    reason: "type_mismatch"
                )
            }
            guard allowed.contains(item) else {
                throw MediaCaptureWireCodec.invalidPayload(
                    operation: operation,
                    field: key,
                    reason: "invalid_enum"
                )
            }
            result.append(item)
        }
        guard Set(result).count == result.count else {
            throw MediaCaptureWireCodec.invalidPayload(
                operation: operation,
                field: key,
                reason: "invalid_format"
            )
        }
        return result
    }

    func sessionHandle(operation: String) throws -> SessionHandle {
        let rawValue = try string("sessionHandle", operation: operation)
        do {
            return try SessionHandle(rawValue: rawValue)
        } catch {
            throw MediaCaptureWireCodec.invalidPayload(
                operation: operation,
                field: "sessionHandle",
                reason: "out_of_range"
            )
        }
    }

    func mediaHandle(operation: String) throws -> MediaHandle {
        let rawValue = try string("mediaHandle", operation: operation)
        do {
            return try MediaHandle(rawValue: rawValue)
        } catch {
            throw MediaCaptureWireCodec.invalidPayload(
                operation: operation,
                field: "mediaHandle",
                reason: "out_of_range"
            )
        }
    }
}

private enum SanitizedJpegValidator {
    static func isValid(_ data: Data, expectedWidth: Int, expectedHeight: Int) -> Bool {
        var bytes = [UInt8](data)
        defer {
            for index in bytes.indices {
                bytes[index] = 0
            }
        }
        guard bytes.count >= 4, bytes[0] == 0xff, bytes[1] == 0xd8 else { return false }
        var offset = 2
        var sawJfif = false
        var sawFrame = false
        var sawScan = false
        var markerIndex = 0
        while offset < bytes.count {
            guard bytes[offset] == 0xff else { return false }
            while offset < bytes.count, bytes[offset] == 0xff { offset += 1 }
            guard offset < bytes.count else { return false }
            let marker = Int(bytes[offset])
            offset += 1
            if marker == 0xd9 {
                return sawJfif && sawFrame && sawScan && offset == bytes.count
            }
            guard marker != 0x00,
                  marker != 0xd8,
                  !(0xd0 ... 0xd7).contains(marker),
                  offset + 2 <= bytes.count
            else { return false }
            let segmentLength = (Int(bytes[offset]) << 8) | Int(bytes[offset + 1])
            guard segmentLength >= 2, offset + segmentLength <= bytes.count else { return false }
            let start = offset + 2
            let end = offset + segmentLength
            if marker == 0xe0 {
                guard markerIndex == 0,
                      !sawJfif,
                      !sawFrame,
                      !sawScan,
                      isJfif(bytes, start: start, end: end)
                else { return false }
                sawJfif = true
            } else if (0xe1 ... 0xef).contains(marker) || marker == 0xfe {
                return false
            } else if !allowedMarkers.contains(marker) {
                return false
            }
            if frameMarkers.contains(marker) {
                guard !sawFrame,
                      !sawScan,
                      end - start >= 6,
                      bytes[start] == 8
                else { return false }
                let height = (Int(bytes[start + 1]) << 8) | Int(bytes[start + 2])
                let width = (Int(bytes[start + 3]) << 8) | Int(bytes[start + 4])
                let components = Int(bytes[start + 5])
                guard (1 ... 4).contains(components),
                      end - start == 6 + (3 * components),
                      width == expectedWidth,
                      height == expectedHeight
                else { return false }
                sawFrame = true
            }
            markerIndex += 1
            offset = end
            if marker == 0xda {
                guard sawFrame, end - start >= 4 else { return false }
                let components = Int(bytes[start])
                guard (1 ... 4).contains(components), end - start == 4 + (2 * components) else {
                    return false
                }
                sawScan = true
                while offset < bytes.count {
                    if bytes[offset] != 0xff {
                        offset += 1
                        continue
                    }
                    let markerStart = offset
                    while offset < bytes.count, bytes[offset] == 0xff { offset += 1 }
                    guard offset < bytes.count else { return false }
                    let scanMarker = Int(bytes[offset])
                    if scanMarker == 0x00 || (0xd0 ... 0xd7).contains(scanMarker) {
                        offset += 1
                    } else {
                        offset = markerStart
                        break
                    }
                }
            }
        }
        return false
    }

    private static func isJfif(_ bytes: [UInt8], start: Int, end: Int) -> Bool {
        let signature: [UInt8] = [0x4a, 0x46, 0x49, 0x46, 0x00]
        guard end - start == 14,
              Array(bytes[start ..< start + signature.count]) == signature,
              bytes[start + 5] == 1,
              bytes[start + 6] <= 2,
              bytes[start + 7] <= 2,
              ((Int(bytes[start + 8]) << 8) | Int(bytes[start + 9])) > 0,
              ((Int(bytes[start + 10]) << 8) | Int(bytes[start + 11])) > 0,
              bytes[start + 12] == 0,
              bytes[start + 13] == 0
        else { return false }
        return true
    }

    private static let frameMarkers: Set<Int> = [
        0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd,
        0xce, 0xcf,
    ]
    private static let allowedMarkers = frameMarkers.union([
        0xc4, 0xcc, 0xda, 0xdb, 0xdc, 0xdd, 0xde, 0xdf,
    ])
}
