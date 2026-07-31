package com.example.mediacapture.ui

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class CaptureGestureControllerTest {
    @Test
    fun tapBeforeThresholdTakesPhotoOnly() {
        val recorder = GestureRecorder()
        val controller = CaptureGestureController(callbacks = recorder)

        controller.configure(
            enabled = true,
            photoEnabled = true,
            videoEnabled = true,
            currentZoom = 1.0,
            minZoom = 1.0,
            maxZoom = 5.0,
        )
        assertTrue(controller.onDown(100f))
        controller.onUp(104f)

        assertEquals(listOf("photo"), recorder.events)
    }

    @Test
    fun longPressRecordsAndReleaseStopsWithoutPhoto() {
        val recorder = GestureRecorder()
        val controller = CaptureGestureController(callbacks = recorder)

        controller.configure(
            enabled = true,
            photoEnabled = true,
            videoEnabled = true,
            currentZoom = 1.0,
            minZoom = 1.0,
            maxZoom = 5.0,
        )
        controller.onDown(100f)
        controller.onLongPress()
        controller.onUp(100f)

        assertEquals(listOf("record_start", "record_stop"), recorder.events)
    }

    @Test
    fun verticalRecordingZoomIsClampedToSnapshot() {
        val recorder = GestureRecorder()
        val controller = CaptureGestureController(callbacks = recorder)

        controller.configure(
            enabled = true,
            photoEnabled = true,
            videoEnabled = true,
            currentZoom = 2.0,
            minZoom = 1.0,
            maxZoom = 3.0,
        )
        controller.onDown(200f)
        controller.onLongPress()
        controller.onMove(-400f)
        controller.onMove(400f)

        assertEquals(listOf("record_start"), recorder.events)
        assertEquals(listOf(3.0, 1.0), recorder.zoomValues)
    }

    @Test
    fun disabledVideoKeepsLongPressFromStartingRecording() {
        val recorder = GestureRecorder()
        val controller = CaptureGestureController(callbacks = recorder)

        controller.configure(
            enabled = true,
            photoEnabled = true,
            videoEnabled = false,
            currentZoom = 1.0,
            minZoom = 1.0,
            maxZoom = 1.0,
        )
        controller.onDown(100f)
        controller.onLongPress()
        controller.onUp(100f)

        assertEquals(listOf("photo"), recorder.events)
    }

    private class GestureRecorder : CaptureGestureCallbacks {
        val events = mutableListOf<String>()
        val zoomValues = mutableListOf<Double>()

        override fun onPhotoClick() {
            events += "photo"
        }

        override fun onRecordStart() {
            events += "record_start"
        }

        override fun onRecordStop() {
            events += "record_stop"
        }

        override fun onZoomChanged(zoomFactor: Double) {
            zoomValues += zoomFactor
        }
    }
}
