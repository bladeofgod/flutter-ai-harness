package com.example.mediacapture.ui

import android.content.Context
import android.view.View
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.test.core.app.ApplicationProvider
import com.example.mediacapture.api.FailureCode
import com.example.mediacapture.api.MediaCapture
import com.example.mediacapture.api.MediaHandle
import com.example.mediacapture.api.MediaType
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertTrue
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
class MediaCaptureFlowCoordinatorTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    @Test
    fun startAttachesSingleLiveSurfaceAndRotationReplacesGeneration() = runTest {
        val fixture = fixture()

        fixture.coordinator.start(MediaCaptureUiConfig())
        advanceUntilIdle()
        fixture.coordinator.rotateOwner()
        advanceUntilIdle()

        assertEquals(listOf(1L, 2L), fixture.fake.liveAttachGenerations)
        assertEquals(listOf(1L), fixture.fake.destroyedGenerations)
        assertEquals(2L, fixture.coordinator.currentOwnerGenerationForTest())
        assertEquals(listOf("start_session", "rotation"), fixture.fake.calls)

        fixture.coordinator.destroyOwner()
        advanceUntilIdle()
    }

    @Test
    fun failedSurfaceRetirementDoesNotCreateOrAttachReplacement() = runTest {
        val fixture = fixture()
        fixture.coordinator.start(MediaCaptureUiConfig())
        advanceUntilIdle()
        fixture.fake.destroyFailuresRemaining = 1

        fixture.coordinator.rotateOwner()
        advanceUntilIdle()

        assertEquals(1, fixture.fake.createRenderViewCount)
        assertEquals(listOf(1L), fixture.fake.liveAttachGenerations)
        assertIs<MediaCaptureFlowResult.Failure>(fixture.coordinator.awaitResult())
    }

    @Test
    fun lateStartSessionIsCancelledBeforeTerminalCleanupReleasesOwnership() = runTest {
        val fixture = fixture()
        val gate = CompletableDeferred<Unit>()
        fixture.fake.startSessionGate = gate
        fixture.fake.startSessionIgnoresCancellation = true
        val starting = launch { fixture.coordinator.start(MediaCaptureUiConfig()) }
        runCurrent()

        fixture.coordinator.destroyOwner()
        runCurrent()
        gate.complete(Unit)
        advanceUntilIdle()

        starting.join()
        assertEquals(listOf("start_session", "cancel"), fixture.fake.calls)
        val result = assertIs<MediaCaptureFlowResult.Failure>(fixture.coordinator.awaitResult())
        assertEquals(FailureCode.SYSTEM_INTERRUPTED, result.failure.code)
    }

    @Test
    fun backgroundFailureWaitsForLateStartBeforeReportingSafeCleanup() = runTest {
        val fixture = fixture()
        val gate = CompletableDeferred<Unit>()
        fixture.fake.startSessionGate = gate
        fixture.fake.startSessionIgnoresCancellation = true
        fixture.fake.failOnBackground = true
        var cleanupSucceeded: Boolean? = null
        fixture.coordinator.setTerminalListener { cleanupSucceeded = it }
        val starting = launch { fixture.coordinator.start(MediaCaptureUiConfig()) }
        runCurrent()

        fixture.coordinator.backgroundOwner()
        runCurrent()

        assertEquals(null, cleanupSucceeded)
        gate.complete(Unit)
        advanceUntilIdle()

        starting.join()
        assertEquals(true, cleanupSucceeded)
        assertEquals(listOf("start_session", "background", "cancel"), fixture.fake.calls)
        assertIs<MediaCaptureFlowResult.Failure>(fixture.coordinator.awaitResult())
    }

    @Test
    fun photoPreviewCanRetakeAndConfirmExactlyOnce() = runTest {
        val fixture = fixture()
        fixture.coordinator.start(MediaCaptureUiConfig())
        advanceUntilIdle()

        fixture.coordinator.onTakePhoto()
        advanceUntilIdle()
        fixture.coordinator.onRetake()
        advanceUntilIdle()
        fixture.coordinator.onTakePhoto()
        advanceUntilIdle()
        fixture.coordinator.onConfirm()
        advanceUntilIdle()
        fixture.coordinator.onCancel()
        advanceUntilIdle()

        assertEquals(listOf("start_session", "take_photo", "retake", "take_photo", "confirm"), fixture.fake.calls)
        assertIs<MediaCaptureFlowResult.Confirmed>(fixture.coordinator.awaitResult())
        assertEquals(2, fixture.fake.previewAttachGenerations.size)
    }

    @Test
    fun repeatedPhotoTapIsDroppedAndPreviewAttachesOnce() = runTest {
        val fixture = fixture()
        fixture.coordinator.start(MediaCaptureUiConfig())
        advanceUntilIdle()
        val gate = CompletableDeferred<Unit>()
        fixture.fake.takePhotoGate = gate

        fixture.coordinator.onTakePhoto()
        fixture.coordinator.onTakePhoto()
        runCurrent()

        assertEquals(1, fixture.fake.calls.count { it == "take_photo" })

        gate.complete(Unit)
        advanceUntilIdle()

        assertEquals(1, fixture.fake.previewAttachGenerations.size)
        fixture.coordinator.destroyOwner()
        advanceUntilIdle()
    }

    @Test
    fun recordingHidesSwitchUntilRetakeRestoresReadyControlsFromSnapshot() = runTest {
        val fixture = fixture()
        fixture.coordinator.start(MediaCaptureUiConfig())
        advanceUntilIdle()
        val switch = fixture.chrome.findButton("Switch camera")
        assertEquals(View.VISIBLE, switch.visibility)

        fixture.coordinator.onStartRecording()
        runCurrent()
        assertEquals(View.INVISIBLE, switch.visibility)

        fixture.coordinator.onStopRecording()
        advanceUntilIdle()
        fixture.coordinator.onRetake()
        advanceUntilIdle()

        assertEquals(View.VISIBLE, switch.visibility)

        fixture.coordinator.destroyOwner()
        advanceUntilIdle()
    }

    @Test
    fun autoStopPreviewUsesUnconfirmedSurface() = runTest {
        val fixture = fixture()
        fixture.coordinator.start(MediaCaptureUiConfig())
        advanceUntilIdle()

        fixture.coordinator.onStartRecording()
        runCurrent()
        fixture.fake.emitAutoStopPreview()
        advanceUntilIdle()

        assertEquals(listOf(2L), fixture.fake.previewAttachGenerations)

        fixture.coordinator.destroyOwner()
        advanceUntilIdle()
    }

    @Test
    fun manualRecordingStopAttachesPreviewOnce() = runTest {
        val fixture = fixture()
        fixture.coordinator.start(MediaCaptureUiConfig())
        advanceUntilIdle()

        fixture.coordinator.onStartRecording()
        runCurrent()
        fixture.coordinator.onStopRecording()
        advanceUntilIdle()

        assertEquals(1, fixture.fake.previewAttachGenerations.size)

        fixture.coordinator.destroyOwner()
        advanceUntilIdle()
    }

    @Test
    fun releaseBeforeRecordingStartsStopsImmediatelyAfterFrameworkStart() = runTest {
        val fixture = fixture()
        fixture.coordinator.start(MediaCaptureUiConfig())
        advanceUntilIdle()
        val startGate = CompletableDeferred<Unit>()
        fixture.fake.startRecordingGate = startGate

        fixture.coordinator.onStartRecording()
        runCurrent()
        fixture.coordinator.onStopRecording()
        runCurrent()

        assertEquals(1, fixture.fake.calls.count { it == "start_recording" })
        assertEquals(0, fixture.fake.calls.count { it == "stop_recording" })

        startGate.complete(Unit)
        advanceUntilIdle()

        assertEquals(1, fixture.fake.calls.count { it == "stop_recording" })
        assertEquals(1, fixture.fake.previewAttachGenerations.size)

        fixture.coordinator.destroyOwner()
        advanceUntilIdle()
    }

    @Test
    fun startRecordingFailureCompletesOnceAndIgnoresRepeatedActions() = runTest {
        val fixture = fixture()
        fixture.coordinator.start(MediaCaptureUiConfig())
        advanceUntilIdle()
        fixture.fake.failNextStartRecording = true

        fixture.coordinator.onStartRecording()
        advanceUntilIdle()
        fixture.coordinator.onCancel()
        fixture.coordinator.onConfirm()
        advanceUntilIdle()

        val result = assertIs<MediaCaptureFlowResult.Failure>(fixture.coordinator.awaitResult())
        assertEquals(FailureCode.PERMISSION_DENIED, result.failure.code)
        assertEquals(listOf("start_session", "start_recording", "cancel"), fixture.fake.calls)
    }

    @Test
    fun backgroundSuspendsAndForegroundReattachesWithHigherGeneration() = runTest {
        val fixture = fixture()
        fixture.coordinator.start(MediaCaptureUiConfig())
        advanceUntilIdle()

        fixture.coordinator.backgroundOwner()
        advanceUntilIdle()

        assertFalse(fixture.coordinator.isCompletedForTest())
        assertEquals(listOf(1L), fixture.fake.destroyedGenerations)

        fixture.coordinator.foregroundOwner()
        advanceUntilIdle()

        assertFalse(fixture.coordinator.isCompletedForTest())
        assertEquals(listOf(1L, 2L), fixture.fake.liveAttachGenerations)
        assertEquals(listOf("start_session", "background"), fixture.fake.calls)

        fixture.coordinator.destroyOwner()
        advanceUntilIdle()

        val result = assertIs<MediaCaptureFlowResult.Failure>(fixture.coordinator.awaitResult())
        assertEquals(FailureCode.SYSTEM_INTERRUPTED, result.failure.code)
    }

    @Test
    fun ownerDestroyCleanupIsTerminalAndIdempotent() = runTest {
        val fixture = fixture()
        fixture.coordinator.start(MediaCaptureUiConfig())
        advanceUntilIdle()

        fixture.coordinator.destroyOwner()
        fixture.coordinator.destroyOwner()
        advanceUntilIdle()

        val result = assertIs<MediaCaptureFlowResult.Failure>(fixture.coordinator.awaitResult())
        assertEquals(FailureCode.SYSTEM_INTERRUPTED, result.failure.code)
        assertEquals(listOf("start_session", "cancel"), fixture.fake.calls)
        assertEquals(listOf(1L), fixture.fake.destroyedGenerations)
    }

    @Test
    fun ownerDestroyWinsConfirmRaceAndReleasesLateLease() = runTest {
        val fixture = fixture()
        fixture.coordinator.start(MediaCaptureUiConfig())
        advanceUntilIdle()
        fixture.coordinator.onTakePhoto()
        advanceUntilIdle()
        val gate = CompletableDeferred<Unit>()
        fixture.fake.confirmGate = gate
        fixture.fake.confirmIgnoresCancellation = true

        fixture.coordinator.onConfirm()
        runCurrent()
        fixture.coordinator.destroyOwner()
        runCurrent()

        val result = assertIs<MediaCaptureFlowResult.Failure>(fixture.coordinator.awaitResult())
        assertEquals(FailureCode.SYSTEM_INTERRUPTED, result.failure.code)

        gate.complete(Unit)
        advanceUntilIdle()

        assertEquals(1, fixture.fake.releasedMediaHandles.size)
    }

    @Test
    fun lateLeaseReleaseRetriesBeforeTerminalCleanupCompletes() = runTest {
        val fixture = fixture()
        fixture.coordinator.start(MediaCaptureUiConfig())
        advanceUntilIdle()
        fixture.coordinator.onTakePhoto()
        advanceUntilIdle()
        val gate = CompletableDeferred<Unit>()
        fixture.fake.confirmGate = gate
        fixture.fake.confirmIgnoresCancellation = true
        fixture.fake.releaseFailuresRemaining = 1
        var cleanupSucceeded: Boolean? = null
        fixture.coordinator.setTerminalListener { cleanupSucceeded = it }

        fixture.coordinator.onConfirm()
        runCurrent()
        fixture.coordinator.destroyOwner()
        runCurrent()
        gate.complete(Unit)
        advanceUntilIdle()

        assertEquals(true, cleanupSucceeded)
        assertEquals(1, fixture.fake.releasedMediaHandles.size)
    }

    @Test
    fun unresolvedLeaseReleaseTransfersOwnershipUntilRecovery() = runTest {
        val retained = mutableListOf<Pair<MediaCapture, MediaHandle>>()
        var recovered: (() -> Unit)? = null
        val fixture =
            fixture(
                leaseCleanupOwner =
                    MediaCaptureLeaseCleanupOwner { mediaCapture, mediaHandle, onSettled ->
                        retained += mediaCapture to mediaHandle
                        recovered = onSettled
                    },
            )
        fixture.coordinator.start(MediaCaptureUiConfig())
        advanceUntilIdle()
        fixture.coordinator.onTakePhoto()
        advanceUntilIdle()
        fixture.fake.confirmGate = CompletableDeferred()
        fixture.fake.confirmCancelsAfterCommit = true
        fixture.fake.releaseFailuresRemaining = 2
        var cleanupSucceeded: Boolean? = null
        var cleanupRecovered = false
        fixture.coordinator.setTerminalListener { cleanupSucceeded = it }
        fixture.coordinator.setCleanupRecoveredListener { cleanupRecovered = true }

        fixture.coordinator.onConfirm()
        runCurrent()
        fixture.coordinator.destroyOwner()
        advanceUntilIdle()

        assertEquals(false, cleanupSucceeded)
        assertEquals(1, retained.size)
        recovered?.invoke()
        assertTrue(cleanupRecovered)
    }

    @Test
    fun ownerDestroyReleasesLeaseCommittedBeforeConfirmCancellation() = runTest {
        val fixture = fixture()
        fixture.coordinator.start(MediaCaptureUiConfig())
        advanceUntilIdle()
        fixture.coordinator.onTakePhoto()
        advanceUntilIdle()
        fixture.fake.confirmGate = CompletableDeferred()
        fixture.fake.confirmCancelsAfterCommit = true

        fixture.coordinator.onConfirm()
        runCurrent()
        fixture.coordinator.destroyOwner()
        advanceUntilIdle()

        assertEquals(1, fixture.fake.releasedMediaHandles.size)
        assertEquals(
            listOf("start_session", "take_photo", "confirm", "cancel"),
            fixture.fake.calls,
        )
        assertIs<MediaCaptureFlowResult.Failure>(fixture.coordinator.awaitResult())
    }

    @Test
    fun failureObservationCompletesFlow() = runTest {
        val fixture = fixture()
        fixture.coordinator.start(MediaCaptureUiConfig())
        advanceUntilIdle()

        fixture.fake.emitFailure(FailureCode.SYSTEM_INTERRUPTED)
        advanceUntilIdle()

        val result = assertIs<MediaCaptureFlowResult.Failure>(fixture.coordinator.awaitResult())
        assertEquals(FailureCode.SYSTEM_INTERRUPTED, result.failure.code)
    }

    @Test
    fun uiConfigCopiesMediaTypesAndEnforcesCapabilityDurationBound() {
        val mediaTypes = mutableSetOf(MediaType.PHOTO)
        val config = MediaCaptureUiConfig(enabledMediaTypes = mediaTypes, maxVideoDurationMillis = 60_000L)

        mediaTypes += MediaType.VIDEO

        assertEquals(setOf(MediaType.PHOTO), config.enabledMediaTypes)
        assertFailsWith<IllegalArgumentException> {
            MediaCaptureUiConfig(maxVideoDurationMillis = 0L)
        }
        assertFailsWith<IllegalArgumentException> {
            MediaCaptureUiConfig(maxVideoDurationMillis = 60_001L)
        }
    }

    private fun TestScope.fixture(
        leaseCleanupOwner: MediaCaptureLeaseCleanupOwner = ProcessMediaCaptureLeaseCleanupOwner,
    ): Fixture {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val lifecycleOwner = TestLifecycleOwner()
        lifecycleOwner.registry.currentState = Lifecycle.State.CREATED
        val chrome = MediaCaptureChromeView(context)
        val fake = FakeMediaCapture(context, lifecycleOwner, dispatcher)
        val coordinator =
            MediaCaptureFlowCoordinator(
                context = context,
                lifecycleOwner = lifecycleOwner,
                mediaCapture = fake,
                chrome = chrome,
                uiDispatcher = dispatcher,
                leaseCleanupOwner = leaseCleanupOwner,
            )
        return Fixture(chrome, fake, coordinator)
    }

    private data class Fixture(
        val chrome: MediaCaptureChromeView,
        val fake: FakeMediaCapture,
        val coordinator: MediaCaptureFlowCoordinator,
    )

    private class TestLifecycleOwner : LifecycleOwner {
        val registry = LifecycleRegistry(this)

        override val lifecycle: Lifecycle
            get() = registry
    }
}

private fun View.findButton(contentDescription: String): View {
    return findButtonOrNull(contentDescription) ?: error("Button $contentDescription not found")
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
