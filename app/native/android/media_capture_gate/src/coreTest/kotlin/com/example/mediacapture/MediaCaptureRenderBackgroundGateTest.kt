@file:OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)

package com.example.mediacapture

import android.content.Context
import android.graphics.Bitmap
import android.graphics.drawable.BitmapDrawable
import android.view.View
import android.widget.ImageView
import android.widget.VideoView
import androidx.camera.core.Preview
import androidx.camera.view.PreviewView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.test.core.app.ApplicationProvider
import com.example.mediacapture.api.MediaCapture
import com.example.mediacapture.api.MediaType
import com.example.mediacapture.framework.CameraXRenderSource
import com.example.mediacapture.rendering.AndroidRenderSource
import com.example.mediacapture.rendering.DefaultAndroidRenderSurfaceFactory
import com.example.mediacapture.rendering.MediaCaptureRenderBinding
import com.example.mediacapture.rendering.MediaCaptureRenderMountEndpoint
import com.example.mediacapture.rendering.MediaCaptureRenderMutationGate
import com.example.mediacapture.rendering.MediaCaptureRenderSurfaceOwner
import com.example.mediacapture.rendering.MediaCaptureRenderView
import java.io.File
import java.io.FileOutputStream
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.runner.RunWith
import org.robolectric.Shadows
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class MediaCaptureRenderBackgroundGateTest {
    @Test
    fun backgroundClearsConcreteCameraXProvider() = runTest {
        val dispatcher = UnconfinedTestDispatcher(testScheduler)
        val lifecycleOwner = GateLifecycleOwner()
        val module = TestModule(this, DefaultAndroidRenderSurfaceFactory(dispatcher, dispatcher))
        val preview = Preview.Builder().build()
        module.framework.prepared =
            module.framework.prepared.copy(liveRenderSource = CameraXRenderSource(preview))
        val session = startReady(module)
        val surface =
            module.core.createRenderView(gateOwner(lifecycleOwner, ownerGeneration = 1))

        module.core.attachLivePreview(session, surface, 1)
        val target = surface.gateChild<PreviewView>()
        assertSame(target.surfaceProvider, preview.surfaceProvider)

        module.core.onAppBackgrounded()
        runCurrent()

        assertNull(preview.surfaceProvider)
        assertEquals(View.GONE, target.visibility)
        module.core.close()
    }

    @Test
    fun backgroundClearsConcretePhotoContent() = runTest {
        val dispatcher = UnconfinedTestDispatcher(testScheduler)
        val lifecycleOwner = GateLifecycleOwner()
        val module = TestModule(this, DefaultAndroidRenderSurfaceFactory(dispatcher, dispatcher))
        val consumer: MediaCapture = module.core
        val context = ApplicationProvider.getApplicationContext<Context>()
        val source = File(context.cacheDir, "gate-background-photo.jpg")
        val bitmap = Bitmap.createBitmap(16, 12, Bitmap.Config.ARGB_8888)
        FileOutputStream(source).use { bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it) }
        bitmap.recycle()
        val session = startReady(module, options(setOf(MediaType.PHOTO)))
        val captured = consumer.takePhoto(session)
        module.framework.previewRenderSource = GatePhotoRenderSource(source)
        val surface = consumer.createRenderView(gateOwner(lifecycleOwner, ownerGeneration = 1))

        consumer.attachUnconfirmedPreview(captured.mediaHandle, surface, 1)
        val target = surface.gateChild<ImageView>()
        assertNotNull(target.drawable as? BitmapDrawable)

        consumer.onAppBackgrounded()
        runCurrent()

        assertNull(target.drawable)
        assertEquals(View.GONE, target.visibility)
        consumer.close()
        source.delete()
    }

    @Test
    fun backgroundClearsConcreteVideoPlayerAndRetiresOldTarget() = runTest {
        val dispatcher = UnconfinedTestDispatcher(testScheduler)
        val lifecycleOwner = GateLifecycleOwner()
        val module = TestModule(this, DefaultAndroidRenderSurfaceFactory(dispatcher, dispatcher))
        val consumer: MediaCapture = module.core
        val context = ApplicationProvider.getApplicationContext<Context>()
        val source = File(context.cacheDir, "gate-background-video.mp4").apply {
            writeBytes(byteArrayOf(0))
        }
        val session = startReady(module, options(setOf(MediaType.VIDEO)))
        consumer.startRecording(session)
        val captured = consumer.stopRecording(session)
        module.framework.previewRenderSource = GateVideoRenderSource(source)
        val surface = consumer.createRenderView(gateOwner(lifecycleOwner, ownerGeneration = 1))

        consumer.attachUnconfirmedPreview(captured.mediaHandle, surface, 1)
        val target = surface.gateChild<VideoView>()
        assertEquals(source.absolutePath, Shadows.shadowOf(target).videoPath)

        consumer.onAppBackgrounded()
        runCurrent()

        assertFalse(surface.containsGateChild(target))
        assertEquals(View.GONE, surface.gateChild<VideoView>().visibility)
        consumer.close()
        source.delete()
    }
}

private class GateLifecycleOwner : LifecycleOwner {
    private val registry = LifecycleRegistry(this).apply {
        currentState = Lifecycle.State.RESUMED
    }

    override fun getLifecycle(): Lifecycle = registry
}

private fun gateOwner(
    lifecycleOwner: LifecycleOwner,
    ownerGeneration: Long,
) = MediaCaptureRenderSurfaceOwner(
    context = ApplicationProvider.getApplicationContext(),
    lifecycleOwner = lifecycleOwner,
    ownerGeneration = ownerGeneration,
)

private inline fun <reified T : View> MediaCaptureRenderView.gateChild(): T =
    (0 until childCount).map(::getChildAt).filterIsInstance<T>().single()

private fun MediaCaptureRenderView.containsGateChild(view: View): Boolean =
    (0 until childCount).any { getChildAt(it) === view }

private data class GatePhotoRenderSource(val file: File) : AndroidRenderSource {
    override suspend fun mount(
        binding: MediaCaptureRenderBinding,
        endpoint: MediaCaptureRenderMountEndpoint,
        mutationGate: MediaCaptureRenderMutationGate,
    ) {
        endpoint.mountPhoto(binding, file, orientationDegrees = 0, mutationGate)
    }
}

private data class GateVideoRenderSource(val file: File) : AndroidRenderSource {
    override suspend fun mount(
        binding: MediaCaptureRenderBinding,
        endpoint: MediaCaptureRenderMountEndpoint,
        mutationGate: MediaCaptureRenderMutationGate,
    ) {
        endpoint.mountVideo(binding, file, mutationGate)
    }
}
