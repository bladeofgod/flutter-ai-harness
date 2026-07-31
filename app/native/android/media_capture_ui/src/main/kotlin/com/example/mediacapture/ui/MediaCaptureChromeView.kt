package com.example.mediacapture.ui

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.util.AttributeSet
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.isGone
import com.example.mediacapture.api.FlashMode
import com.example.mediacapture.api.MediaType
import com.example.mediacapture.api.SessionReady
import com.example.mediacapture.rendering.MediaCaptureRenderView
import kotlin.math.roundToInt

@SuppressLint("ClickableViewAccessibility")
internal class MediaCaptureChromeView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : FrameLayout(context, attrs) {
    private val handler = Handler(Looper.getMainLooper())
    private val surfaceContainer = FrameLayout(context)
    private val bottomInsetScrim = View(context).apply { setBackgroundColor(Color.BLACK) }
    private val closeButton = CaptureIconButton(context, CaptureIcon.CLOSE, R.string.media_capture_cancel)
    private val switchButton = CaptureIconButton(context, CaptureIcon.SWITCH_CAMERA, R.string.media_capture_switch_camera)
    private val flashButton = CaptureIconButton(context, CaptureIcon.FLASH_OFF, R.string.media_capture_flash)
    private val shutterButton = CaptureButton(context)
    private val hintText =
        TextView(context).apply {
            setTextColor(Color.WHITE)
            textSize = 14f
            gravity = Gravity.CENTER
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        }
    private val bottomBar = CaptureControlBar(context)
    private val confirmLabel =
        TextView(context).apply {
            text = resources.getString(R.string.media_capture_send)
            setTextColor(Color.WHITE)
            textSize = 12f
            gravity = Gravity.CENTER
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
            background = pill(PRIMARY_BLUE, 16)
        }
    private val confirmButton =
        FrameLayout(context).apply {
            contentDescription = resources.getString(R.string.media_capture_confirm)
            isClickable = true
            isFocusable = true
            minimumWidth = dp(54)
            minimumHeight = dp(48)
            addView(
                confirmLabel,
                LayoutParams(dp(54), dp(32), Gravity.CENTER),
            )
        }
    private val previewBar =
        FrameLayout(context).apply {
            setBackgroundColor(Color.BLACK)
            visibility = GONE
        }

    private var callbacks: Callbacks? = null
    private var ready: SessionReady? = null
    private var enabledMediaTypes: Set<MediaType> = setOf(MediaType.PHOTO, MediaType.VIDEO)
    private var maxVideoDurationMillis = 60_000L
    private var currentZoom = 1.0
    private var currentFlashMode = FlashMode.OFF
    private var mode = Mode.LOADING
    private var focusGestureActive = false
    private var longPressRunnable: Runnable? = null
    private val gestures =
        CaptureGestureController(
            callbacks =
                object : CaptureGestureCallbacks {
                    override fun onPhotoClick() {
                        callbacks?.onTakePhoto()
                    }

                    override fun onRecordStart() {
                        callbacks?.onStartRecording()
                    }

                    override fun onRecordStop() {
                        callbacks?.onStopRecording()
                    }

                    override fun onZoomChanged(zoomFactor: Double) {
                        currentZoom = zoomFactor
                        callbacks?.onZoomChanged(zoomFactor)
                    }
                },
        )

    init {
        setBackgroundColor(Color.BLACK)
        fitsSystemWindows = false
        isFocusable = true
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        ViewCompat.setOnApplyWindowInsetsListener(this) { _, insets ->
            val safeInsets =
                insets.getInsets(
                    WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout(),
                )
            applyChromeInsets(safeInsets.left, safeInsets.top, safeInsets.right, safeInsets.bottom)
            insets
        }

        addView(
            surfaceContainer,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT),
        )
        surfaceContainer.setOnTouchListener(::handleSurfaceTouch)
        addView(bottomInsetScrim, bottomParams(0))

        bottomBar.setBackgroundColor(Color.BLACK)
        bottomBar.bind(flashButton, shutterButton, switchButton)
        bottomBar.addView(flashButton, FrameLayout.LayoutParams(dp(48), dp(48)))
        bottomBar.addView(shutterButton, FrameLayout.LayoutParams(dp(80), dp(80)))
        bottomBar.addView(switchButton, FrameLayout.LayoutParams(dp(48), dp(48)))
        previewBar.addView(
            confirmButton,
            FrameLayout.LayoutParams(dp(54), dp(48), Gravity.END or Gravity.CENTER_VERTICAL).apply {
                marginEnd = dp(16)
            },
        )

        addView(closeButton, topStartParams())
        addView(hintText, hintParams())
        addView(bottomBar, bottomParams(CONTROL_BAR_HEIGHT_DP))
        addView(previewBar, bottomParams(PREVIEW_BAR_HEIGHT_DP))

        closeButton.setOnClickListener {
            if (mode == Mode.PREVIEW) callbacks?.onRetake() else callbacks?.onCancel()
        }
        switchButton.setOnClickListener { callbacks?.onSwitchCamera() }
        flashButton.setOnClickListener { callbacks?.onCycleFlash() }
        confirmButton.setOnClickListener { callbacks?.onConfirm() }
        shutterButton.setGestureListener(::onShutterTouch)
        shutterButton.setOnClickListener {
            when (mode) {
                Mode.READY -> if (MediaType.PHOTO in enabledMediaTypes) callbacks?.onTakePhoto()
                Mode.RECORDING -> callbacks?.onStopRecording()
                else -> Unit
            }
        }
        shutterButton.setOnLongClickListener {
            if (mode == Mode.READY && MediaType.VIDEO in enabledMediaTypes) {
                callbacks?.onStartRecording()
                true
            } else {
                false
            }
        }
        applyState()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        ViewCompat.requestApplyInsets(this)
    }

    fun setCallbacks(callbacks: Callbacks?) {
        this.callbacks = callbacks
    }

    fun setEnabledMediaTypes(mediaTypes: Set<MediaType>) {
        enabledMediaTypes = mediaTypes.toSet()
        applyState()
    }

    fun setMaxVideoDurationMillis(durationMillis: Long) {
        require(durationMillis > 0L)
        maxVideoDurationMillis = durationMillis
    }

    fun showSurface(surface: MediaCaptureRenderView) {
        surfaceContainer.removeAllViews()
        surface.setOnTouchListener(::handleSurfaceTouch)
        surfaceContainer.addView(
            surface,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT),
        )
    }

    fun clearSurface() {
        surfaceContainer.removeAllViews()
    }

    fun showLoading() {
        mode = Mode.LOADING
        applyState()
    }

    fun showReady(
        snapshot: SessionReady,
        flashMode: FlashMode = initialFlashMode(snapshot),
        zoomFactor: Double = snapshot.minZoomFactor,
    ) {
        ready = snapshot
        currentZoom = zoomFactor.coerceIn(snapshot.minZoomFactor, snapshot.maxZoomFactor)
        setFlashMode(flashMode)
        mode = Mode.READY
        applyState()
    }

    fun showRecording(elapsedMillis: Long) {
        val enteredRecording = mode != Mode.RECORDING
        mode = Mode.RECORDING
        shutterButton.recordingProgress =
            (elapsedMillis.toFloat() / maxVideoDurationMillis.toFloat()).coerceIn(0f, 1f)
        if (enteredRecording) applyState()
    }

    fun showPreview() {
        mode = Mode.PREVIEW
        applyState()
    }

    fun showTerminal() {
        mode = Mode.TERMINAL
        applyState()
    }

    private fun applyState() {
        val snapshot = ready
        val canUseControls = mode == Mode.READY
        val photoEnabled = canUseControls && MediaType.PHOTO in enabledMediaTypes
        val videoEnabled = canUseControls && MediaType.VIDEO in enabledMediaTypes
        val flashVisible = canUseControls && snapshot?.supportedFlashModes.orEmpty().isNotEmpty()
        val switchVisible = canUseControls && snapshot?.switchCameraSupported == true

        gestures.configure(
            enabled = mode == Mode.READY || mode == Mode.RECORDING,
            photoEnabled = photoEnabled,
            videoEnabled = videoEnabled,
            currentZoom = currentZoom,
            minZoom = snapshot?.minZoomFactor ?: 1.0,
            maxZoom = snapshot?.maxZoomFactor ?: 1.0,
        )

        shutterButton.isEnabled = mode == Mode.READY || mode == Mode.RECORDING
        shutterButton.isRecording = mode == Mode.RECORDING
        bottomBar.setRecording(mode == Mode.RECORDING)
        switchButton.visibility = if (switchVisible) VISIBLE else INVISIBLE
        switchButton.isEnabled = switchVisible
        flashButton.visibility = if (flashVisible) VISIBLE else INVISIBLE
        flashButton.isEnabled = flashVisible
        bottomBar.visibility = if (mode == Mode.PREVIEW || mode == Mode.TERMINAL) GONE else VISIBLE
        previewBar.visibility = if (mode == Mode.PREVIEW) VISIBLE else GONE
        hintText.visibility =
            if (mode == Mode.READY && currentFlashMode != FlashMode.OFF) VISIBLE else GONE
        updateHintText()
        closeButton.visibility = if (mode == Mode.TERMINAL) GONE else VISIBLE
        closeButton.isEnabled = mode != Mode.TERMINAL
        closeButton.contentDescription =
            resources.getString(
                if (mode == Mode.PREVIEW) R.string.media_capture_retake else R.string.media_capture_cancel,
            )
        confirmButton.isEnabled = mode == Mode.PREVIEW
    }

    private fun onShutterTouch(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                if (!gestures.onDown(event.y)) return false
                longPressRunnable =
                    Runnable {
                        longPressRunnable = null
                        gestures.onLongPress()
                    }.also { handler.postDelayed(it, gestures.longPressMillis) }
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                gestures.onMove(event.y)
                return true
            }
            MotionEvent.ACTION_UP -> {
                longPressRunnable?.let(handler::removeCallbacks)
                longPressRunnable = null
                gestures.onUp(event.y)
                return true
            }
            MotionEvent.ACTION_CANCEL -> {
                longPressRunnable?.let(handler::removeCallbacks)
                longPressRunnable = null
                gestures.onCancel()
                return true
            }
        }
        return false
    }

    private fun handleSurfaceTouch(
        view: View,
        event: MotionEvent,
    ): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                focusGestureActive =
                    mode == Mode.READY && ready?.focusPointSupported == true &&
                        view.width > 0 && view.height > 0
                return focusGestureActive
            }
            MotionEvent.ACTION_MOVE -> return focusGestureActive
            MotionEvent.ACTION_UP -> {
                if (!focusGestureActive) return false
                focusGestureActive = false
                callbacks?.onFocusPoint(
                    (event.x / view.width.toDouble()).coerceIn(0.0, 1.0),
                    (event.y / view.height.toDouble()).coerceIn(0.0, 1.0),
                )
                return true
            }
            MotionEvent.ACTION_CANCEL -> {
                val consumed = focusGestureActive
                focusGestureActive = false
                return consumed
            }
        }
        return false
    }

    fun setFlashMode(mode: FlashMode) {
        currentFlashMode = mode
        val modeLabel =
            resources.getString(
                when (mode) {
                    FlashMode.OFF -> R.string.media_capture_flash_off
                    FlashMode.ON -> R.string.media_capture_flash_on
                    FlashMode.AUTO -> R.string.media_capture_flash_auto
                    FlashMode.TORCH -> R.string.media_capture_flash_torch
                },
            )
        flashButton.contentDescription = resources.getString(R.string.media_capture_flash_mode, modeLabel)
        flashButton.setIcon(if (mode == FlashMode.OFF) CaptureIcon.FLASH_OFF else CaptureIcon.FLASH_ON)
        flashButton.isSelected = mode != FlashMode.OFF
        updateHintText()
    }

    private fun updateHintText() {
        hintText.setText(R.string.media_capture_flash_enabled)
    }

    private fun initialFlashMode(snapshot: SessionReady): FlashMode =
        FlashMode.OFF.takeIf { it in snapshot.supportedFlashModes }
            ?: snapshot.supportedFlashModes.minByOrNull { it.ordinal }
            ?: currentFlashMode

    private fun topStartParams(): LayoutParams =
        LayoutParams(dp(48), dp(48), Gravity.TOP or Gravity.START).apply {
            marginStart = dp(4)
            topMargin = dp(MIN_TOP_CONTROL_MARGIN_DP)
        }

    private fun hintParams(): LayoutParams =
        LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT, Gravity.BOTTOM).apply {
            marginStart = dp(24)
            marginEnd = dp(24)
            bottomMargin = dp(CONTROL_BAR_HEIGHT_DP + 4)
        }

    private fun bottomParams(heightDp: Int): LayoutParams =
        LayoutParams(LayoutParams.MATCH_PARENT, dp(heightDp), Gravity.BOTTOM)

    private fun applyChromeInsets(
        left: Int,
        top: Int,
        right: Int,
        bottom: Int,
    ) {
        closeButton.layoutParams =
            (closeButton.layoutParams as LayoutParams).apply {
                marginStart = left + dp(4)
                topMargin = maxOf(top + dp(4), dp(MIN_TOP_CONTROL_MARGIN_DP))
            }
        hintText.layoutParams =
            (hintText.layoutParams as LayoutParams).apply {
                marginStart = left + dp(24)
                marginEnd = right + dp(24)
                bottomMargin = bottom + dp(CONTROL_BAR_HEIGHT_DP + 4)
            }
        bottomBar.layoutParams =
            (bottomBar.layoutParams as LayoutParams).apply {
                marginStart = left
                marginEnd = right
                bottomMargin = bottom
            }
        bottomInsetScrim.layoutParams =
            (bottomInsetScrim.layoutParams as LayoutParams).apply {
                height = bottom
                bottomMargin = 0
            }
        bottomInsetScrim.visibility = if (bottom > 0) VISIBLE else GONE
        previewBar.layoutParams =
            (previewBar.layoutParams as LayoutParams).apply {
                marginStart = left
                marginEnd = right
                bottomMargin = bottom
            }
        requestLayout()
    }

    private fun pill(
        color: Int,
        radiusDp: Int,
    ): GradientDrawable =
        GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(color)
            cornerRadius = dp(radiusDp).toFloat()
        }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).roundToInt()

    interface Callbacks {
        fun onTakePhoto()

        fun onStartRecording()

        fun onStopRecording()

        fun onZoomChanged(zoomFactor: Double)

        fun onSwitchCamera()

        fun onCycleFlash()

        fun onFocusPoint(
            normalizedX: Double,
            normalizedY: Double,
        )

        fun onRetake()

        fun onConfirm()

        fun onCancel()
    }

    private enum class Mode { LOADING, READY, RECORDING, PREVIEW, TERMINAL }

    private companion object {
        const val CONTROL_BAR_HEIGHT_DP = 112
        const val PREVIEW_BAR_HEIGHT_DP = 64
        const val MIN_TOP_CONTROL_MARGIN_DP = 12
        val PRIMARY_BLUE: Int = Color.rgb(0, 76, 255)
    }
}

private class CaptureControlBar(context: Context) : FrameLayout(context) {
    private lateinit var flashButton: View
    private lateinit var shutterButton: View
    private lateinit var switchButton: View
    private var recording = false

    fun bind(
        flashButton: View,
        shutterButton: View,
        switchButton: View,
    ) {
        this.flashButton = flashButton
        this.shutterButton = shutterButton
        this.switchButton = switchButton
    }

    fun setRecording(recording: Boolean) {
        if (this.recording == recording) return
        this.recording = recording
        val size = dp(if (recording) 98 else 80)
        shutterButton.layoutParams = shutterButton.layoutParams.apply {
            width = size
            height = size
        }
        requestLayout()
    }

    override fun onLayout(
        changed: Boolean,
        left: Int,
        top: Int,
        right: Int,
        bottom: Int,
    ) {
        super.onLayout(changed, left, top, right, bottom)
        val contentWidth = right - left
        val centerY = (bottom - top) / 2
        placeCentered(flashButton, (contentWidth * 78f / 375f).roundToInt(), centerY)
        placeCentered(shutterButton, contentWidth / 2, centerY)
        placeCentered(switchButton, (contentWidth * 298f / 375f).roundToInt(), centerY)
    }

    private fun placeCentered(
        child: View,
        centerX: Int,
        centerY: Int,
    ) {
        if (child.isGone) return
        val childLeft = centerX - child.measuredWidth / 2
        val childTop = centerY - child.measuredHeight / 2
        child.layout(
            childLeft,
            childTop,
            childLeft + child.measuredWidth,
            childTop + child.measuredHeight,
        )
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).roundToInt()
}

private enum class CaptureIcon { CLOSE, FLASH_OFF, FLASH_ON, SWITCH_CAMERA }

@SuppressLint("ViewConstructor")
private class CaptureIconButton(
    context: Context,
    private var icon: CaptureIcon,
    label: Int,
) : View(context) {
    private val paint =
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            strokeWidth = dp(1.8f)
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
    private val path = Path()

    init {
        contentDescription = resources.getString(label)
        minimumWidth = dp(48f).roundToInt()
        minimumHeight = dp(48f).roundToInt()
        isClickable = true
        isFocusable = true
    }

    fun setIcon(icon: CaptureIcon) {
        if (this.icon == icon) return
        this.icon = icon
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        when (icon) {
            CaptureIcon.CLOSE -> drawClose(canvas)
            CaptureIcon.FLASH_OFF -> drawFlash(canvas, slashed = true)
            CaptureIcon.FLASH_ON -> drawFlash(canvas, slashed = false)
            CaptureIcon.SWITCH_CAMERA -> drawSwitchCamera(canvas)
        }
    }

    private fun drawClose(canvas: Canvas) {
        paint.style = Paint.Style.STROKE
        val offset = dp(6f)
        canvas.drawLine(width / 2f - offset, height / 2f - offset, width / 2f + offset, height / 2f + offset, paint)
        canvas.drawLine(width / 2f + offset, height / 2f - offset, width / 2f - offset, height / 2f + offset, paint)
    }

    private fun drawFlash(
        canvas: Canvas,
        slashed: Boolean,
    ) {
        val centerX = width / 2f
        val centerY = height / 2f
        path.reset()
        path.moveTo(centerX + dp(1f), centerY - dp(11f))
        path.lineTo(centerX - dp(7f), centerY + dp(1f))
        path.lineTo(centerX - dp(1f), centerY + dp(1f))
        path.lineTo(centerX - dp(2f), centerY + dp(11f))
        path.lineTo(centerX + dp(7f), centerY - dp(2f))
        path.lineTo(centerX + dp(1f), centerY - dp(2f))
        path.close()
        paint.style = if (slashed) Paint.Style.STROKE else Paint.Style.FILL
        canvas.drawPath(path, paint)
        if (slashed) {
            canvas.drawLine(
                centerX - dp(10f),
                centerY - dp(10f),
                centerX + dp(10f),
                centerY + dp(10f),
                paint,
            )
        }
    }

    private fun drawSwitchCamera(canvas: Canvas) {
        val centerX = width / 2f
        val centerY = height / 2f
        paint.style = Paint.Style.STROKE
        val body = RectF(centerX - dp(10f), centerY - dp(7f), centerX + dp(10f), centerY + dp(8f))
        canvas.drawRoundRect(body, dp(3f), dp(3f), paint)
        path.reset()
        path.moveTo(centerX - dp(5f), centerY - dp(7f))
        path.lineTo(centerX - dp(2f), centerY - dp(10f))
        path.lineTo(centerX + dp(3f), centerY - dp(10f))
        path.lineTo(centerX + dp(6f), centerY - dp(7f))
        canvas.drawPath(path, paint)
        val lens = RectF(centerX - dp(5f), centerY - dp(5f), centerX + dp(5f), centerY + dp(5f))
        canvas.drawArc(lens, 210f, 150f, false, paint)
        canvas.drawArc(lens, 30f, 150f, false, paint)
        canvas.drawLine(centerX - dp(5f), centerY + dp(2f), centerX - dp(5f), centerY - dp(2f), paint)
        canvas.drawLine(centerX + dp(5f), centerY - dp(2f), centerX + dp(5f), centerY + dp(2f), paint)
    }

    private fun dp(value: Float): Float = value * resources.displayMetrics.density
}

private class CaptureButton(context: Context) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var listener: ((MotionEvent) -> Boolean)? = null

    var isRecording: Boolean = false
        set(value) {
            field = value
            contentDescription =
                resources.getString(
                    if (value) R.string.media_capture_stop_recording else R.string.media_capture_capture,
                )
            invalidate()
        }

    var recordingProgress: Float = 0f
        set(value) {
            field = value.coerceIn(0f, 1f)
            invalidate()
        }

    init {
        contentDescription = resources.getString(R.string.media_capture_capture)
        minimumWidth = dp(64)
        minimumHeight = dp(64)
        isClickable = true
        isFocusable = true
    }

    fun setGestureListener(listener: (MotionEvent) -> Boolean) {
        this.listener = listener
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent): Boolean =
        listener?.invoke(event) ?: super.onTouchEvent(event)

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (isRecording) drawRecording(canvas) else drawPhoto(canvas)
    }

    private fun drawPhoto(canvas: Canvas) {
        val centerX = width / 2f
        val centerY = height / 2f
        val radius = minOf(width, height) / 2f - dp(2)
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = dp(2).toFloat()
        paint.color = Color.WHITE
        canvas.drawCircle(centerX, centerY, radius, paint)
        paint.style = Paint.Style.FILL
        canvas.drawCircle(centerX, centerY, radius - dp(7), paint)
    }

    private fun drawRecording(canvas: Canvas) {
        val centerX = width / 2f
        val centerY = height / 2f
        val radius = minOf(width, height) / 2f - dp(3)
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = dp(6).toFloat()
        paint.strokeCap = Paint.Cap.ROUND
        paint.color = Color.rgb(164, 164, 164)
        canvas.drawCircle(centerX, centerY, radius, paint)
        paint.color = Color.rgb(47, 105, 255)
        val oval = RectF(centerX - radius, centerY - radius, centerX + radius, centerY + radius)
        canvas.drawArc(oval, -90f, 360f * recordingProgress, false, paint)
        paint.style = Paint.Style.FILL
        paint.color = Color.WHITE
        canvas.drawCircle(centerX, centerY, dp(16).toFloat(), paint)
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).roundToInt()
}
