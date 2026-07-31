package com.example.mediacapture.api

import com.example.mediacapture.rendering.MediaCaptureRenderSurfaceOwner
import com.example.mediacapture.rendering.MediaCaptureRenderView
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow

@JvmInline
value class SessionHandle(val value: String) {
    init {
        require(value.isNotBlank() && value.length <= 128)
    }
}

@JvmInline
value class MediaHandle(val value: String) {
    init {
        require(value.isNotBlank() && value.length <= 128)
    }
}

enum class MediaType { PHOTO, VIDEO }

enum class CameraPosition { REAR, FRONT }

enum class FlashMode { OFF, ON, AUTO, TORCH }

enum class PermissionResource { CAMERA, MICROPHONE }

enum class PermissionState {
    NOT_DETERMINED,
    GRANTED,
    DENIED,
    RESTRICTED,
    PERMANENTLY_DENIED,
    UNSUPPORTED,
}

enum class SessionState {
    REQUESTING_PERMISSION,
    PREPARING,
    READY,
    RECORDING,
    PREVIEWING,
    COMPLETED,
    CANCELLED,
    FAILED,
}

enum class MediaState {
    PREVIEW,
    LEASED,
    RELEASE_GRACE,
    EXPIRY_GRACE,
    DISCARDED,
    RELEASED,
    EXPIRED,
}

enum class AttachmentKind { LIVE_PREVIEW, UNCONFIRMED_PREVIEW }

enum class FailureCode(
    val wireValue: String,
    val recoverable: Boolean,
    val terminal: Boolean,
) {
    PERMISSION_DENIED("permission_denied", true, true),
    PERMISSION_RESTRICTED("permission_restricted", false, true),
    PERMISSION_PERMANENTLY_DENIED("permission_permanently_denied", false, true),
    RESOURCE_IN_USE("resource_in_use", true, true),
    STORAGE_FULL("storage_full", true, true),
    ENCODING_FAILED("encoding_failed", true, true),
    MEDIA_INVALID("media_invalid", false, false),
    SESSION_INVALID("session_invalid", false, false),
    UNSUPPORTED_CAPABILITY("unsupported_capability", true, false),
    SYSTEM_INTERRUPTED("system_interrupted", true, true),
    SESSION_CONFLICT("session_conflict", true, false),
    INVALID_STATE("invalid_state", true, false),
    INVALID_ARGUMENT("invalid_argument", true, false),
    SESSION_TIMEOUT("session_timeout", true, true),
    THUMBNAIL_GENERATION_FAILED("thumbnail_generation_failed", true, false),
    THUMBNAIL_GENERATION_CANCELLED("thumbnail_generation_cancelled", true, false),
    THUMBNAIL_OVERLOADED("thumbnail_overloaded", true, false),
    ATTACHMENT_GENERATION_RETIRED("attachment_generation_retired", false, false),
    ATTACHMENT_TARGET_CONFLICT("attachment_target_conflict", true, false),
    MEDIA_EXPORT_CONFLICT("media_export_conflict", true, false),
    MEDIA_EXPORT_OVERLOADED("media_export_overloaded", true, false),
    MEDIA_EXPORT_TOO_LARGE("media_export_too_large", true, false),
    MEDIA_EXPORT_SINK_REJECTED("media_export_sink_rejected", true, false),
    MEDIA_EXPORT_READ_FAILED("media_export_read_failed", true, false),
    MEDIA_EXPORT_WRITE_FAILED("media_export_write_failed", true, false),
    MEDIA_EXPORT_CANCELLED("media_export_cancelled", true, false),
    MEDIA_EXPORT_TIMED_OUT("media_export_timed_out", true, false),
}

data class MediaCaptureFailure(val code: FailureCode)

class MediaCaptureException(
    val failure: MediaCaptureFailure,
    cause: Throwable? = null,
) : Exception(failure.code.wireValue, cause)

data class SessionOptions(
    val enabledMediaTypes: Set<MediaType>,
    val preferredCamera: CameraPosition,
    val audioEnabled: Boolean,
    val maxVideoDurationMillis: Long,
)

data class SessionCreated(val sessionHandle: SessionHandle)

data class SessionReady(
    val sessionHandle: SessionHandle,
    val activeCamera: CameraPosition,
    val availableCameras: Set<CameraPosition>,
    val switchCameraSupported: Boolean,
    val supportedFlashModes: Set<FlashMode>,
    val focusPointSupported: Boolean,
    val minZoomFactor: Double,
    val maxZoomFactor: Double,
)

data class RecordingStarted(
    val sessionHandle: SessionHandle,
    val audioIncluded: Boolean,
)

data class MediaMetadata(
    val mediaType: MediaType,
    val pixelWidth: Int,
    val pixelHeight: Int,
    val durationMillis: Long?,
    val orientationDegrees: Int,
    val byteLength: Long,
    val contentType: String,
)

data class MediaPreview(
    val mediaHandle: MediaHandle,
    val metadata: MediaMetadata,
)

data class ConfirmedMedia(
    val mediaHandle: MediaHandle,
    val metadata: MediaMetadata,
    val leaseExpiresAtEpochMillis: Long,
)

data class SessionCancelled(val sessionHandle: SessionHandle)

data class MediaReleased(val mediaHandle: MediaHandle)

data class RenderAttachmentResult(
    val attachmentKind: AttachmentKind,
    val ownerGeneration: Long,
)

data class MediaThumbnail(
    val mediaHandle: MediaHandle,
    val copy: ByteArray,
    val pixelWidth: Int,
    val pixelHeight: Int,
    val mediaType: MediaType,
    val posterFrameMillis: Long?,
) {
    val byteLength: Int = copy.size
    val contentType: String = "image/jpeg"
    val orientationDegrees: Int = 0
}

data class MediaExportResult(
    val mediaHandle: MediaHandle,
    val mediaType: MediaType,
    val contentType: String,
    val byteLength: Long,
)

interface MediaCopySink {
    suspend fun begin(mediaType: MediaType, contentType: String, byteLength: Long)

    /**
     * Consumes callback-scoped borrowed memory. The sink must finish reading or copy the first
     * [byteCount] bytes before this call returns and must not retain [buffer]. Core may reuse and
     * wipe the array immediately after the callback completes.
     */
    suspend fun write(buffer: ByteArray, byteCount: Int)

    /**
     * Atomically publishes the target. Implementations must cooperate with cancellation and must
     * leave the target abortable when this call throws or is cancelled. Durable publication may
     * only become observable when this call completes successfully.
     */
    suspend fun commit(byteLength: Long)

    /** Discards a begun, uncommitted target and must be safe after an interrupted commit attempt. */
    suspend fun abort()
}

sealed interface MediaCaptureEvent {
    data class Ready(val value: SessionReady) : MediaCaptureEvent

    data class SessionFailed(
        val sessionHandle: SessionHandle,
        val failure: MediaCaptureFailure,
    ) : MediaCaptureEvent

    data class PreviewReady(
        val sessionHandle: SessionHandle,
        val preview: MediaPreview,
    ) : MediaCaptureEvent

    data class LeaseExpired(val mediaHandle: MediaHandle) : MediaCaptureEvent

    data class ReadRevoked(val mediaHandle: MediaHandle) : MediaCaptureEvent

    data class AttachmentRevoked(
        val attachmentKind: AttachmentKind,
        val ownerGeneration: Long,
    ) : MediaCaptureEvent
}

data class SessionObservation(
    val state: SessionState,
    val ready: SessionReady? = null,
    val preview: MediaPreview? = null,
    val terminalFailure: MediaCaptureFailure? = null,
)

interface ScopedMediaRead {
    val byteLength: Long
    val contentType: String

    suspend fun readBytes(): ByteArray

    suspend fun close()
}

interface ThumbnailRead {
    suspend fun await(): MediaThumbnail

    suspend fun cancel()
}

interface MediaCapture {
    val events: SharedFlow<MediaCaptureEvent>

    suspend fun permissionState(resource: PermissionResource): PermissionState

    suspend fun startSession(options: SessionOptions): SessionCreated

    suspend fun takePhoto(sessionHandle: SessionHandle): MediaPreview

    suspend fun startRecording(sessionHandle: SessionHandle): RecordingStarted

    suspend fun stopRecording(sessionHandle: SessionHandle): MediaPreview

    suspend fun switchCamera(sessionHandle: SessionHandle)

    suspend fun setFlashMode(sessionHandle: SessionHandle, flashMode: FlashMode)

    suspend fun setFocusPoint(sessionHandle: SessionHandle, normalizedX: Double, normalizedY: Double)

    suspend fun setZoom(sessionHandle: SessionHandle, zoomFactor: Double)

    suspend fun retake(mediaHandle: MediaHandle): SessionHandle

    suspend fun confirm(mediaHandle: MediaHandle): ConfirmedMedia

    suspend fun cancel(sessionHandle: SessionHandle): SessionCancelled

    suspend fun <T> withMediaRead(
        mediaHandle: MediaHandle,
        block: suspend (ScopedMediaRead) -> T,
    ): T

    suspend fun releaseMedia(mediaHandle: MediaHandle): MediaReleased

    suspend fun createRenderView(owner: MediaCaptureRenderSurfaceOwner): MediaCaptureRenderView

    suspend fun attachLivePreview(
        sessionHandle: SessionHandle,
        surface: MediaCaptureRenderView,
        ownerGeneration: Long,
    ): RenderAttachmentResult

    suspend fun detachLivePreview(
        sessionHandle: SessionHandle,
        surface: MediaCaptureRenderView,
        ownerGeneration: Long,
    ): RenderAttachmentResult

    suspend fun attachUnconfirmedPreview(
        mediaHandle: MediaHandle,
        surface: MediaCaptureRenderView,
        ownerGeneration: Long,
    ): RenderAttachmentResult

    suspend fun detachUnconfirmedPreview(
        mediaHandle: MediaHandle,
        surface: MediaCaptureRenderView,
        ownerGeneration: Long,
    ): RenderAttachmentResult

    suspend fun readMediaThumbnail(mediaHandle: MediaHandle, maxPixelEdge: Int): ThumbnailRead

    suspend fun copyConfirmedMediaToSink(
        mediaHandle: MediaHandle,
        sink: MediaCopySink,
        maxLength: Long,
    ): MediaExportResult = throw MediaCaptureException(
        MediaCaptureFailure(FailureCode.UNSUPPORTED_CAPABILITY),
    )

    suspend fun sessionState(sessionHandle: SessionHandle): SessionState

    suspend fun sessionObservation(sessionHandle: SessionHandle): StateFlow<SessionObservation>

    suspend fun mediaState(mediaHandle: MediaHandle): MediaState

    suspend fun onDisplayRotationChanged()

    suspend fun onAppBackgrounded()

    suspend fun onPreviewOwnerDestroyed(surface: MediaCaptureRenderView)

    suspend fun onAppRestarted()

    suspend fun close()
}
