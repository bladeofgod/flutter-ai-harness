@file:OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)

package com.example.mediacapture

import com.example.mediacapture.api.FailureCode
import com.example.mediacapture.api.FlashMode
import com.example.mediacapture.api.MediaCaptureEvent
import com.example.mediacapture.api.MediaState
import com.example.mediacapture.api.MediaType
import com.example.mediacapture.api.PermissionResource
import com.example.mediacapture.api.PermissionState
import com.example.mediacapture.api.SessionState
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest

class MediaCaptureCoreStateTest {
    @Test
    fun `start is immediate requests camera only after explicit action and emits ready`() = runTest {
        val module = TestModule(this)
        val events = mutableListOf<MediaCaptureEvent>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { module.core.events.toList(events) }
        module.permissions.states[PermissionResource.CAMERA] = PermissionState.NOT_DETERMINED
        module.permissions.requestResults[PermissionResource.CAMERA] = PermissionState.GRANTED

        assertEquals(PermissionState.NOT_DETERMINED, module.core.permissionState(PermissionResource.CAMERA))
        assertTrue(module.permissions.requests.isEmpty())
        val created = module.core.startSession(options(audio = true))
        assertEquals(SessionState.REQUESTING_PERMISSION, module.core.sessionState(created.sessionHandle))
        assertTrue(module.permissions.requests.isEmpty())

        runCurrent()

        assertEquals(listOf(PermissionResource.CAMERA), module.permissions.requests)
        assertEquals(SessionState.READY, module.core.sessionState(created.sessionHandle))
        assertTrue(events.single() is MediaCaptureEvent.Ready)
        assertEquals(1, module.files.residueCleanups)
        module.core.close()
    }

    @Test
    fun `single active session cancel and tombstone semantics are deterministic`() = runTest {
        val module = TestModule(this)
        val session = startReady(module)

        assertEquals(
            FailureCode.SESSION_CONFLICT,
            failureCode { module.core.startSession(options()) },
        )
        val first = module.core.cancel(session)
        val second = module.core.cancel(session)
        assertEquals(first, second)
        assertEquals(SessionState.CANCELLED, module.core.sessionState(session))

        val replacement = startReady(module)
        assertNotEquals(session, replacement)
        module.clock.now += 300_001
        assertEquals(FailureCode.SESSION_INVALID, failureCode { module.core.sessionState(session) })
        module.core.cancel(replacement)
        module.core.close()
    }

    @Test
    fun `permission failure preparing state and preview timeout become typed terminal events`() = runTest {
        val module = TestModule(this)
        val events = mutableListOf<MediaCaptureEvent>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { module.core.events.toList(events) }
        module.permissions.states[PermissionResource.CAMERA] = PermissionState.DENIED
        val denied = module.core.startSession(options()).sessionHandle
        runCurrent()
        assertEquals(SessionState.FAILED, module.core.sessionState(denied))
        assertTrue(
            events.any {
                it is MediaCaptureEvent.SessionFailed &&
                    it.failure.code == FailureCode.PERMISSION_DENIED
            },
        )

        module.permissions.states[PermissionResource.CAMERA] = PermissionState.GRANTED
        module.framework.prepareGate = kotlinx.coroutines.CompletableDeferred()
        val session = module.core.startSession(options(setOf(MediaType.PHOTO))).sessionHandle
        runCurrent()
        assertEquals(SessionState.PREPARING, module.core.sessionState(session))
        requireNotNull(module.framework.prepareGate).complete(Unit)
        runCurrent()
        val preview = module.core.takePhoto(session)

        module.clock.now += 600_000
        advanceTimeBy(600_000)
        runCurrent()
        assertEquals(SessionState.FAILED, module.core.sessionState(session))
        assertEquals(MediaState.DISCARDED, module.core.mediaState(preview.mediaHandle))
        assertTrue(
            events.any {
                it is MediaCaptureEvent.SessionFailed &&
                    it.failure.code == FailureCode.SESSION_TIMEOUT
            },
        )
        module.core.close()
    }

    @Test
    fun `photo retake deletes preview and returns session to ready`() = runTest {
        val module = TestModule(this)
        val session = startReady(module, options(enabled = setOf(MediaType.PHOTO)))
        val preview = module.core.takePhoto(session)

        assertEquals(SessionState.PREVIEWING, module.core.sessionState(session))
        assertEquals(MediaState.PREVIEW, module.core.mediaState(preview.mediaHandle))
        assertEquals(session, module.core.retake(preview.mediaHandle))
        assertEquals(SessionState.READY, module.core.sessionState(session))
        assertEquals(MediaState.DISCARDED, module.core.mediaState(preview.mediaHandle))
        assertEquals(1, module.files.deleted.size)
        module.core.cancel(session)
        module.core.close()
    }

    @Test
    fun `recording requests microphone only when audio is enabled and stop is idempotent`() = runTest {
        val module = TestModule(this)
        module.permissions.states[PermissionResource.MICROPHONE] = PermissionState.NOT_DETERMINED
        module.permissions.requestResults[PermissionResource.MICROPHONE] = PermissionState.GRANTED
        val session = startReady(module, options(enabled = setOf(MediaType.VIDEO), audio = true))

        val started = module.core.startRecording(session)
        assertTrue(started.audioIncluded)
        assertEquals(listOf(PermissionResource.MICROPHONE), module.permissions.requests)
        val first = module.core.stopRecording(session)
        val second = module.core.stopRecording(session)
        assertEquals(first, second)
        assertEquals(10_000, module.framework.lastMaxDuration)
        module.core.cancel(session)
        module.core.close()
    }

    @Test
    fun `controls validate finite structured input without changing state`() = runTest {
        val module = TestModule(this)
        val session = startReady(module)

        assertEquals(FailureCode.INVALID_ARGUMENT, failureCode { module.core.setZoom(session, Double.NaN) })
        assertEquals(FailureCode.INVALID_ARGUMENT, failureCode { module.core.setZoom(session, 5.0) })
        assertEquals(
            FailureCode.INVALID_ARGUMENT,
            failureCode { module.core.setFocusPoint(session, -0.1, 0.5) },
        )
        assertEquals(SessionState.READY, module.core.sessionState(session))

        module.core.setFlashMode(session, FlashMode.AUTO)
        module.core.setFocusPoint(session, 0.25, 0.75)
        module.core.setZoom(session, 2.0)
        assertEquals(FlashMode.AUTO, module.framework.lastFlash)
        assertEquals(0.25 to 0.75, module.framework.lastFocus)
        assertEquals(2.0, module.framework.lastZoom)
        module.core.cancel(session)
        module.core.close()
    }

    @Test
    fun `confirmed lease release grace and tombstone preserve idempotent result`() = runTest {
        val module = TestModule(this)
        val media = captureConfirmedPhoto(module)

        val first = module.core.releaseMedia(media)
        val second = module.core.releaseMedia(media)
        assertEquals(first, second)
        assertEquals(MediaState.RELEASE_GRACE, module.core.mediaState(media))
        assertEquals(FailureCode.INVALID_STATE, failureCode { module.core.withMediaRead(media) { } })

        module.clock.now += 60_000
        advanceTimeBy(60_000)
        runCurrent()
        assertEquals(MediaState.RELEASED, module.core.mediaState(media))
        assertEquals(1, module.files.revoked.size)
        assertEquals(1, module.files.deleted.size)

        module.clock.now += 300_001
        assertEquals(FailureCode.MEDIA_INVALID, failureCode { module.core.mediaState(media) })
        module.core.close()
    }

    @Test
    fun `lease expiry denies reads then revokes storage after bounded grace`() = runTest {
        val module = TestModule(this)
        val events = mutableListOf<MediaCaptureEvent>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { module.core.events.toList(events) }
        val media = captureConfirmedPhoto(module)

        module.clock.now += 86_400_000
        advanceTimeBy(86_400_000)
        runCurrent()
        assertEquals(MediaState.EXPIRY_GRACE, module.core.mediaState(media))
        assertTrue(events.any { it is MediaCaptureEvent.LeaseExpired })
        assertEquals(FailureCode.INVALID_STATE, failureCode { module.core.withMediaRead(media) { } })

        module.clock.now += 60_000
        advanceTimeBy(60_000)
        runCurrent()
        assertEquals(MediaState.EXPIRED, module.core.mediaState(media))
        assertTrue(events.any { it is MediaCaptureEvent.ReadRevoked })
        module.core.close()
    }

    @Test
    fun `callback scoped native read closes access and restart invalidates registry`() = runTest {
        val module = TestModule(this)
        val media = captureConfirmedPhoto(module)
        var closed = false
        var readRef: FakeRead? = null

        module.core.withMediaRead(media) { read ->
            assertEquals("image/jpeg", read.contentType)
            assertTrue(read.readBytes().isNotEmpty())
            readRef = read as FakeRead
            closed = read.closed
        }
        assertFalse(closed)
        assertTrue(requireNotNull(readRef).closed)

        module.core.onAppRestarted()
        assertEquals(FailureCode.MEDIA_INVALID, failureCode { module.core.mediaState(media) })
        assertTrue(module.files.deleted.isNotEmpty())
        module.core.close()
    }

    @Test
    fun `duration limit automatically stops recording and emits preview`() = runTest {
        val module = TestModule(this)
        val events = mutableListOf<MediaCaptureEvent>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { module.core.events.toList(events) }
        val session = startReady(module, options(setOf(MediaType.VIDEO), duration = 1_000))
        module.core.startRecording(session)

        advanceTimeBy(1_000)
        runCurrent()

        assertEquals(SessionState.PREVIEWING, module.core.sessionState(session))
        assertTrue(events.any { it is MediaCaptureEvent.PreviewReady })
        module.core.cancel(session)
        module.core.close()
    }
}
