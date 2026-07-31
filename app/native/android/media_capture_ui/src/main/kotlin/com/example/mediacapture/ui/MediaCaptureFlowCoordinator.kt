package com.example.mediacapture.ui

import android.content.Context
import android.os.SystemClock
import androidx.lifecycle.LifecycleOwner
import com.example.mediacapture.api.ConfirmedMedia
import com.example.mediacapture.api.FailureCode
import com.example.mediacapture.api.FlashMode
import com.example.mediacapture.api.MediaCapture
import com.example.mediacapture.api.MediaCaptureException
import com.example.mediacapture.api.MediaCaptureFailure
import com.example.mediacapture.api.MediaHandle
import com.example.mediacapture.api.MediaPreview
import com.example.mediacapture.api.SessionHandle
import com.example.mediacapture.api.SessionObservation
import com.example.mediacapture.api.SessionReady
import com.example.mediacapture.api.SessionState
import com.example.mediacapture.rendering.MediaCaptureRenderSurfaceOwner
import com.example.mediacapture.rendering.MediaCaptureRenderView
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

internal class MediaCaptureFlowCoordinator(
    private val context: Context,
    private val lifecycleOwner: LifecycleOwner,
    private val mediaCapture: MediaCapture,
    private val chrome: MediaCaptureChromeView,
    private val uiDispatcher: CoroutineDispatcher,
    private val generationSeed: AtomicLong = AtomicLong(0L),
    private val leaseCleanupOwner: MediaCaptureLeaseCleanupOwner =
        ProcessMediaCaptureLeaseCleanupOwner,
) : MediaCaptureChromeView.Callbacks {
    private val coordinatorJob = SupervisorJob()
    private val scope = CoroutineScope(coordinatorJob + uiDispatcher)
    private val result = CompletableDeferred<MediaCaptureFlowResult>()
    private val actionMutex = Mutex()
    private val terminalClaimed = AtomicBoolean(false)
    private val ownerClosed = AtomicBoolean(false)
    private val cleanupFailed = AtomicBoolean(false)
    private val leaseCleanupPending = AtomicBoolean(false)
    private val terminalCleanupFinalized = AtomicBoolean(false)
    private val presentationCleanupReported = AtomicBoolean(false)
    private val stateLock = Any()

    private var sessionHandle: SessionHandle? = null
    private var readySnapshot: SessionReady? = null
    private var preview: MediaPreview? = null
    private var surface: MediaCaptureRenderView? = null
    private var surfaceGeneration = 0L
    private var observationJob: Job? = null
    private var recordingTimerJob: Job? = null
    private var backgroundJob: Job? = null
    @Volatile private var activeActionJob: Job? = null
    private var flashMode = FlashMode.OFF
    private var recordingStartedAtMillis = 0L
    private var stopRecordingWhenStarted = false
    private var latestSessionState = SessionState.REQUESTING_PERMISSION
    @Volatile private var ownerBackgrounded = false
    private var foregroundPending = false
    @Volatile private var phase = Phase.STARTING
    private var terminalListener: ((Boolean) -> Unit)? = null
    private var cleanupRecoveredListener: (() -> Unit)? = null

    fun launch(block: suspend CoroutineScope.() -> Unit): Job = scope.launch(block = block)

    fun setTerminalListener(listener: (Boolean) -> Unit) {
        terminalListener = listener
    }

    fun setCleanupRecoveredListener(listener: () -> Unit) {
        cleanupRecoveredListener = listener
    }

    suspend fun awaitResult(): MediaCaptureFlowResult = result.await()

    internal fun isCompletedForTest(): Boolean = result.isCompleted

    suspend fun start(config: MediaCaptureUiConfig) {
        withContext(uiDispatcher) {
            chrome.setCallbacks(this@MediaCaptureFlowCoordinator)
            chrome.setEnabledMediaTypes(config.enabledMediaTypes)
            chrome.setMaxVideoDurationMillis(config.maxVideoDurationMillis)
            chrome.showLoading()
        }
        runAction(setOf(Phase.STARTING)) {
            val created = mediaCapture.startSession(config.toSessionOptions())
            val ownerAlreadyClosed =
                synchronized(stateLock) {
                    if (terminalClaimed.get() || ownerClosed.get()) {
                        true
                    } else {
                        sessionHandle = created.sessionHandle
                        false
                    }
                }
            if (ownerAlreadyClosed) {
                settleLateSession(created.sessionHandle)
                return@runAction
            }
            if (ownerBackgrounded) {
                mediaCapture.onAppBackgrounded()
            }
            observeSession(created.sessionHandle)
        }
    }

    fun presentationFailed(throwable: Throwable) {
        requestTerminal(MediaCaptureFlowResult.Failure(throwable.toCaptureFailure()))
    }

    fun rotateOwner() {
        scope.launch {
            runAction(setOf(Phase.READY, Phase.RECORDING, Phase.PREVIEW)) {
                mediaCapture.onDisplayRotationChanged()
                replaceSurfaceAndAttach()
            }
        }
    }

    fun backgroundOwner() {
        val actionToCancel =
            synchronized(stateLock) {
                if (terminalClaimed.get() || ownerClosed.get() || ownerBackgrounded) return
                ownerBackgrounded = true
                foregroundPending = false
                phase = Phase.BACKGROUNDED
                activeActionJob
            }
        actionToCancel?.cancel()
        stopRecordingTimer()
        backgroundJob =
            scope.launch {
                try {
                    mediaCapture.onAppBackgrounded()
                    val oldSurface = surface
                    surface = null
                    withContext(uiDispatcher) {
                        chrome.clearSurface()
                        chrome.showLoading()
                    }
                    if (oldSurface != null) {
                        mediaCapture.onPreviewOwnerDestroyed(oldSurface)
                    }
                } catch (throwable: Throwable) {
                    if (throwable is CancellationException) throw throwable
                    completeFromCurrent(
                        MediaCaptureFlowResult.Failure(throwable.toCaptureFailure()),
                        actionToAwait = actionToCancel,
                    )
                }
            }
    }

    fun foregroundOwner() {
        val pendingBackgroundJob =
            synchronized(stateLock) {
                if (
                    terminalClaimed.get() || ownerClosed.get() || !ownerBackgrounded ||
                    foregroundPending
                ) {
                    return
                }
                foregroundPending = true
                backgroundJob
            }
        scope.launch {
            try {
                pendingBackgroundJob?.join()
                synchronized(stateLock) {
                    if (terminalClaimed.get() || ownerClosed.get()) return@launch
                    ownerBackgrounded = false
                    foregroundPending = false
                    phase = restoredPhase()
                }
                replaceSurfaceAndAttach()
                withContext(uiDispatcher) { showRestoredChrome() }
            } catch (throwable: Throwable) {
                synchronized(stateLock) { foregroundPending = false }
                if (throwable is CancellationException) throw throwable
                completeFromCurrent(MediaCaptureFlowResult.Failure(throwable.toCaptureFailure()))
            }
        }
    }

    fun destroyOwner() {
        requestTerminal(
            MediaCaptureFlowResult.Failure(MediaCaptureFailure(FailureCode.SYSTEM_INTERRUPTED)),
        )
    }

    override fun onTakePhoto() {
        if (!claimPhase(Phase.READY, Phase.CAPTURING)) return
        scope.launch {
            runAction(setOf(Phase.CAPTURING)) {
                val handle = sessionHandle ?: return@runAction
                withContext(uiDispatcher) { chrome.showLoading() }
                showPreview(mediaCapture.takePhoto(handle))
            }
        }
    }

    override fun onStartRecording() {
        if (!claimPhase(Phase.READY, Phase.STARTING_RECORDING)) return
        synchronized(stateLock) { stopRecordingWhenStarted = false }
        scope.launch {
            runAction(setOf(Phase.STARTING_RECORDING)) {
                val handle = sessionHandle ?: return@runAction
                withContext(uiDispatcher) { chrome.showRecording(0L) }
                recordingStartedAtMillis = SystemClock.elapsedRealtime()
                mediaCapture.startRecording(handle)
                val stopImmediately =
                    synchronized(stateLock) {
                        if (ownerBackgrounded || terminalClaimed.get()) {
                            false
                        } else if (stopRecordingWhenStarted) {
                            stopRecordingWhenStarted = false
                            phase = Phase.STOPPING_RECORDING
                            true
                        } else {
                            phase = Phase.RECORDING
                            false
                        }
                    }
                if (stopImmediately) {
                    withContext(uiDispatcher) { chrome.showLoading() }
                    showPreview(mediaCapture.stopRecording(handle))
                } else if (!ownerBackgrounded && !terminalClaimed.get()) {
                    startRecordingTimer()
                }
            }
        }
    }

    override fun onStopRecording() {
        val stopNow =
            synchronized(stateLock) {
                when {
                    terminalClaimed.get() || ownerClosed.get() || ownerBackgrounded -> false
                    phase == Phase.STARTING_RECORDING -> {
                        stopRecordingWhenStarted = true
                        false
                    }
                    phase == Phase.RECORDING -> {
                        phase = Phase.STOPPING_RECORDING
                        true
                    }
                    else -> false
                }
            }
        if (!stopNow) return
        scope.launch {
            runAction(setOf(Phase.STOPPING_RECORDING)) {
                val handle = sessionHandle ?: return@runAction
                stopRecordingTimer()
                withContext(uiDispatcher) { chrome.showLoading() }
                showPreview(mediaCapture.stopRecording(handle))
            }
        }
    }

    override fun onZoomChanged(zoomFactor: Double) {
        if (phase != Phase.RECORDING) return
        scope.launch {
            val handle = sessionHandle ?: return@launch
            runAction(setOf(Phase.RECORDING)) { mediaCapture.setZoom(handle, zoomFactor) }
        }
    }

    override fun onSwitchCamera() {
        if (phase != Phase.READY) return
        scope.launch {
            val handle = sessionHandle ?: return@launch
            runAction(setOf(Phase.READY)) { mediaCapture.switchCamera(handle) }
        }
    }

    override fun onCycleFlash() {
        if (phase != Phase.READY) return
        scope.launch {
            val handle = sessionHandle ?: return@launch
            val snapshot = readySnapshot ?: return@launch
            val modes = snapshot.supportedFlashModes.sortedBy { it.ordinal }
            if (modes.isEmpty()) return@launch
            val currentIndex = modes.indexOf(flashMode).takeIf { it >= 0 } ?: -1
            val next = modes[(currentIndex + 1) % modes.size]
            runAction(setOf(Phase.READY)) {
                mediaCapture.setFlashMode(handle, next)
                flashMode = next
                withContext(uiDispatcher) { chrome.setFlashMode(next) }
            }
        }
    }

    override fun onFocusPoint(normalizedX: Double, normalizedY: Double) {
        if (phase != Phase.READY) return
        scope.launch {
            val handle = sessionHandle ?: return@launch
            val snapshot = readySnapshot ?: return@launch
            if (!snapshot.focusPointSupported) return@launch
            runAction(setOf(Phase.READY)) {
                mediaCapture.setFocusPoint(
                    handle,
                    normalizedX.coerceIn(0.0, 1.0),
                    normalizedY.coerceIn(0.0, 1.0),
                )
            }
        }
    }

    override fun onRetake() {
        if (!claimPhase(Phase.PREVIEW, Phase.RETAKING)) return
        scope.launch {
            runAction(setOf(Phase.RETAKING)) {
                val mediaHandle = preview?.mediaHandle ?: return@runAction
                withContext(uiDispatcher) { chrome.showLoading() }
                val retakenSession = mediaCapture.retake(mediaHandle)
                preview = null
                sessionHandle = retakenSession
                replaceSurfaceAndAttach()
                phase = Phase.READY
                readySnapshot?.let { snapshot ->
                    withContext(uiDispatcher) { chrome.showReady(snapshot, flashMode) }
                }
            }
        }
    }

    override fun onConfirm() {
        if (!claimPhase(Phase.PREVIEW, Phase.CONFIRMING)) return
        scope.launch {
            runAction(setOf(Phase.CONFIRMING)) {
                val mediaHandle = preview?.mediaHandle ?: return@runAction
                completeConfirmed(mediaCapture.confirm(mediaHandle))
            }
        }
    }

    override fun onCancel() {
        requestTerminal(MediaCaptureFlowResult.Cancelled)
    }

    fun cancelFromPresenter() {
        requestTerminal(MediaCaptureFlowResult.Cancelled)
    }

    private fun observeSession(handle: SessionHandle) {
        observationJob?.cancel()
        observationJob =
            scope.launch {
                try {
                    mediaCapture.sessionObservation(handle).collect { observation ->
                        actionMutex.withLock {
                            if (!terminalClaimed.get()) applyObservation(observation)
                        }
                    }
                } catch (throwable: Throwable) {
                    if (throwable is CancellationException) throw throwable
                    completeFromCurrent(MediaCaptureFlowResult.Failure(throwable.toCaptureFailure()))
                }
            }
    }

    private suspend fun applyObservation(observation: SessionObservation) {
        if (terminalClaimed.get()) return
        latestSessionState = observation.state
        observation.ready?.let { readySnapshot = defensiveReady(it) }
        observation.preview?.let {
            stopRecordingTimer()
            if (ownerBackgrounded) {
                preview = it
            } else {
                showPreview(it)
            }
        }
        if (observation.terminalFailure != null || observation.state == SessionState.FAILED) {
            completeFromCurrent(
                MediaCaptureFlowResult.Failure(
                    observation.terminalFailure ?: MediaCaptureFailure(FailureCode.SYSTEM_INTERRUPTED),
                ),
            )
            return
        }
        if (observation.state == SessionState.CANCELLED) {
            completeFromCurrent(MediaCaptureFlowResult.Cancelled)
            return
        }
        if (ownerBackgrounded || observation.preview != null) return
        when (observation.state) {
            SessionState.READY -> {
                if (phase == Phase.STARTING || phase == Phase.READY || phase == Phase.RETAKING) {
                    phase = Phase.READY
                }
                val snapshot = readySnapshot ?: return
                selectInitialFlashMode(snapshot)
                withContext(uiDispatcher) { chrome.showReady(snapshot, flashMode) }
                if (surface == null) replaceSurfaceAndAttach()
            }
            SessionState.RECORDING -> {
                if (phase == Phase.STARTING_RECORDING || phase == Phase.RECORDING) {
                    phase = Phase.RECORDING
                }
            }
            else -> Unit
        }
    }

    private suspend fun showPreview(nextPreview: MediaPreview) {
        stopRecordingTimer()
        val alreadyAttached = preview?.mediaHandle == nextPreview.mediaHandle && surface != null
        preview = nextPreview
        latestSessionState = SessionState.PREVIEWING
        if (ownerBackgrounded || terminalClaimed.get()) return
        phase = Phase.PREVIEW
        if (!alreadyAttached) replaceSurfaceAndAttach()
        withContext(uiDispatcher) { chrome.showPreview() }
    }

    private suspend fun replaceSurfaceAndAttach() {
        if (terminalClaimed.get() || ownerClosed.get() || ownerBackgrounded) return
        val activeSession = sessionHandle
        val activePreview = preview
        val oldSurface = surface
        if (oldSurface != null) {
            mediaCapture.onPreviewOwnerDestroyed(oldSurface)
            if (surface === oldSurface) surface = null
        }
        val ownerGeneration = generationSeed.incrementAndGet()
        surfaceGeneration = ownerGeneration
        val newSurface =
            mediaCapture.createRenderView(
                MediaCaptureRenderSurfaceOwner(context, lifecycleOwner, ownerGeneration),
            )
        if (terminalClaimed.get() || ownerClosed.get() || ownerBackgrounded) {
            try {
                mediaCapture.onPreviewOwnerDestroyed(newSurface)
            } catch (throwable: Throwable) {
                cleanupFailed.set(true)
            }
            return
        }
        surface = newSurface
        withContext(uiDispatcher) { chrome.showSurface(newSurface) }
        if (activePreview != null) {
            mediaCapture.attachUnconfirmedPreview(activePreview.mediaHandle, newSurface, ownerGeneration)
        } else if (activeSession != null && readySnapshot != null) {
            mediaCapture.attachLivePreview(activeSession, newSurface, ownerGeneration)
        }
    }

    private suspend fun runAction(
        allowedPhases: Set<Phase>,
        action: suspend () -> Unit,
    ) {
        if (!canRunAction(allowedPhases)) return
        actionMutex.withLock {
            val currentJob = currentCoroutineContext()[Job]
            val registered =
                synchronized(stateLock) {
                    if (!canRunAction(allowedPhases)) {
                        false
                    } else {
                        activeActionJob = currentJob
                        true
                    }
                }
            if (!registered) return@withLock
            try {
                action()
            } catch (throwable: Throwable) {
                if (throwable is CancellationException) {
                    if (!terminalClaimed.get() && !ownerBackgrounded) throw throwable
                } else {
                    completeFromCurrent(MediaCaptureFlowResult.Failure(throwable.toCaptureFailure()))
                }
            } finally {
                synchronized(stateLock) {
                    if (activeActionJob === currentJob) activeActionJob = null
                }
            }
        }
    }

    private fun canRunAction(allowedPhases: Set<Phase>): Boolean =
        !terminalClaimed.get() && !ownerClosed.get() && !ownerBackgrounded && phase in allowedPhases

    private fun claimPhase(expected: Phase, next: Phase): Boolean =
        synchronized(stateLock) {
            if (
                terminalClaimed.get() || ownerClosed.get() || ownerBackgrounded ||
                phase != expected
            ) {
                false
            } else {
                phase = next
                true
            }
        }

    private fun requestTerminal(flowResult: MediaCaptureFlowResult) {
        val actionToCancel =
            synchronized(stateLock) {
                if (!terminalClaimed.compareAndSet(false, true)) return
                ownerClosed.set(true)
                val active = activeActionJob
                phase = Phase.TERMINAL
                foregroundPending = false
                active
            }
        actionToCancel?.cancel()
        scope.launch { finishCompletion(flowResult, actionToCancel) }
    }

    private suspend fun completeFromCurrent(
        flowResult: MediaCaptureFlowResult,
        actionToAwait: Job? = null,
    ) {
        if (!terminalClaimed.compareAndSet(false, true)) return
        ownerClosed.set(true)
        synchronized(stateLock) {
            phase = Phase.TERMINAL
            foregroundPending = false
        }
        finishCompletion(flowResult, actionToAwait)
    }

    private suspend fun completeConfirmed(confirmed: ConfirmedMedia) {
        if (!terminalClaimed.compareAndSet(false, true)) {
            withContext(NonCancellable) {
                try {
                    releaseLeaseOrRetain(confirmed.mediaHandle)
                } catch (throwable: Throwable) {
                    cleanupFailed.set(true)
                }
            }
            return
        }
        ownerClosed.set(true)
        synchronized(stateLock) {
            phase = Phase.TERMINAL
            foregroundPending = false
        }
        finishCompletion(MediaCaptureFlowResult.Confirmed(confirmed))
    }

    private suspend fun finishCompletion(
        flowResult: MediaCaptureFlowResult,
        actionToAwait: Job? = null,
    ) =
        withContext(NonCancellable) {
            val currentJob = currentCoroutineContext()[Job]
            if (observationJob !== currentJob) observationJob?.cancel()
            if (backgroundJob !== currentJob) backgroundJob?.cancel()
            stopRecordingTimer()
            if (flowResult !is MediaCaptureFlowResult.Confirmed) {
                settleSessionForTerminal()
            }
            if (actionToAwait != null && actionToAwait !== currentJob) {
                val settled = withTimeoutOrNull(5_000L) { actionToAwait.join() } != null
                if (!settled) cleanupFailed.set(true)
            }
            val oldSurface = surface
            surface = null
            ownerBackgrounded = false
            try {
                withContext(uiDispatcher) {
                    chrome.showTerminal()
                    chrome.clearSurface()
                    chrome.setCallbacks(null)
                }
            } catch (throwable: Throwable) {
                cleanupFailed.set(true)
            }
            if (oldSurface != null) {
                try {
                    mediaCapture.onPreviewOwnerDestroyed(oldSurface)
                } catch (throwable: Throwable) {
                    cleanupFailed.set(true)
                }
            }
            terminalCleanupFinalized.set(true)
            val presentationCleanupSucceeded =
                !cleanupFailed.get() && !leaseCleanupPending.get()
            try {
                terminalListener?.invoke(presentationCleanupSucceeded)
            } catch (throwable: Throwable) {
                cleanupFailed.set(true)
            }
            presentationCleanupReported.set(true)
            if (
                !presentationCleanupSucceeded && !leaseCleanupPending.get() &&
                !cleanupFailed.get()
            ) {
                cleanupRecoveredListener?.invoke()
            }
            result.complete(flowResult)
            coordinatorJob.cancel()
        }

    private suspend fun settleLateSession(handle: SessionHandle) {
        withContext(NonCancellable) {
            try {
                mediaCapture.cancel(handle)
            } catch (throwable: Throwable) {
                cleanupFailed.set(true)
            }
        }
    }

    private suspend fun settleSessionForTerminal() {
        val handle = sessionHandle ?: return
        try {
            mediaCapture.cancel(handle)
            return
        } catch (throwable: Throwable) {
            // Confirm may have committed the lease before cancellation became
            // observable. The retained preview handle is the stable fallback.
        }
        val mediaHandle = preview?.mediaHandle
        if (mediaHandle == null) {
            cleanupFailed.set(true)
            return
        }
        try {
            releaseLeaseOrRetain(mediaHandle)
        } catch (throwable: Throwable) {
            cleanupFailed.set(true)
        }
    }

    private suspend fun releaseLeaseOrRetain(mediaHandle: MediaHandle) {
        repeat(IMMEDIATE_RELEASE_ATTEMPTS) { attempt ->
            try {
                mediaCapture.releaseMedia(mediaHandle)
                return
            } catch (throwable: Throwable) {
                if (throwable is CancellationException) throw throwable
                val failureCode = (throwable as? MediaCaptureException)?.failure?.code
                if (failureCode == FailureCode.MEDIA_INVALID) return
                if (attempt + 1 < IMMEDIATE_RELEASE_ATTEMPTS) {
                    delay(IMMEDIATE_RELEASE_RETRY_MILLIS)
                }
            }
        }
        retainLeaseCleanup(mediaHandle)
    }

    private fun retainLeaseCleanup(mediaHandle: MediaHandle) {
        if (!leaseCleanupPending.compareAndSet(false, true)) return
        leaseCleanupOwner.retain(mediaCapture, mediaHandle) {
            leaseCleanupPending.set(false)
            if (
                terminalCleanupFinalized.get() && presentationCleanupReported.get() &&
                !cleanupFailed.get()
            ) {
                cleanupRecoveredListener?.invoke()
            }
        }
    }

    private fun startRecordingTimer() {
        recordingTimerJob?.cancel()
        recordingTimerJob =
            scope.launch(uiDispatcher) {
                while (!terminalClaimed.get() && phase == Phase.RECORDING) {
                    chrome.showRecording(SystemClock.elapsedRealtime() - recordingStartedAtMillis)
                    delay(250L)
                }
            }
    }

    private fun stopRecordingTimer() {
        recordingTimerJob?.cancel()
        recordingTimerJob = null
    }

    private fun defensiveReady(snapshot: SessionReady): SessionReady =
        snapshot.copy(
            availableCameras = snapshot.availableCameras.toSet(),
            supportedFlashModes = snapshot.supportedFlashModes.toSet(),
        )

    private fun selectInitialFlashMode(snapshot: SessionReady) {
        if (flashMode !in snapshot.supportedFlashModes) {
            flashMode =
                FlashMode.OFF.takeIf { it in snapshot.supportedFlashModes }
                    ?: snapshot.supportedFlashModes.minByOrNull { it.ordinal }
                    ?: FlashMode.OFF
        }
    }

    private fun restoredPhase(): Phase =
        when {
            preview != null -> Phase.PREVIEW
            latestSessionState == SessionState.RECORDING -> Phase.RECORDING
            readySnapshot != null -> Phase.READY
            else -> Phase.STARTING
        }

    private fun showRestoredChrome() {
        when {
            preview != null -> chrome.showPreview()
            latestSessionState == SessionState.RECORDING -> {
                phase = Phase.RECORDING
                chrome.showRecording(SystemClock.elapsedRealtime() - recordingStartedAtMillis)
                startRecordingTimer()
            }
            readySnapshot != null -> chrome.showReady(checkNotNull(readySnapshot), flashMode)
            else -> chrome.showLoading()
        }
    }

    internal fun currentOwnerGenerationForTest(): Long = surfaceGeneration

    private enum class Phase {
        STARTING,
        READY,
        CAPTURING,
        STARTING_RECORDING,
        RECORDING,
        STOPPING_RECORDING,
        PREVIEW,
        RETAKING,
        CONFIRMING,
        BACKGROUNDED,
        TERMINAL,
    }

    private companion object {
        const val IMMEDIATE_RELEASE_ATTEMPTS = 2
        const val IMMEDIATE_RELEASE_RETRY_MILLIS = 50L
    }
}
