package com.example.mediacapture.ui

import kotlin.math.abs

internal data class CaptureGestureConfig(
    val longPressMillis: Long = 360L,
    val tapSlopPx: Float = 18f,
    val zoomStartSlopPx: Float = 20f,
    val zoomPixelsPerFactor: Float = 96f,
)

internal interface CaptureGestureCallbacks {
    fun onPhotoClick()

    fun onRecordStart()

    fun onRecordStop()

    fun onZoomChanged(zoomFactor: Double)
}

internal class CaptureGestureController(
    private val config: CaptureGestureConfig = CaptureGestureConfig(),
    private val callbacks: CaptureGestureCallbacks,
) {
    private var state: State = State.IDLE
    private var downY = 0f
    private var baseZoom = 1.0
    private var minZoom = 1.0
    private var maxZoom = 1.0
    private var longPressFired = false
    private var enabled = true
    private var photoEnabled = true
    private var videoEnabled = true

    val longPressMillis: Long
        get() = config.longPressMillis

    fun configure(
        enabled: Boolean,
        photoEnabled: Boolean,
        videoEnabled: Boolean,
        currentZoom: Double,
        minZoom: Double,
        maxZoom: Double,
    ) {
        this.enabled = enabled
        this.photoEnabled = photoEnabled
        this.videoEnabled = videoEnabled
        this.minZoom = minZoom
        this.maxZoom = maxZoom.coerceAtLeast(minZoom)
        baseZoom = currentZoom.coerceIn(this.minZoom, this.maxZoom)
        if (!enabled && state != State.IDLE) {
            state = State.IDLE
            longPressFired = false
        }
    }

    fun onDown(y: Float): Boolean {
        if (!enabled) return false
        downY = y
        longPressFired = false
        state = State.PRESSED
        return true
    }

    fun onLongPress() {
        if (state != State.PRESSED || longPressFired || !videoEnabled) return
        longPressFired = true
        state = State.RECORDING
        callbacks.onRecordStart()
    }

    fun onMove(y: Float) {
        if (state != State.RECORDING) return
        val delta = downY - y
        if (abs(delta) < config.zoomStartSlopPx) return
        val requested = baseZoom + (delta / config.zoomPixelsPerFactor)
        callbacks.onZoomChanged(requested.coerceIn(minZoom, maxZoom))
    }

    fun onUp(y: Float) {
        when (state) {
            State.PRESSED -> {
                val withinTapSlop = abs(downY - y) <= config.tapSlopPx
                state = State.IDLE
                if (!longPressFired && photoEnabled && withinTapSlop) callbacks.onPhotoClick()
            }
            State.RECORDING -> {
                state = State.IDLE
                callbacks.onRecordStop()
            }
            State.IDLE -> Unit
        }
        longPressFired = false
    }

    fun onCancel() {
        if (state == State.RECORDING) callbacks.onRecordStop()
        state = State.IDLE
        longPressFired = false
    }

    private enum class State { IDLE, PRESSED, RECORDING }
}
