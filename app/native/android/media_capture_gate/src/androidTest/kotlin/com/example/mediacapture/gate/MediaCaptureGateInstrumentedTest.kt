package com.example.mediacapture.gate

import androidx.activity.ComponentActivity
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.example.media_capture.MediaCaptureBridgePlugin
import com.example.mediacapture.api.MediaCapture
import com.example.mediacapture.rendering.MediaCaptureRenderSurfaceOwner
import com.example.mediacapture.rendering.MediaCaptureRenderView
import com.example.mediacapture.ui.MediaCaptureUiConfig
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNotSame
import kotlin.test.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

class MediaCaptureGateActivity : ComponentActivity()

@RunWith(AndroidJUnit4::class)
class MediaCaptureGateInstrumentedTest {
    @Test
    fun lifecycleRecreationKeepsCoreUiAndBridgeBoundariesLoadableWithoutCamera() {
        var firstActivity: MediaCaptureGateActivity? = null
        var firstOwner: MediaCaptureRenderSurfaceOwner? = null

        ActivityScenario.launch(MediaCaptureGateActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                firstActivity = activity
                firstOwner = MediaCaptureRenderSurfaceOwner(activity, activity, ownerGeneration = 1)
                assertTrue(activity.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED))
                assertEquals(1L, firstOwner?.ownerGeneration)
                assertEquals(60_000L, MediaCaptureUiConfig().toSessionOptions().maxVideoDurationMillis)
                assertNotNull(MediaCaptureBridgePlugin())
            }

            scenario.recreate()

            scenario.onActivity { recreated ->
                assertNotSame(firstActivity, recreated)
                assertEquals(Lifecycle.State.DESTROYED, firstActivity?.lifecycle?.currentState)
                val replacement =
                    MediaCaptureRenderSurfaceOwner(recreated, recreated, ownerGeneration = 2)
                assertEquals(2L, replacement.ownerGeneration)
            }
        }

        assertEquals(Lifecycle.State.DESTROYED, firstActivity?.lifecycle?.currentState)
        assertTrue(
            MediaCapture::class.java.methods.any {
                it.returnType == MediaCaptureRenderView::class.java ||
                    it.parameterTypes.contains(MediaCaptureRenderView::class.java)
            },
        )
        assertFalse(
            MediaCapture::class.java.methods.any { method ->
                (listOf(method.returnType) + method.parameterTypes).any {
                    it.name.startsWith("io.flutter")
                }
            },
        )
    }
}
