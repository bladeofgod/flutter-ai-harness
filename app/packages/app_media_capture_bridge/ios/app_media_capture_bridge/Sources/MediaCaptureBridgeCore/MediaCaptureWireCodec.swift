import CoreFoundation
import Foundation
import MediaCapture

package enum MediaCaptureWireCodec {
    private static let generatedFieldsById = Dictionary(
        uniqueKeysWithValues: generatedMediaCaptureWireFields.map { ($0.id, $0) }
    )
    private static let generatedPayloadsById = Dictionary(
        uniqueKeysWithValues: generatedPayloadDescriptors.map { ($0.id, $0) }
    )
    package static let methods = Set(GeneratedMediaCaptureWireMethod.allCases.map(\.rawValue))
    static let generatedPayloadDescriptorCoverage: Set<String> = Set(
        GeneratedMediaCaptureWireMethod.allCases.map(requestPayloadId)
            + GeneratedMediaCaptureWireResult.allCases.map(resultPayloadId)
            + GeneratedMediaCaptureWireEvent.allCases.map(eventPayloadId)
            + ["session_timeout_failure_payload"]
    )

    package static func decodeRequest(
        operation: String,
        arguments: Any?
    ) throws -> MediaCaptureWireRequest {
        guard GeneratedMediaCaptureWireMethod(rawValue: operation) != nil else {
            throw invalidPayload(operation: "unknown_operation", field: "payload", reason: "invalid_enum")
        }
        let envelope = try WireObject(arguments, operation: operation, field: "payload")
        try requireGeneratedEnvelope(
            envelope,
            id: "/lifecycle/requestEnvelope",
            operation: operation
        )
        let version = try envelope.integer("wireVersion", operation: operation)
        guard version == Int64(mediaCaptureWireVersion) else {
            throw MediaCaptureWireFailure(
                code: GeneratedMediaCaptureWireError.incompatibleWireVersion.rawValue,
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
        try requireGeneratedEnvelope(
            envelope,
            id: "/lifecycle/eventListenEnvelope",
            operation: "unknown_operation"
        )
        let version = try envelope.integer("wireVersion", operation: "unknown_operation")
        guard version == Int64(mediaCaptureWireVersion) else {
            throw MediaCaptureWireFailure(
                code: GeneratedMediaCaptureWireError.incompatibleWireVersion.rawValue,
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
            resultType: .sessionCreated,
            payload: ["sessionHandle": outputHandle(handle.rawValue)]
        )
    }

    package static func controlApplied(
        requestId: String,
        handle: SessionHandle
    ) throws -> [String: Any] {
        try result(
            requestId: requestId,
            resultType: .controlApplied,
            payload: ["sessionHandle": outputHandle(handle.rawValue)]
        )
    }

    package static func recordingStarted(
        requestId: String,
        value: MediaCaptureRecordingValue
    ) throws -> [String: Any] {
        try result(
            requestId: requestId,
            resultType: .recordingStarted,
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
            resultType: .mediaPreview,
            payload: try mediaPayload(metadata)
        )
    }

    package static func retakeReady(
        requestId: String,
        handle: SessionHandle
    ) throws -> [String: Any] {
        try result(
            requestId: requestId,
            resultType: .retakeReady,
            payload: ["sessionHandle": outputHandle(handle.rawValue)]
        )
    }

    package static func confirmedMedia(
        requestId: String,
        value: MediaCaptureConfirmedValue
    ) throws -> [String: Any] {
        try confirmedMedia(requestId: requestId, value: value, resultType: .confirmedMedia)
    }

    package static func captureFlowConfirmed(
        requestId: String,
        value: MediaCaptureConfirmedValue
    ) throws -> [String: Any] {
        try confirmedMedia(requestId: requestId, value: value, resultType: .captureFlowConfirmed)
    }

    private static func confirmedMedia(
        requestId: String,
        value: MediaCaptureConfirmedValue,
        resultType: GeneratedMediaCaptureWireResult
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
            resultType: .sessionCancelled,
            payload: ["sessionHandle": outputHandle(handle.rawValue)]
        )
    }

    package static func mediaReleased(
        requestId: String,
        handle: MediaHandle
    ) throws -> [String: Any] {
        try result(
            requestId: requestId,
            resultType: .mediaReleased,
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
            resultType: .materializedMediaResource,
            payload: [
                "exportHandle": exportHandle,
                "fileUri": fileURI,
                "mediaType": wireMediaType(metadata.mediaType),
                "contentType": metadata.mediaType == .photo ? "image/jpeg" : "video/mp4",
                "byteLength": Int64(metadata.byteLength),
                "durationMillis": metadata.durationMilliseconds.map { Int64($0) as Any } ?? NSNull(),
                "expiresAt": expiresAtEpochMilliseconds,
            ]
        )
    }

    package static func materializedMediaReleased(requestId: String) throws -> [String: Any] {
        try result(requestId: requestId, resultType: .materializedMediaReleased, payload: [:])
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
            resultType: .mediaThumbnail,
            payload: [
                "mediaHandle": try outputHandle(encoded.mediaHandle.rawValue),
                "thumbnailCopy": encoded.bytes,
                "thumbnailByteLength": Int64(encoded.byteLength),
                "thumbnailPixelWidth": Int64(encoded.pixelWidth),
                "thumbnailPixelHeight": Int64(encoded.pixelHeight),
                "thumbnailContentType": encoded.contentType,
                "thumbnailOrientationDegrees": Int64(encoded.orientationDegrees),
                "mediaType": wireMediaType(encoded.mediaType),
                "posterFrameMillis": encoded.posterFrameMilliseconds.map { Int64($0) as Any } ?? NSNull(),
            ]
        )
    }

    package static func captureFlowCancelled(requestId: String) throws -> [String: Any] {
        try result(requestId: requestId, resultType: .captureFlowCancelled, payload: [:])
    }

    package static func captureFlowDismissed(requestId: String) throws -> [String: Any] {
        try result(requestId: requestId, resultType: .captureFlowDismissed, payload: [:])
    }

    package static func event(_ event: MediaCaptureEvent) throws -> [String: Any]? {
        switch event {
        case let .sessionReady(snapshot):
            return try eventEnvelope(type: .sessionReady, payload: readyPayload(snapshot))
        case let .sessionFailed(sessionHandle, failure):
            if failure.id == .sessionTimeout {
                return try failureEnvelope(
                    type: .sessionTimeout,
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
            return try eventEnvelope(
                type: .sessionFailed,
                payload: [
                    "sessionHandle": try outputHandle(sessionHandle.rawValue),
                    "terminalFailureId": try wireCapabilityFailureId(failure.id),
                ]
            )
        case let .mediaPreviewReady(sessionHandle, metadata):
            var payload = try mediaPayload(metadata)
            payload["sessionHandle"] = try outputHandle(sessionHandle.rawValue)
            return try eventEnvelope(type: .mediaPreviewReady, payload: payload)
        case let .mediaLeaseExpired(handle):
            return try eventEnvelope(
                type: .mediaLeaseExpired,
                payload: ["mediaHandle": try outputHandle(handle.rawValue)]
            )
        case let .mediaReadRevoked(handle):
            return try eventEnvelope(
                type: .mediaReadRevoked,
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
        let failureId: String
        do {
            failureId = try wireCapabilityFailureId(failure.id)
        } catch {
            return wireEncodingFailure(operation: operation)
        }
        return MediaCaptureWireFailure(
            code: failureId,
            details: [
                "operation": safeOperation(operation),
                "capabilityFailureId": failureId,
            ]
        )
    }

    package static func invalidPayload(
        operation: String,
        field: String,
        reason: String
    ) -> MediaCaptureWireFailure {
        MediaCaptureWireFailure(
            code: GeneratedMediaCaptureWireError.invalidWirePayload.rawValue,
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
            code: GeneratedMediaCaptureWireError.bridgeUnavailable.rawValue,
            details: ["operation": safeOperation(operation), "lifecycleReason": safeReason]
        )
    }

    package static func bridgeOverloaded(
        operation: String,
        capacity: String
    ) -> MediaCaptureWireFailure {
        let safeCapacity = capacities.contains(capacity) ? capacity : "pending_requests"
        return MediaCaptureWireFailure(
            code: GeneratedMediaCaptureWireError.bridgeOverloaded.rawValue,
            details: ["operation": safeOperation(operation), "capacity": safeCapacity]
        )
    }

    package static func duplicateRequest(operation: String) -> MediaCaptureWireFailure {
        MediaCaptureWireFailure(
            code: GeneratedMediaCaptureWireError.duplicateRequest.rawValue,
            details: ["operation": safeOperation(operation)]
        )
    }

    package static func listenerAlreadyActive() -> MediaCaptureWireFailure {
        MediaCaptureWireFailure(
            code: GeneratedMediaCaptureWireError.listenerAlreadyActive.rawValue,
            details: [:]
        )
    }

    package static func presentationConflict() -> MediaCaptureWireFailure {
        MediaCaptureWireFailure(
            code: GeneratedMediaCaptureWireError.presentationConflict.rawValue,
            details: [
                "operation": GeneratedMediaCaptureWireMethod.presentCaptureFlow.rawValue,
                "capacity": "active_presentation",
            ]
        )
    }

    package static func wireEncodingFailure(operation: String) -> MediaCaptureWireFailure {
        MediaCaptureWireFailure(
            code: GeneratedMediaCaptureWireError.wireEncodingFailed.rawValue,
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
            code: GeneratedMediaCaptureWireError.transferStoreOverloaded.rawValue,
            details: ["operation": safeOperation(operation), "capacity": capacity]
        )
    }

    package static func transferStoreUnavailable(operation: String) -> MediaCaptureWireFailure {
        MediaCaptureWireFailure(
            code: GeneratedMediaCaptureWireError.transferStoreUnavailable.rawValue,
            details: [
                "operation": safeOperation(operation),
                "lifecycleReason": "adapter_disposed",
            ]
        )
    }

    package static func materializedMediaInvalid() -> MediaCaptureWireFailure {
        MediaCaptureWireFailure(
            code: GeneratedMediaCaptureWireError.materializedMediaInvalid.rawValue,
            details: ["operation": GeneratedMediaCaptureWireMethod.releaseMaterializedMedia.rawValue]
        )
    }

    private static func decodePayload(
        operation: String,
        payload: WireObject
    ) throws -> MediaCaptureWirePayload {
        guard let method = GeneratedMediaCaptureWireMethod(rawValue: operation) else {
            throw invalidPayload(operation: "unknown_operation", field: "payload", reason: "invalid_enum")
        }
        try requireGeneratedPayload(
            payload,
            id: requestPayloadId(method),
            operation: operation
        )
        switch method {
        case .startSession, .presentCaptureFlow:
            let mediaTypeValues = try payload.enumList(
                "enabledMediaTypes",
                operation: operation,
                allowed: generatedField("enabled_media_types").enumValues
            )
            let preferredCamera = try payload.enumValue(
                "preferredCamera",
                operation: operation,
                allowed: generatedField("preferred_camera").enumValues
            )
            let duration = try payload.integer("maxVideoDurationMillis", operation: operation)
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
        case .takePhoto, .startRecording, .stopRecording, .switchCamera, .cancel:
            return .sessionAction(try payload.sessionHandle(operation: operation))
        case .setFlashMode:
            let value = try payload.enumValue(
                "flashMode",
                operation: operation,
                allowed: generatedField("flash_mode").enumValues
            )
            guard let mode = FlashMode(rawValue: value) else {
                throw invalidPayload(operation: operation, field: "flashMode", reason: "invalid_enum")
            }
            return .flash(sessionHandle: try payload.sessionHandle(operation: operation), mode: mode)
        case .setFocusPoint:
            return .focus(
                sessionHandle: try payload.sessionHandle(operation: operation),
                normalizedX: try payload.finiteDouble("normalizedX", operation: operation),
                normalizedY: try payload.finiteDouble("normalizedY", operation: operation)
            )
        case .setZoom:
            let factor = try payload.finiteDouble("zoomFactor", operation: operation)
            return .zoom(sessionHandle: try payload.sessionHandle(operation: operation), factor: factor)
        case .retake, .confirm, .releaseMedia:
            return .mediaAction(try payload.mediaHandle(operation: operation))
        case .materializeMediaResource:
            return .materialize(try payload.mediaHandle(operation: operation))
        case .releaseMaterializedMedia:
            let exportHandle = try payload.string("exportHandle", operation: operation)
            guard isExportHandle(exportHandle) else {
                throw invalidPayload(
                    operation: operation,
                    field: "exportHandle",
                    reason: "invalid_format"
                )
            }
            return .releaseMaterialized(exportHandle: exportHandle)
        case .readMediaThumbnail:
            let edge = try payload.integer("maxPixelEdge", operation: operation)
            return .thumbnail(
                mediaHandle: try payload.mediaHandle(operation: operation),
                maxPixelEdge: Int(edge)
            )
        case .dismissCaptureFlow:
            let requestId = try payload.string("presentationRequestId", operation: operation)
            guard isRequestId(requestId) else {
                throw invalidPayload(
                    operation: operation,
                    field: "presentationRequestId",
                    reason: "invalid_format"
                )
            }
            return .dismissPresentation(presentationRequestId: requestId)
        }
    }

    private static func result(
        requestId: String,
        resultType: GeneratedMediaCaptureWireResult,
        payload: [String: Any]
    ) throws -> [String: Any] {
        guard isRequestId(requestId) else {
            throw wireEncodingFailure(operation: "unknown_operation")
        }
        try requireGeneratedOutputPayload(id: resultPayloadId(resultType), value: payload)
        let envelope: [String: Any] = [
            "wireVersion": Int64(mediaCaptureWireVersion),
            "requestId": requestId,
            "resultType": resultType.rawValue,
            "payload": payload,
        ]
        requireGeneratedOutputEnvelope(envelope, id: "/lifecycle/resultEnvelope")
        return envelope
    }

    private static func requestPayloadId(_ method: GeneratedMediaCaptureWireMethod) -> String {
        switch method {
        case .startSession, .presentCaptureFlow:
            return "start_session_request_payload"
        case .takePhoto, .startRecording, .stopRecording, .switchCamera, .cancel:
            return "session_action_request_payload"
        case .setFlashMode:
            return "flash_mode_request_payload"
        case .setFocusPoint:
            return "focus_point_request_payload"
        case .setZoom:
            return "zoom_request_payload"
        case .retake, .confirm, .releaseMedia:
            return "media_handle_request_payload"
        case .readMediaThumbnail:
            return "media_thumbnail_request_payload"
        case .materializeMediaResource:
            return "materialize_media_resource_request_payload"
        case .releaseMaterializedMedia:
            return "release_materialized_media_request_payload"
        case .dismissCaptureFlow:
            return "dismiss_capture_flow_request_payload"
        }
    }

    private static func resultPayloadId(_ result: GeneratedMediaCaptureWireResult) -> String {
        switch result {
        case .sessionCreated:
            return "session_created_result_payload"
        case .controlApplied:
            return "control_applied_result_payload"
        case .recordingStarted:
            return "recording_started_result_payload"
        case .mediaPreview:
            return "media_preview_result_payload"
        case .retakeReady:
            return "retake_ready_result_payload"
        case .confirmedMedia, .captureFlowConfirmed:
            return "confirmed_media_result_payload"
        case .sessionCancelled:
            return "session_cancelled_result_payload"
        case .mediaReleased:
            return "media_released_result_payload"
        case .mediaThumbnail:
            return "media_thumbnail_result_payload"
        case .materializedMediaResource:
            return "materialized_media_result_payload"
        case .materializedMediaReleased:
            return "materialized_media_released_result_payload"
        case .captureFlowDismissed, .captureFlowCancelled:
            return "capture_flow_dismissed_result_payload"
        }
    }

    private static func eventPayloadId(_ event: GeneratedMediaCaptureWireEvent) -> String {
        switch event {
        case .sessionReady:
            return "session_ready_event_payload"
        case .sessionFailed:
            return "session_failed_event_payload"
        case .mediaPreviewReady:
            return "media_preview_ready_event_payload"
        case .mediaLeaseExpired:
            return "media_lease_expired_event_payload"
        case .mediaReadRevoked:
            return "media_read_revoked_event_payload"
        }
    }

    private static func generatedField(_ id: String) -> GeneratedWireFieldDescriptor {
        guard let field = generatedFieldsById[id] else {
            preconditionFailure("Generated Media Capture Wire field is missing")
        }
        return field
    }

    private static func requireGeneratedEnvelope(
        _ value: WireObject,
        id: String,
        operation: String
    ) throws {
        precondition(generatedEnvelopeUnknownFieldPolicies[id] == "reject")
        guard let keys = generatedEnvelopeRequiredKeys[id] else {
            preconditionFailure("Generated Media Capture Wire envelope is missing")
        }
        try value.requireKeys(keys, operation: operation)
    }

    private static func requireGeneratedPayload(
        _ value: WireObject,
        id: String,
        operation: String
    ) throws {
        guard let payload = generatedPayloadsById[id] else {
            preconditionFailure("Generated Media Capture Wire payload is missing")
        }
        precondition(payload.unknownFieldPolicy == "reject")
        let fields = payload.fieldIds.map(generatedField)
        let allowedKeys = Set(fields.map(\.key))
        if let missing = fields.first(where: { $0.required && !value.contains($0.key) }) {
            throw invalidPayload(
                operation: operation,
                field: missing.key,
                reason: "missing_required_field"
            )
        }
        if value.keys.contains(where: { !allowedKeys.contains($0) }) {
            throw invalidPayload(operation: operation, field: "unknown_field", reason: "unknown_field")
        }
        for field in fields where value.contains(field.key) {
            let fieldValue = value.rawValue(field.key)
            guard generatedMatchesWireFieldPrimitive(fieldValue, field: field) else {
                throw invalidPayload(
                    operation: operation,
                    field: field.key,
                    reason: primitiveFailureReason(fieldValue, field: field)
                )
            }
        }
    }

    private static func primitiveFailureReason(
        _ value: Any?,
        field: GeneratedWireFieldDescriptor
    ) -> String {
        guard let value, !(value is NSNull) else { return "null_not_allowed" }
        let typeMatches: Bool
        switch field.type {
        case "bool":
            typeMatches = generatedIsWireBoolean(value)
        case "bytes":
            typeMatches = value is Data
        case "double":
            typeMatches = generatedWireDouble(value) != nil
        case "int":
            typeMatches = generatedWireInteger(value) != nil
        case "string":
            typeMatches = value is String
        case "list_string":
            typeMatches = (value as? [Any])?.allSatisfy { $0 is String } == true
        default:
            typeMatches = false
        }
        guard typeMatches else { return "type_mismatch" }
        if let number = generatedWireDouble(value), field.finite, !number.isFinite {
            return "non_finite"
        }
        if let string = value as? String,
           !field.enumValues.isEmpty,
           !field.enumValues.contains(string) {
            return "invalid_enum"
        }
        if let values = value as? [String], !field.enumValues.isEmpty {
            if !values.allSatisfy(field.enumValues.contains) { return "invalid_enum" }
            if Set(values).count != values.count { return "invalid_format" }
        }
        return "out_of_range"
    }

    private static func requireGeneratedOutputEnvelope(_ value: [String: Any], id: String) {
        precondition(generatedEnvelopeUnknownFieldPolicies[id] == "reject")
        guard let keys = generatedEnvelopeRequiredKeys[id] else {
            preconditionFailure("Generated Media Capture Wire envelope is missing")
        }
        precondition(generatedHasExactWireKeys(value, requiredKeys: keys))
    }

    private static func requireGeneratedOutputPayload(
        id: String,
        value: [String: Any]
    ) throws {
        guard let payload = generatedPayloadsById[id] else {
            preconditionFailure("Generated Media Capture Wire payload is missing")
        }
        precondition(payload.unknownFieldPolicy == "reject")
        let fields = payload.fieldIds.map(generatedField)
        let allowedKeys = Set(fields.map(\.key))
        guard value.keys.allSatisfy(allowedKeys.contains),
              fields.allSatisfy({ !$0.required || value[$0.key] != nil }),
              try fields.filter({ value[$0.key] != nil }).allSatisfy({ field in
                  try matchesGeneratedOutputPrimitive(value[field.key], field: field)
              })
        else {
            throw wireEncodingFailure(operation: "unknown_operation")
        }
    }

    private static func matchesGeneratedOutputPrimitive(
        _ value: Any?,
        field: GeneratedWireFieldDescriptor
    ) throws -> Bool {
        if value is NSNull {
            return generatedMatchesWireFieldPrimitive(nil, field: field)
        }
        if let bytes = value as? MediaCaptureWireBytes {
            var copy = bytes.copyData()
            defer {
                copy.resetBytes(in: 0 ..< copy.count)
                copy.removeAll(keepingCapacity: false)
            }
            return generatedMatchesWireFieldPrimitive(copy, field: field)
        }
        return generatedMatchesWireFieldPrimitive(value, field: field)
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
            "activeCamera": wireCamera(value.activeCamera),
            "availableCameras": value.availableCameras.map(wireCamera),
            "switchCameraSupported": value.switchCameraSupported,
            "supportedFlashModes": value.supportedFlashModes.map(wireFlashMode),
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
            "mediaType": wireMediaType(value.mediaType),
            "pixelWidth": Int64(value.pixelWidth),
            "pixelHeight": Int64(value.pixelHeight),
            "durationMillis": value.durationMilliseconds.map { Int64($0) as Any } ?? NSNull(),
            "orientationDegrees": Int64(value.orientationDegrees),
            "byteLength": Int64(value.byteLength),
        ]
    }

    private static func eventEnvelope(
        type: GeneratedMediaCaptureWireEvent,
        payload: [String: Any]
    ) throws -> [String: Any] {
        try requireGeneratedOutputPayload(id: eventPayloadId(type), value: payload)
        let envelope: [String: Any] = [
            "wireVersion": Int64(mediaCaptureWireVersion),
            "eventType": type.rawValue,
            "payload": payload,
        ]
        requireGeneratedOutputEnvelope(envelope, id: "/lifecycle/eventEnvelope")
        return envelope
    }

    private static func failureEnvelope(
        type: GeneratedMediaCaptureWireFailure,
        payload: [String: Any]
    ) throws -> [String: Any] {
        try requireGeneratedOutputPayload(id: "session_timeout_failure_payload", value: payload)
        let envelope: [String: Any] = [
            "wireVersion": Int64(mediaCaptureWireVersion),
            "failureType": type.rawValue,
            "payload": payload,
        ]
        requireGeneratedOutputEnvelope(envelope, id: "/lifecycle/failureEnvelope")
        return envelope
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
        guard let lengths = generatedOpaqueHandleLengths["export_handle"] else {
            preconditionFailure("Generated export handle boundary is missing")
        }
        return lengths.contains(value.utf8.count) && value.utf8.allSatisfy {
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
        precondition(generatedRequestIdWireType == "string")
        precondition(generatedRequestIdFormat == "ascii_token")
        precondition(generatedRequestIdPattern == "^[A-Za-z0-9_-]{1,128}$")
        return isAsciiIdentifier(
            value,
            minimumLength: generatedRequestIdMinLength,
            maximumLength: generatedRequestIdMaxLength
        )
    }

    package static func isOpaqueHandle(_ value: String) -> Bool {
        guard let sessionLengths = generatedOpaqueHandleLengths["session_handle"],
              let mediaLengths = generatedOpaqueHandleLengths["media_handle"]
        else {
            preconditionFailure("Generated opaque handle boundary is missing")
        }
        precondition(sessionLengths == mediaLengths)
        return sessionLengths.contains(value.utf8.count)
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

    private static func generatedErrorDetailValues(_ key: String) -> Set<String> {
        guard let descriptor = generatedErrorDetailDescriptors.first(where: { $0.key == key }) else {
            preconditionFailure("Generated Media Capture Wire error detail is missing")
        }
        return descriptor.enumValues
    }

    private static func wireMediaType(_ value: MediaType) -> String {
        let wireValue: String
        switch value {
        case .photo:
            wireValue = "photo"
        case .video:
            wireValue = "video"
        }
        precondition(generatedField("media_type").enumValues.contains(wireValue))
        return wireValue
    }

    private static func wireCamera(_ value: CameraPosition) -> String {
        let wireValue: String
        switch value {
        case .rear:
            wireValue = "rear"
        case .front:
            wireValue = "front"
        }
        precondition(generatedField("active_camera").enumValues.contains(wireValue))
        return wireValue
    }

    private static func wireFlashMode(_ value: FlashMode) -> String {
        let wireValue: String
        switch value {
        case .off:
            wireValue = "off"
        case .on:
            wireValue = "on"
        case .auto:
            wireValue = "auto"
        case .torch:
            wireValue = "torch"
        }
        precondition(generatedField("flash_mode").enumValues.contains(wireValue))
        return wireValue
    }

    private static func wireCapabilityFailureId(_ value: MediaCaptureFailure.ID) throws -> String {
        guard let descriptor = generatedErrorDescriptors.first(where: {
            $0.source == "capability_failure" && $0.capabilityFailureId == value.rawValue
        }) else {
            throw wireEncodingFailure(operation: "unknown_operation")
        }
        precondition(descriptor.code == value.rawValue)
        return descriptor.code
    }

    private static let allowedFields = generatedErrorDetailValues("field")
    private static let allowedReasons = generatedErrorDetailValues("reason")
    private static let lifecycleReasons = generatedErrorDetailValues("lifecycleReason")
    private static let capacities = generatedErrorDetailValues("capacity")

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

    var keys: Dictionary<String, Any>.Keys { storage.keys }

    func contains(_ key: String) -> Bool { storage[key] != nil }

    func rawValue(_ key: String) -> Any? { storage[key] }

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
