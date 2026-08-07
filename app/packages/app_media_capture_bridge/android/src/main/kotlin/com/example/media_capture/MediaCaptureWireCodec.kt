package com.example.media_capture

import com.example.mediacapture.api.CameraPosition
import com.example.mediacapture.api.ConfirmedMedia
import com.example.mediacapture.api.FailureCode
import com.example.mediacapture.api.FlashMode
import com.example.mediacapture.api.MediaCaptureEvent
import com.example.mediacapture.api.MediaHandle
import com.example.mediacapture.api.MediaMetadata
import com.example.mediacapture.api.MediaPreview
import com.example.mediacapture.api.MediaThumbnail
import com.example.mediacapture.api.MediaType
import com.example.mediacapture.api.SessionHandle
import com.example.mediacapture.api.SessionOptions
import com.example.mediacapture.api.SessionReady
import java.io.ByteArrayOutputStream
import java.net.URI
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets

internal const val MEDIA_CAPTURE_WIRE_VERSION = generatedMediaCaptureWireVersion
internal const val MEDIA_CAPTURE_COMMANDS_CHANNEL = generatedCommandsChannel
internal const val MEDIA_CAPTURE_EVENTS_CHANNEL = generatedEventsChannel

internal sealed interface MediaCaptureWirePayload {
    data class StartSession(val options: SessionOptions) : MediaCaptureWirePayload

    data class SessionAction(val sessionHandle: SessionHandle) : MediaCaptureWirePayload

    data class Flash(
        val sessionHandle: SessionHandle,
        val flashMode: FlashMode,
    ) : MediaCaptureWirePayload

    data class Focus(
        val sessionHandle: SessionHandle,
        val normalizedX: Double,
        val normalizedY: Double,
    ) : MediaCaptureWirePayload

    data class Zoom(
        val sessionHandle: SessionHandle,
        val zoomFactor: Double,
    ) : MediaCaptureWirePayload

    data class MediaAction(val mediaHandle: MediaHandle) : MediaCaptureWirePayload

    data class Thumbnail(
        val mediaHandle: MediaHandle,
        val maxPixelEdge: Int,
    ) : MediaCaptureWirePayload

    data class Materialize(val mediaHandle: MediaHandle) : MediaCaptureWirePayload

    data class ReleaseMaterialized(val exportHandle: String) : MediaCaptureWirePayload

    data class DismissPresentation(val presentationRequestId: String) : MediaCaptureWirePayload
}

internal data class MediaCaptureWireRequest(
    val requestId: String,
    val operation: String,
    val payload: MediaCaptureWirePayload,
)

internal class MediaCaptureWireFailure(
    val code: String,
    val details: Map<String, Any?>,
) : Exception(code) {
    init {
        val descriptor = generatedErrorDescriptors.single { it.code == code }
        require(descriptor.messagePolicy == "static_redacted")
        require(details.keys.all { it in descriptor.detailsAllowedKeys })
    }
}

internal object MediaCaptureWireCodec {
    private val requestIdPattern = Regex(generatedRequestIdPattern)
    private val opaqueHandlePattern = Regex("^[A-Za-z0-9_-]+$")
    private val generatedFieldsById = generatedMediaCaptureWireFields.associateBy { it.id }
    private val generatedFieldsByKey = generatedMediaCaptureWireFields.associateBy { it.key }
    private val generatedPayloadsById = generatedPayloadDescriptors.associateBy { it.id }

    val methods: Set<String> =
        GeneratedMediaCaptureWireMethod.entries.mapTo(linkedSetOf()) { it.wireValue }

    fun decodeRequest(operation: String, arguments: Any?): MediaCaptureWireRequest {
        if (operation !in methods) {
            throw invalidPayload("unknown_operation", "payload", "invalid_enum")
        }
        val envelope = readMap(arguments, operation, "payload")
        requireGeneratedEnvelope(envelope, "/lifecycle/requestEnvelope", operation)
        val version = readInt(envelope, "wireVersion", operation)
        if (version != MEDIA_CAPTURE_WIRE_VERSION.toLong()) {
            throw MediaCaptureWireFailure(
                code = GeneratedMediaCaptureWireError.incompatibleWireVersion.wireValue,
                details =
                    mapOf(
                        "actualWireVersion" to version,
                        "expectedWireVersion" to MEDIA_CAPTURE_WIRE_VERSION,
                    ),
            )
        }
        val requestId = readString(envelope, "requestId", operation)
        if (!requestIdPattern.matches(requestId)) {
            throw invalidPayload(operation, "requestId", "invalid_format")
        }
        val payload = readMap(envelope["payload"], operation, "payload")
        return MediaCaptureWireRequest(
            requestId = requestId,
            operation = operation,
            payload = decodePayload(operation, payload),
        )
    }

    fun decodeListenArguments(arguments: Any?) {
        val envelope = readMap(arguments, "unknown_operation", "payload")
        requireGeneratedEnvelope(envelope, "/lifecycle/eventListenEnvelope", "unknown_operation")
        val version = readInt(envelope, "wireVersion", "unknown_operation")
        if (version != MEDIA_CAPTURE_WIRE_VERSION.toLong()) {
            throw MediaCaptureWireFailure(
                GeneratedMediaCaptureWireError.incompatibleWireVersion.wireValue,
                mapOf(
                    "actualWireVersion" to version,
                    "expectedWireVersion" to MEDIA_CAPTURE_WIRE_VERSION,
                ),
            )
        }
    }

    fun result(
        requestId: String,
        resultType: String,
        payload: Map<String, Any?>,
    ): Map<String, Any?> {
        requireRequestIdForOutput(requestId)
        requireGeneratedOutputPayload(resultPayloadId(resultType), payload)
        val envelope = mapOf(
            "wireVersion" to MEDIA_CAPTURE_WIRE_VERSION,
            "requestId" to requestId,
            "resultType" to resultType,
            "payload" to payload,
        )
        requireGeneratedOutputEnvelope(envelope, "/lifecycle/resultEnvelope")
        return envelope
    }

    fun sessionCreated(requestId: String, handle: SessionHandle): Map<String, Any?> =
        result(
            requestId,
            GeneratedMediaCaptureWireResult.sessionCreated.wireValue,
            mapOf("sessionHandle" to outputHandle(handle.value)),
        )

    fun controlApplied(requestId: String, handle: SessionHandle): Map<String, Any?> =
        result(
            requestId,
            GeneratedMediaCaptureWireResult.controlApplied.wireValue,
            mapOf("sessionHandle" to outputHandle(handle.value)),
        )

    fun recordingStarted(
        requestId: String,
        handle: SessionHandle,
        audioIncluded: Boolean,
    ): Map<String, Any?> =
        result(
            requestId,
            GeneratedMediaCaptureWireResult.recordingStarted.wireValue,
            mapOf("sessionHandle" to outputHandle(handle.value), "audioIncluded" to audioIncluded),
        )

    fun mediaPreview(requestId: String, preview: MediaPreview): Map<String, Any?> =
        result(
            requestId,
            GeneratedMediaCaptureWireResult.mediaPreview.wireValue,
            mediaPayload(preview.mediaHandle, preview.metadata),
        )

    fun retakeReady(requestId: String, handle: SessionHandle): Map<String, Any?> =
        result(
            requestId,
            GeneratedMediaCaptureWireResult.retakeReady.wireValue,
            mapOf("sessionHandle" to outputHandle(handle.value)),
        )

    fun confirmedMedia(requestId: String, media: ConfirmedMedia): Map<String, Any?> {
        return result(
            requestId,
            GeneratedMediaCaptureWireResult.confirmedMedia.wireValue,
            mediaPayload(media.mediaHandle, media.metadata) +
                ("leaseExpiresAt" to media.leaseExpiresAtEpochMillis),
        )
    }

    fun sessionCancelled(requestId: String, handle: SessionHandle): Map<String, Any?> =
        result(
            requestId,
            GeneratedMediaCaptureWireResult.sessionCancelled.wireValue,
            mapOf("sessionHandle" to outputHandle(handle.value)),
        )

    fun mediaReleased(requestId: String, handle: MediaHandle): Map<String, Any?> =
        result(
            requestId,
            GeneratedMediaCaptureWireResult.mediaReleased.wireValue,
            mapOf("mediaHandle" to outputHandle(handle.value)),
        )

    fun thumbnail(
        requestId: String,
        thumbnail: MediaThumbnail,
        maxPixelEdge: Int,
    ): Map<String, Any?> {
        validateThumbnail(thumbnail, maxPixelEdge)
        return result(
            requestId,
            GeneratedMediaCaptureWireResult.mediaThumbnail.wireValue,
            mapOf(
                "mediaHandle" to outputHandle(thumbnail.mediaHandle.value),
                "thumbnailCopy" to thumbnail.copy.copyOf(),
                "thumbnailByteLength" to thumbnail.byteLength,
                "thumbnailPixelWidth" to thumbnail.pixelWidth,
                "thumbnailPixelHeight" to thumbnail.pixelHeight,
                "thumbnailContentType" to "image/jpeg",
                "thumbnailOrientationDegrees" to 0,
                "mediaType" to thumbnail.mediaType.wireValue,
                "posterFrameMillis" to thumbnail.posterFrameMillis,
            ),
        )
    }

    fun materializedMedia(
        requestId: String,
        exportHandle: String,
        fileUri: String,
        metadata: MediaMetadata,
        expiresAtEpochMillis: Long,
    ): Map<String, Any?> {
        requireExportHandle(exportHandle)
        requireCanonicalFileUri(fileUri)
        require(metadata.byteLength in 1L..MAX_MATERIALIZED_BYTES)
        require(
            metadata.contentType ==
                if (metadata.mediaType == MediaType.PHOTO) "image/jpeg" else "video/mp4",
        )
        require(
            if (metadata.mediaType == MediaType.PHOTO) {
                metadata.durationMillis == null
            } else {
                metadata.durationMillis != null
            },
        )
        return result(
            requestId,
            GeneratedMediaCaptureWireResult.materializedMediaResource.wireValue,
            mapOf(
                "exportHandle" to exportHandle,
                "fileUri" to fileUri,
                "mediaType" to metadata.mediaType.wireValue,
                "contentType" to metadata.contentType,
                "byteLength" to metadata.byteLength,
                "durationMillis" to metadata.durationMillis,
                "expiresAt" to expiresAtEpochMillis,
            ),
        )
    }

    fun materializedMediaReleased(requestId: String): Map<String, Any?> =
        result(requestId, GeneratedMediaCaptureWireResult.materializedMediaReleased.wireValue, emptyMap())

    fun captureFlowDismissed(requestId: String): Map<String, Any?> =
        result(requestId, GeneratedMediaCaptureWireResult.captureFlowDismissed.wireValue, emptyMap())

    fun flowConfirmed(requestId: String, media: ConfirmedMedia): Map<String, Any?> {
        return result(
            requestId,
            GeneratedMediaCaptureWireResult.captureFlowConfirmed.wireValue,
            mediaPayload(media.mediaHandle, media.metadata) +
                ("leaseExpiresAt" to media.leaseExpiresAtEpochMillis),
        )
    }

    fun flowCancelled(requestId: String): Map<String, Any?> =
        result(requestId, GeneratedMediaCaptureWireResult.captureFlowCancelled.wireValue, emptyMap())

    fun event(event: MediaCaptureEvent): Map<String, Any?>? =
        when (event) {
            is MediaCaptureEvent.Ready ->
                eventEnvelope(
                    GeneratedMediaCaptureWireEvent.sessionReady.wireValue,
                    readyPayload(event.value),
                )
            is MediaCaptureEvent.SessionFailed -> {
                if (event.failure.code == FailureCode.SESSION_TIMEOUT) {
                    failureEnvelope(
                        GeneratedMediaCaptureWireFailure.sessionTimeout.wireValue,
                        mapOf("sessionHandle" to outputHandle(event.sessionHandle.value)),
                    )
                } else {
                    require(
                        event.failure.code in
                            setOf(
                                FailureCode.PERMISSION_DENIED,
                                FailureCode.PERMISSION_RESTRICTED,
                                FailureCode.PERMISSION_PERMANENTLY_DENIED,
                                FailureCode.RESOURCE_IN_USE,
                                FailureCode.STORAGE_FULL,
                                FailureCode.ENCODING_FAILED,
                                FailureCode.SYSTEM_INTERRUPTED,
                            ),
                    )
                    eventEnvelope(
                        GeneratedMediaCaptureWireEvent.sessionFailed.wireValue,
                        mapOf(
                            "sessionHandle" to outputHandle(event.sessionHandle.value),
                            "terminalFailureId" to event.failure.code.wireValue,
                        ),
                    )
                }
            }
            is MediaCaptureEvent.PreviewReady ->
                eventEnvelope(
                    GeneratedMediaCaptureWireEvent.mediaPreviewReady.wireValue,
                    mapOf("sessionHandle" to outputHandle(event.sessionHandle.value)) +
                        mediaPayload(event.preview.mediaHandle, event.preview.metadata),
                )
            is MediaCaptureEvent.LeaseExpired ->
                eventEnvelope(
                    GeneratedMediaCaptureWireEvent.mediaLeaseExpired.wireValue,
                    mapOf("mediaHandle" to outputHandle(event.mediaHandle.value)),
                )
            is MediaCaptureEvent.ReadRevoked ->
                eventEnvelope(
                    GeneratedMediaCaptureWireEvent.mediaReadRevoked.wireValue,
                    mapOf("mediaHandle" to outputHandle(event.mediaHandle.value)),
                )
            is MediaCaptureEvent.AttachmentRevoked -> null
        }

    fun invalidPayload(operation: String, field: String, reason: String): MediaCaptureWireFailure =
        MediaCaptureWireFailure(
            GeneratedMediaCaptureWireError.invalidWirePayload.wireValue,
            mapOf("operation" to safeOperation(operation), "field" to field, "reason" to reason),
        )

    fun bridgeUnavailable(operation: String, reason: String): MediaCaptureWireFailure =
        MediaCaptureWireFailure(
            GeneratedMediaCaptureWireError.bridgeUnavailable.wireValue,
            mapOf("operation" to safeOperation(operation), "lifecycleReason" to reason),
        )

    fun bridgeOverloaded(operation: String, capacity: String): MediaCaptureWireFailure =
        MediaCaptureWireFailure(
            GeneratedMediaCaptureWireError.bridgeOverloaded.wireValue,
            mapOf("operation" to safeOperation(operation), "capacity" to capacity),
        )

    fun duplicateRequest(operation: String): MediaCaptureWireFailure =
        MediaCaptureWireFailure(
            GeneratedMediaCaptureWireError.duplicateRequest.wireValue,
            mapOf("operation" to safeOperation(operation)),
        )

    fun listenerAlreadyActive(): MediaCaptureWireFailure =
        MediaCaptureWireFailure(
            GeneratedMediaCaptureWireError.listenerAlreadyActive.wireValue,
            emptyMap(),
        )

    fun presentationConflict(): MediaCaptureWireFailure =
        MediaCaptureWireFailure(
            GeneratedMediaCaptureWireError.presentationConflict.wireValue,
            mapOf(
                "operation" to GeneratedMediaCaptureWireMethod.presentCaptureFlow.wireValue,
                "capacity" to "active_presentation",
            ),
        )

    fun transferStoreOverloaded(operation: String, capacity: String): MediaCaptureWireFailure =
        MediaCaptureWireFailure(
            GeneratedMediaCaptureWireError.transferStoreOverloaded.wireValue,
            mapOf("operation" to safeOperation(operation), "capacity" to capacity),
        )

    fun transferStoreUnavailable(operation: String): MediaCaptureWireFailure =
        MediaCaptureWireFailure(
            GeneratedMediaCaptureWireError.transferStoreUnavailable.wireValue,
            mapOf("operation" to safeOperation(operation), "lifecycleReason" to "adapter_disposed"),
        )

    fun materializedMediaInvalid(): MediaCaptureWireFailure =
        MediaCaptureWireFailure(
            GeneratedMediaCaptureWireError.materializedMediaInvalid.wireValue,
            mapOf("operation" to GeneratedMediaCaptureWireMethod.releaseMaterializedMedia.wireValue),
        )

    fun capabilityFailure(operation: String, code: FailureCode): MediaCaptureWireFailure =
        MediaCaptureWireFailure(
            code.wireValue,
            mapOf(
                "operation" to safeOperation(operation),
                "capabilityFailureId" to code.wireValue,
            ),
        )

    fun wireEncodingFailure(operation: String): MediaCaptureWireFailure =
        MediaCaptureWireFailure(
            GeneratedMediaCaptureWireError.wireEncodingFailed.wireValue,
            mapOf(
                "operation" to safeOperation(operation),
                "field" to "unknown_field",
                "reason" to "native_value_unencodable",
            ),
        )

    private fun decodePayload(
        operation: String,
        payload: Map<String, Any?>,
    ): MediaCaptureWirePayload {
        requireGeneratedPayload(payload, requestPayloadId(operation), operation)
        return when (operation) {
            GeneratedMediaCaptureWireMethod.startSession.wireValue,
            GeneratedMediaCaptureWireMethod.presentCaptureFlow.wireValue,
            -> {
                val mediaTypes =
                    readEnumList(payload, "enabledMediaTypes", operation)
                        .mapTo(linkedSetOf(), ::mediaType)
                val preferred = camera(readEnum(payload, "preferredCamera", operation))
                val duration = readInt(payload, "maxVideoDurationMillis", operation)
                MediaCaptureWirePayload.StartSession(
                    SessionOptions(
                        enabledMediaTypes = mediaTypes,
                        preferredCamera = preferred,
                        audioEnabled = readBoolean(payload, "audioEnabled", operation),
                        maxVideoDurationMillis = duration,
                    ),
                )
            }
            GeneratedMediaCaptureWireMethod.takePhoto.wireValue,
            GeneratedMediaCaptureWireMethod.startRecording.wireValue,
            GeneratedMediaCaptureWireMethod.stopRecording.wireValue,
            GeneratedMediaCaptureWireMethod.switchCamera.wireValue,
            GeneratedMediaCaptureWireMethod.cancel.wireValue,
            -> {
                MediaCaptureWirePayload.SessionAction(sessionHandle(payload, operation))
            }
            GeneratedMediaCaptureWireMethod.setFlashMode.wireValue -> {
                MediaCaptureWirePayload.Flash(
                    sessionHandle(payload, operation),
                    flashMode(readEnum(payload, "flashMode", operation)),
                )
            }
            GeneratedMediaCaptureWireMethod.setFocusPoint.wireValue -> {
                MediaCaptureWirePayload.Focus(
                    sessionHandle(payload, operation),
                    readFiniteDouble(payload, "normalizedX", operation),
                    readFiniteDouble(payload, "normalizedY", operation),
                )
            }
            GeneratedMediaCaptureWireMethod.setZoom.wireValue -> {
                val zoom = readFiniteDouble(payload, "zoomFactor", operation)
                MediaCaptureWirePayload.Zoom(sessionHandle(payload, operation), zoom)
            }
            GeneratedMediaCaptureWireMethod.retake.wireValue,
            GeneratedMediaCaptureWireMethod.confirm.wireValue,
            GeneratedMediaCaptureWireMethod.releaseMedia.wireValue,
            -> {
                MediaCaptureWirePayload.MediaAction(mediaHandle(payload, operation))
            }
            GeneratedMediaCaptureWireMethod.readMediaThumbnail.wireValue -> {
                val maxPixelEdge = readInt(payload, "maxPixelEdge", operation)
                MediaCaptureWirePayload.Thumbnail(
                    mediaHandle(payload, operation),
                    maxPixelEdge.toInt(),
                )
            }
            GeneratedMediaCaptureWireMethod.materializeMediaResource.wireValue -> {
                MediaCaptureWirePayload.Materialize(mediaHandle(payload, operation))
            }
            GeneratedMediaCaptureWireMethod.releaseMaterializedMedia.wireValue -> {
                val handle = readString(payload, "exportHandle", operation)
                val length = checkNotNull(generatedOpaqueHandleLengths["export_handle"])
                if (!opaqueHandlePattern.matches(handle) || handle.length !in length) {
                    throw invalidPayload(operation, "exportHandle", "invalid_format")
                }
                MediaCaptureWirePayload.ReleaseMaterialized(handle)
            }
            GeneratedMediaCaptureWireMethod.dismissCaptureFlow.wireValue -> {
                val presentationRequestId = readString(payload, "presentationRequestId", operation)
                if (!requestIdPattern.matches(presentationRequestId)) {
                    throw invalidPayload(operation, "presentationRequestId", "invalid_format")
                }
                MediaCaptureWirePayload.DismissPresentation(presentationRequestId)
            }
            else -> throw invalidPayload("unknown_operation", "payload", "invalid_enum")
        }
    }

    private fun requestPayloadId(operation: String): String =
        when (operation) {
            GeneratedMediaCaptureWireMethod.startSession.wireValue,
            GeneratedMediaCaptureWireMethod.presentCaptureFlow.wireValue,
            -> "start_session_request_payload"
            GeneratedMediaCaptureWireMethod.takePhoto.wireValue,
            GeneratedMediaCaptureWireMethod.startRecording.wireValue,
            GeneratedMediaCaptureWireMethod.stopRecording.wireValue,
            GeneratedMediaCaptureWireMethod.switchCamera.wireValue,
            GeneratedMediaCaptureWireMethod.cancel.wireValue,
            -> "session_action_request_payload"
            GeneratedMediaCaptureWireMethod.setFlashMode.wireValue -> "flash_mode_request_payload"
            GeneratedMediaCaptureWireMethod.setFocusPoint.wireValue -> "focus_point_request_payload"
            GeneratedMediaCaptureWireMethod.setZoom.wireValue -> "zoom_request_payload"
            GeneratedMediaCaptureWireMethod.retake.wireValue,
            GeneratedMediaCaptureWireMethod.confirm.wireValue,
            GeneratedMediaCaptureWireMethod.releaseMedia.wireValue,
            -> "media_handle_request_payload"
            GeneratedMediaCaptureWireMethod.readMediaThumbnail.wireValue -> "media_thumbnail_request_payload"
            GeneratedMediaCaptureWireMethod.materializeMediaResource.wireValue ->
                "materialize_media_resource_request_payload"
            GeneratedMediaCaptureWireMethod.releaseMaterializedMedia.wireValue ->
                "release_materialized_media_request_payload"
            GeneratedMediaCaptureWireMethod.dismissCaptureFlow.wireValue ->
                "dismiss_capture_flow_request_payload"
            else -> error("Validated operation expected")
        }

    private fun resultPayloadId(resultType: String): String =
        when (resultType) {
            GeneratedMediaCaptureWireResult.sessionCreated.wireValue -> "session_created_result_payload"
            GeneratedMediaCaptureWireResult.controlApplied.wireValue -> "control_applied_result_payload"
            GeneratedMediaCaptureWireResult.recordingStarted.wireValue -> "recording_started_result_payload"
            GeneratedMediaCaptureWireResult.mediaPreview.wireValue -> "media_preview_result_payload"
            GeneratedMediaCaptureWireResult.retakeReady.wireValue -> "retake_ready_result_payload"
            GeneratedMediaCaptureWireResult.confirmedMedia.wireValue,
            GeneratedMediaCaptureWireResult.captureFlowConfirmed.wireValue,
            -> "confirmed_media_result_payload"
            GeneratedMediaCaptureWireResult.sessionCancelled.wireValue -> "session_cancelled_result_payload"
            GeneratedMediaCaptureWireResult.mediaReleased.wireValue -> "media_released_result_payload"
            GeneratedMediaCaptureWireResult.mediaThumbnail.wireValue -> "media_thumbnail_result_payload"
            GeneratedMediaCaptureWireResult.materializedMediaResource.wireValue -> "materialized_media_result_payload"
            GeneratedMediaCaptureWireResult.materializedMediaReleased.wireValue ->
                "materialized_media_released_result_payload"
            GeneratedMediaCaptureWireResult.captureFlowDismissed.wireValue,
            GeneratedMediaCaptureWireResult.captureFlowCancelled.wireValue,
            -> "capture_flow_dismissed_result_payload"
            else -> error("Generated result type expected")
        }

    private fun eventPayloadId(eventType: String): String =
        when (eventType) {
            GeneratedMediaCaptureWireEvent.sessionReady.wireValue -> "session_ready_event_payload"
            GeneratedMediaCaptureWireEvent.sessionFailed.wireValue -> "session_failed_event_payload"
            GeneratedMediaCaptureWireEvent.mediaPreviewReady.wireValue -> "media_preview_ready_event_payload"
            GeneratedMediaCaptureWireEvent.mediaLeaseExpired.wireValue -> "media_lease_expired_event_payload"
            GeneratedMediaCaptureWireEvent.mediaReadRevoked.wireValue -> "media_read_revoked_event_payload"
            else -> error("Generated event type expected")
        }

    private fun requireGeneratedEnvelope(
        value: Map<String, Any?>,
        id: String,
        operation: String,
    ) {
        check(generatedEnvelopeUnknownFieldPolicies[id] == "reject")
        requireKeys(value, checkNotNull(generatedEnvelopeRequiredKeys[id]), operation)
    }

    private fun requireGeneratedPayload(
        value: Map<String, Any?>,
        id: String,
        operation: String,
    ) {
        val payload = checkNotNull(generatedPayloadsById[id])
        check(payload.unknownFieldPolicy == "reject")
        val fields = payload.fieldIds.map { checkNotNull(generatedFieldsById[it]) }
        val allowedKeys = fields.mapTo(linkedSetOf()) { it.key }
        val missing = fields.firstOrNull { it.required && !value.containsKey(it.key) }
        if (missing != null) {
            throw invalidPayload(operation, missing.key, "missing_required_field")
        }
        val unknown = value.keys.firstOrNull { it !in allowedKeys }
        if (unknown != null) {
            throw invalidPayload(operation, "unknown_field", "unknown_field")
        }
        fields.filter { value.containsKey(it.key) }.forEach { field ->
            val fieldValue = value[field.key]
            if (!generatedMatchesWireFieldPrimitive(fieldValue, field)) {
                throw invalidPayload(operation, field.key, primitiveFailureReason(fieldValue, field))
            }
        }
    }

    private fun primitiveFailureReason(
        value: Any?,
        field: GeneratedWireFieldDescriptor,
    ): String {
        if (value == null) return "null_not_allowed"
        val typeMatches =
            when (field.type) {
                "bool" -> value is Boolean
                "bytes" -> value is ByteArray
                "double" -> value is Double
                "int" -> value is Int || value is Long
                "string" -> value is String
                "list_bool" -> value is List<*> && value.all { it is Boolean }
                "list_double" -> value is List<*> && value.all { it is Double }
                "list_int" -> value is List<*> && value.all { it is Int || it is Long }
                "list_string" -> value is List<*> && value.all { it is String }
                else -> false
            }
        if (!typeMatches) return "type_mismatch"
        if (value is Double && field.finite && !value.isFinite()) return "non_finite"
        if (value is List<*> && field.type == "list_double" && field.finite &&
            value.any { it is Double && !it.isFinite() }
        ) {
            return "non_finite"
        }
        if (value is String && field.enumValues.isNotEmpty() && value !in field.enumValues) {
            return "invalid_enum"
        }
        if (value is List<*> && field.type == "list_string" && field.enumValues.isNotEmpty()) {
            if (!value.all { it is String && it in field.enumValues }) return "invalid_enum"
            if (value.toSet().size != value.size) return "invalid_format"
        }
        return "out_of_range"
    }

    private fun requireGeneratedOutputEnvelope(value: Map<String, Any?>, id: String) {
        check(generatedEnvelopeUnknownFieldPolicies[id] == "reject")
        require(generatedHasExactWireKeys(value, checkNotNull(generatedEnvelopeRequiredKeys[id])))
    }

    private fun requireGeneratedOutputPayload(id: String, value: Map<String, Any?>) {
        val payload = checkNotNull(generatedPayloadsById[id])
        check(payload.unknownFieldPolicy == "reject")
        val fields = payload.fieldIds.map { checkNotNull(generatedFieldsById[it]) }
        val allowedKeys = fields.mapTo(linkedSetOf()) { it.key }
        require(value.keys.all { it in allowedKeys })
        require(fields.all { !it.required || value.containsKey(it.key) })
        require(
            fields.filter { value.containsKey(it.key) }
                .all { generatedMatchesWireFieldPrimitive(value[it.key], it) },
        )
    }

    private fun readyPayload(ready: SessionReady): Map<String, Any?> {
        require(ready.activeCamera in ready.availableCameras)
        require(ready.maxZoomFactor >= ready.minZoomFactor)
        return mapOf(
            "sessionHandle" to outputHandle(ready.sessionHandle.value),
            "activeCamera" to ready.activeCamera.wireValue,
            "availableCameras" to ready.availableCameras.map { it.wireValue },
            "switchCameraSupported" to ready.switchCameraSupported,
            "supportedFlashModes" to ready.supportedFlashModes.map { it.wireValue },
            "focusPointSupported" to ready.focusPointSupported,
            "minZoomFactor" to ready.minZoomFactor,
            "maxZoomFactor" to ready.maxZoomFactor,
        )
    }

    private fun mediaPayload(
        handle: MediaHandle,
        metadata: MediaMetadata,
    ): Map<String, Any?> {
        when (metadata.mediaType) {
            MediaType.PHOTO -> require(metadata.durationMillis == null)
            MediaType.VIDEO -> require(metadata.durationMillis != null)
        }
        return mapOf(
            "mediaHandle" to outputHandle(handle.value),
            "mediaType" to metadata.mediaType.wireValue,
            "pixelWidth" to metadata.pixelWidth,
            "pixelHeight" to metadata.pixelHeight,
            "durationMillis" to metadata.durationMillis,
            "orientationDegrees" to metadata.orientationDegrees,
            "byteLength" to metadata.byteLength,
        )
    }

    private fun validateThumbnail(thumbnail: MediaThumbnail, maxPixelEdge: Int) {
        require(thumbnail.byteLength == thumbnail.copy.size)
        require(thumbnail.pixelWidth <= maxPixelEdge && thumbnail.pixelHeight <= maxPixelEdge)
        when (thumbnail.mediaType) {
            MediaType.PHOTO -> require(thumbnail.posterFrameMillis == null)
            MediaType.VIDEO -> require(thumbnail.posterFrameMillis != null)
        }
        validateSanitizedJpeg(thumbnail.copy, thumbnail.pixelWidth, thumbnail.pixelHeight)
    }

    private fun validateSanitizedJpeg(bytes: ByteArray, expectedWidth: Int, expectedHeight: Int) {
        require(bytes.size >= 4 && bytes.u8(0) == 0xff && bytes.u8(1) == 0xd8)
        var offset = 2
        var markerIndex = 0
        var sawJfif = false
        var sawFrame = false
        var sawScan = false
        while (offset < bytes.size) {
            require(bytes.u8(offset) == 0xff)
            while (offset < bytes.size && bytes.u8(offset) == 0xff) offset += 1
            require(offset < bytes.size)
            val marker = bytes.u8(offset++)
            if (marker == 0xd9) {
                require(sawJfif && sawFrame && sawScan && offset == bytes.size)
                return
            }
            require(marker != 0x00 && marker != 0xd8 && marker !in 0xd0..0xd7)
            require(offset + 2 <= bytes.size)
            val segmentLength = (bytes.u8(offset) shl 8) or bytes.u8(offset + 1)
            require(segmentLength >= 2 && offset + segmentLength <= bytes.size)
            val start = offset + 2
            val end = offset + segmentLength
            when {
                marker == 0xe0 -> {
                    require(markerIndex == 0 && !sawJfif && !sawFrame && !sawScan)
                    validateJfif(bytes, start, end)
                    sawJfif = true
                }
                marker in 0xe1..0xef || marker == 0xfe -> error("JPEG metadata is not allowed")
                marker !in allowedJpegMarkers -> error("JPEG marker is not allowed")
            }
            if (marker in startOfFrameMarkers) {
                require(!sawFrame && !sawScan)
                val components = bytes.u8(start + 5)
                require(end - start == 6 + (3 * components) && components in 1..4)
                require(bytes.u8(start) == 8)
                val height = (bytes.u8(start + 1) shl 8) or bytes.u8(start + 2)
                val width = (bytes.u8(start + 3) shl 8) or bytes.u8(start + 4)
                require(width == expectedWidth && height == expectedHeight)
                sawFrame = true
            }
            markerIndex += 1
            offset = end
            if (marker == 0xda) {
                require(sawFrame)
                val components = bytes.u8(start)
                require(components in 1..4 && end - start == 4 + (2 * components))
                sawScan = true
                while (offset < bytes.size) {
                    if (bytes.u8(offset) != 0xff) {
                        offset += 1
                        continue
                    }
                    val markerStart = offset
                    while (offset < bytes.size && bytes.u8(offset) == 0xff) offset += 1
                    require(offset < bytes.size)
                    val scanMarker = bytes.u8(offset)
                    if (scanMarker == 0x00 || scanMarker in 0xd0..0xd7) {
                        offset += 1
                    } else {
                        offset = markerStart
                        break
                    }
                }
            }
        }
        error("JPEG end marker is missing")
    }

    private fun validateJfif(bytes: ByteArray, start: Int, end: Int) {
        val signature = byteArrayOf(0x4a, 0x46, 0x49, 0x46, 0x00)
        require(end - start == 14)
        require(signature.indices.all { index -> bytes.u8(start + index) == signature[index].toInt() })
        require(bytes.u8(start + 5) == 1 && bytes.u8(start + 6) <= 2)
        require(bytes.u8(start + 7) <= 2)
        require(((bytes.u8(start + 8) shl 8) or bytes.u8(start + 9)) > 0)
        require(((bytes.u8(start + 10) shl 8) or bytes.u8(start + 11)) > 0)
        require(bytes.u8(start + 12) == 0 && bytes.u8(start + 13) == 0)
    }

    private fun eventEnvelope(type: String, payload: Map<String, Any?>): Map<String, Any?> {
        requireGeneratedOutputPayload(eventPayloadId(type), payload)
        val envelope =
            mapOf(
                "wireVersion" to MEDIA_CAPTURE_WIRE_VERSION,
                "eventType" to type,
                "payload" to payload,
            )
        requireGeneratedOutputEnvelope(envelope, "/lifecycle/eventEnvelope")
        return envelope
    }

    private fun failureEnvelope(type: String, payload: Map<String, Any?>): Map<String, Any?> {
        require(type == GeneratedMediaCaptureWireFailure.sessionTimeout.wireValue)
        requireGeneratedOutputPayload("session_timeout_failure_payload", payload)
        val envelope =
            mapOf(
                "wireVersion" to MEDIA_CAPTURE_WIRE_VERSION,
                "failureType" to type,
                "payload" to payload,
            )
        requireGeneratedOutputEnvelope(envelope, "/lifecycle/failureEnvelope")
        return envelope
    }

    private fun sessionHandle(map: Map<String, Any?>, operation: String): SessionHandle =
        SessionHandle(readHandle(map, "sessionHandle", operation))

    private fun mediaHandle(map: Map<String, Any?>, operation: String): MediaHandle =
        MediaHandle(readHandle(map, "mediaHandle", operation))

    private fun readHandle(map: Map<String, Any?>, key: String, operation: String): String {
        val value = readString(map, key, operation)
        val descriptor = checkNotNull(generatedFieldsByKey[key])
        val lengths = checkNotNull(generatedOpaqueHandleLengths[descriptor.id])
        if (value.length !in lengths) throw invalidPayload(operation, key, "out_of_range")
        return value
    }

    private fun outputHandle(value: String): String {
        val sessionLengths = checkNotNull(generatedOpaqueHandleLengths["session_handle"])
        val mediaLengths = checkNotNull(generatedOpaqueHandleLengths["media_handle"])
        check(sessionLengths == mediaLengths)
        require(value.length in sessionLengths)
        return value
    }

    private fun requireExportHandle(value: String) {
        require(opaqueHandlePattern.matches(value))
        require(value.length in checkNotNull(generatedOpaqueHandleLengths["export_handle"]))
    }

    internal fun requireCanonicalFileUri(value: String) {
        require(value.length <= MAX_FILE_URI_LENGTH && value.startsWith("file:///"))
        value.forEachIndexed { index, character ->
            require(character.code in 0x21..0x7e)
            if (character == '%') {
                require(index + 2 < value.length)
                require(value[index + 1].isUpperHex() && value[index + 2].isUpperHex())
            }
        }
        val uri = URI(value)
        require(
            uri.scheme == "file" && uri.rawUserInfo == null && uri.host == null &&
                uri.port == -1 && uri.rawQuery == null && uri.rawFragment == null &&
                uri.toASCIIString() == value,
        )
        val rawPath = checkNotNull(uri.rawPath)
        require(
            rawPath.startsWith('/') && rawPath.length > 1 && !rawPath.endsWith('/') &&
                !rawPath.substring(1).contains("//"),
        )
        rawPath.substring(1).split('/').forEach { segment ->
            val decoded = decodeUriSegment(segment)
            require(
                decoded.isNotEmpty() && decoded != "." && decoded != ".." &&
                    '/' !in decoded && '\\' !in decoded &&
                    decoded.none { it.code < 0x20 || it.code == 0x7f },
            )
        }
    }

    private fun decodeUriSegment(segment: String): String {
        val decoded = StringBuilder()
        var index = 0
        while (index < segment.length) {
            if (segment[index] != '%') {
                decoded.append(segment[index])
                index += 1
                continue
            }
            val bytes = ByteArrayOutputStream()
            while (index < segment.length && segment[index] == '%') {
                require(index + 2 < segment.length)
                require(segment[index + 1].isUpperHex() && segment[index + 2].isUpperHex())
                bytes.write(segment.substring(index + 1, index + 3).toInt(16))
                index += 3
            }
            val decoder =
                StandardCharsets.UTF_8.newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
            decoded.append(decoder.decode(ByteBuffer.wrap(bytes.toByteArray())))
        }
        return decoded.toString()
    }

    private fun requireRequestIdForOutput(value: String) {
        require(requestIdPattern.matches(value))
    }

    private fun readMap(value: Any?, operation: String, field: String): Map<String, Any?> {
        if (value !is Map<*, *>) throw invalidPayload(operation, field, "type_mismatch")
        val result = linkedMapOf<String, Any?>()
        for ((key, item) in value) {
            if (key !is String) throw invalidPayload(operation, field, "type_mismatch")
            result[key] = item
        }
        return result
    }

    private fun requireKeys(
        map: Map<String, Any?>,
        expected: Set<String>,
        operation: String,
    ) {
        val missing = expected.firstOrNull { !map.containsKey(it) }
        if (missing != null) throw invalidPayload(operation, missing, "missing_required_field")
        val unknown = map.keys.firstOrNull { it !in expected }
        if (unknown != null) throw invalidPayload(operation, "unknown_field", "unknown_field")
    }

    private fun readString(map: Map<String, Any?>, key: String, operation: String): String {
        val value = map[key]
        if (value == null) throw invalidPayload(operation, key, "null_not_allowed")
        if (value !is String) throw invalidPayload(operation, key, "type_mismatch")
        return value
    }

    private fun readBoolean(map: Map<String, Any?>, key: String, operation: String): Boolean {
        val value = map[key]
        if (value == null) throw invalidPayload(operation, key, "null_not_allowed")
        if (value !is Boolean) throw invalidPayload(operation, key, "type_mismatch")
        return value
    }

    private fun readInt(map: Map<String, Any?>, key: String, operation: String): Long {
        val value = map[key]
        if (value == null) throw invalidPayload(operation, key, "null_not_allowed")
        return when (value) {
            is Int -> value.toLong()
            is Long -> value
            else -> throw invalidPayload(operation, key, "type_mismatch")
        }
    }

    private fun readFiniteDouble(
        map: Map<String, Any?>,
        key: String,
        operation: String,
    ): Double {
        val value = map[key]
        if (value == null) throw invalidPayload(operation, key, "null_not_allowed")
        if (value !is Double) throw invalidPayload(operation, key, "type_mismatch")
        return value
    }

    private fun readEnum(
        map: Map<String, Any?>,
        key: String,
        operation: String,
    ): String {
        val value = readString(map, key, operation)
        val values = checkNotNull(generatedFieldsByKey[key]).enumValues
        if (value !in values) throw invalidPayload(operation, key, "invalid_enum")
        return value
    }

    private fun readEnumList(
        map: Map<String, Any?>,
        key: String,
        operation: String,
    ): List<String> {
        val field = checkNotNull(generatedFieldsByKey[key])
        val values = field.enumValues
        val raw = map[key]
        if (raw == null) throw invalidPayload(operation, key, "null_not_allowed")
        if (raw !is List<*>) throw invalidPayload(operation, key, "type_mismatch")
        val decoded =
            raw.map { item ->
                if (item !is String) throw invalidPayload(operation, key, "type_mismatch")
                if (item !in values) throw invalidPayload(operation, key, "invalid_enum")
                item
            }
        if (decoded.toSet().size != decoded.size) {
            throw invalidPayload(operation, key, "invalid_format")
        }
        return decoded
    }

    private fun safeOperation(operation: String): String =
        operation.takeIf { it in methods } ?: "unknown_operation"

    private val startOfFrameMarkers =
        setOf(0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf)
    private val allowedJpegMarkers = startOfFrameMarkers + setOf(0xc4, 0xcc, 0xda, 0xdb, 0xdc, 0xdd, 0xde, 0xdf)

    private const val MAX_MATERIALIZED_BYTES = 52_428_800L
    private const val MAX_FILE_URI_LENGTH = 4096
}

private fun Char.isUpperHex(): Boolean = this in '0'..'9' || this in 'A'..'F'

private fun ByteArray.u8(index: Int): Int = this[index].toInt() and 0xff

private val MediaType.wireValue: String
    get() =
        generatedFieldEnumValue(
            "media_type",
            when (this) {
                MediaType.PHOTO -> "photo"
                MediaType.VIDEO -> "video"
            },
        )

private val CameraPosition.wireValue: String
    get() =
        generatedFieldEnumValue(
            "active_camera",
            when (this) {
                CameraPosition.REAR -> "rear"
                CameraPosition.FRONT -> "front"
            },
        )

private val FlashMode.wireValue: String
    get() =
        generatedFieldEnumValue(
            "flash_mode",
            when (this) {
                FlashMode.OFF -> "off"
                FlashMode.ON -> "on"
                FlashMode.AUTO -> "auto"
                FlashMode.TORCH -> "torch"
            },
        )

private fun generatedFieldEnumValue(fieldId: String, value: String): String {
    val field = generatedMediaCaptureWireFields.single { it.id == fieldId }
    check(value in field.enumValues)
    return value
}

private fun mediaType(value: String): MediaType =
    when (value) {
        "photo" -> MediaType.PHOTO
        "video" -> MediaType.VIDEO
        else -> error("Validated media type expected")
    }

private fun camera(value: String): CameraPosition =
    when (value) {
        "rear" -> CameraPosition.REAR
        "front" -> CameraPosition.FRONT
        else -> error("Validated camera expected")
    }

private fun flashMode(value: String): FlashMode =
    when (value) {
        "off" -> FlashMode.OFF
        "on" -> FlashMode.ON
        "auto" -> FlashMode.AUTO
        "torch" -> FlashMode.TORCH
        else -> error("Validated flash mode expected")
    }
