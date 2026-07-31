package com.example.mediacapture.framework

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.FocusMeteringAction
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.core.SurfaceOrientedMeteringPointFactory
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.core.content.ContextCompat
import androidx.exifinterface.media.ExifInterface
import androidx.lifecycle.LifecycleOwner
import com.example.mediacapture.api.CameraPosition
import com.example.mediacapture.api.FailureCode
import com.example.mediacapture.api.FlashMode
import com.example.mediacapture.api.MediaMetadata
import com.example.mediacapture.api.MediaType
import com.example.mediacapture.api.PermissionResource
import com.example.mediacapture.api.PermissionState
import com.example.mediacapture.api.SessionOptions
import com.example.mediacapture.rendering.AndroidRenderSource
import com.example.mediacapture.rendering.MediaCaptureRenderBinding
import com.example.mediacapture.rendering.MediaCaptureRenderMountEndpoint
import com.example.mediacapture.rendering.MediaCaptureRenderMutationGate
import com.google.common.util.concurrent.ListenableFuture
import java.io.File
import java.util.Collections
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executor
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext

/** Activity/Fragment permission APIs stay outside Core and are injected through this narrow delegate. */
interface AndroidPermissionDelegate {
    suspend fun currentState(resource: PermissionResource): PermissionState

    suspend fun request(resource: PermissionResource): PermissionState
}

internal class AndroidPermissionGateway(
    private val delegate: AndroidPermissionDelegate,
) : PermissionGateway {
    override suspend fun currentState(resource: PermissionResource): PermissionState =
        delegate.currentState(resource)

    override suspend fun request(resource: PermissionResource): PermissionState = delegate.request(resource)
}

/**
 * CameraX implementation of the capture SPI. CameraX objects remain private to this class and its
 * module-internal render source.
 */
internal class CameraXCaptureFramework(
    context: Context,
    private val lifecycleOwner: LifecycleOwner,
    private val fileStore: AndroidPrivateMediaStore,
    private val mainDispatcher: CoroutineDispatcher,
    private val ioDispatcher: CoroutineDispatcher,
    private val cleanupScope: CoroutineScope,
) : CaptureFramework {
    private val appContext = context.applicationContext
    private val mainExecutor: Executor = ContextCompat.getMainExecutor(appContext)
    private var provider: ProcessCameraProvider? = null
    private var camera: Camera? = null
    private var preview: Preview? = null
    private var imageCapture: ImageCapture? = null
    private var videoCapture: VideoCapture<Recorder>? = null
    private var selectedCamera = CameraPosition.REAR
    private var recording: Recording? = null
    private var recordingResult: CompletableDeferred<Unit>? = null
    private var recordingGuard: CameraXMediaHandoffGuard? = null
    private var lastVideo: CapturedMedia? = null
    private val pendingCleanupReferences: MutableSet<StoredMediaReference> =
        Collections.newSetFromMap(ConcurrentHashMap())

    override suspend fun prepare(options: SessionOptions): PreparedCapture {
        return try {
            val cameraProvider =
                provider ?: ProcessCameraProvider.getInstance(appContext).await().also { provider = it }
            withContext(mainDispatcher) {
                selectedCamera = selectAvailableCamera(cameraProvider, options.preferredCamera)
                bind(cameraProvider, selectedCamera)
            }
        } catch (exception: CancellationException) {
            throw exception
        } catch (exception: FrameworkException) {
            throw exception
        } catch (exception: Exception) {
            throw mapAndroidFrameworkFailure(exception, FailureCode.RESOURCE_IN_USE)
        }
    }

    override suspend fun takePhoto(): CapturedMedia {
        val capture = imageCapture ?: frameworkFailure(FailureCode.INVALID_STATE)
        val stored = withContext(ioDispatcher) { fileStore.allocate("jpg", "image/jpeg") }
        val ownership =
            CameraXMediaHandoffGuard(
                stored,
                fileStore,
                cleanupScope,
                pendingCleanupReferences,
            )
        try {
            val output = ImageCapture.OutputFileOptions.Builder(stored.file).build()
            withContext(mainDispatcher) {
                suspendCancellableCoroutine<Unit> { continuation ->
                    capture.takePicture(
                        output,
                        mainExecutor,
                        object : ImageCapture.OnImageSavedCallback {
                            override fun onImageSaved(outputFileResults: ImageCapture.OutputFileResults) {
                                if (continuation.isActive) {
                                    continuation.resume(Unit)
                                } else {
                                    ownership.cleanupAsync()
                                }
                            }

                            override fun onError(exception: ImageCaptureException) {
                                if (continuation.isActive) {
                                    continuation.resumeWithException(
                                        mapAndroidFrameworkFailure(
                                            exception,
                                            mapImageCaptureFailure(exception),
                                        ),
                                    )
                                } else {
                                    ownership.cleanupAsync()
                                }
                            }
                        },
                    )
                }
            }
            return withContext(ioDispatcher) {
                AndroidPhotoMetadataSanitizer.sanitize(stored.file)
                ownership.transfer(CapturedMedia(stored, photoMetadata(stored.file)))
            }
        } catch (exception: CancellationException) {
            withContext(NonCancellable) { ownership.cleanupNow() }
            throw exception
        } catch (exception: FrameworkException) {
            withContext(NonCancellable) { ownership.cleanupNow() }
            throw exception
        } catch (exception: Exception) {
            withContext(NonCancellable) { ownership.cleanupNow() }
            throw mapAndroidFrameworkFailure(exception, FailureCode.ENCODING_FAILED)
        }
    }

    @SuppressLint("MissingPermission")
    override suspend fun startRecording(audioEnabled: Boolean, maxDurationMillis: Long) {
        if (recording != null) frameworkFailure(FailureCode.INVALID_STATE)
        lastVideo = null
        recordingResult = null
        recordingGuard = null
        val capture = videoCapture ?: frameworkFailure(FailureCode.INVALID_STATE)
        val stored = withContext(ioDispatcher) { fileStore.allocate("mp4", "video/mp4") }
        val ownership =
            CameraXMediaHandoffGuard(
                stored,
                fileStore,
                cleanupScope,
                pendingCleanupReferences,
            )
        val pending =
            try {
                val output =
                    FileOutputOptions.Builder(stored.file)
                        .setDurationLimitMillis(maxDurationMillis)
                        .build()
                capture.output.prepareRecording(appContext, output).let { recording ->
                    if (audioEnabled) recording.withAudioEnabled() else recording
                }
            } catch (exception: FrameworkException) {
                withContext(NonCancellable) { ownership.cleanupNow() }
                throw exception
            } catch (exception: Exception) {
                withContext(NonCancellable) { ownership.cleanupNow() }
                throw mapAndroidFrameworkFailure(exception, FailureCode.ENCODING_FAILED)
            }
        val started = CompletableDeferred<Unit>()
        val finalized = CompletableDeferred<Unit>()
        recordingGuard = ownership
        recordingResult = finalized
        try {
            withContext(mainDispatcher) {
                recording =
                    pending.start(mainExecutor) { event ->
                        when (event) {
                            is VideoRecordEvent.Start -> started.complete(Unit)
                            is VideoRecordEvent.Finalize -> {
                                recording = null
                                if (event.hasError()) {
                                    ownership.cleanupAsync()
                                    val failure = FrameworkException(mapVideoFailure(event.error))
                                    started.completeExceptionally(failure)
                                    finalized.completeExceptionally(failure)
                                } else {
                                    finalized.complete(Unit)
                                }
                            }
                        }
                    }
            }
        } catch (exception: CancellationException) {
            withContext(NonCancellable) { ownership.cleanupNow() }
            clearRecordingOwnership()
            throw exception
        } catch (exception: SecurityException) {
            withContext(NonCancellable) { ownership.cleanupNow() }
            clearRecordingOwnership()
            frameworkFailure(FailureCode.PERMISSION_DENIED)
        } catch (_: IllegalStateException) {
            withContext(NonCancellable) { ownership.cleanupNow() }
            clearRecordingOwnership()
            frameworkFailure(FailureCode.RESOURCE_IN_USE)
        } catch (exception: Exception) {
            withContext(NonCancellable) { ownership.cleanupNow() }
            clearRecordingOwnership()
            throw mapAndroidFrameworkFailure(exception, FailureCode.ENCODING_FAILED)
        }
        try {
            started.await()
        } catch (exception: CancellationException) {
            withContext(NonCancellable) { cancelRecording() }
            throw exception
        }
    }

    override suspend fun stopRecording(): CapturedMedia {
        lastVideo?.let { return it }
        try {
            val active = recording
            val result = recordingResult ?: frameworkFailure(FailureCode.INVALID_STATE)
            val ownership = recordingGuard ?: frameworkFailure(FailureCode.INVALID_STATE)
            val stored = ownership.stored
            if (active != null) withContext(mainDispatcher) { active.stop() }
            result.await()
            return withContext(ioDispatcher) {
                ownership.transfer(CapturedMedia(stored, videoMetadata(stored.file))).also {
                    lastVideo = it
                    recordingGuard = null
                }
            }
        } catch (exception: CancellationException) {
            withContext(NonCancellable) { cleanupRecordingOwnership() }
            throw exception
        } catch (exception: FrameworkException) {
            withContext(NonCancellable) { cleanupRecordingOwnership() }
            throw exception
        } catch (exception: Exception) {
            withContext(NonCancellable) { cleanupRecordingOwnership() }
            throw mapAndroidFrameworkFailure(exception, FailureCode.ENCODING_FAILED)
        }
    }

    override suspend fun switchCamera(): PreparedCapture {
        try {
            if (recording != null) frameworkFailure(FailureCode.INVALID_STATE)
            val cameraProvider = provider ?: frameworkFailure(FailureCode.INVALID_STATE)
            val next =
                when (selectedCamera) {
                    CameraPosition.REAR -> CameraPosition.FRONT
                    CameraPosition.FRONT -> CameraPosition.REAR
                }
            if (!cameraProvider.hasCamera(next.selector)) {
                frameworkFailure(FailureCode.UNSUPPORTED_CAPABILITY)
            }
            selectedCamera = next
            return withContext(mainDispatcher) { bind(cameraProvider, next) }
        } catch (exception: CancellationException) {
            throw exception
        } catch (exception: FrameworkException) {
            throw exception
        } catch (exception: Exception) {
            throw mapAndroidFrameworkFailure(exception, FailureCode.SYSTEM_INTERRUPTED)
        }
    }

    override suspend fun setFlashMode(flashMode: FlashMode) {
        val capture = imageCapture ?: frameworkFailure(FailureCode.INVALID_STATE)
        val activeCamera = camera ?: frameworkFailure(FailureCode.INVALID_STATE)
        cameraCall(FailureCode.SYSTEM_INTERRUPTED) {
            withContext(mainDispatcher) {
                when (flashMode) {
                    FlashMode.OFF -> {
                        activeCamera.cameraControl.enableTorch(false).await()
                        capture.flashMode = ImageCapture.FLASH_MODE_OFF
                    }
                    FlashMode.ON -> {
                        activeCamera.cameraControl.enableTorch(false).await()
                        capture.flashMode = ImageCapture.FLASH_MODE_ON
                    }
                    FlashMode.AUTO -> {
                        activeCamera.cameraControl.enableTorch(false).await()
                        capture.flashMode = ImageCapture.FLASH_MODE_AUTO
                    }
                    FlashMode.TORCH -> activeCamera.cameraControl.enableTorch(true).await()
                }
            }
        }
    }

    override suspend fun setFocusPoint(normalizedX: Double, normalizedY: Double) {
        val activeCamera = camera ?: frameworkFailure(FailureCode.INVALID_STATE)
        val point = SurfaceOrientedMeteringPointFactory(1f, 1f).createPoint(
            normalizedX.toFloat(),
            normalizedY.toFloat(),
        )
        cameraCall(FailureCode.SYSTEM_INTERRUPTED) {
            withContext(mainDispatcher) {
                activeCamera.cameraControl.startFocusAndMetering(FocusMeteringAction.Builder(point).build()).await()
            }
        }
    }

    override suspend fun setZoom(zoomFactor: Double) {
        val activeCamera = camera ?: frameworkFailure(FailureCode.INVALID_STATE)
        cameraCall(FailureCode.SYSTEM_INTERRUPTED) {
            withContext(mainDispatcher) {
                activeCamera.cameraControl.setZoomRatio(zoomFactor.toFloat()).await()
            }
        }
    }

    override suspend fun previewRenderSource(
        reference: StoredMediaReference,
        metadata: MediaMetadata,
    ): AndroidRenderSource = StoredMediaRenderSource(reference.requireCameraXStoredMedia(), metadata)

    override suspend fun cancelRecording() {
        val hasUnclaimedOutput = lastVideo == null && recordingGuard != null
        withContext(mainDispatcher) { recording?.close() }
        recording = null
        if (hasUnclaimedOutput) recordingResult?.cancel()
        recordingResult = null
        if (hasUnclaimedOutput) cleanupRecordingOwnership()
        recordingGuard = null
        lastVideo = null
    }

    override suspend fun close() {
        cancelRecording()
        withContext(mainDispatcher) { provider?.unbindAll() }
        camera = null
        preview = null
        imageCapture = null
        videoCapture = null
    }

    override suspend fun drainPendingCleanupReferences(): List<StoredMediaReference> =
        pendingCleanupReferences.toList().also { drained ->
            drained.forEach(pendingCleanupReferences::remove)
        }

    private suspend fun cleanupRecordingOwnership() {
        recordingGuard?.cleanupNow()
        recordingGuard = null
    }

    private fun clearRecordingOwnership() {
        recordingGuard = null
        recordingResult = null
        recording = null
    }

    private fun bind(
        cameraProvider: ProcessCameraProvider,
        position: CameraPosition,
    ): PreparedCapture {
        val nextPreview = preview ?: Preview.Builder().build()
        val nextImageCapture = ImageCapture.Builder().build()
        val nextVideoCapture = VideoCapture.withOutput(Recorder.Builder().build())
        cameraProvider.unbindAll()
        val nextCamera =
            try {
                cameraProvider.bindToLifecycle(
                    lifecycleOwner,
                    position.selector,
                    nextPreview,
                    nextImageCapture,
                    nextVideoCapture,
                )
            } catch (_: IllegalArgumentException) {
                frameworkFailure(FailureCode.UNSUPPORTED_CAPABILITY)
            } catch (_: IllegalStateException) {
                frameworkFailure(FailureCode.RESOURCE_IN_USE)
            }
        camera = nextCamera
        preview = nextPreview
        imageCapture = nextImageCapture
        videoCapture = nextVideoCapture
        val available =
            CameraPosition.entries.filterTo(linkedSetOf()) { cameraProvider.hasCamera(it.selector) }
        val flashModes =
            if (nextCamera.cameraInfo.hasFlashUnit()) {
                setOf(FlashMode.OFF, FlashMode.ON, FlashMode.AUTO, FlashMode.TORCH)
            } else {
                setOf(FlashMode.OFF)
            }
        val zoomState = nextCamera.cameraInfo.zoomState.value
        return PreparedCapture(
            activeCamera = position,
            availableCameras = available,
            supportedFlashModes = flashModes,
            focusPointSupported = true,
            minZoomFactor = zoomState?.minZoomRatio?.toDouble() ?: 1.0,
            maxZoomFactor = zoomState?.maxZoomRatio?.toDouble() ?: 1.0,
            liveRenderSource = CameraXRenderSource(nextPreview),
        )
    }

    private fun selectAvailableCamera(
        cameraProvider: ProcessCameraProvider,
        preferred: CameraPosition,
    ): CameraPosition {
        if (cameraProvider.hasCamera(preferred.selector)) return preferred
        return CameraPosition.entries.firstOrNull { cameraProvider.hasCamera(it.selector) }
            ?: frameworkFailure(FailureCode.UNSUPPORTED_CAPABILITY)
    }

    private fun photoMetadata(file: File): MediaMetadata {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0 || file.length() <= 0) {
            frameworkFailure(FailureCode.ENCODING_FAILED)
        }
        val rotation = ExifInterface(file).rotationDegrees
        return MediaMetadata(
            mediaType = MediaType.PHOTO,
            pixelWidth = bounds.outWidth,
            pixelHeight = bounds.outHeight,
            durationMillis = null,
            orientationDegrees = rotation,
            byteLength = file.length(),
            contentType = "image/jpeg",
        )
    }

    private fun videoMetadata(file: File): MediaMetadata {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(file.absolutePath)
            val width = retriever.intMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
            val height = retriever.intMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
            val duration = retriever.longMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
            val rotation = retriever.intMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
            if (width <= 0 || height <= 0 || duration !in 1L..60_000L || file.length() <= 0) {
                frameworkFailure(FailureCode.ENCODING_FAILED)
            }
            return MediaMetadata(
                mediaType = MediaType.VIDEO,
                pixelWidth = width,
                pixelHeight = height,
                durationMillis = duration,
                orientationDegrees = rotation,
                byteLength = file.length(),
                contentType = "video/mp4",
            )
        } finally {
            retriever.release()
        }
    }

    private fun MediaMetadataRetriever.intMetadata(key: Int): Int =
        extractMetadata(key)?.toIntOrNull() ?: -1

    private fun MediaMetadataRetriever.longMetadata(key: Int): Long =
        extractMetadata(key)?.toLongOrNull() ?: -1L
}

internal class CameraXMediaHandoffGuard(
    val stored: AndroidStoredMedia,
    private val fileStore: MediaFileStore,
    private val cleanupScope: CoroutineScope,
    private val pendingCleanupReferences: MutableSet<StoredMediaReference>,
) {
    private val transferred = AtomicBoolean(false)

    fun transfer(media: CapturedMedia): CapturedMedia {
        check(transferred.compareAndSet(false, true))
        pendingCleanupReferences.remove(stored)
        return media
    }

    suspend fun cleanupNow() {
        withContext(NonCancellable) {
            if (transferred.get()) return@withContext
            pendingCleanupReferences += stored
            val deleted =
                runCatching {
                    fileStore.revokeReads(stored)
                    fileStore.delete(stored)
                }.getOrDefault(false)
            if (deleted) {
                pendingCleanupReferences.remove(stored)
            } else {
                pendingCleanupReferences += stored
            }
        }
    }

    fun cleanupAsync() {
        if (transferred.get()) return
        pendingCleanupReferences += stored
        cleanupScope.launch { cleanupNow() }
    }
}

internal data class CameraXRenderSource(val cameraPreview: Preview) : AndroidRenderSource {
    override suspend fun mount(
        binding: MediaCaptureRenderBinding,
        endpoint: MediaCaptureRenderMountEndpoint,
        mutationGate: MediaCaptureRenderMutationGate,
    ) {
        endpoint.mountLive(binding, cameraPreview, mutationGate)
    }
}

internal data class StoredMediaRenderSource(
    val storedMedia: AndroidStoredMedia,
    val metadata: MediaMetadata,
) : AndroidRenderSource {
    override suspend fun mount(
        binding: MediaCaptureRenderBinding,
        endpoint: MediaCaptureRenderMountEndpoint,
        mutationGate: MediaCaptureRenderMutationGate,
    ) {
        when (storedMedia.storedContentType) {
            "image/jpeg" ->
                endpoint.mountPhoto(
                    binding,
                    storedMedia.file,
                    metadata.orientationDegrees,
                    mutationGate,
                )
            "video/mp4" -> endpoint.mountVideo(binding, storedMedia.file, mutationGate)
            else -> frameworkFailure(FailureCode.ENCODING_FAILED)
        }
    }
}

private val CameraPosition.selector: CameraSelector
    get() =
        when (this) {
            CameraPosition.REAR -> CameraSelector.DEFAULT_BACK_CAMERA
            CameraPosition.FRONT -> CameraSelector.DEFAULT_FRONT_CAMERA
        }

private fun StoredMediaReference.requireCameraXStoredMedia(): AndroidStoredMedia =
    this as? AndroidStoredMedia ?: frameworkFailure(FailureCode.MEDIA_INVALID)

private fun mapImageCaptureFailure(exception: ImageCaptureException): FailureCode =
    when (exception.imageCaptureError) {
        ImageCapture.ERROR_FILE_IO -> FailureCode.STORAGE_FULL
        ImageCapture.ERROR_CAMERA_CLOSED -> FailureCode.SYSTEM_INTERRUPTED
        ImageCapture.ERROR_CAPTURE_FAILED -> FailureCode.ENCODING_FAILED
        else -> FailureCode.ENCODING_FAILED
    }

private fun mapVideoFailure(error: Int): FailureCode =
    when (error) {
        VideoRecordEvent.Finalize.ERROR_INSUFFICIENT_STORAGE -> FailureCode.STORAGE_FULL
        VideoRecordEvent.Finalize.ERROR_SOURCE_INACTIVE,
        VideoRecordEvent.Finalize.ERROR_RECORDING_GARBAGE_COLLECTED,
        -> FailureCode.SYSTEM_INTERRUPTED
        else -> FailureCode.ENCODING_FAILED
    }

private suspend fun <T> ListenableFuture<T>.await(): T =
    suspendCancellableCoroutine { continuation ->
        addListener(
            {
                try {
                    continuation.resume(get())
                } catch (exception: Exception) {
                    continuation.resumeWithException(
                        mapAndroidFrameworkFailure(exception, FailureCode.SYSTEM_INTERRUPTED),
                    )
                }
            },
            Runnable::run,
        )
        continuation.invokeOnCancellation { cancel(true) }
    }

private fun frameworkFailure(code: FailureCode): Nothing = throw FrameworkException(code)

private suspend fun <T> cameraCall(
    fallback: FailureCode,
    block: suspend () -> T,
): T =
    try {
        block()
    } catch (exception: CancellationException) {
        throw exception
    } catch (exception: FrameworkException) {
        throw exception
    } catch (exception: Throwable) {
        throw mapAndroidFrameworkFailure(exception, fallback)
    }

internal fun mapAndroidFrameworkFailure(
    throwable: Throwable,
    fallback: FailureCode,
): FrameworkException {
    var current: Throwable? = throwable
    while (current != null) {
        if (current is SecurityException) return FrameworkException(FailureCode.PERMISSION_DENIED)
        current = current.cause
    }
    return FrameworkException(fallback)
}
