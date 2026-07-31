package com.example.media_capture

import com.example.mediacapture.api.AttachmentKind
import com.example.mediacapture.api.CameraPosition
import com.example.mediacapture.api.ConfirmedMedia
import com.example.mediacapture.api.FailureCode
import com.example.mediacapture.api.FlashMode
import com.example.mediacapture.api.MediaCapture
import com.example.mediacapture.api.MediaCaptureEvent
import com.example.mediacapture.api.MediaCaptureException
import com.example.mediacapture.api.MediaCaptureFailure
import com.example.mediacapture.api.MediaHandle
import com.example.mediacapture.api.MediaCopySink
import com.example.mediacapture.api.MediaExportResult
import com.example.mediacapture.api.MediaMetadata
import com.example.mediacapture.api.MediaPreview
import com.example.mediacapture.api.MediaReleased
import com.example.mediacapture.api.MediaState
import com.example.mediacapture.api.MediaThumbnail
import com.example.mediacapture.api.MediaType
import com.example.mediacapture.api.PermissionResource
import com.example.mediacapture.api.PermissionState
import com.example.mediacapture.api.RecordingStarted
import com.example.mediacapture.api.RenderAttachmentResult
import com.example.mediacapture.api.ScopedMediaRead
import com.example.mediacapture.api.SessionCancelled
import com.example.mediacapture.api.SessionCreated
import com.example.mediacapture.api.SessionHandle
import com.example.mediacapture.api.SessionObservation
import com.example.mediacapture.api.SessionOptions
import com.example.mediacapture.api.SessionReady
import com.example.mediacapture.api.SessionState
import com.example.mediacapture.api.ThumbnailRead
import com.example.mediacapture.rendering.MediaCaptureRenderSurfaceOwner
import com.example.mediacapture.rendering.MediaCaptureRenderView
import java.util.Base64
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext

internal class FakeMediaCapture : MediaCapture {
    private var sessionCounter = 0
    private val eventFlow = MutableSharedFlow<MediaCaptureEvent>(extraBufferCapacity = 16)
    private val observations = mutableMapOf<String, MutableStateFlow<SessionObservation>>()

    val calls = mutableListOf<String>()
    val cancelledSessions = mutableListOf<String>()
    val releasedMedia = mutableListOf<String>()
    var startGate: CompletableDeferred<Unit>? = null
    var startIgnoresCancellation = false
    var thumbnailGate: CompletableDeferred<Unit>? = null
    var thumbnailIgnoresCancellation = false
    var thumbnailBytes = Base64.getDecoder().decode(ONE_PIXEL_JPEG_BASE64)
    var thumbnailHandleOverride: MediaHandle? = null
    var confirmedHandleOverride: MediaHandle? = null
    var confirmedLeaseExpiresAt = 123_456L
    var confirmGate: CompletableDeferred<Unit>? = null
    var confirmIgnoresCancellation = false
    var exportGate: CompletableDeferred<Unit>? = null
    var exportIgnoresCancellation = false
    var exportBytes = ByteArray(128) { index -> (index and 0xff).toByte() }
    var exportMediaType = MediaType.PHOTO
    var exportContentType = "image/jpeg"
    var exportResultHandleOverride: MediaHandle? = null
    var recordingHandleOverride: SessionHandle? = null
    var cancelFailuresRemaining = 0
    var releaseFailuresRemaining = 0
    var nextFailure: FailureCode? = null
    var closeCount = 0
    val eventSubscriberCount: Int
        get() = eventFlow.subscriptionCount.value

    override val events: SharedFlow<MediaCaptureEvent> = eventFlow

    override suspend fun permissionState(resource: PermissionResource): PermissionState = PermissionState.GRANTED

    override suspend fun startSession(options: SessionOptions): SessionCreated {
        failIfRequested()
        calls += "start_session"
        val gate = startGate
        if (gate != null) {
            if (startIgnoresCancellation) {
                withContext(NonCancellable) { gate.await() }
            } else {
                gate.await()
            }
        }
        val handle = SessionHandle("session-${++sessionCounter}")
        observations[handle.value] = MutableStateFlow(SessionObservation(SessionState.READY, ready(handle)))
        return SessionCreated(handle)
    }

    override suspend fun takePhoto(sessionHandle: SessionHandle): MediaPreview {
        failIfRequested()
        calls += "take_photo"
        return preview(MediaHandle("media-${sessionHandle.value}"))
    }

    override suspend fun startRecording(sessionHandle: SessionHandle): RecordingStarted {
        failIfRequested()
        calls += "start_recording"
        return RecordingStarted(recordingHandleOverride ?: sessionHandle, audioIncluded = true)
    }

    override suspend fun stopRecording(sessionHandle: SessionHandle): MediaPreview {
        failIfRequested()
        calls += "stop_recording"
        return preview(MediaHandle("video-${sessionHandle.value}"), MediaType.VIDEO)
    }

    override suspend fun switchCamera(sessionHandle: SessionHandle) {
        failIfRequested()
        calls += "switch_camera"
    }

    override suspend fun setFlashMode(sessionHandle: SessionHandle, flashMode: FlashMode) {
        failIfRequested()
        calls += "set_flash_mode"
    }

    override suspend fun setFocusPoint(
        sessionHandle: SessionHandle,
        normalizedX: Double,
        normalizedY: Double,
    ) {
        failIfRequested()
        calls += "set_focus_point"
    }

    override suspend fun setZoom(sessionHandle: SessionHandle, zoomFactor: Double) {
        failIfRequested()
        calls += "set_zoom"
    }

    override suspend fun retake(mediaHandle: MediaHandle): SessionHandle {
        failIfRequested()
        calls += "retake"
        return SessionHandle(mediaHandle.value.removePrefix("media-"))
    }

    override suspend fun confirm(mediaHandle: MediaHandle): ConfirmedMedia {
        failIfRequested()
        calls += "confirm"
        val gate = confirmGate
        if (gate != null) {
            if (confirmIgnoresCancellation) {
                withContext(NonCancellable) { gate.await() }
            } else {
                gate.await()
            }
        }
        return ConfirmedMedia(
            confirmedHandleOverride ?: mediaHandle,
            metadata(MediaType.PHOTO),
            confirmedLeaseExpiresAt,
        )
    }

    override suspend fun cancel(sessionHandle: SessionHandle): SessionCancelled {
        calls += "cancel"
        if (cancelFailuresRemaining > 0) {
            cancelFailuresRemaining -= 1
            throw MediaCaptureException(MediaCaptureFailure(FailureCode.SYSTEM_INTERRUPTED))
        }
        cancelledSessions += sessionHandle.value
        return SessionCancelled(sessionHandle)
    }

    override suspend fun <T> withMediaRead(
        mediaHandle: MediaHandle,
        block: suspend (ScopedMediaRead) -> T,
    ): T = error("Raw media read must not be used by the bridge")

    override suspend fun releaseMedia(mediaHandle: MediaHandle): MediaReleased {
        calls += "release_media"
        if (releaseFailuresRemaining > 0) {
            releaseFailuresRemaining -= 1
            throw MediaCaptureException(MediaCaptureFailure(FailureCode.SYSTEM_INTERRUPTED))
        }
        releasedMedia += mediaHandle.value
        return MediaReleased(mediaHandle)
    }

    override suspend fun createRenderView(owner: MediaCaptureRenderSurfaceOwner): MediaCaptureRenderView =
        error("Render surface is Native UI-only")

    override suspend fun attachLivePreview(
        sessionHandle: SessionHandle,
        surface: MediaCaptureRenderView,
        ownerGeneration: Long,
    ): RenderAttachmentResult = RenderAttachmentResult(AttachmentKind.LIVE_PREVIEW, ownerGeneration)

    override suspend fun detachLivePreview(
        sessionHandle: SessionHandle,
        surface: MediaCaptureRenderView,
        ownerGeneration: Long,
    ): RenderAttachmentResult = RenderAttachmentResult(AttachmentKind.LIVE_PREVIEW, ownerGeneration)

    override suspend fun attachUnconfirmedPreview(
        mediaHandle: MediaHandle,
        surface: MediaCaptureRenderView,
        ownerGeneration: Long,
    ): RenderAttachmentResult = RenderAttachmentResult(AttachmentKind.UNCONFIRMED_PREVIEW, ownerGeneration)

    override suspend fun detachUnconfirmedPreview(
        mediaHandle: MediaHandle,
        surface: MediaCaptureRenderView,
        ownerGeneration: Long,
    ): RenderAttachmentResult = RenderAttachmentResult(AttachmentKind.UNCONFIRMED_PREVIEW, ownerGeneration)

    override suspend fun readMediaThumbnail(mediaHandle: MediaHandle, maxPixelEdge: Int): ThumbnailRead {
        failIfRequested()
        calls += "read_media_thumbnail"
        return object : ThumbnailRead {
            override suspend fun await(): MediaThumbnail {
                val gate = thumbnailGate
                if (gate != null) {
                    if (thumbnailIgnoresCancellation) {
                        withContext(NonCancellable) { gate.await() }
                    } else {
                        gate.await()
                    }
                }
                return MediaThumbnail(
                    mediaHandle = thumbnailHandleOverride ?: mediaHandle,
                    copy = thumbnailBytes,
                    pixelWidth = 1,
                    pixelHeight = 1,
                    mediaType = MediaType.PHOTO,
                    posterFrameMillis = null,
                )
            }

            override suspend fun cancel() {
                calls += "cancel_thumbnail"
            }
        }
    }

    override suspend fun copyConfirmedMediaToSink(
        mediaHandle: MediaHandle,
        sink: MediaCopySink,
        maxLength: Long,
    ): MediaExportResult {
        failIfRequested()
        calls += "copy_confirmed_media_to_sink"
        val gate = exportGate
        if (gate != null) {
            if (exportIgnoresCancellation) {
                withContext(NonCancellable) { gate.await() }
            } else {
                gate.await()
            }
        }
        try {
            sink.begin(exportMediaType, exportContentType, exportBytes.size.toLong())
            exportBytes.asList().chunked(32).forEach { chunk ->
                sink.write(chunk.toByteArray(), chunk.size)
            }
            sink.commit(exportBytes.size.toLong())
        } catch (exception: Exception) {
            withContext(NonCancellable) { runCatching { sink.abort() } }
            throw exception
        }
        return MediaExportResult(
            mediaHandle = exportResultHandleOverride ?: mediaHandle,
            mediaType = exportMediaType,
            contentType = exportContentType,
            byteLength = exportBytes.size.toLong(),
        )
    }

    override suspend fun sessionState(sessionHandle: SessionHandle): SessionState = SessionState.READY

    override suspend fun sessionObservation(sessionHandle: SessionHandle): StateFlow<SessionObservation> =
        observations.getOrPut(sessionHandle.value) {
            MutableStateFlow(SessionObservation(SessionState.READY, ready(sessionHandle)))
        }

    override suspend fun mediaState(mediaHandle: MediaHandle): MediaState = MediaState.LEASED

    override suspend fun onDisplayRotationChanged() = Unit

    override suspend fun onAppBackgrounded() = Unit

    override suspend fun onPreviewOwnerDestroyed(surface: MediaCaptureRenderView) = Unit

    override suspend fun onAppRestarted() = Unit

    override suspend fun close() {
        closeCount += 1
    }

    suspend fun emit(event: MediaCaptureEvent) {
        eventFlow.emit(event)
    }

    fun ready(handle: SessionHandle): SessionReady =
        SessionReady(
            sessionHandle = handle,
            activeCamera = CameraPosition.REAR,
            availableCameras = setOf(CameraPosition.REAR, CameraPosition.FRONT),
            switchCameraSupported = true,
            supportedFlashModes = setOf(FlashMode.OFF, FlashMode.AUTO),
            focusPointSupported = true,
            minZoomFactor = 1.0,
            maxZoomFactor = 4.0,
        )

    fun preview(handle: MediaHandle, type: MediaType = MediaType.PHOTO): MediaPreview =
        MediaPreview(handle, metadata(type))

    fun confirmed(handle: MediaHandle = MediaHandle("flow-media")): ConfirmedMedia =
        ConfirmedMedia(handle, metadata(MediaType.PHOTO), 123_456L)

    private fun metadata(type: MediaType): MediaMetadata =
        MediaMetadata(
            mediaType = type,
            pixelWidth = 100,
            pixelHeight = 100,
            durationMillis = if (type == MediaType.VIDEO) 1_000L else null,
            orientationDegrees = 0,
            byteLength = 128L,
            contentType = if (type == MediaType.VIDEO) "video/mp4" else "image/jpeg",
        )

    private fun failIfRequested() {
        val failure = nextFailure ?: return
        nextFailure = null
        throw MediaCaptureException(MediaCaptureFailure(failure))
    }

    private companion object {
        const val ONE_PIXEL_JPEG_BASE64 =
            "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////" +
                "////////////////////////////////////////////////////////2wBDAf//" +
                "////////////////////////////////////////////////////////////////////" +
                "////////////////wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAA" +
                "AAAAAAf/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAF//8QAFBAB" +
                "AAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABBQJ//8QAFBEBAAAAAAAAAAAAAAAAAAAA" +
                "AP/aAAgBAwEBPwF//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAgEBPwF//8QA" +
                "FBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQAGPwJ//8QAFBABAAAAAAAAAAAAAAAA" +
                "AAAAAP/aAAgBAQABPyF//9oADAMBAAIAAwAAABD/xAAUEQEAAAAAAAAAAAAAAAAA" +
                "AAAA/9oACAEDAQE/EH//xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAECAQE/EH//" +
                "xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAE/EH//2Q=="
    }
}

internal class FakePresentationController : MediaCaptureBridgePresenter {
    val sessions = mutableListOf<FakePresentationSession>()
    var completeOnDismiss = true
    var presentFailure: IllegalStateException? = null
    var beforePresent: (() -> Unit)? = null

    override fun present(config: com.example.mediacapture.ui.MediaCaptureUiConfig): MediaCaptureBridgePresentationSession {
        beforePresent?.invoke()
        return presentFailure?.let { throw it }
            ?: FakePresentationSession(completeOnDismiss).also(sessions::add)
    }
}

internal class FakePresentationSession(
    private val completeOnDismiss: Boolean,
) : MediaCaptureBridgePresentationSession {
    val outcome = CompletableDeferred<com.example.mediacapture.ui.MediaCaptureFlowResult>()
    var dismissCount = 0

    override suspend fun awaitResult(): com.example.mediacapture.ui.MediaCaptureFlowResult = outcome.await()

    override fun dismiss() {
        dismissCount += 1
        if (completeOnDismiss) {
            outcome.complete(com.example.mediacapture.ui.MediaCaptureFlowResult.Cancelled)
        }
    }
}
