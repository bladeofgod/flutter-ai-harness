package com.example.mediacapture

import com.example.mediacapture.api.CameraPosition
import com.example.mediacapture.api.FlashMode
import com.example.mediacapture.api.MediaMetadata
import com.example.mediacapture.api.MediaType
import com.example.mediacapture.api.PermissionResource
import com.example.mediacapture.api.PermissionState
import com.example.mediacapture.api.ScopedMediaRead
import com.example.mediacapture.api.SessionOptions
import com.example.mediacapture.framework.CaptureFramework
import com.example.mediacapture.framework.CapturedMedia
import com.example.mediacapture.framework.MediaCaptureClock
import com.example.mediacapture.framework.MediaFileStore
import com.example.mediacapture.framework.OpaqueHandleGenerator
import com.example.mediacapture.framework.PermissionGateway
import com.example.mediacapture.framework.PreparedCapture
import com.example.mediacapture.framework.StoredMediaReference
import com.example.mediacapture.framework.StreamingMediaRead
import com.example.mediacapture.framework.ThumbnailArtifact
import com.example.mediacapture.framework.ThumbnailGenerationRequest
import com.example.mediacapture.framework.ThumbnailGenerationWork
import com.example.mediacapture.framework.ThumbnailGenerator
import com.example.mediacapture.rendering.AndroidRenderSource
import com.example.mediacapture.rendering.AndroidRenderTargetAdapter
import com.example.mediacapture.rendering.MediaCaptureRenderBinding
import com.example.mediacapture.rendering.MediaCaptureRenderMountEndpoint
import com.example.mediacapture.rendering.MediaCaptureRenderMutationGate
import java.util.ArrayDeque
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext

internal class FakeClock(var now: Long = 1_000L) : MediaCaptureClock {
    override fun nowEpochMillis(): Long = now
}

internal class SequenceHandles : OpaqueHandleGenerator {
    private var next = 0
    var fixed: String? = null

    override fun nextHandle(): String = fixed ?: "harness-handle-${next++}-0123456789abcdef"
}

internal class FakePermissions : PermissionGateway {
    val states = mutableMapOf(
        PermissionResource.CAMERA to PermissionState.GRANTED,
        PermissionResource.MICROPHONE to PermissionState.GRANTED,
    )
    val requestResults = mutableMapOf<PermissionResource, PermissionState>()
    val requests = mutableListOf<PermissionResource>()

    override suspend fun currentState(resource: PermissionResource): PermissionState =
        states.getValue(resource)

    override suspend fun request(resource: PermissionResource): PermissionState {
        requests += resource
        return requestResults[resource] ?: states.getValue(resource)
    }
}

internal data class FakeStoredMedia(val id: Int) : StoredMediaReference

internal object FakeRenderSource : AndroidRenderSource {
    override suspend fun mount(
        binding: MediaCaptureRenderBinding,
        endpoint: MediaCaptureRenderMountEndpoint,
        mutationGate: MediaCaptureRenderMutationGate,
    ) = Unit
}

internal class FakeRenderAdapter : AndroidRenderTargetAdapter {
    var attachCount = 0
    var commitCount = 0
    var revokeCount = 0
    var detachCount = 0
    var activeGuard: (() -> Boolean)? = null
    var onAttach: (suspend () -> Unit)? = null
    var onCommit: (suspend () -> Unit)? = null
    var onRevoke: (suspend () -> Unit)? = null
    var onDetach: (suspend () -> Unit)? = null
    var throwOnAttach = false
    var throwOnRevoke = false
    var throwOnDetach = false

    override suspend fun attach(
        binding: MediaCaptureRenderBinding,
        source: AndroidRenderSource,
        mutationGate: MediaCaptureRenderMutationGate,
    ) {
        attachCount++
        activeGuard = mutationGate::isCallbackActive
        onAttach?.invoke()
        if (throwOnAttach) error("attach failure")
    }

    override suspend fun revokeCallbacks(binding: MediaCaptureRenderBinding) {
        revokeCount++
        onRevoke?.invoke()
        if (throwOnRevoke) error("revoke failure")
    }

    override suspend fun commitCallbacks(binding: MediaCaptureRenderBinding) {
        commitCount++
        onCommit?.invoke()
    }

    override suspend fun detach(binding: MediaCaptureRenderBinding) {
        detachCount++
        onDetach?.invoke()
        if (throwOnDetach) error("detach failure")
    }
}

internal class FakeCaptureFramework : CaptureFramework {
    var prepared =
        PreparedCapture(
            activeCamera = CameraPosition.REAR,
            availableCameras = setOf(CameraPosition.REAR, CameraPosition.FRONT),
            supportedFlashModes = FlashMode.entries.toSet(),
            focusPointSupported = true,
            minZoomFactor = 1.0,
            maxZoomFactor = 4.0,
            liveRenderSource = FakeRenderSource,
        )
    var prepareCount = 0
    var prepareGate: CompletableDeferred<Unit>? = null
    var prepareIgnoresCancellation = false
    var closeCount = 0
    var closeFailure: Throwable? = null
    var cancelRecordingCount = 0
    var startRecordingCount = 0
    var stopRecordingCount = 0
    var controlCount = 0
    var recording = false
    var photoIndex = 0
    var videoIndex = 100
    var lastFlash: FlashMode? = null
    var lastFocus: Pair<Double, Double>? = null
    var lastZoom: Double? = null
    var lastMaxDuration: Long? = null
    var nextPhotoMetadata: MediaMetadata? = null
    var photoGate: CompletableDeferred<Unit>? = null
    var photoIgnoresCancellation = false
    var onPhotoProduced: (() -> Unit)? = null
    var startRecordingGate: CompletableDeferred<Unit>? = null
    var startRecordingIgnoresCancellation = false
    var stopRecordingGate: CompletableDeferred<Unit>? = null
    var stopRecordingIgnoresCancellation = false
    var controlGate: CompletableDeferred<Unit>? = null
    var controlIgnoresCancellation = false
    var pendingCleanupDrainGate: CompletableDeferred<Unit>? = null
    var onPendingCleanupDrain: (() -> Unit)? = null
    val pendingCleanupReferences = mutableListOf<StoredMediaReference>()
    var previewRenderSource: AndroidRenderSource = FakeRenderSource

    override suspend fun prepare(options: SessionOptions): PreparedCapture {
        prepareCount++
        awaitGate(prepareGate, prepareIgnoresCancellation)
        return prepared
    }

    override suspend fun takePhoto(): CapturedMedia {
        awaitGate(photoGate, photoIgnoresCancellation)
        val index = photoIndex++
        return CapturedMedia(FakeStoredMedia(index), nextPhotoMetadata ?: photoMetadata()).also {
            onPhotoProduced?.invoke()
        }
    }

    override suspend fun startRecording(audioEnabled: Boolean, maxDurationMillis: Long) {
        startRecordingCount++
        awaitGate(startRecordingGate, startRecordingIgnoresCancellation)
        recording = true
        lastMaxDuration = maxDurationMillis
    }

    override suspend fun stopRecording(): CapturedMedia {
        stopRecordingCount++
        awaitGate(stopRecordingGate, stopRecordingIgnoresCancellation)
        recording = false
        val index = videoIndex++
        return CapturedMedia(FakeStoredMedia(index), videoMetadata())
    }

    override suspend fun switchCamera(): PreparedCapture {
        controlCount++
        awaitGate(controlGate, controlIgnoresCancellation)
        prepared =
            prepared.copy(
                activeCamera =
                    if (prepared.activeCamera == CameraPosition.REAR) {
                        CameraPosition.FRONT
                    } else {
                        CameraPosition.REAR
                    },
            )
        return prepared
    }

    override suspend fun setFlashMode(flashMode: FlashMode) {
        controlCount++
        awaitGate(controlGate, controlIgnoresCancellation)
        lastFlash = flashMode
    }

    override suspend fun setFocusPoint(normalizedX: Double, normalizedY: Double) {
        controlCount++
        awaitGate(controlGate, controlIgnoresCancellation)
        lastFocus = normalizedX to normalizedY
    }

    override suspend fun setZoom(zoomFactor: Double) {
        controlCount++
        awaitGate(controlGate, controlIgnoresCancellation)
        lastZoom = zoomFactor
    }

    override suspend fun previewRenderSource(
        reference: StoredMediaReference,
        metadata: MediaMetadata,
    ): AndroidRenderSource = previewRenderSource

    override suspend fun cancelRecording() {
        cancelRecordingCount++
        recording = false
    }

    override suspend fun close() {
        closeCount++
        closeFailure?.let { throw it }
    }

    override suspend fun drainPendingCleanupReferences(): List<StoredMediaReference> {
        onPendingCleanupDrain?.invoke()
        pendingCleanupDrainGate?.await()
        return pendingCleanupReferences.toList().also { pendingCleanupReferences.clear() }
    }

    private suspend fun awaitGate(gate: CompletableDeferred<Unit>?, ignoreCancellation: Boolean) {
        gate ?: return
        try {
            gate.await()
        } catch (exception: kotlinx.coroutines.CancellationException) {
            if (!ignoreCancellation) throw exception
            withContext(NonCancellable) { gate.await() }
        }
    }
}

internal class FakeFileStore : MediaFileStore {
    val deleted = mutableListOf<StoredMediaReference>()
    val revoked = mutableListOf<StoredMediaReference>()
    val streamingClosed = mutableListOf<StoredMediaReference>()
    val streamingOpened = mutableListOf<StoredMediaReference>()
    val bytes = mutableMapOf<StoredMediaReference, ByteArray>()
    val generatedStreamingLengths = mutableMapOf<StoredMediaReference, Long>()
    var residueCleanups = 0
    var deleteSucceeds = true
    var streamingReadFailureAfterReads: Int? = null
    var streamingOperationObserver: ((String) -> Unit)? = null

    override suspend fun cleanupRestartResidue() {
        residueCleanups++
    }

    override suspend fun delete(reference: StoredMediaReference): Boolean {
        deleted += reference
        return deleteSucceeds
    }

    override suspend fun openRead(
        reference: StoredMediaReference,
        byteLength: Long,
        contentType: String,
    ): ScopedMediaRead = FakeRead(byteLength, contentType)

    override suspend fun openStreamingRead(
        reference: StoredMediaReference,
        byteLength: Long,
        contentType: String,
    ): StreamingMediaRead {
        streamingOperationObserver?.invoke("open")
        streamingOpened += reference
        generatedStreamingLengths[reference]?.let { generatedLength ->
            return FakeGeneratedStreamingRead(
                reference = reference,
                byteLength = generatedLength,
                contentType = contentType,
                operationObserver = streamingOperationObserver,
                onClose = { streamingClosed += it },
            )
        }
        val sourceBytes =
            bytes[reference] ?: ByteArray(byteLength.toInt()) { index ->
                (index % 251).toByte()
            }
        return FakeStreamingRead(
            reference = reference,
            sourceBytes = sourceBytes,
            byteLength = byteLength,
            contentType = contentType,
            failAfterReads = streamingReadFailureAfterReads,
            operationObserver = streamingOperationObserver,
            onClose = { streamingClosed += it },
        )
    }

    override suspend fun revokeReads(reference: StoredMediaReference) {
        revoked += reference
    }
}

internal class FakeGeneratedStreamingRead(
    private val reference: StoredMediaReference,
    override val byteLength: Long,
    override val contentType: String,
    private val operationObserver: ((String) -> Unit)?,
    private val onClose: (StoredMediaReference) -> Unit,
) : StreamingMediaRead {
    private var offset = 0L
    private var closed = false

    override suspend fun read(buffer: ByteArray): Int {
        operationObserver?.invoke("read")
        if (offset >= byteLength) return -1
        val count = minOf(buffer.size.toLong(), byteLength - offset).toInt()
        repeat(count) { index -> buffer[index] = ((offset + index) % 251).toByte() }
        offset += count
        return count
    }

    override suspend fun close() {
        operationObserver?.invoke("close")
        if (!closed) {
            closed = true
            onClose(reference)
        }
    }
}

internal class FakeStreamingRead(
    private val reference: StoredMediaReference,
    private val sourceBytes: ByteArray,
    override val byteLength: Long,
    override val contentType: String,
    private val failAfterReads: Int?,
    private val operationObserver: ((String) -> Unit)?,
    private val onClose: (StoredMediaReference) -> Unit,
) : StreamingMediaRead {
    private var offset = 0
    private var reads = 0
    var closed = false

    override suspend fun read(buffer: ByteArray): Int {
        operationObserver?.invoke("read")
        failAfterReads?.let {
            if (reads >= it) error("private source read detail")
        }
        reads++
        if (offset >= sourceBytes.size) return -1
        val count = minOf(buffer.size, sourceBytes.size - offset)
        sourceBytes.copyInto(buffer, destinationOffset = 0, startIndex = offset, endIndex = offset + count)
        offset += count
        return count
    }

    override suspend fun close() {
        operationObserver?.invoke("close")
        if (!closed) {
            closed = true
            onClose(reference)
        }
    }
}

internal class FakeRead(
    override val byteLength: Long,
    override val contentType: String,
) : ScopedMediaRead {
    var closed = false

    override suspend fun readBytes(): ByteArray = byteArrayOf(1, 2, 3)

    override suspend fun close() {
        closed = true
    }
}

internal class FakeThumbnailGenerator : ThumbnailGenerator {
    val queuedWorks = ArrayDeque<FakeThumbnailWork>()
    val opened = mutableListOf<Pair<StoredMediaReference, ThumbnailGenerationRequest>>()

    override suspend fun open(
        reference: StoredMediaReference,
        metadata: MediaMetadata,
        request: ThumbnailGenerationRequest,
    ): ThumbnailGenerationWork {
        opened += reference to request
        return if (queuedWorks.isEmpty()) FakeThumbnailWork(metadata.defaultArtifact()) else queuedWorks.removeFirst()
    }
}

internal class FakeThumbnailWork(
    val artifact: ThumbnailArtifact,
    val gate: CompletableDeferred<Unit>? = null,
    val failGeneration: Boolean = false,
    val throwAt: Set<String> = emptySet(),
) : ThumbnailGenerationWork {
    val steps = mutableListOf<String>()

    override suspend fun generate(): ThumbnailArtifact {
        steps += "generate"
        gate?.await()
        if (failGeneration) error("private decoder detail")
        return artifact
    }

    override suspend fun revokeSourceAccess() {
        steps += "revoke_source_access"
        throwIfRequested("revoke_source_access")
    }

    override suspend fun cancelAndAwaitDecoder() {
        steps += "cancel_and_await_decoder"
        throwIfRequested("cancel_and_await_decoder")
    }

    override suspend fun closeSourceHandles() {
        steps += "close_source_handles"
        throwIfRequested("close_source_handles")
    }

    override fun wipeDecodedPixels() {
        steps += "wipe_decoded_pixels"
        throwIfRequested("wipe_decoded_pixels")
    }

    override fun wipeGenerationBuffer() {
        steps += "wipe_generation_buffer"
        artifact.encodedJpeg.fill(0)
        throwIfRequested("wipe_generation_buffer")
    }

    override fun discardPartialCopy() {
        steps += "discard_partial_copy"
        throwIfRequested("discard_partial_copy")
    }

    override suspend fun closeSourceAccess() {
        steps += "close_source_access"
        throwIfRequested("close_source_access")
    }

    override suspend fun finishAndCloseDecoder() {
        steps += "finish_and_close_decoder"
        throwIfRequested("finish_and_close_decoder")
    }

    private fun throwIfRequested(step: String) {
        if (step in throwAt) error("$step failure")
    }
}

internal fun photoMetadata() =
    MediaMetadata(MediaType.PHOTO, 1600, 1200, null, 0, 20_000, "image/jpeg")

internal fun videoMetadata() =
    MediaMetadata(MediaType.VIDEO, 1920, 1080, 3_000, 0, 50_000, "video/mp4")

internal fun MediaMetadata.defaultArtifact(): ThumbnailArtifact =
    ThumbnailArtifact(
        encodedJpeg = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 0xD9.toByte()),
        pixelWidth = 128,
        pixelHeight = 96,
        orientationDegrees = 0,
        actualPosterFrameMillis = if (mediaType == MediaType.VIDEO) 1_500 else null,
    )
