@file:OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)

package com.example.mediacapture

import com.example.mediacapture.api.FailureCode
import com.example.mediacapture.api.MediaMetadata
import com.example.mediacapture.api.MediaState
import com.example.mediacapture.api.MediaType
import com.example.mediacapture.api.SessionState
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest

class ReviewRegressionTest {
    @Test
    fun `responsive framework cancellation drains without releasing capture gate`() = runTest {
        val module = TestModule(this)
        val session = startReady(module, options(setOf(MediaType.PHOTO)))
        val gate = CompletableDeferred<Unit>()
        module.framework.photoGate = gate
        val capture = launch { runCatching { module.core.takePhoto(session) } }
        runCurrent()

        val cancel = async { module.core.cancel(session) }
        runCurrent()

        cancel.await()
        capture.join()
        assertFalse(gate.isCompleted)
        assertEquals(1, module.framework.closeCount)
        module.core.close()
    }

    @Test
    fun `nonresponsive framework drain times out and poisons reuse`() = runTest {
        val module = TestModule(this)
        val session = startReady(module, options(setOf(MediaType.PHOTO)))
        val gate = CompletableDeferred<Unit>()
        module.framework.photoGate = gate
        module.framework.photoIgnoresCancellation = true
        val capture = backgroundScope.launch { runCatching { module.core.takePhoto(session) } }
        runCurrent()

        val cancel = async { module.core.cancel(session) }
        runCurrent()
        assertFalse(cancel.isCompleted)

        advanceTimeBy(5_000)
        runCurrent()
        cancel.await()
        assertEquals(0, module.framework.closeCount)
        assertEquals(FailureCode.SESSION_CONFLICT, failureCode { module.core.startSession(options()) })

        gate.complete(Unit)
        runCurrent()
        capture.join()
        module.core.close()
    }

    @Test
    fun `retake poisons photo stuck in final cleanup after preview publication`() = runTest {
        val module = TestModule(this)
        val session = startReady(module, options(setOf(MediaType.PHOTO)))
        val cleanupGate = CompletableDeferred<Unit>()
        val cleanupEntered = CompletableDeferred<Unit>()
        module.framework.pendingCleanupDrainGate = cleanupGate
        module.framework.onPendingCleanupDrain = { cleanupEntered.complete(Unit) }
        val capture = backgroundScope.launch { runCatching { module.core.takePhoto(session) } }
        runCurrent()

        assertTrue(cleanupEntered.isCompleted)
        val observation = module.core.sessionObservation(session).value
        assertEquals(SessionState.PREVIEWING, observation.state)
        val preview = requireNotNull(observation.preview)
        assertFalse(capture.isCompleted)

        val retake = async { module.core.retake(preview.mediaHandle) }
        runCurrent()
        assertFalse(retake.isCompleted)
        advanceTimeBy(5_000)
        runCurrent()

        assertEquals(session, retake.await())
        assertEquals(SessionState.READY, module.core.sessionState(session))
        assertNull(module.core.sessionObservation(session).value.preview)
        assertEquals(MediaState.DISCARDED, module.core.mediaState(preview.mediaHandle))
        assertEquals(FailureCode.INVALID_STATE, failureCode { module.core.takePhoto(session) })

        val restart = async { module.core.onAppRestarted() }
        runCurrent()
        restart.await()
        assertEquals(FailureCode.SESSION_CONFLICT, failureCode { module.core.startSession(options()) })
        assertEquals(0, module.framework.closeCount)

        cleanupGate.complete(Unit)
        runCurrent()
        capture.join()
        module.core.close()
    }

    @Test
    fun `nonresponsive prepare times out lifecycle and poisons reuse`() = runTest {
        val module = TestModule(this)
        val gate = CompletableDeferred<Unit>()
        module.framework.prepareGate = gate
        module.framework.prepareIgnoresCancellation = true
        val session = module.core.startSession(options()).sessionHandle
        runCurrent()
        assertEquals(SessionState.PREPARING, module.core.sessionState(session))

        val cancel = async { module.core.cancel(session) }
        runCurrent()
        assertFalse(cancel.isCompleted)
        advanceTimeBy(5_000)
        runCurrent()

        cancel.await()
        assertEquals(0, module.framework.closeCount)
        assertEquals(FailureCode.SESSION_CONFLICT, failureCode { module.core.startSession(options()) })

        gate.complete(Unit)
        runCurrent()
        module.core.close()
    }

    @Test
    fun `cancel drains old photo before framework can serve replacement session`() = runTest {
        val module = TestModule(this)
        val session = startReady(module, options(setOf(MediaType.PHOTO)))
        val gate = CompletableDeferred<Unit>()
        module.framework.photoGate = gate
        module.framework.photoIgnoresCancellation = true
        val capture = async { runCatching { module.core.takePhoto(session) } }
        runCurrent()

        val cancel = async { module.core.cancel(session) }
        runCurrent()
        assertFalse(cancel.isCompleted)
        assertEquals(FailureCode.SESSION_CONFLICT, failureCode { module.core.startSession(options()) })

        gate.complete(Unit)
        runCurrent()
        capture.join()
        assertTrue(capture.isCancelled)
        cancel.await()
        assertEquals(1, module.files.deleted.size)

        module.framework.photoGate = null
        val replacement = startReady(module)
        assertEquals(SessionState.READY, module.core.sessionState(replacement))
        module.core.cancel(replacement)
        module.core.close()
    }

    @Test
    fun `cancel drains old recording stop and control before replacement`() = runTest {
        val recordingModule = TestModule(this)
        val recordingSession =
            startReady(recordingModule, options(setOf(MediaType.VIDEO)))
        recordingModule.core.startRecording(recordingSession)
        val stopGate = CompletableDeferred<Unit>()
        recordingModule.framework.stopRecordingGate = stopGate
        recordingModule.framework.stopRecordingIgnoresCancellation = true
        val stop = async { runCatching { recordingModule.core.stopRecording(recordingSession) } }
        runCurrent()
        val recordingCancel = async { recordingModule.core.cancel(recordingSession) }
        runCurrent()
        assertFalse(recordingCancel.isCompleted)
        stopGate.complete(Unit)
        runCurrent()
        stop.join()
        assertTrue(stop.isCancelled)
        recordingCancel.await()
        assertEquals(1, recordingModule.files.deleted.size)
        recordingModule.core.close()

        val controlModule = TestModule(this)
        val controlSession = startReady(controlModule)
        val controlGate = CompletableDeferred<Unit>()
        controlModule.framework.controlGate = controlGate
        controlModule.framework.controlIgnoresCancellation = true
        val control = async { runCatching { controlModule.core.setZoom(controlSession, 2.0) } }
        runCurrent()
        val controlCancel = async { controlModule.core.cancel(controlSession) }
        runCurrent()
        assertFalse(controlCancel.isCompleted)
        assertEquals(FailureCode.SESSION_CONFLICT, failureCode { controlModule.core.startSession(options()) })
        controlGate.complete(Unit)
        runCurrent()
        control.join()
        assertTrue(control.isCancelled)
        controlCancel.await()
        controlModule.framework.controlGate = null
        val replacement = startReady(controlModule)
        controlModule.core.cancel(replacement)
        controlModule.core.close()
    }

    @Test
    fun `concurrent captures serialize and second caller revalidates session state`() = runTest {
        val module = TestModule(this)
        val session = startReady(module, options(setOf(MediaType.PHOTO)))
        val gate = CompletableDeferred<Unit>()
        module.framework.photoGate = gate
        val first = async { module.core.takePhoto(session) }
        runCurrent()
        val second = async { failureCode { module.core.takePhoto(session) } }
        runCurrent()

        assertFalse(first.isCompleted)
        assertFalse(second.isCompleted)
        gate.complete(Unit)
        runCurrent()

        first.await()
        assertEquals(FailureCode.INVALID_STATE, second.await())
        assertEquals(1, module.framework.photoIndex)
        module.core.cancel(session)
        module.core.close()
    }

    @Test
    fun `framework close failure poisons owner without reuse or hidden retry`() = runTest {
        val module = TestModule(this)
        val session = startReady(module)
        module.framework.closeFailure = IllegalStateException("camera close failed")

        module.core.cancel(session)

        assertEquals(1, module.framework.closeCount)
        assertEquals(FailureCode.SESSION_CONFLICT, failureCode { module.core.startSession(options()) })
        module.core.onAppRestarted()
        assertEquals(FailureCode.SESSION_CONFLICT, failureCode { module.core.startSession(options()) })
        assertEquals(1, module.framework.closeCount)
        module.core.close()
        assertEquals(1, module.framework.closeCount)
    }

    @Test
    fun `terminal media becomes cleanup pending before delete retry and preview is cleared`() = runTest {
        val module = TestModule(this)
        val session = startReady(module, options(setOf(MediaType.PHOTO)))
        val preview = module.core.takePhoto(session)
        assertNotNull(module.core.sessionObservation(session).value.preview)
        module.files.deleteSucceeds = false

        module.core.cancel(session)

        assertEquals(MediaState.DISCARDED, module.core.mediaState(preview.mediaHandle))
        assertNull(module.core.sessionObservation(session).value.preview)
        assertEquals(
            FailureCode.INVALID_STATE,
            failureCode {
                module.core.attachUnconfirmedPreview(preview.mediaHandle, FakeRenderAdapter(), 1)
            },
        )
        module.files.deleteSucceeds = true
        module.clock.now += 1_000
        advanceTimeBy(1_000)
        runCurrent()
        assertEquals(MediaState.DISCARDED, module.core.mediaState(preview.mediaHandle))
        module.core.close()
    }

    @Test
    fun `retake and timeout clear preview for late state flow subscribers`() = runTest {
        val retakeModule = TestModule(this)
        val retakeSession = startReady(retakeModule, options(setOf(MediaType.PHOTO)))
        val first = retakeModule.core.takePhoto(retakeSession)
        retakeModule.core.retake(first.mediaHandle)
        assertEquals(SessionState.READY, retakeModule.core.sessionObservation(retakeSession).value.state)
        assertNull(retakeModule.core.sessionObservation(retakeSession).value.preview)
        retakeModule.core.cancel(retakeSession)
        retakeModule.core.close()

        val timeoutModule = TestModule(this)
        val timeoutSession = startReady(timeoutModule, options(setOf(MediaType.PHOTO)))
        timeoutModule.core.takePhoto(timeoutSession)
        timeoutModule.clock.now += 600_000
        advanceTimeBy(600_000)
        runCurrent()
        assertEquals(SessionState.FAILED, timeoutModule.core.sessionObservation(timeoutSession).value.state)
        assertNull(timeoutModule.core.sessionObservation(timeoutSession).value.preview)
        timeoutModule.core.close()
    }

    @Test
    fun `framework pending cleanup transfers to module retry owner`() = runTest {
        val module = TestModule(this)
        val session = startReady(module)
        val pending = FakeStoredMedia(9_999)
        module.framework.pendingCleanupReferences += pending
        module.files.deleteSucceeds = false

        module.core.setFlashMode(session, com.example.mediacapture.api.FlashMode.OFF)
        module.clock.now += 1_000
        advanceTimeBy(1_000)
        runCurrent()
        assertTrue(module.files.deleted.contains(pending))

        module.files.deleteSucceeds = true
        module.clock.now += 1_000
        advanceTimeBy(1_000)
        runCurrent()
        assertTrue(module.files.deleted.count { it == pending } >= 2)
        module.core.cancel(session)
        module.core.close()
    }

    @Test
    fun `cancel waits stale prepare cleanup and blocks immediate replacement`() = runTest {
        val module = TestModule(this)
        val gate = CompletableDeferred<Unit>()
        module.framework.prepareGate = gate
        module.framework.prepareIgnoresCancellation = true
        val session = module.core.startSession(options()).sessionHandle
        runCurrent()
        assertEquals(SessionState.PREPARING, module.core.sessionState(session))

        val cancel = async { module.core.cancel(session) }
        runCurrent()
        assertFalse(cancel.isCompleted)
        assertEquals(FailureCode.SESSION_CONFLICT, failureCode { module.core.startSession(options()) })

        gate.complete(Unit)
        runCurrent()
        cancel.await()
        assertEquals(1, module.framework.closeCount)

        module.framework.prepareGate = null
        val replacement = startReady(module)
        assertEquals(SessionState.READY, module.core.sessionState(replacement))
        module.core.cancel(replacement)
        module.core.close()
    }

    @Test
    fun `old recording timer cannot stop a later recording generation`() = runTest {
        val module = TestModule(this)
        val session = startReady(module, options(setOf(MediaType.VIDEO), duration = 1_000))
        module.core.startRecording(session)
        runCurrent()
        advanceTimeBy(400)
        val first = module.core.stopRecording(session)
        module.core.retake(first.mediaHandle)
        module.core.startRecording(session)
        runCurrent()

        advanceTimeBy(600)
        runCurrent()
        assertEquals(SessionState.RECORDING, module.core.sessionState(session))

        val second = module.core.stopRecording(session)
        assertTrue(second.mediaHandle != first.mediaHandle)
        module.core.cancel(session)
        module.core.close()
    }

    @Test
    fun `capture cancellation and invalid output never orphan uncommitted media`() = runTest {
        val module = TestModule(this)
        val session = startReady(module, options(setOf(MediaType.PHOTO)))
        lateinit var capture: kotlinx.coroutines.Job
        module.framework.onPhotoProduced = { capture.cancel() }
        capture = launch(start = kotlinx.coroutines.CoroutineStart.LAZY) { module.core.takePhoto(session) }
        capture.start()
        runCurrent()
        capture.join()
        assertEquals(1, module.files.deleted.size)

        module.framework.onPhotoProduced = null
        module.framework.nextPhotoMetadata =
            MediaMetadata(MediaType.PHOTO, 0, 10, null, 0, 10, "image/jpeg")
        assertEquals(FailureCode.ENCODING_FAILED, failureCode { module.core.takePhoto(session) })
        assertEquals(2, module.files.deleted.size)
        module.core.close()
    }

    @Test
    fun `handle exhaustion cleans captured file and reports encoding failure`() = runTest {
        val module = TestModule(this)
        module.handles.fixed = "one-module-handle-with-enough-entropy"
        val session = startReady(module, options(setOf(MediaType.PHOTO)))

        assertEquals(FailureCode.ENCODING_FAILED, failureCode { module.core.takePhoto(session) })
        assertEquals(1, module.files.deleted.size)
        assertEquals(SessionState.FAILED, module.core.sessionState(session))
        module.core.close()
    }

    @Test
    fun `delete failure does not announce read revoked and retries deterministically`() = runTest {
        val module = TestModule(this)
        val media = captureConfirmedPhoto(module)
        module.files.deleteSucceeds = false
        module.core.releaseMedia(media)
        module.clock.now += 60_000
        advanceTimeBy(60_000)
        runCurrent()
        assertEquals(MediaState.RELEASE_GRACE, module.core.mediaState(media))

        module.files.deleteSucceeds = true
        module.clock.now += 1_000
        advanceTimeBy(1_000)
        runCurrent()
        assertEquals(MediaState.RELEASED, module.core.mediaState(media))
        module.core.close()
    }

    @Test
    fun `late subscriber sees ready snapshot and option sets are defensive copies`() = runTest {
        val module = TestModule(this)
        val enabled = mutableSetOf(MediaType.PHOTO)
        val cameras = mutableSetOf(com.example.mediacapture.api.CameraPosition.REAR)
        val flashes = mutableSetOf(com.example.mediacapture.api.FlashMode.OFF)
        module.framework.prepared =
            module.framework.prepared.copy(
                availableCameras = cameras,
                supportedFlashModes = flashes,
            )
        val session = module.core.startSession(options(enabled = enabled)).sessionHandle
        enabled.clear()
        enabled += MediaType.VIDEO
        runCurrent()
        cameras += com.example.mediacapture.api.CameraPosition.FRONT
        flashes += com.example.mediacapture.api.FlashMode.TORCH

        val observation = module.core.sessionObservation(session).value
        assertEquals(SessionState.READY, observation.state)
        assertNotNull(observation.ready)
        assertEquals(setOf(com.example.mediacapture.api.CameraPosition.REAR), observation.ready.availableCameras)
        assertEquals(setOf(com.example.mediacapture.api.FlashMode.OFF), observation.ready.supportedFlashModes)
        module.core.takePhoto(session)
        module.core.cancel(session)
        module.core.close()
    }
}
