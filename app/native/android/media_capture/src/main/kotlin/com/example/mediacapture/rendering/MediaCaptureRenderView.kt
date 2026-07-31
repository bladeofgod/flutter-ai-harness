package com.example.mediacapture.rendering

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.VideoView
import androidx.camera.core.Preview
import androidx.camera.view.PreviewView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import com.example.mediacapture.api.FailureCode
import com.example.mediacapture.api.MediaCaptureException
import com.example.mediacapture.api.MediaCaptureFailure
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/** Inputs required to create one fresh, module-defined render surface. */
class MediaCaptureRenderSurfaceOwner(
    context: Context,
    lifecycleOwner: LifecycleOwner,
    val ownerGeneration: Long,
) {
    internal val context: Context = context
    internal val lifecycleOwner: LifecycleOwner = lifecycleOwner
    internal val lifecycle: Lifecycle
        get() = lifecycleOwner.lifecycle
}

/**
 * Concrete surface owned by one native UI lifecycle. CameraX and media sources remain internal to
 * the module; consumers only place this outer view in their hierarchy.
 */
@SuppressLint("ViewConstructor")
class MediaCaptureRenderView private constructor(
    owner: MediaCaptureRenderSurfaceOwner,
    private val mainDispatcher: CoroutineDispatcher,
    ioDispatcher: CoroutineDispatcher,
) : FrameLayout(owner.context) {
    internal val ownerGeneration: Long = owner.ownerGeneration
    private val lifecycle = owner.lifecycle
    private val lifecyclePhaseActive =
        AtomicBoolean(lifecycle.currentState.isAtLeast(Lifecycle.State.CREATED))
    private val lifecycleDestroyed =
        AtomicBoolean(lifecycle.currentState == Lifecycle.State.DESTROYED)
    private val moduleOwner = AtomicReference<MediaCaptureRenderModuleOwner?>(null)
    private val ownerDestroyedCallback = AtomicReference<(() -> Unit)?>(null)
    private val activeMutationGate = AtomicReference<MediaCaptureRenderMutationGate?>(null)
    private val mountEndpoint =
        MediaCaptureRenderMountEndpoint(
            surface = this,
            mainDispatcher = mainDispatcher,
            ioDispatcher = ioDispatcher,
        )

    internal val renderTarget: AndroidRenderTargetAdapter =
        object : AndroidRenderTargetAdapter {
            override suspend fun attach(
                binding: MediaCaptureRenderBinding,
                source: AndroidRenderSource,
                mutationGate: MediaCaptureRenderMutationGate,
            ) {
                if (!claimMutationGate(mutationGate)) {
                    renderFailure(FailureCode.ATTACHMENT_TARGET_CONFLICT)
                }
                try {
                    source.mount(binding, mountEndpoint, mutationGate)
                } catch (exception: Throwable) {
                    releaseMutationGate(mutationGate)
                    throw exception
                }
            }

            override suspend fun commitCallbacks(binding: MediaCaptureRenderBinding) {
                mountEndpoint.commitCallbacks(binding)
            }

            override suspend fun revokeCallbacks(binding: MediaCaptureRenderBinding) {
                mountEndpoint.revokeCallbacks(binding)
            }

            override suspend fun detach(binding: MediaCaptureRenderBinding) {
                mountEndpoint.detach(binding)
            }
        }

    private val lifecycleObserver =
        object : LifecycleEventObserver {
            override fun onStateChanged(source: LifecycleOwner, event: Lifecycle.Event) {
                when (event) {
                    Lifecycle.Event.ON_CREATE -> lifecyclePhaseActive.set(true)
                    Lifecycle.Event.ON_DESTROY -> {
                        activeMutationGate.get()?.invalidate()
                        lifecyclePhaseActive.set(false)
                        if (lifecycleDestroyed.compareAndSet(false, true)) {
                            ownerDestroyedCallback.getAndSet(null)?.invoke()
                        }
                        lifecycle.removeObserver(this)
                    }
                    else -> Unit
                }
            }
        }

    init {
        lifecycle.addObserver(lifecycleObserver)
    }

    internal companion object {
        fun create(
            owner: MediaCaptureRenderSurfaceOwner,
            mainDispatcher: CoroutineDispatcher,
            ioDispatcher: CoroutineDispatcher,
        ): MediaCaptureRenderView = MediaCaptureRenderView(owner, mainDispatcher, ioDispatcher)
    }

    internal fun isLifecycleActive(): Boolean =
        lifecyclePhaseActive.get() && !lifecycleDestroyed.get()

    internal fun registerModuleOwner(owner: MediaCaptureRenderModuleOwner) {
        check(moduleOwner.compareAndSet(null, owner))
    }

    internal fun isOwnedBy(owner: MediaCaptureRenderModuleOwner): Boolean = moduleOwner.get() === owner

    private fun claimMutationGate(gate: MediaCaptureRenderMutationGate): Boolean =
        activeMutationGate.compareAndSet(null, gate)

    internal fun releaseMutationGate(gate: MediaCaptureRenderMutationGate) {
        activeMutationGate.compareAndSet(gate, null)
    }

    internal fun setOwnerDestroyedCallback(callback: () -> Unit) {
        check(ownerDestroyedCallback.compareAndSet(null, callback))
        if (lifecycleDestroyed.get() && ownerDestroyedCallback.compareAndSet(callback, null)) {
            callback.invoke()
        }
    }

    internal suspend fun abandonFactoryOutput() {
        ownerDestroyedCallback.set(null)
        activeMutationGate.getAndSet(null)?.invalidate()
        lifecyclePhaseActive.set(false)
        lifecycleDestroyed.set(true)
        withContext(mainDispatcher) { lifecycle.removeObserver(lifecycleObserver) }
    }
}

internal interface AndroidRenderSource {
    suspend fun mount(
        binding: MediaCaptureRenderBinding,
        endpoint: MediaCaptureRenderMountEndpoint,
        mutationGate: MediaCaptureRenderMutationGate,
    )
}

internal interface AndroidRenderTargetAdapter {
    suspend fun attach(
        binding: MediaCaptureRenderBinding,
        source: AndroidRenderSource,
        mutationGate: MediaCaptureRenderMutationGate,
    )

    suspend fun commitCallbacks(binding: MediaCaptureRenderBinding) {}

    suspend fun revokeCallbacks(binding: MediaCaptureRenderBinding)

    suspend fun detach(binding: MediaCaptureRenderBinding)
}

internal class MediaCaptureRenderBinding {
    private val asyncFailureHandler = AtomicReference<(() -> Unit)?>(null)

    fun setAsyncFailureHandler(handler: () -> Unit) {
        check(asyncFailureHandler.compareAndSet(null, handler))
    }

    fun reportAsyncFailure() {
        asyncFailureHandler.get()?.invoke()
    }

    fun clearAsyncFailureHandler() {
        asyncFailureHandler.set(null)
    }
}

internal class MediaCaptureRenderModuleOwner

internal class MediaCaptureRenderMutationGate {
    private val lock = ReentrantLock()
    private var active = true
    private var committed = false

    fun isInstallActive(): Boolean = lock.withLock { active }

    fun commit(): Boolean = lock.withLock {
        if (!active) return false
        committed = true
        true
    }

    fun invalidate() = lock.withLock {
        active = false
        committed = false
    }

    fun performInstall(mutation: () -> Unit): Boolean = lock.withLock {
        if (!active || committed) return false
        mutation()
        true
    }

    fun performCallback(mutation: () -> Unit): Boolean = lock.withLock {
        if (!active || !committed) return false
        mutation()
        true
    }

    fun isCallbackActive(): Boolean = lock.withLock { active && committed }
}

internal interface AndroidRenderSurfaceFactory {
    suspend fun create(owner: MediaCaptureRenderSurfaceOwner): MediaCaptureRenderView
}

internal class DefaultAndroidRenderSurfaceFactory(
    private val mainDispatcher: CoroutineDispatcher,
    private val ioDispatcher: CoroutineDispatcher,
) : AndroidRenderSurfaceFactory {
    override suspend fun create(owner: MediaCaptureRenderSurfaceOwner): MediaCaptureRenderView {
        if (owner.ownerGeneration <= 0) renderFailure(FailureCode.INVALID_ARGUMENT)
        return withContext(mainDispatcher) {
            if (!owner.lifecycle.currentState.isAtLeast(Lifecycle.State.CREATED)) {
                renderFailure(FailureCode.INVALID_STATE)
            }
            MediaCaptureRenderView.create(owner, mainDispatcher, ioDispatcher)
        }
    }
}

/** Closed module-internal endpoint for PreviewView, photo content, and video player mounting. */
internal class MediaCaptureRenderMountEndpoint(
    private val surface: MediaCaptureRenderView,
    private val mainDispatcher: CoroutineDispatcher,
    private val ioDispatcher: CoroutineDispatcher,
) {
    private val mutex = Mutex()
    private val previewView =
        PreviewView(surface.context).apply {
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
            scaleType = PreviewView.ScaleType.FILL_CENTER
            visibility = View.GONE
        }
    private val photoView =
        ImageView(surface.context).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP
            visibility = View.GONE
        }
    private var videoView = createVideoView()
    private var mounted: MountedContent? = null

    init {
        val layout =
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            )
        surface.addView(previewView, layout)
        surface.addView(photoView, layout)
        surface.addView(videoView, layout)
    }

    suspend fun mountLive(
        binding: MediaCaptureRenderBinding,
        preview: Preview,
        mutationGate: MediaCaptureRenderMutationGate,
    ) = mutex.withLock {
        ensureEmptyAndActive(binding, mutationGate)
        withContext(mainDispatcher) {
            ensureInstallMutation(mutationGate) {
                mounted = MountedContent.Live(binding, preview, mutationGate)
                showOnly(previewView)
                preview.setSurfaceProvider(previewView.surfaceProvider)
            }
        }
    }

    suspend fun mountPhoto(
        binding: MediaCaptureRenderBinding,
        source: File,
        orientationDegrees: Int,
        mutationGate: MediaCaptureRenderMutationGate,
    ) = mutex.withLock {
        ensureEmptyAndActive(binding, mutationGate)
        val targetEdge =
            withContext(mainDispatcher) {
                ensureActive(mutationGate)
                maxOf(surface.width, surface.height).takeIf { it > 0 } ?: DEFAULT_PHOTO_EDGE
            }
        val bitmap =
            withContext(ioDispatcher) {
                ensureActive(mutationGate)
                decodePhoto(source, targetEdge, orientationDegrees)
            }
        try {
            withContext(mainDispatcher) {
                ensureInstallMutation(mutationGate) {
                    mounted = MountedContent.Photo(binding, bitmap, mutationGate)
                    photoView.setImageBitmap(bitmap)
                    showOnly(photoView)
                }
            }
        } catch (exception: Throwable) {
            if (mounted?.binding !== binding) bitmap.recycle()
            throw exception
        }
    }

    suspend fun mountVideo(
        binding: MediaCaptureRenderBinding,
        source: File,
        mutationGate: MediaCaptureRenderMutationGate,
    ) = mutex.withLock {
        ensureEmptyAndActive(binding, mutationGate)
        withContext(mainDispatcher) {
            ensureInstallMutation(mutationGate) {
                val target = videoView
                mounted = MountedContent.Video(binding, target, mutationGate)
                target.setOnPreparedListener { player ->
                    runCatching {
                        mutationGate.performCallback {
                            player.isLooping = true
                            target.start()
                        }
                    }
                }
                target.setOnErrorListener { _, _, _ ->
                    if (!mutationGate.performCallback { binding.reportAsyncFailure() }) {
                        mutationGate.performInstall { binding.reportAsyncFailure() }
                    }
                    true
                }
                target.setVideoPath(source.absolutePath)
                showOnly(target)
            }
        }
    }

    suspend fun commitCallbacks(binding: MediaCaptureRenderBinding) = mutex.withLock {
        val current = mounted?.takeIf { it.binding === binding } ?: return@withLock
        if (current is MountedContent.Video) {
            withContext(mainDispatcher) {
                current.mutationGate.performCallback { current.target.start() }
            }
        }
    }

    suspend fun revokeCallbacks(binding: MediaCaptureRenderBinding) = mutex.withLock {
        val current = mounted?.takeIf { it.binding === binding } ?: return@withLock
        withContext(NonCancellable + mainDispatcher) {
            when (current) {
                is MountedContent.Live -> current.preview.setSurfaceProvider(null)
                is MountedContent.Photo -> Unit
                is MountedContent.Video -> current.target.stopPlayback()
            }
        }
    }

    suspend fun detach(binding: MediaCaptureRenderBinding) = mutex.withLock {
        val current = mounted?.takeIf { it.binding === binding } ?: return@withLock
        mounted = null
        try {
            withContext(NonCancellable + mainDispatcher) {
                if (current is MountedContent.Live) {
                    runCatching { current.preview.setSurfaceProvider(null) }
                }
                if (current is MountedContent.Video) {
                    runCatching { current.target.setOnPreparedListener(null) }
                    runCatching { current.target.setOnErrorListener(null) }
                    runCatching { current.target.stopPlayback() }
                    runCatching { current.target.setVideoURI(null) }
                    runCatching { surface.removeView(current.target) }
                    if (videoView === current.target) {
                        runCatching {
                            val replacement = createVideoView()
                            surface.addView(replacement, matchParentLayout())
                            videoView = replacement
                        }
                    }
                }
                runCatching { photoView.setImageDrawable(null) }
                runCatching { previewView.visibility = View.GONE }
                runCatching { photoView.visibility = View.GONE }
                runCatching { videoView.visibility = View.GONE }
            }
            runCatching { (current as? MountedContent.Photo)?.bitmap?.recycle() }
        } finally {
            surface.releaseMutationGate(current.mutationGate)
        }
    }

    private fun ensureEmptyAndActive(
        binding: MediaCaptureRenderBinding,
        mutationGate: MediaCaptureRenderMutationGate,
    ) {
        if (mounted?.binding !== null && mounted?.binding !== binding) {
            renderFailure(FailureCode.ATTACHMENT_TARGET_CONFLICT)
        }
        ensureActive(mutationGate)
    }

    private fun ensureActive(gate: MediaCaptureRenderMutationGate) {
        if (!gate.isInstallActive() || !surface.isLifecycleActive()) {
            renderFailure(FailureCode.INVALID_STATE)
        }
    }

    private fun ensureInstallMutation(
        gate: MediaCaptureRenderMutationGate,
        mutation: () -> Unit,
    ) {
        if (!surface.isLifecycleActive() || !gate.performInstall(mutation)) {
            renderFailure(FailureCode.INVALID_STATE)
        }
    }

    private fun showOnly(visible: View) {
        previewView.visibility = if (visible === previewView) View.VISIBLE else View.GONE
        photoView.visibility = if (visible === photoView) View.VISIBLE else View.GONE
        videoView.visibility = if (visible === videoView) View.VISIBLE else View.GONE
    }

    private fun createVideoView(): VideoView =
        VideoView(surface.context).apply { visibility = View.GONE }

    private fun decodePhoto(
        source: File,
        targetEdge: Int,
        orientationDegrees: Int,
    ): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(source.absolutePath, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            renderFailure(FailureCode.SYSTEM_INTERRUPTED)
        }
        var sample = 1
        val boundedEdge = targetEdge.coerceAtMost(MAX_PHOTO_EDGE)
        while (maxOf(bounds.outWidth / sample, bounds.outHeight / sample) > boundedEdge ||
            (bounds.outWidth / sample).toLong() * (bounds.outHeight / sample) > MAX_PHOTO_PIXELS
        ) {
            sample *= 2
        }
        val decoded =
            BitmapFactory.decodeFile(
                source.absolutePath,
                BitmapFactory.Options().apply { inSampleSize = sample },
            ) ?: renderFailure(FailureCode.SYSTEM_INTERRUPTED)
        if (orientationDegrees == 0) return decoded
        val upright =
            Bitmap.createBitmap(
                decoded,
                0,
                0,
                decoded.width,
                decoded.height,
                Matrix().apply { postRotate(orientationDegrees.toFloat()) },
                true,
            )
        if (upright !== decoded) decoded.recycle()
        return upright
    }

    private fun matchParentLayout(): FrameLayout.LayoutParams =
        FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT,
        )

    private sealed interface MountedContent {
        val binding: MediaCaptureRenderBinding
        val mutationGate: MediaCaptureRenderMutationGate

        data class Live(
            override val binding: MediaCaptureRenderBinding,
            val preview: Preview,
            override val mutationGate: MediaCaptureRenderMutationGate,
        ) : MountedContent

        data class Photo(
            override val binding: MediaCaptureRenderBinding,
            val bitmap: Bitmap,
            override val mutationGate: MediaCaptureRenderMutationGate,
        ) : MountedContent

        data class Video(
            override val binding: MediaCaptureRenderBinding,
            val target: VideoView,
            override val mutationGate: MediaCaptureRenderMutationGate,
        ) : MountedContent
    }

    private companion object {
        const val DEFAULT_PHOTO_EDGE = 2_048
        const val MAX_PHOTO_EDGE = 2_048
        const val MAX_PHOTO_PIXELS = 4_194_304L
    }
}

private fun renderFailure(code: FailureCode): Nothing =
    throw MediaCaptureException(MediaCaptureFailure(code))
