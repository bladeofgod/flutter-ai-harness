package com.example.mediacapture.ui

import android.content.Context
import androidx.lifecycle.LifecycleOwner
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
import java.lang.reflect.Constructor
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext

internal class FakeMediaCapture(
    private val context: Context,
    private val lifecycleOwner: LifecycleOwner,
    private val dispatcher: CoroutineDispatcher,
) : MediaCapture {
    private val sessionHandle = SessionHandle("session-1")
    private val mediaHandle = MediaHandle("media-1")
    private val observation =
        MutableStateFlow(SessionObservation(SessionState.REQUESTING_PERMISSION))
    private val eventFlow = MutableSharedFlow<MediaCaptureEvent>()
    private var surfaceConstructor: Constructor<MediaCaptureRenderView>? = null

    val calls = mutableListOf<String>()
    val liveAttachGenerations = mutableListOf<Long>()
    val previewAttachGenerations = mutableListOf<Long>()
    val destroyedGenerations = mutableListOf<Long>()
    val zoomValues = mutableListOf<Double>()
    val focusPoints = mutableListOf<Pair<Double, Double>>()
    val releasedMediaHandles = mutableListOf<MediaHandle>()
    var failNextStartRecording = false
    var takePhotoGate: CompletableDeferred<Unit>? = null
    var startRecordingGate: CompletableDeferred<Unit>? = null
    var startSessionGate: CompletableDeferred<Unit>? = null
    var startSessionIgnoresCancellation = false
    var confirmGate: CompletableDeferred<Unit>? = null
    var confirmIgnoresCancellation = false
    var confirmCancelsAfterCommit = false
    private var confirmLeaseCommitted = false
    var cancelFailuresRemaining = 0
    var destroyFailuresRemaining = 0
    var releaseFailuresRemaining = 0
    var failOnBackground = false
    var createRenderViewCount = 0

    override val events: SharedFlow<MediaCaptureEvent> = eventFlow

    override suspend fun permissionState(resource: PermissionResource): PermissionState =
        PermissionState.GRANTED

    override suspend fun startSession(options: SessionOptions): SessionCreated {
        calls += "start_session"
        val gate = startSessionGate
        if (gate != null) {
            if (startSessionIgnoresCancellation) {
                withContext(NonCancellable) { gate.await() }
            } else {
                gate.await()
            }
        }
        observation.value = SessionObservation(SessionState.READY, ready())
        return SessionCreated(sessionHandle)
    }

    override suspend fun takePhoto(sessionHandle: SessionHandle): MediaPreview {
        calls += "take_photo"
        takePhotoGate?.await()
        return preview().also {
            observation.value = SessionObservation(SessionState.PREVIEWING, ready(), it)
        }
    }

    override suspend fun startRecording(sessionHandle: SessionHandle): RecordingStarted {
        calls += "start_recording"
        startRecordingGate?.await()
        if (failNextStartRecording) {
            throw MediaCaptureException(MediaCaptureFailure(FailureCode.PERMISSION_DENIED))
        }
        observation.value = SessionObservation(SessionState.RECORDING, ready())
        return RecordingStarted(sessionHandle, audioIncluded = true)
    }

    override suspend fun stopRecording(sessionHandle: SessionHandle): MediaPreview {
        calls += "stop_recording"
        return preview(MediaType.VIDEO).also {
            observation.value = SessionObservation(SessionState.PREVIEWING, ready(), it)
        }
    }

    override suspend fun switchCamera(sessionHandle: SessionHandle) {
        calls += "switch_camera"
    }

    override suspend fun setFlashMode(
        sessionHandle: SessionHandle,
        flashMode: FlashMode,
    ) {
        calls += "flash_${flashMode.name}"
    }

    override suspend fun setFocusPoint(
        sessionHandle: SessionHandle,
        normalizedX: Double,
        normalizedY: Double,
    ) {
        focusPoints += normalizedX to normalizedY
    }

    override suspend fun setZoom(
        sessionHandle: SessionHandle,
        zoomFactor: Double,
    ) {
        zoomValues += zoomFactor
    }

    override suspend fun retake(mediaHandle: MediaHandle): SessionHandle {
        calls += "retake"
        observation.value = SessionObservation(SessionState.READY, ready())
        return sessionHandle
    }

    override suspend fun confirm(mediaHandle: MediaHandle): ConfirmedMedia {
        calls += "confirm"
        if (confirmCancelsAfterCommit) confirmLeaseCommitted = true
        val gate = confirmGate
        if (gate != null) {
            if (confirmIgnoresCancellation) {
                withContext(NonCancellable) { gate.await() }
            } else {
                gate.await()
            }
        }
        if (confirmCancelsAfterCommit) throw CancellationException("committed confirm cancelled")
        return ConfirmedMedia(mediaHandle, metadata(MediaType.PHOTO), 123_456L)
    }

    override suspend fun cancel(sessionHandle: SessionHandle): SessionCancelled {
        calls += "cancel"
        if (confirmLeaseCommitted) {
            throw MediaCaptureException(MediaCaptureFailure(FailureCode.INVALID_STATE))
        }
        if (cancelFailuresRemaining > 0) {
            cancelFailuresRemaining -= 1
            throw MediaCaptureException(MediaCaptureFailure(FailureCode.SYSTEM_INTERRUPTED))
        }
        observation.value = SessionObservation(SessionState.CANCELLED, ready())
        return SessionCancelled(sessionHandle)
    }

    override suspend fun <T> withMediaRead(
        mediaHandle: MediaHandle,
        block: suspend (ScopedMediaRead) -> T,
    ): T = error("Not used by UI")

    override suspend fun releaseMedia(mediaHandle: MediaHandle): MediaReleased {
        if (releaseFailuresRemaining > 0) {
            releaseFailuresRemaining -= 1
            throw MediaCaptureException(MediaCaptureFailure(FailureCode.SYSTEM_INTERRUPTED))
        }
        confirmLeaseCommitted = false
        releasedMediaHandles += mediaHandle
        return MediaReleased(mediaHandle)
    }

    override suspend fun createRenderView(owner: MediaCaptureRenderSurfaceOwner): MediaCaptureRenderView {
        createRenderViewCount += 1
        return surfaceConstructor()
            .newInstance(
                MediaCaptureRenderSurfaceOwner(context, lifecycleOwner, owner.ownerGeneration),
                dispatcher,
                dispatcher,
            )
    }

    override suspend fun attachLivePreview(
        sessionHandle: SessionHandle,
        surface: MediaCaptureRenderView,
        ownerGeneration: Long,
    ): RenderAttachmentResult {
        liveAttachGenerations += ownerGeneration
        return RenderAttachmentResult(AttachmentKind.LIVE_PREVIEW, ownerGeneration)
    }

    override suspend fun detachLivePreview(
        sessionHandle: SessionHandle,
        surface: MediaCaptureRenderView,
        ownerGeneration: Long,
    ): RenderAttachmentResult = RenderAttachmentResult(AttachmentKind.LIVE_PREVIEW, ownerGeneration)

    override suspend fun attachUnconfirmedPreview(
        mediaHandle: MediaHandle,
        surface: MediaCaptureRenderView,
        ownerGeneration: Long,
    ): RenderAttachmentResult {
        previewAttachGenerations += ownerGeneration
        return RenderAttachmentResult(AttachmentKind.UNCONFIRMED_PREVIEW, ownerGeneration)
    }

    override suspend fun detachUnconfirmedPreview(
        mediaHandle: MediaHandle,
        surface: MediaCaptureRenderView,
        ownerGeneration: Long,
    ): RenderAttachmentResult = RenderAttachmentResult(AttachmentKind.UNCONFIRMED_PREVIEW, ownerGeneration)

    override suspend fun readMediaThumbnail(
        mediaHandle: MediaHandle,
        maxPixelEdge: Int,
    ): ThumbnailRead =
        object : ThumbnailRead {
            override suspend fun await(): MediaThumbnail =
                MediaThumbnail(mediaHandle, ByteArray(1), 1, 1, MediaType.PHOTO, null)

            override suspend fun cancel() = Unit
        }

    override suspend fun sessionState(sessionHandle: SessionHandle): SessionState =
        observation.value.state

    override suspend fun sessionObservation(sessionHandle: SessionHandle): StateFlow<SessionObservation> =
        observation

    override suspend fun mediaState(mediaHandle: MediaHandle): MediaState = MediaState.PREVIEW

    override suspend fun onDisplayRotationChanged() {
        calls += "rotation"
    }

    override suspend fun onAppBackgrounded() {
        calls += "background"
        if (failOnBackground) {
            throw MediaCaptureException(MediaCaptureFailure(FailureCode.SYSTEM_INTERRUPTED))
        }
    }

    override suspend fun onPreviewOwnerDestroyed(surface: MediaCaptureRenderView) {
        if (destroyFailuresRemaining > 0) {
            destroyFailuresRemaining -= 1
            throw MediaCaptureException(MediaCaptureFailure(FailureCode.SYSTEM_INTERRUPTED))
        }
        destroyedGenerations += surface.ownerGenerationForTest()
    }

    override suspend fun onAppRestarted() {
        calls += "restart"
    }

    override suspend fun close() {
        calls += "close"
    }

    fun emitAutoStopPreview() {
        observation.value = SessionObservation(SessionState.PREVIEWING, ready(), preview(MediaType.VIDEO))
    }

    fun emitFailure(code: FailureCode) {
        observation.value = SessionObservation(SessionState.FAILED, ready(), terminalFailure = MediaCaptureFailure(code))
    }

    private fun ready(): SessionReady =
        SessionReady(
            sessionHandle = sessionHandle,
            activeCamera = CameraPosition.REAR,
            availableCameras = setOf(CameraPosition.REAR, CameraPosition.FRONT),
            switchCameraSupported = true,
            supportedFlashModes = setOf(FlashMode.OFF, FlashMode.ON, FlashMode.AUTO),
            focusPointSupported = true,
            minZoomFactor = 1.0,
            maxZoomFactor = 4.0,
        )

    private fun preview(type: MediaType = MediaType.PHOTO): MediaPreview =
        MediaPreview(mediaHandle, metadata(type))

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

    @Suppress("UNCHECKED_CAST")
    private fun surfaceConstructor(): Constructor<MediaCaptureRenderView> {
        surfaceConstructor?.let { return it }
        val constructor =
            MediaCaptureRenderView::class.java.declaredConstructors.single {
                it.parameterTypes.size == 3
            } as Constructor<MediaCaptureRenderView>
        constructor.isAccessible = true
        surfaceConstructor = constructor
        return constructor
    }
}

private fun MediaCaptureRenderView.ownerGenerationForTest(): Long {
    val field = MediaCaptureRenderView::class.java.getDeclaredField("ownerGeneration")
    field.isAccessible = true
    return field.getLong(this)
}
