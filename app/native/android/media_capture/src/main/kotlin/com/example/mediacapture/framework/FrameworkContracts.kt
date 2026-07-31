package com.example.mediacapture.framework

import com.example.mediacapture.api.CameraPosition
import com.example.mediacapture.api.FailureCode
import com.example.mediacapture.api.FlashMode
import com.example.mediacapture.api.MediaMetadata
import com.example.mediacapture.api.PermissionResource
import com.example.mediacapture.api.PermissionState
import com.example.mediacapture.api.ScopedMediaRead
import com.example.mediacapture.api.SessionOptions
import com.example.mediacapture.rendering.AndroidRenderSource

internal fun interface MediaCaptureClock {
    fun nowEpochMillis(): Long
}

internal fun interface OpaqueHandleGenerator {
    fun nextHandle(): String
}

internal interface PermissionGateway {
    suspend fun currentState(resource: PermissionResource): PermissionState

    suspend fun request(resource: PermissionResource): PermissionState
}

/** Opaque module-owned storage reference. It intentionally has no path or URI API. */
internal interface StoredMediaReference

internal data class CapturedMedia(
    val reference: StoredMediaReference,
    val metadata: MediaMetadata,
)

internal data class PreparedCapture(
    val activeCamera: CameraPosition,
    val availableCameras: Set<CameraPosition>,
    val supportedFlashModes: Set<FlashMode>,
    val focusPointSupported: Boolean,
    val minZoomFactor: Double,
    val maxZoomFactor: Double,
    val liveRenderSource: AndroidRenderSource,
)

/** Narrow module-internal CameraX boundary with no Flutter, Wire, path, or URI type. */
internal interface CaptureFramework {
    suspend fun prepare(options: SessionOptions): PreparedCapture

    suspend fun takePhoto(): CapturedMedia

    suspend fun startRecording(audioEnabled: Boolean, maxDurationMillis: Long)

    suspend fun stopRecording(): CapturedMedia

    suspend fun switchCamera(): PreparedCapture

    suspend fun setFlashMode(flashMode: FlashMode)

    suspend fun setFocusPoint(normalizedX: Double, normalizedY: Double)

    suspend fun setZoom(zoomFactor: Double)

    suspend fun previewRenderSource(
        reference: StoredMediaReference,
        metadata: MediaMetadata,
    ): AndroidRenderSource

    suspend fun cancelRecording()

    suspend fun close()

    /** Transfers failed pre-handoff cleanup back to Core for deterministic retry. */
    suspend fun drainPendingCleanupReferences(): List<StoredMediaReference> = emptyList()
}

internal interface MediaFileStore {
    suspend fun cleanupRestartResidue()

    suspend fun delete(reference: StoredMediaReference): Boolean

    suspend fun openRead(
        reference: StoredMediaReference,
        byteLength: Long,
        contentType: String,
    ): ScopedMediaRead

    suspend fun openStreamingRead(
        reference: StoredMediaReference,
        byteLength: Long,
        contentType: String,
    ): StreamingMediaRead

    suspend fun revokeReads(reference: StoredMediaReference)
}

internal interface StreamingMediaRead {
    val byteLength: Long
    val contentType: String

    suspend fun read(buffer: ByteArray): Int

    suspend fun close()
}

internal data class ThumbnailGenerationRequest(
    val maxPixelEdge: Int,
    val maxDecodedPixels: Int = 1_048_576,
    val maxWorkingBytes: Long = 8_388_608,
    val videoTargetFrameMillis: Long?,
)

internal data class ThumbnailArtifact(
    val encodedJpeg: ByteArray,
    val pixelWidth: Int,
    val pixelHeight: Int,
    val orientationDegrees: Int,
    val actualPosterFrameMillis: Long?,
)

internal interface ThumbnailGenerationWork {
    suspend fun generate(): ThumbnailArtifact

    suspend fun revokeSourceAccess()

    suspend fun cancelAndAwaitDecoder()

    suspend fun closeSourceHandles()

    fun wipeDecodedPixels()

    fun wipeGenerationBuffer()

    fun discardPartialCopy()

    suspend fun closeSourceAccess()

    suspend fun finishAndCloseDecoder()
}

internal interface ThumbnailGenerator {
    suspend fun open(
        reference: StoredMediaReference,
        metadata: MediaMetadata,
        request: ThumbnailGenerationRequest,
    ): ThumbnailGenerationWork
}

internal class FrameworkException(
    val failureCode: FailureCode,
    cause: Throwable? = null,
) : Exception(failureCode.wireValue, cause)
