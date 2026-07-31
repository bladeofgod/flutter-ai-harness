package com.example.mediacapture.ui

import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.os.Looper
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.core.graphics.Insets
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.test.core.app.ApplicationProvider
import com.example.mediacapture.api.CameraPosition
import com.example.mediacapture.api.FlashMode
import com.example.mediacapture.api.SessionHandle
import com.example.mediacapture.api.SessionReady
import com.example.mediacapture.rendering.MediaCaptureRenderSurfaceOwner
import com.example.mediacapture.rendering.MediaCaptureRenderView
import java.time.Duration
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.coroutines.Dispatchers
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf

@RunWith(RobolectricTestRunner::class)
class MediaCaptureChromeViewTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    @Test
    fun controlsHaveAccessibleLabelsAndStableWidthLayout() {
        val view = MediaCaptureChromeView(context)
        view.measure(
            View.MeasureSpec.makeMeasureSpec(320, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(640, View.MeasureSpec.EXACTLY),
        )
        view.layout(0, 0, 320, 640)
        view.showReady(ready())

        assertTrue(view.findButton("Cancel capture").contentDescription.isNotBlank())
        assertTrue(view.findButton("Switch camera").measuredWidth >= 48)
        assertTrue(view.findButtonStartingWith("Flash").measuredWidth >= 48)
        assertEquals(320, view.measuredWidth)
    }

    @Test
    fun surfaceTapSendsClampedFocusPoint() {
        val view = MediaCaptureChromeView(context)
        val callbacks = RecordingCallbacks()
        view.setCallbacks(callbacks)
        val surface = renderSurface()
        view.showSurface(surface)
        view.measure(
            View.MeasureSpec.makeMeasureSpec(320, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(640, View.MeasureSpec.EXACTLY),
        )
        view.layout(0, 0, 320, 640)
        view.showReady(ready())

        assertTrue(surface.dispatchTouchEvent(event(MotionEvent.ACTION_DOWN, 80f, 160f)))
        assertTrue(surface.dispatchTouchEvent(event(MotionEvent.ACTION_UP, 80f, 160f)))

        assertEquals(listOf(0.25 to 0.25), callbacks.focusPoints)
    }

    @Test
    fun accessibilityClickAndLongClickDriveCaptureActions() {
        val view = MediaCaptureChromeView(context)
        val callbacks = RecordingCallbacks()
        view.setCallbacks(callbacks)
        view.showReady(ready())
        val capture = view.findButton("Capture")

        assertTrue(capture.performClick())
        assertTrue(capture.performLongClick())
        view.showRecording(0L)
        assertTrue(capture.performClick())

        assertEquals(listOf("photo", "record_start", "record_stop"), callbacks.actions)
    }

    @Test
    fun touchLongPressRecordsUntilFingerIsReleased() {
        val view = MediaCaptureChromeView(context)
        val callbacks = RecordingCallbacks()
        view.setCallbacks(callbacks)
        view.showReady(ready())
        view.measure(
            View.MeasureSpec.makeMeasureSpec(375, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(812, View.MeasureSpec.EXACTLY),
        )
        view.layout(0, 0, 375, 812)
        val capture = view.findButton("Capture")

        assertTrue(capture.dispatchTouchEvent(event(MotionEvent.ACTION_DOWN, 40f, 40f)))
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(361L))
        assertEquals(listOf("record_start"), callbacks.actions)

        view.showRecording(0L)
        assertTrue(capture.dispatchTouchEvent(event(MotionEvent.ACTION_UP, 40f, 40f)))
        assertEquals(listOf("record_start", "record_stop"), callbacks.actions)
    }

    @Test
    fun readyStateExposesInitialAndSelectedFlashModes() {
        val view = MediaCaptureChromeView(context)

        view.showReady(ready())
        val flashOff = view.findButton("Flash off")

        assertEquals(false, flashOff.isSelected)

        view.setFlashMode(FlashMode.ON)
        val flashOn = view.findButton("Flash on")

        assertTrue(flashOn.isSelected)
    }

    @Test
    fun recordingUsesProgressControlAndHidesBothSideActions() {
        val view = MediaCaptureChromeView(context)
        view.setMaxVideoDurationMillis(60_000L)
        view.showReady(ready())
        view.showRecording(15_000L)
        view.measure(
            View.MeasureSpec.makeMeasureSpec(375, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(812, View.MeasureSpec.EXACTLY),
        )
        view.layout(0, 0, 375, 812)

        assertEquals(View.INVISIBLE, view.findButton("Switch camera").visibility)
        assertEquals(View.INVISIBLE, view.findButtonStartingWith("Flash").visibility)
        assertEquals(98, view.findButton("Stop recording").measuredWidth)
        assertEquals(98, view.findButton("Stop recording").measuredHeight)
    }

    @Test
    fun previewUsesTopCloseForRetakeAndBottomSendForConfirm() {
        val view = MediaCaptureChromeView(context)
        val callbacks = RecordingCallbacks()
        view.setCallbacks(callbacks)
        view.showPreview()
        view.measure(
            View.MeasureSpec.makeMeasureSpec(375, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(812, View.MeasureSpec.EXACTLY),
        )
        view.layout(0, 0, 375, 812)

        val confirm = view.findButton("Confirm")
        assertEquals(48, confirm.measuredHeight)
        assertEquals("send", view.findText("send").text.toString())

        assertTrue(view.findButton("Retake").performClick())
        assertTrue(confirm.performClick())

        assertEquals(listOf("retake", "confirm"), callbacks.actions)
    }

    @Test
    fun systemBarsKeepChromeSafeAndFillBottomInsetWithBlack() {
        val view = MediaCaptureChromeView(context)
        val insets =
            WindowInsetsCompat.Builder()
                .setInsets(WindowInsetsCompat.Type.systemBars(), Insets.of(8, 24, 12, 32))
                .build()

        ViewCompat.dispatchApplyWindowInsets(view, insets)
        view.measure(
            View.MeasureSpec.makeMeasureSpec(375, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(812, View.MeasureSpec.EXACTLY),
        )
        view.layout(0, 0, 375, 812)

        val closeParams = view.findButton("Cancel capture").layoutParams as ViewGroup.MarginLayoutParams
        val bottomInsetFill =
            (0 until view.childCount)
                .map(view::getChildAt)
                .single { child ->
                    (child.background as? ColorDrawable)?.color == Color.BLACK &&
                        child.top == 780 && child.bottom == 812
                }
        assertEquals(12, closeParams.marginStart)
        assertEquals(28, closeParams.topMargin)
        assertEquals(375, bottomInsetFill.width)
        assertEquals(0, view.paddingLeft)
        assertEquals(0, view.paddingTop)
        assertEquals(0, view.paddingRight)
        assertEquals(0, view.paddingBottom)
    }

    @Test
    fun landscapeAndLargeFontKeepControlsInsideViewport() {
        val configuration =
            Configuration(context.resources.configuration).apply {
                orientation = Configuration.ORIENTATION_LANDSCAPE
                fontScale = 2f
            }
        val view = MediaCaptureChromeView(context.createConfigurationContext(configuration))
        view.showReady(ready())
        view.setFlashMode(FlashMode.ON)
        view.measure(
            View.MeasureSpec.makeMeasureSpec(640, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(320, View.MeasureSpec.EXACTLY),
        )
        view.layout(0, 0, 640, 320)

        assertChildrenInside(view, view.width, view.height)
        val hint = view.findText(view.resources.getString(R.string.media_capture_flash_enabled))
        val textHeight = hint.paint.fontMetrics.run { bottom - top }
        assertTrue(hint.measuredHeight >= textHeight)
    }

    private fun ready(): SessionReady =
        SessionReady(
            sessionHandle = SessionHandle("session-1"),
            activeCamera = CameraPosition.REAR,
            availableCameras = setOf(CameraPosition.REAR, CameraPosition.FRONT),
            switchCameraSupported = true,
            supportedFlashModes = setOf(FlashMode.OFF, FlashMode.ON),
            focusPointSupported = true,
            minZoomFactor = 1.0,
            maxZoomFactor = 4.0,
        )

    private fun event(
        action: Int,
        x: Float,
        y: Float,
    ): MotionEvent =
        MotionEvent.obtain(0L, 0L, action, x, y, 0)

    private fun renderSurface(): MediaCaptureRenderView {
        val owner = TestLifecycleOwner()
        val constructor =
            MediaCaptureRenderView::class.java.declaredConstructors.single {
                it.parameterTypes.size == 3
            }
        constructor.isAccessible = true
        @Suppress("UNCHECKED_CAST")
        return constructor.newInstance(
            MediaCaptureRenderSurfaceOwner(context, owner, 1L),
            Dispatchers.Unconfined,
            Dispatchers.Unconfined,
        ) as MediaCaptureRenderView
    }

    private class TestLifecycleOwner : LifecycleOwner {
        private val registry = LifecycleRegistry(this).apply { currentState = Lifecycle.State.CREATED }

        override val lifecycle: Lifecycle = registry
    }

    private class RecordingCallbacks : MediaCaptureChromeView.Callbacks {
        val focusPoints = mutableListOf<Pair<Double, Double>>()
        val actions = mutableListOf<String>()

        override fun onTakePhoto() {
            actions += "photo"
        }

        override fun onStartRecording() {
            actions += "record_start"
        }

        override fun onStopRecording() {
            actions += "record_stop"
        }

        override fun onZoomChanged(zoomFactor: Double) = Unit

        override fun onSwitchCamera() = Unit

        override fun onCycleFlash() = Unit

        override fun onFocusPoint(
            normalizedX: Double,
            normalizedY: Double,
        ) {
            focusPoints += normalizedX to normalizedY
        }

        override fun onRetake() {
            actions += "retake"
        }

        override fun onConfirm() {
            actions += "confirm"
        }

        override fun onCancel() = Unit
    }
}

private fun View.findText(text: String): TextView {
    return findTextOrNull(text) ?: error("Text $text not found")
}

private fun View.findTextOrNull(text: String): TextView? {
    if (this is TextView && this.text.toString() == text) return this
    if (this is ViewGroup) {
        for (index in 0 until childCount) {
            getChildAt(index).findTextOrNull(text)?.let { return it }
        }
    }
    return null
}

private fun View.findButton(contentDescription: String): View {
    return findButtonOrNull(contentDescription) ?: error("Button $contentDescription not found")
}

private fun View.findButtonStartingWith(contentDescription: String): View {
    return findButtonStartingWithOrNull(contentDescription)
        ?: error("Button starting with $contentDescription not found")
}

private fun View.findButtonStartingWithOrNull(contentDescription: String): View? {
    if (this.contentDescription?.startsWith(contentDescription) == true) return this
    if (this is android.view.ViewGroup) {
        for (index in 0 until childCount) {
            getChildAt(index).findButtonStartingWithOrNull(contentDescription)?.let { return it }
        }
    }
    return null
}

private fun View.findButtonOrNull(contentDescription: String): View? {
    if (this.contentDescription == contentDescription) return this
    if (this is android.view.ViewGroup) {
        for (index in 0 until childCount) {
            getChildAt(index).findButtonOrNull(contentDescription)?.let { return it }
        }
    }
    return null
}

private fun assertChildrenInside(
    view: ViewGroup,
    width: Int,
    height: Int,
) {
    for (index in 0 until view.childCount) {
        val child = view.getChildAt(index)
        assertTrue(child.left >= 0)
        assertTrue(child.top >= 0)
        assertTrue(child.right <= width)
        assertTrue(child.bottom <= height)
    }
}
