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
import com.example.mediacapture.api.FailureCode
import com.example.mediacapture.api.MediaCapture
import com.example.mediacapture.api.MediaType
import com.example.mediacapture.framework.CameraXRenderSource
import com.example.mediacapture.rendering.AndroidRenderSource
import com.example.mediacapture.rendering.AndroidRenderSurfaceFactory
import com.example.mediacapture.rendering.DefaultAndroidRenderSurfaceFactory
import com.example.mediacapture.rendering.MediaCaptureRenderBinding
import com.example.mediacapture.rendering.MediaCaptureRenderMountEndpoint
import com.example.mediacapture.rendering.MediaCaptureRenderMutationGate
import com.example.mediacapture.rendering.MediaCaptureRenderSurfaceOwner
import com.example.mediacapture.rendering.MediaCaptureRenderView
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.runner.RunWith
import org.robolectric.Shadows
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class MediaCaptureRenderViewTest {
    @Test
    fun `native consumer receives fresh concrete surfaces and CameraX provider is mounted`() =
        runTest {
            val dispatcher = UnconfinedTestDispatcher(testScheduler)
            val lifecycleOwner = ResumedLifecycleOwner()
            val factory = DefaultAndroidRenderSurfaceFactory(dispatcher, dispatcher)
            val module = TestModule(this, factory)
            val cameraPreview = Preview.Builder().build()
            module.framework.prepared =
                module.framework.prepared.copy(liveRenderSource = CameraXRenderSource(cameraPreview))
            val session = startReady(module)
            val consumer: MediaCapture = module.core
            val owner = surfaceOwner(lifecycleOwner, ownerGeneration = 1)

            val surface = consumer.createRenderView(owner)
            val sameOwnerFreshSurface = consumer.createRenderView(owner)

            assertFalse(surface === sameOwnerFreshSurface)
            assertEquals(
                FailureCode.INVALID_STATE,
                failureCode {
                    consumer.createRenderView(
                        surfaceOwner(InitializedLifecycleOwner(), ownerGeneration = 3),
                    )
                },
            )
            assertEquals(
                FailureCode.INVALID_ARGUMENT,
                failureCode { consumer.attachLivePreview(session, surface, 2) },
            )
            assertNull(cameraPreview.surfaceProvider)
            consumer.attachLivePreview(session, surface, 1)
            val previewView = surface.requireChild<PreviewView>()
            assertEquals(View.VISIBLE, previewView.visibility)
            assertSame(previewView.surfaceProvider, cameraPreview.surfaceProvider)

            assertEquals(
                FailureCode.ATTACHMENT_TARGET_CONFLICT,
                failureCode { consumer.attachLivePreview(session, sameOwnerFreshSurface, 1) },
            )
            assertSame(previewView.surfaceProvider, cameraPreview.surfaceProvider)

            val replacement =
                consumer.createRenderView(surfaceOwner(lifecycleOwner, ownerGeneration = 2))
            consumer.attachLivePreview(session, replacement, 2)
            assertEquals(View.GONE, previewView.visibility)
            assertSame(
                replacement.requireChild<PreviewView>().surfaceProvider,
                cameraPreview.surfaceProvider,
            )

            consumer.detachLivePreview(session, replacement, 2)
            assertNull(cameraPreview.surfaceProvider)
            assertEquals(
                FailureCode.ATTACHMENT_GENERATION_RETIRED,
                failureCode { consumer.attachLivePreview(session, replacement, 2) },
            )
            consumer.cancel(session)
            consumer.close()
        }

    @Test
    fun `photo and video sources mount real module targets and terminal cleanup clears content`() =
        runTest {
            val dispatcher = UnconfinedTestDispatcher(testScheduler)
            val lifecycleOwner = ResumedLifecycleOwner()
            val module = TestModule(this, DefaultAndroidRenderSurfaceFactory(dispatcher, dispatcher))
            val consumer: MediaCapture = module.core
            val context = ApplicationProvider.getApplicationContext<Context>()

            val photoSession = startReady(module, options(setOf(MediaType.PHOTO)))
            val photoPreview = consumer.takePhoto(photoSession)
            val photoFile = File(context.cacheDir, "render-photo-source.jpg")
            val bitmap = Bitmap.createBitmap(16, 12, Bitmap.Config.ARGB_8888)
            FileOutputStream(photoFile).use { bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it) }
            bitmap.recycle()
            module.framework.previewRenderSource = PhotoRenderSource(photoFile, orientationDegrees = 90)
            val photoSurface =
                consumer.createRenderView(surfaceOwner(lifecycleOwner, ownerGeneration = 1))

            consumer.attachUnconfirmedPreview(photoPreview.mediaHandle, photoSurface, 1)

            val photoTarget = photoSurface.requireChild<ImageView>()
            assertEquals(View.VISIBLE, photoTarget.visibility)
            val renderedPhoto = assertNotNull(photoTarget.drawable as? BitmapDrawable).bitmap
            assertEquals(12, renderedPhoto.width)
            assertEquals(16, renderedPhoto.height)
            consumer.confirm(photoPreview.mediaHandle)
            assertEquals(View.GONE, photoTarget.visibility)
            assertNull(photoTarget.drawable)
            consumer.releaseMedia(photoPreview.mediaHandle)

            val videoSession = startReady(module, options(setOf(MediaType.VIDEO)))
            consumer.startRecording(videoSession)
            val videoPreview = consumer.stopRecording(videoSession)
            val videoFile = File(context.cacheDir, "render-video-source.mp4").apply { writeBytes(byteArrayOf(0)) }
            module.framework.previewRenderSource = VideoRenderSource(videoFile)
            val videoSurface =
                consumer.createRenderView(surfaceOwner(lifecycleOwner, ownerGeneration = 2))

            consumer.attachUnconfirmedPreview(videoPreview.mediaHandle, videoSurface, 2)

            val videoTarget = videoSurface.requireChild<VideoView>()
            assertEquals(View.VISIBLE, videoTarget.visibility)
            assertEquals(videoFile.absolutePath, Shadows.shadowOf(videoTarget).videoPath)
            consumer.retake(videoPreview.mediaHandle)
            assertFalse(videoSurface.containsChild(videoTarget))
            assertEquals(View.GONE, videoSurface.requireChild<VideoView>().visibility)
            consumer.cancel(videoSession)
            consumer.close()
            photoFile.delete()
            videoFile.delete()
        }

    @Test
    fun `owner destruction revokes the committed surface before stale callbacks mutate it`() =
        runTest {
            val dispatcher = UnconfinedTestDispatcher(testScheduler)
            val lifecycleOwner = ResumedLifecycleOwner()
            val module = TestModule(this, DefaultAndroidRenderSurfaceFactory(dispatcher, dispatcher))
            val cameraPreview = Preview.Builder().build()
            module.framework.prepared =
                module.framework.prepared.copy(liveRenderSource = CameraXRenderSource(cameraPreview))
            val session = startReady(module)
            val surface =
                module.core.createRenderView(surfaceOwner(lifecycleOwner, ownerGeneration = 1))
            module.core.attachLivePreview(session, surface, 1)

            lifecycleOwner.destroy()
            runCurrent()

            assertNull(cameraPreview.surfaceProvider)
            assertEquals(View.GONE, surface.requireChild<PreviewView>().visibility)
            assertEquals(
                FailureCode.ATTACHMENT_GENERATION_RETIRED,
                failureCode { module.core.attachLivePreview(session, surface, 1) },
            )
            module.core.cancel(session)
            module.core.close()
        }

    @Test
    fun `active video errors revoke attachment while stale errors are dropped`() = runTest {
        val dispatcher = UnconfinedTestDispatcher(testScheduler)
        val lifecycleOwner = ResumedLifecycleOwner()
        val module = TestModule(this, DefaultAndroidRenderSurfaceFactory(dispatcher, dispatcher))
        val session = startReady(module, options(setOf(MediaType.VIDEO)))
        module.core.startRecording(session)
        val preview = module.core.stopRecording(session)
        val context = ApplicationProvider.getApplicationContext<Context>()
        val source = File(context.cacheDir, "render-video-error.mp4").apply {
            writeBytes(byteArrayOf(0))
        }
        module.framework.previewRenderSource = VideoRenderSource(source)
        val surface =
            module.core.createRenderView(surfaceOwner(lifecycleOwner, ownerGeneration = 1))
        module.core.attachUnconfirmedPreview(preview.mediaHandle, surface, 1)
        val target = surface.requireChild<VideoView>()
        val errorListener = assertNotNull(Shadows.shadowOf(target).onErrorListener)

        assertTrue(errorListener.onError(null, 100, 200))
        runCurrent()

        assertFalse(surface.containsChild(target))
        assertEquals(
            FailureCode.ATTACHMENT_GENERATION_RETIRED,
            failureCode {
                module.core.attachUnconfirmedPreview(preview.mediaHandle, surface, 1)
            },
        )
        assertTrue(errorListener.onError(null, 300, 400))
        runCurrent()
        assertFalse(surface.containsChild(target))

        module.core.retake(preview.mediaHandle)
        module.core.cancel(session)
        module.core.close()
        source.delete()
    }

    @Test
    fun `surface registration cannot cross module instance or app restart`() =
        runTest {
            val dispatcher = UnconfinedTestDispatcher(testScheduler)
            val lifecycleOwner = ResumedLifecycleOwner()
            val factory = DefaultAndroidRenderSurfaceFactory(dispatcher, dispatcher)
            val firstModule = TestModule(this, factory)
            val secondModule = TestModule(this, factory)
            val firstSurface =
                firstModule.core.createRenderView(surfaceOwner(lifecycleOwner, ownerGeneration = 1))
            val secondPreview = Preview.Builder().build()
            secondModule.framework.prepared =
                secondModule.framework.prepared.copy(
                    liveRenderSource = CameraXRenderSource(secondPreview),
                )
            val secondSession = startReady(secondModule)

            assertEquals(
                FailureCode.INVALID_ARGUMENT,
                failureCode { secondModule.core.attachLivePreview(secondSession, firstSurface, 1) },
            )
            assertNull(secondPreview.surfaceProvider)

            firstModule.core.onAppRestarted()
            val firstPreview = Preview.Builder().build()
            firstModule.framework.prepared =
                firstModule.framework.prepared.copy(
                    liveRenderSource = CameraXRenderSource(firstPreview),
                )
            val restartedSession = startReady(firstModule)
            assertEquals(
                FailureCode.INVALID_ARGUMENT,
                failureCode {
                    firstModule.core.attachLivePreview(restartedSession, firstSurface, 1)
                },
            )
            assertNull(firstPreview.surfaceProvider)

            firstModule.core.cancel(restartedSession)
            secondModule.core.cancel(secondSession)
            firstModule.core.close()
            secondModule.core.close()
        }

    @Test
    fun `cancelled surface creation abandons output before and during registration`() = runTest {
        val testScope = this
        suspend fun assertAbandoned(
            factory: TrackingRenderSurfaceFactory,
            configure: (TestModule, CompletableDeferred<Unit>) -> Unit,
        ) {
            val module = TestModule(testScope, factory)
            val release = CompletableDeferred<Unit>()
            configure(module, release)
            val creation =
                async {
                    module.core.createRenderView(
                        surfaceOwner(ResumedLifecycleOwner(), ownerGeneration = 1),
                    )
                }
            runCurrent()
            factory.created.await()

            creation.cancel()
            release.complete(Unit)
            runCurrent()
            creation.cancelAndJoin()

            assertTrue(creation.isCancelled)
            assertFalse(factory.surface.isLifecycleActive())
            module.core.close()
        }

        val dispatcher = UnconfinedTestDispatcher(testScheduler)
        val factoryReturn = TrackingRenderSurfaceFactory(dispatcher)
        assertAbandoned(factoryReturn) { _, release ->
            factoryReturn.returnGate = release
        }

        val registration = TrackingRenderSurfaceFactory(dispatcher)
        assertAbandoned(registration) { module, release ->
            module.core.renderViewBeforeRegistrationForTest = { release.await() }
        }
    }

    @Test
    fun `mutation gate serializes invalidation and drops stale target mutations`() {
        val gate = MediaCaptureRenderMutationGate()
        gate.commit()
        val mutationEntered = CountDownLatch(1)
        val releaseMutation = CountDownLatch(1)
        val invalidationFinished = CountDownLatch(1)
        val mutationCount = AtomicInteger()

        val mutationThread =
            Thread {
                gate.performCallback {
                    mutationEntered.countDown()
                    check(releaseMutation.await(2, TimeUnit.SECONDS))
                    mutationCount.incrementAndGet()
                }
            }.apply { start() }
        assertTrue(mutationEntered.await(2, TimeUnit.SECONDS))

        val invalidationThread =
            Thread {
                gate.invalidate()
                invalidationFinished.countDown()
            }.apply { start() }
        assertFalse(invalidationFinished.await(50, TimeUnit.MILLISECONDS))
        releaseMutation.countDown()
        mutationThread.join(2_000)
        invalidationThread.join(2_000)

        assertEquals(1, mutationCount.get())
        assertTrue(invalidationFinished.await(2, TimeUnit.SECONDS))
        assertFalse(gate.performCallback { mutationCount.incrementAndGet() })
        assertFalse(gate.performInstall { mutationCount.incrementAndGet() })
        assertEquals(1, mutationCount.get())
    }

    @Test
    fun `public consumer boundary has no Flutter Wire source or platform backing target type`() {
        val forbiddenFragments =
            listOf(
                "flutter",
                "wire",
                "AndroidRenderSource",
                "AndroidRenderTargetAdapter",
                "PreviewView",
                "SurfaceProvider",
                "java.io.File",
            )
        val publicApiTypes =
            MediaCapture::class.java.methods.flatMap { method ->
                listOf(method.returnType.name) + method.parameterTypes.map { it.name }
            }

        forbiddenFragments.forEach { fragment ->
            assertFalse(publicApiTypes.any { it.contains(fragment, ignoreCase = true) }, fragment)
        }
        assertTrue(
            MediaCapture::class.java.methods.any {
                it.returnType == MediaCaptureRenderView::class.java ||
                    it.parameterTypes.contains(MediaCaptureRenderView::class.java)
            },
        )
    }

    private fun surfaceOwner(
        lifecycleOwner: LifecycleOwner,
        ownerGeneration: Long,
    ) = MediaCaptureRenderSurfaceOwner(
        context = ApplicationProvider.getApplicationContext(),
        lifecycleOwner = lifecycleOwner,
        ownerGeneration = ownerGeneration,
    )
}

private class TrackingRenderSurfaceFactory(
    private val dispatcher: CoroutineDispatcher,
) : AndroidRenderSurfaceFactory {
    val created = CompletableDeferred<Unit>()
    lateinit var surface: MediaCaptureRenderView
    var returnGate: CompletableDeferred<Unit>? = null

    override suspend fun create(owner: MediaCaptureRenderSurfaceOwner): MediaCaptureRenderView {
        surface = MediaCaptureRenderView.create(owner, dispatcher, dispatcher)
        created.complete(Unit)
        returnGate?.await()
        return surface
    }
}

private class ResumedLifecycleOwner : LifecycleOwner {
    private val registry = LifecycleRegistry(this)

    init {
        registry.currentState = Lifecycle.State.RESUMED
    }

    override fun getLifecycle(): Lifecycle = registry

    fun destroy() {
        registry.currentState = Lifecycle.State.DESTROYED
    }
}

private class InitializedLifecycleOwner : LifecycleOwner {
    private val registry = LifecycleRegistry(this)

    override fun getLifecycle(): Lifecycle = registry
}

private data class PhotoRenderSource(
    val file: File,
    val orientationDegrees: Int,
) : AndroidRenderSource {
    override suspend fun mount(
        binding: MediaCaptureRenderBinding,
        endpoint: MediaCaptureRenderMountEndpoint,
        mutationGate: MediaCaptureRenderMutationGate,
    ) {
        endpoint.mountPhoto(binding, file, orientationDegrees, mutationGate)
    }
}

private data class VideoRenderSource(val file: File) : AndroidRenderSource {
    override suspend fun mount(
        binding: MediaCaptureRenderBinding,
        endpoint: MediaCaptureRenderMountEndpoint,
        mutationGate: MediaCaptureRenderMutationGate,
    ) {
        endpoint.mountVideo(binding, file, mutationGate)
    }
}

private inline fun <reified T : View> MediaCaptureRenderView.requireChild(): T =
    (0 until childCount)
        .asSequence()
        .map(::getChildAt)
        .filterIsInstance<T>()
        .single()

private fun MediaCaptureRenderView.containsChild(target: View): Boolean =
    (0 until childCount).any { getChildAt(it) === target }
