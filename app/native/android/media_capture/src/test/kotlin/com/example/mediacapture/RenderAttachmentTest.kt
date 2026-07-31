@file:OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)

package com.example.mediacapture

import com.example.mediacapture.api.FailureCode
import com.example.mediacapture.api.MediaType
import com.example.mediacapture.rendering.MediaCaptureRenderMutationGate
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest

class RenderAttachmentTest {
    @Test
    fun `render mutation gate linearizes install callback commit and invalidation`() {
        val gate = MediaCaptureRenderMutationGate()
        val installEntered = CountDownLatch(1)
        val releaseInstall = CountDownLatch(1)
        val invalidationStarted = CountDownLatch(1)
        val executor = Executors.newFixedThreadPool(2)
        try {
            val install =
                executor.submit<Boolean> {
                    gate.performInstall {
                        installEntered.countDown()
                        check(releaseInstall.await(5, TimeUnit.SECONDS))
                    }
                }
            assertTrue(installEntered.await(5, TimeUnit.SECONDS))
            val invalidation =
                executor.submit {
                    invalidationStarted.countDown()
                    gate.invalidate()
                }
            assertTrue(invalidationStarted.await(5, TimeUnit.SECONDS))
            assertFalse(invalidation.isDone)

            releaseInstall.countDown()
            assertTrue(install.get(5, TimeUnit.SECONDS))
            invalidation.get(5, TimeUnit.SECONDS)

            assertFalse(gate.performInstall {})
            assertFalse(gate.commit())
            assertFalse(gate.performCallback {})
        } finally {
            releaseInstall.countDown()
            executor.shutdownNow()
        }

        val committedGate = MediaCaptureRenderMutationGate()
        assertFalse(committedGate.performCallback {})
        assertTrue(committedGate.commit())
        assertTrue(committedGate.performCallback {})
        committedGate.invalidate()
        assertFalse(committedGate.performCallback {})
    }

    @Test
    fun `cleanup invalidates immediately but detaches only after attach settles`() = runTest {
        val module = TestModule(this)
        val session = startReady(module)
        val gate = CompletableDeferred<Unit>()
        val adapter = FakeRenderAdapter().apply { onAttach = { gate.await() } }
        val attach = async { failureCode { module.core.attachLivePreview(session, adapter, 1) } }
        runCurrent()
        assertEquals(1, adapter.attachCount)

        val cleanup = async { module.core.onAppBackgrounded() }
        runCurrent()

        assertFalse(cleanup.isCompleted)
        assertFalse(requireNotNull(adapter.activeGuard).invoke())
        assertEquals(0, adapter.detachCount)

        gate.complete(Unit)
        runCurrent()
        assertEquals(FailureCode.INVALID_STATE, attach.await())
        cleanup.await()
        assertEquals(1, adapter.revokeCount)
        assertEquals(1, adapter.detachCount)
        module.core.cancel(session)
        module.core.close()
    }

    @Test
    fun `cancellation rolls back mount commit and callback ownership windows`() = runTest {
        val testScope = this
        suspend fun assertCancelledRollback(
            configure: (TestModule, FakeRenderAdapter, CompletableDeferred<Unit>) -> Unit,
        ) {
            val module = TestModule(testScope)
            val session = testScope.startReady(module)
            val gate = CompletableDeferred<Unit>()
            val adapter = FakeRenderAdapter()
            configure(module, adapter, gate)
            val attach = async { module.core.attachLivePreview(session, adapter, 1) }
            runCurrent()

            attach.cancelAndJoin()
            runCurrent()

            assertTrue(attach.isCancelled)
            assertEquals(1, adapter.revokeCount)
            assertEquals(1, adapter.detachCount)
            assertFalse(requireNotNull(adapter.activeGuard).invoke())
            module.core.cancel(session)
            module.core.close()
        }

        assertCancelledRollback { _, adapter, gate -> adapter.onAttach = { gate.await() } }
        assertCancelledRollback { module, _, gate ->
            module.core.attachmentBeforeCommitForTest = { gate.await() }
        }
        assertCancelledRollback { _, adapter, gate -> adapter.onCommit = { gate.await() } }
    }

    @Test
    fun `reentrant adapter does not deadlock and stale attach is cleaned`() = runTest {
        val module = TestModule(this)
        val session = startReady(module)
        val adapter = FakeRenderAdapter()
        adapter.onAttach = { module.core.detachLivePreview(session, adapter, 1) }

        assertEquals(
            FailureCode.INVALID_STATE,
            failureCode { module.core.attachLivePreview(session, adapter, 1) },
        )
        assertEquals(1, adapter.revokeCount)
        assertEquals(1, adapter.detachCount)
        module.core.cancel(session)
        module.core.close()
    }

    @Test
    fun `throwing revoke and detach cannot block lifecycle cleanup`() = runTest {
        val module = TestModule(this)
        val session = startReady(module)
        val adapter = FakeRenderAdapter().apply {
            throwOnRevoke = true
            throwOnDetach = true
        }
        module.core.attachLivePreview(session, adapter, 1)

        module.core.onAppBackgrounded()

        assertEquals(1, adapter.revokeCount)
        assertEquals(1, adapter.detachCount)
        val replacement = FakeRenderAdapter()
        module.core.attachLivePreview(session, replacement, 2)
        module.core.cancel(session)
        module.core.close()
    }

    @Test
    fun `generation high watermark identity and stale detach preserve current binding`() = runTest {
        val module = TestModule(this)
        val session = startReady(module)
        val first = FakeRenderAdapter()
        val second = FakeRenderAdapter()

        module.core.attachLivePreview(session, first, 1)
        module.core.attachLivePreview(session, first, 1)
        assertEquals(1, first.attachCount)
        assertTrue(requireNotNull(first.activeGuard).invoke())

        assertEquals(
            FailureCode.ATTACHMENT_TARGET_CONFLICT,
            failureCode { module.core.attachLivePreview(session, second, 1) },
        )
        assertEquals(0, second.attachCount)

        module.core.attachLivePreview(session, second, 2)
        assertFalse(requireNotNull(first.activeGuard).invoke())
        assertEquals(1, first.revokeCount)
        assertEquals(1, first.detachCount)
        assertTrue(requireNotNull(second.activeGuard).invoke())

        assertEquals(
            FailureCode.ATTACHMENT_GENERATION_RETIRED,
            failureCode { module.core.attachLivePreview(session, first, 1) },
        )
        module.core.detachLivePreview(session, first, 1)
        assertTrue(requireNotNull(second.activeGuard).invoke())
        assertEquals(0, second.detachCount)

        module.core.detachLivePreview(session, second, 2)
        assertFalse(requireNotNull(second.activeGuard).invoke())
        assertEquals(
            FailureCode.ATTACHMENT_GENERATION_RETIRED,
            failureCode { module.core.attachLivePreview(session, second, 2) },
        )
        module.core.cancel(session)
        module.core.close()
    }

    @Test
    fun `capture and media ownership transitions revoke attachments before cleanup or transfer`() = runTest {
        val module = TestModule(this)
        val session = startReady(module, options(setOf(MediaType.PHOTO)))
        val live = FakeRenderAdapter()
        module.core.attachLivePreview(session, live, 10)

        val preview = module.core.takePhoto(session)
        assertEquals(1, live.revokeCount)
        assertEquals(1, live.detachCount)
        assertFalse(requireNotNull(live.activeGuard).invoke())

        val unconfirmed = FakeRenderAdapter()
        module.core.attachUnconfirmedPreview(preview.mediaHandle, unconfirmed, 1)
        module.core.confirm(preview.mediaHandle)
        assertEquals(1, unconfirmed.revokeCount)
        assertEquals(1, unconfirmed.detachCount)
        assertFalse(requireNotNull(unconfirmed.activeGuard).invoke())
        module.core.releaseMedia(preview.mediaHandle)
        module.core.close()
    }

    @Test
    fun `rotation background and owner destruction require fresh generations`() = runTest {
        val module = TestModule(this)
        val session = startReady(module)
        val adapter = FakeRenderAdapter()

        module.core.attachLivePreview(session, adapter, 1)
        module.core.onDisplayRotationChanged()
        assertEquals(1, adapter.detachCount)
        assertEquals(
            FailureCode.ATTACHMENT_GENERATION_RETIRED,
            failureCode { module.core.attachLivePreview(session, adapter, 1) },
        )

        module.core.attachLivePreview(session, adapter, 2)
        module.core.onAppBackgrounded()
        assertEquals(2, adapter.detachCount)

        module.core.attachLivePreview(session, adapter, 3)
        module.core.onPreviewOwnerDestroyed(adapter)
        assertEquals(3, adapter.detachCount)
        assertFalse(requireNotNull(adapter.activeGuard).invoke())
        module.core.cancel(session)
        module.core.close()
    }

    @Test
    fun `unconfirmed stale detach cannot revoke replacement owner`() = runTest {
        val module = TestModule(this)
        val session = startReady(module, options(setOf(MediaType.PHOTO)))
        val preview = module.core.takePhoto(session)
        val first = FakeRenderAdapter()
        val second = FakeRenderAdapter()

        module.core.attachUnconfirmedPreview(preview.mediaHandle, first, 1)
        module.core.attachUnconfirmedPreview(preview.mediaHandle, second, 2)
        module.core.detachUnconfirmedPreview(preview.mediaHandle, first, 1)

        assertTrue(requireNotNull(second.activeGuard).invoke())
        assertEquals(0, second.detachCount)
        module.core.retake(preview.mediaHandle)
        assertEquals(1, second.detachCount)
        module.core.cancel(session)
        module.core.close()
    }
}
