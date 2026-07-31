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

internal const val MEDIA_CAPTURE_WIRE_VERSION = 3
internal const val MEDIA_CAPTURE_COMMANDS_CHANNEL = "com.example.media_capture.commands"
internal const val MEDIA_CAPTURE_EVENTS_CHANNEL = "com.example.media_capture.events"

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
) : Exception(code)

internal object MediaCaptureWireCodec {
    private val requestIdPattern = Regex("^[A-Za-z0-9_-]{1,128}$")
    private val exportHandlePattern = Regex("^[A-Za-z0-9_-]{22,64}$")
    private val orientationValues = setOf(0, 90, 180, 270)

    val methods: Set<String> =
        setOf(
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
            "materialize_media_resource",
            "release_materialized_media",
            "present_capture_flow",
            "dismiss_capture_flow",
        )

    fun decodeRequest(operation: String, arguments: Any?): MediaCaptureWireRequest {
        if (operation !in methods) {
            throw invalidPayload("unknown_operation", "payload", "invalid_enum")
        }
        val envelope = readMap(arguments, operation, "payload")
        requireKeys(
            envelope,
            setOf("wireVersion", "requestId", "payload"),
            operation,
        )
        val version = readInt(envelope, "wireVersion", operation)
        if (version != MEDIA_CAPTURE_WIRE_VERSION.toLong()) {
            throw MediaCaptureWireFailure(
                code = "incompatible_wire_version",
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
        requireKeys(envelope, setOf("wireVersion"), "unknown_operation")
        val version = readInt(envelope, "wireVersion", "unknown_operation")
        if (version != MEDIA_CAPTURE_WIRE_VERSION.toLong()) {
            throw MediaCaptureWireFailure(
                "incompatible_wire_version",
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
        return mapOf(
            "wireVersion" to MEDIA_CAPTURE_WIRE_VERSION,
            "requestId" to requestId,
            "resultType" to resultType,
            "payload" to payload,
        )
    }

    fun sessionCreated(requestId: String, handle: SessionHandle): Map<String, Any?> =
        result(requestId, "session_created", mapOf("sessionHandle" to outputHandle(handle.value)))

    fun controlApplied(requestId: String, handle: SessionHandle): Map<String, Any?> =
        result(requestId, "control_applied", mapOf("sessionHandle" to outputHandle(handle.value)))

    fun recordingStarted(
        requestId: String,
        handle: SessionHandle,
        audioIncluded: Boolean,
    ): Map<String, Any?> =
        result(
            requestId,
            "recording_started",
            mapOf("sessionHandle" to outputHandle(handle.value), "audioIncluded" to audioIncluded),
        )

    fun mediaPreview(requestId: String, preview: MediaPreview): Map<String, Any?> =
        result(requestId, "media_preview", mediaPayload(preview.mediaHandle, preview.metadata))

    fun retakeReady(requestId: String, handle: SessionHandle): Map<String, Any?> =
        result(requestId, "retake_ready", mapOf("sessionHandle" to outputHandle(handle.value)))

    fun confirmedMedia(requestId: String, media: ConfirmedMedia): Map<String, Any?> {
        require(media.leaseExpiresAtEpochMillis >= 0L)
        return result(
            requestId,
            "confirmed_media",
            mediaPayload(media.mediaHandle, media.metadata) +
                ("leaseExpiresAt" to media.leaseExpiresAtEpochMillis),
        )
    }

    fun sessionCancelled(requestId: String, handle: SessionHandle): Map<String, Any?> =
        result(requestId, "session_cancelled", mapOf("sessionHandle" to outputHandle(handle.value)))

    fun mediaReleased(requestId: String, handle: MediaHandle): Map<String, Any?> =
        result(requestId, "media_released", mapOf("mediaHandle" to outputHandle(handle.value)))

    fun thumbnail(
        requestId: String,
        thumbnail: MediaThumbnail,
        maxPixelEdge: Int,
    ): Map<String, Any?> {
        validateThumbnail(thumbnail, maxPixelEdge)
        return result(
            requestId,
            "media_thumbnail",
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
        require(metadata.orientationDegrees in orientationValues)
        require(
            metadata.contentType ==
                if (metadata.mediaType == MediaType.PHOTO) "image/jpeg" else "video/mp4",
        )
        require(
            if (metadata.mediaType == MediaType.PHOTO) {
                metadata.durationMillis == null
            } else {
                metadata.durationMillis != null && metadata.durationMillis in 1L..60_000L
            },
        )
        require(expiresAtEpochMillis >= 0L)
        return result(
            requestId,
            "materialized_media_resource",
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
        result(requestId, "materialized_media_released", emptyMap())

    fun captureFlowDismissed(requestId: String): Map<String, Any?> =
        result(requestId, "capture_flow_dismissed", emptyMap())

    fun flowConfirmed(requestId: String, media: ConfirmedMedia): Map<String, Any?> {
        require(media.leaseExpiresAtEpochMillis >= 0L)
        return result(
            requestId,
            "capture_flow_confirmed",
            mediaPayload(media.mediaHandle, media.metadata) +
                ("leaseExpiresAt" to media.leaseExpiresAtEpochMillis),
        )
    }

    fun flowCancelled(requestId: String): Map<String, Any?> =
        result(requestId, "capture_flow_cancelled", emptyMap())

    fun event(event: MediaCaptureEvent): Map<String, Any?>? =
        when (event) {
            is MediaCaptureEvent.Ready ->
                eventEnvelope("session_ready", readyPayload(event.value))
            is MediaCaptureEvent.SessionFailed -> {
                if (event.failure.code == FailureCode.SESSION_TIMEOUT) {
                    failureEnvelope(
                        "session_timeout",
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
                        "session_failed",
                        mapOf(
                            "sessionHandle" to outputHandle(event.sessionHandle.value),
                            "terminalFailureId" to event.failure.code.wireValue,
                        ),
                    )
                }
            }
            is MediaCaptureEvent.PreviewReady ->
                eventEnvelope(
                    "media_preview_ready",
                    mapOf("sessionHandle" to outputHandle(event.sessionHandle.value)) +
                        mediaPayload(event.preview.mediaHandle, event.preview.metadata),
                )
            is MediaCaptureEvent.LeaseExpired ->
                eventEnvelope(
                    "media_lease_expired",
                    mapOf("mediaHandle" to outputHandle(event.mediaHandle.value)),
                )
            is MediaCaptureEvent.ReadRevoked ->
                eventEnvelope(
                    "media_read_revoked",
                    mapOf("mediaHandle" to outputHandle(event.mediaHandle.value)),
                )
            is MediaCaptureEvent.AttachmentRevoked -> null
        }

    fun invalidPayload(operation: String, field: String, reason: String): MediaCaptureWireFailure =
        MediaCaptureWireFailure(
            "invalid_wire_payload",
            mapOf("operation" to safeOperation(operation), "field" to field, "reason" to reason),
        )

    fun bridgeUnavailable(operation: String, reason: String): MediaCaptureWireFailure =
        MediaCaptureWireFailure(
            "bridge_unavailable",
            mapOf("operation" to safeOperation(operation), "lifecycleReason" to reason),
        )

    fun bridgeOverloaded(operation: String, capacity: String): MediaCaptureWireFailure =
        MediaCaptureWireFailure(
            "bridge_overloaded",
            mapOf("operation" to safeOperation(operation), "capacity" to capacity),
        )

    fun duplicateRequest(operation: String): MediaCaptureWireFailure =
        MediaCaptureWireFailure(
            "duplicate_request",
            mapOf("operation" to safeOperation(operation)),
        )

    fun listenerAlreadyActive(): MediaCaptureWireFailure =
        MediaCaptureWireFailure("listener_already_active", emptyMap())

    fun presentationConflict(): MediaCaptureWireFailure =
        MediaCaptureWireFailure(
            "presentation_conflict",
            mapOf("operation" to "present_capture_flow", "capacity" to "active_presentation"),
        )

    fun transferStoreOverloaded(operation: String, capacity: String): MediaCaptureWireFailure =
        MediaCaptureWireFailure(
            "transfer_store_overloaded",
            mapOf("operation" to safeOperation(operation), "capacity" to capacity),
        )

    fun transferStoreUnavailable(operation: String): MediaCaptureWireFailure =
        MediaCaptureWireFailure(
            "transfer_store_unavailable",
            mapOf("operation" to safeOperation(operation), "lifecycleReason" to "adapter_disposed"),
        )

    fun materializedMediaInvalid(): MediaCaptureWireFailure =
        MediaCaptureWireFailure(
            "materialized_media_invalid",
            mapOf("operation" to "release_materialized_media"),
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
            "wire_encoding_failed",
            mapOf(
                "operation" to safeOperation(operation),
                "field" to "unknown_field",
                "reason" to "native_value_unencodable",
            ),
        )

    private fun decodePayload(
        operation: String,
        payload: Map<String, Any?>,
    ): MediaCaptureWirePayload =
        when (operation) {
            "start_session", "present_capture_flow" -> {
                requireKeys(
                    payload,
                    setOf(
                        "enabledMediaTypes",
                        "preferredCamera",
                        "audioEnabled",
                        "maxVideoDurationMillis",
                    ),
                    operation,
                )
                val mediaTypes =
                    readEnumList(payload, "enabledMediaTypes", operation, setOf("photo", "video"))
                        .mapTo(linkedSetOf(), ::mediaType)
                val preferred = camera(readEnum(payload, "preferredCamera", operation, setOf("rear", "front")))
                val duration = readInt(payload, "maxVideoDurationMillis", operation)
                if (duration !in 1L..60_000L) {
                    throw invalidPayload(operation, "maxVideoDurationMillis", "out_of_range")
                }
                MediaCaptureWirePayload.StartSession(
                    SessionOptions(
                        enabledMediaTypes = mediaTypes,
                        preferredCamera = preferred,
                        audioEnabled = readBoolean(payload, "audioEnabled", operation),
                        maxVideoDurationMillis = duration,
                    ),
                )
            }
            "take_photo", "start_recording", "stop_recording", "switch_camera", "cancel" -> {
                requireKeys(payload, setOf("sessionHandle"), operation)
                MediaCaptureWirePayload.SessionAction(sessionHandle(payload, operation))
            }
            "set_flash_mode" -> {
                requireKeys(payload, setOf("sessionHandle", "flashMode"), operation)
                MediaCaptureWirePayload.Flash(
                    sessionHandle(payload, operation),
                    flashMode(
                        readEnum(
                            payload,
                            "flashMode",
                            operation,
                            setOf("off", "on", "auto", "torch"),
                        ),
                    ),
                )
            }
            "set_focus_point" -> {
                requireKeys(payload, setOf("sessionHandle", "normalizedX", "normalizedY"), operation)
                MediaCaptureWirePayload.Focus(
                    sessionHandle(payload, operation),
                    readFiniteDouble(payload, "normalizedX", operation, 0.0, 1.0),
                    readFiniteDouble(payload, "normalizedY", operation, 0.0, 1.0),
                )
            }
            "set_zoom" -> {
                requireKeys(payload, setOf("sessionHandle", "zoomFactor"), operation)
                val zoom = readFiniteDouble(payload, "zoomFactor", operation, 0.01, null)
                MediaCaptureWirePayload.Zoom(sessionHandle(payload, operation), zoom)
            }
            "retake", "confirm", "release_media" -> {
                requireKeys(payload, setOf("mediaHandle"), operation)
                MediaCaptureWirePayload.MediaAction(mediaHandle(payload, operation))
            }
            "read_media_thumbnail" -> {
                requireKeys(payload, setOf("mediaHandle", "maxPixelEdge"), operation)
                val maxPixelEdge = readInt(payload, "maxPixelEdge", operation)
                if (maxPixelEdge !in 64L..512L) {
                    throw invalidPayload(operation, "maxPixelEdge", "out_of_range")
                }
                MediaCaptureWirePayload.Thumbnail(
                    mediaHandle(payload, operation),
                    maxPixelEdge.toInt(),
                )
            }
            "materialize_media_resource" -> {
                requireKeys(payload, setOf("mediaHandle"), operation)
                MediaCaptureWirePayload.Materialize(mediaHandle(payload, operation))
            }
            "release_materialized_media" -> {
                requireKeys(payload, setOf("exportHandle"), operation)
                val handle = readString(payload, "exportHandle", operation)
                if (!exportHandlePattern.matches(handle)) {
                    throw invalidPayload(operation, "exportHandle", "invalid_format")
                }
                MediaCaptureWirePayload.ReleaseMaterialized(handle)
            }
            "dismiss_capture_flow" -> {
                requireKeys(payload, setOf("presentationRequestId"), operation)
                val presentationRequestId = readString(payload, "presentationRequestId", operation)
                if (!requestIdPattern.matches(presentationRequestId)) {
                    throw invalidPayload(operation, "presentationRequestId", "invalid_format")
                }
                MediaCaptureWirePayload.DismissPresentation(presentationRequestId)
            }
            else -> throw invalidPayload("unknown_operation", "payload", "invalid_enum")
        }

    private fun readyPayload(ready: SessionReady): Map<String, Any?> {
        require(ready.availableCameras.isNotEmpty() && ready.availableCameras.size <= 2)
        require(ready.activeCamera in ready.availableCameras)
        require(ready.supportedFlashModes.isNotEmpty() && ready.supportedFlashModes.size <= 4)
        require(ready.minZoomFactor.isFinite() && ready.minZoomFactor >= 0.01)
        require(ready.maxZoomFactor.isFinite() && ready.maxZoomFactor >= ready.minZoomFactor)
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
        require(metadata.pixelWidth > 0 && metadata.pixelHeight > 0)
        require(metadata.orientationDegrees in orientationValues)
        require(metadata.byteLength > 0L)
        when (metadata.mediaType) {
            MediaType.PHOTO -> require(metadata.durationMillis == null)
            MediaType.VIDEO ->
                require(metadata.durationMillis != null && metadata.durationMillis in 1L..60_000L)
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
        require(thumbnail.copy.isNotEmpty() && thumbnail.copy.size <= 524_288)
        require(thumbnail.byteLength == thumbnail.copy.size)
        require(thumbnail.pixelWidth in 1..maxPixelEdge && thumbnail.pixelHeight in 1..maxPixelEdge)
        require(maxPixelEdge in 64..512)
        when (thumbnail.mediaType) {
            MediaType.PHOTO -> require(thumbnail.posterFrameMillis == null)
            MediaType.VIDEO ->
                require(
                    thumbnail.posterFrameMillis != null &&
                        thumbnail.posterFrameMillis in 0L..60_000L,
                )
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

    private fun eventEnvelope(type: String, payload: Map<String, Any?>): Map<String, Any?> =
        mapOf("wireVersion" to MEDIA_CAPTURE_WIRE_VERSION, "eventType" to type, "payload" to payload)

    private fun failureEnvelope(type: String, payload: Map<String, Any?>): Map<String, Any?> =
        mapOf("wireVersion" to MEDIA_CAPTURE_WIRE_VERSION, "failureType" to type, "payload" to payload)

    private fun sessionHandle(map: Map<String, Any?>, operation: String): SessionHandle =
        SessionHandle(readHandle(map, "sessionHandle", operation))

    private fun mediaHandle(map: Map<String, Any?>, operation: String): MediaHandle =
        MediaHandle(readHandle(map, "mediaHandle", operation))

    private fun readHandle(map: Map<String, Any?>, key: String, operation: String): String {
        val value = readString(map, key, operation)
        if (!isValidHandle(value)) throw invalidPayload(operation, key, "out_of_range")
        return value
    }

    private fun outputHandle(value: String): String {
        require(isValidHandle(value))
        return value
    }

    private fun requireExportHandle(value: String) {
        require(exportHandlePattern.matches(value))
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

    private fun isValidHandle(value: String): Boolean = value.isNotEmpty() && value.length <= 128

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
        minimum: Double,
        maximum: Double?,
    ): Double {
        val value = map[key]
        if (value == null) throw invalidPayload(operation, key, "null_not_allowed")
        if (value !is Double) throw invalidPayload(operation, key, "type_mismatch")
        if (!value.isFinite()) throw invalidPayload(operation, key, "non_finite")
        if (value < minimum || (maximum != null && value > maximum)) {
            throw invalidPayload(operation, key, "out_of_range")
        }
        return value
    }

    private fun readEnum(
        map: Map<String, Any?>,
        key: String,
        operation: String,
        values: Set<String>,
    ): String {
        val value = readString(map, key, operation)
        if (value !in values) throw invalidPayload(operation, key, "invalid_enum")
        return value
    }

    private fun readEnumList(
        map: Map<String, Any?>,
        key: String,
        operation: String,
        values: Set<String>,
    ): List<String> {
        val raw = map[key]
        if (raw == null) throw invalidPayload(operation, key, "null_not_allowed")
        if (raw !is List<*>) throw invalidPayload(operation, key, "type_mismatch")
        if (raw.isEmpty() || raw.size > values.size) {
            throw invalidPayload(operation, key, "out_of_range")
        }
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
    get() = name.lowercase()

private val CameraPosition.wireValue: String
    get() = name.lowercase()

private val FlashMode.wireValue: String
    get() = name.lowercase()

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
