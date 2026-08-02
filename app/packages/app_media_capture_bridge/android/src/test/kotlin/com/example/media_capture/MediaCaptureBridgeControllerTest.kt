package com.example.media_capture

import android.app.Activity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import com.example.mediacapture.api.FailureCode
import com.example.mediacapture.api.MediaCaptureEvent
import com.example.mediacapture.api.MediaCaptureFailure
import com.example.mediacapture.api.MediaHandle
import com.example.mediacapture.api.MediaType
import com.example.mediacapture.api.SessionReady
import com.example.mediacapture.api.SessionHandle
import com.example.mediacapture.ui.MediaCaptureFlowResult
import java.io.File
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import kotlin.coroutines.CoroutineContext

@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
class MediaCaptureBridgeControllerTest {
    @Test
    fun directMethodsMapAllResultsAndNeverUseRawMediaRead() = runTest {
        val fixture = fixture()
        val firstSession = fixture.start("start-1")

        fixture.call("switch_camera", "switch-1", sessionPayload(firstSession)).expectType("control_applied")
        fixture.call(
            "set_flash_mode",
            "flash-1",
            mapOf("sessionHandle" to firstSession, "flashMode" to "auto"),
        ).expectType("control_applied")
        fixture.call(
            "set_focus_point",
            "focus-1",
            mapOf("sessionHandle" to firstSession, "normalizedX" to 0.2, "normalizedY" to 0.8),
        ).expectType("control_applied")
        fixture.call(
            "set_zoom",
            "zoom-1",
            mapOf("sessionHandle" to firstSession, "zoomFactor" to 2.0),
        ).expectType("control_applied")
        fixture.call("start_recording", "record-1", sessionPayload(firstSession))
            .expectType("recording_started")
        fixture.call("stop_recording", "stop-1", sessionPayload(firstSession))
            .expectType("media_preview")

        val photo = fixture.call("take_photo", "photo-1", sessionPayload(firstSession))
        photo.expectType("media_preview")
        val mediaHandle = photo.payloadString("mediaHandle")
        fixture.call("retake", "retake-1", mediaPayload(mediaHandle)).expectType("retake_ready")
        val secondPhoto = fixture.call("take_photo", "photo-2", sessionPayload(firstSession))
        val confirmed = fixture.call("confirm", "confirm-1", mediaPayload(secondPhoto.payloadString("mediaHandle")))
        confirmed.expectType("confirmed_media")

        val thumbnail =
            fixture.call(
                "read_media_thumbnail",
                "thumb-1",
                mapOf("mediaHandle" to confirmed.payloadString("mediaHandle"), "maxPixelEdge" to 128),
            )
        thumbnail.expectType("media_thumbnail")
        assertIs<ByteArray>(thumbnail.payload()["thumbnailCopy"])
        fixture.call(
            "release_media",
            "release-1",
            mediaPayload(confirmed.payloadString("mediaHandle")),
        ).expectType("media_released")

        val cancelSession = fixture.start("start-2")
        fixture.call("cancel", "cancel-1", sessionPayload(cancelSession)).expectType("session_cancelled")

        assertEquals(
            setOf(
                "start_session",
                "switch_camera",
                "set_flash_mode",
                "set_focus_point",
                "set_zoom",
                "start_recording",
                "stop_recording",
                "take_photo",
                "retake",
                "confirm",
                "read_media_thumbnail",
                "release_media",
                "cancel",
            ),
            fixture.fake.calls.toSet(),
        )
    }

    @Test
    fun capabilityErrorsAreAllowlistedAndRedacted() = runTest {
        val fixture = fixture()
        val session = fixture.start("start-1")
        fixture.fake.nextFailure = FailureCode.STORAGE_FULL

        val photo = fixture.call("take_photo", "photo-1", sessionPayload(session))

        assertEquals("storage_full", photo.errorCode)
        assertEquals("Media capture operation failed.", photo.errorMessage)
        assertEquals(
            mapOf("operation" to "take_photo", "capabilityFailureId" to "storage_full"),
            photo.errorDetails,
        )

        fixture.fake.nextFailure = FailureCode.STORAGE_FULL
        val flash =
            fixture.call(
                "set_flash_mode",
                "flash-1",
                mapOf("sessionHandle" to session, "flashMode" to "off"),
            )
        assertEquals("wire_encoding_failed", flash.errorCode)
        assertFalse(flash.toString().contains("Storage"))
    }

    @Test
    fun outboundThumbnailRejectsMetadataBeforeFlutterDelivery() = runTest {
        val fixture = fixture()
        val lease = fixture.confirmPhoto()
        val jpeg = fixture.fake.thumbnailBytes
        fixture.fake.thumbnailBytes =
            byteArrayOf(
                0xff.toByte(),
                0xd8.toByte(),
                0xff.toByte(),
                0xe1.toByte(),
                0x00,
                0x08,
                0x45,
                0x78,
                0x69,
                0x66,
                0x00,
                0x00,
            ) + jpeg.drop(2)

        val result =
            fixture.call(
                "read_media_thumbnail",
                "metadata-thumb",
                mapOf("mediaHandle" to lease, "maxPixelEdge" to 128),
            )

        assertEquals("wire_encoding_failed", result.errorCode)
        assertEquals(
            setOf("operation", "field", "reason"),
            result.errorDetails?.keys,
        )
        assertFalse(result.toString().contains("Exif"))

        val noJfifFixture = fixture()
        val noJfifLease = noJfifFixture.confirmPhoto()
        val canonical = noJfifFixture.fake.thumbnailBytes
        noJfifFixture.fake.thumbnailBytes = canonical.take(2).toByteArray() + canonical.drop(20)
        val noJfif =
            noJfifFixture.call(
                "read_media_thumbnail",
                "missing-jfif",
                mapOf("mediaHandle" to noJfifLease, "maxPixelEdge" to 128),
            )
        assertEquals("wire_encoding_failed", noJfif.errorCode)
    }

    @Test
    fun nativeResourceIdentityAndLeaseMetadataAreValidatedBeforeDelivery() = runTest {
        val thumbnailFixture = fixture()
        val lease = thumbnailFixture.confirmPhoto()
        val bytes = thumbnailFixture.fake.thumbnailBytes
        thumbnailFixture.fake.thumbnailHandleOverride = MediaHandle("different-media")

        val thumbnail =
            thumbnailFixture.call(
                "read_media_thumbnail",
                "mismatched-thumb",
                mapOf("mediaHandle" to lease, "maxPixelEdge" to 128),
            )

        assertEquals("wire_encoding_failed", thumbnail.errorCode)
        assertTrue(bytes.all { it == 0.toByte() })

        val confirmFixture = fixture()
        val session = confirmFixture.start("invalid-lease-start")
        val preview =
            confirmFixture.call(
                "take_photo",
                "invalid-lease-photo",
                sessionPayload(session),
            )
        confirmFixture.fake.confirmedLeaseExpiresAt = -1L
        val confirmed =
            confirmFixture.call(
                "confirm",
                "invalid-lease-confirm",
                mediaPayload(preview.payloadString("mediaHandle")),
            )

        assertEquals("wire_encoding_failed", confirmed.errorCode)
        assertEquals(listOf(preview.payloadString("mediaHandle")), confirmFixture.fake.releasedMedia)

        val recordingFixture = fixture()
        val recordingSession = recordingFixture.start("mismatched-recording-start")
        recordingFixture.fake.recordingHandleOverride = SessionHandle("different-session")
        val recording =
            recordingFixture.call(
                "start_recording",
                "mismatched-recording",
                sessionPayload(recordingSession),
            )

        assertEquals("wire_encoding_failed", recording.errorCode)
        assertEquals(
            setOf(recordingSession, "different-session"),
            recordingFixture.fake.cancelledSessions.toSet(),
        )
    }

    @Test
    fun duplicateAndPendingCapacityRejectBeforeAdditionalCoreCalls() = runTest {
        val fixture = fixture()
        val gate = CompletableDeferred<Unit>()
        fixture.fake.startGate = gate
        val results = mutableListOf<RecordingResult>()

        repeat(32) { index ->
            results += fixture.callWithoutDrain("start_session", "pending-$index", startPayload())
        }
        runCurrent()
        val duplicate = fixture.callWithoutDrain("start_session", "pending-0", startPayload())
        val overloaded = fixture.callWithoutDrain("start_session", "pending-32", startPayload())
        runCurrent()

        assertEquals("duplicate_request", duplicate.errorCode)
        assertEquals("bridge_overloaded", overloaded.errorCode)
        assertEquals("pending_requests", overloaded.errorDetails?.get("capacity"))
        assertEquals(32, fixture.fake.calls.count { it == "start_session" })

        gate.complete(Unit)
        advanceUntilIdle()
        assertTrue(results.all { it.successValue != null })
    }

    @Test
    fun completedRequestIdStaysReservedUntilTombstoneExpiry() = runTest {
        var now = 0L
        val fixture = fixture(nowMillis = { now })
        fixture.call("start_session", "same-id", startPayload()).expectType("session_created")

        assertEquals(
            "duplicate_request",
            fixture.call("start_session", "same-id", startPayload()).errorCode,
        )
        now = 300_000L
        fixture.call("start_session", "same-id", startPayload()).expectType("session_created")
    }

    @Test
    fun completedCapacityNeverEvictsLiveTombstones() = runTest {
        val fixture = fixture()

        repeat(4096) { index ->
            val result =
                fixture.call(
                    "release_media",
                    "completed-$index",
                    mediaPayload("missing-$index"),
                )
            assertEquals("media_invalid", result.errorCode)
        }
        val overloaded =
            fixture.call(
                "release_media",
                "completed-overflow",
                mediaPayload("missing-overflow"),
            )

        assertEquals("bridge_overloaded", overloaded.errorCode)
        assertEquals("completed_request_tombstones", overloaded.errorDetails?.get("capacity"))
    }

    @Test
    fun eventsUseOneGenerationAndMapFiveWireEventsPlusTimeoutFailure() = runTest {
        val fixture = fixture()
        val sink = RecordingEventSink()
        fixture.controller.onListen(mapOf("wireVersion" to 3), sink)
        val second = RecordingEventSink()
        fixture.controller.onListen(mapOf("wireVersion" to 3), second)
        runCurrent()
        assertEquals("listener_already_active", second.errorCode)

        val session = fixture.start("start-1")
        fixture.fake.emit(MediaCaptureEvent.Ready(fixture.fake.ready(SessionHandle(session))))
        fixture.fake.emit(
            MediaCaptureEvent.PreviewReady(
                SessionHandle(session),
                fixture.fake.preview(MediaHandle("event-media")),
            ),
        )
        val confirmed = fixture.call("confirm", "confirm-1", mediaPayload("event-media"))
        val media = MediaHandle(confirmed.payloadString("mediaHandle"))
        fixture.fake.emit(MediaCaptureEvent.LeaseExpired(media))
        fixture.fake.emit(MediaCaptureEvent.ReadRevoked(media))

        val failedSession = fixture.start("start-2")
        fixture.fake.emit(
            MediaCaptureEvent.SessionFailed(
                SessionHandle(failedSession),
                MediaCaptureFailure(FailureCode.SYSTEM_INTERRUPTED),
            ),
        )
        val timeoutSession = fixture.start("start-3")
        fixture.fake.emit(
            MediaCaptureEvent.SessionFailed(
                SessionHandle(timeoutSession),
                MediaCaptureFailure(FailureCode.SESSION_TIMEOUT),
            ),
        )
        advanceUntilIdle()

        assertEquals(
            listOf(
                "session_ready",
                "media_preview_ready",
                "media_lease_expired",
                "media_read_revoked",
                "session_failed",
            ),
            sink.values.mapNotNull { (it as Map<*, *>)["eventType"] as? String },
        )
        assertEquals("session_timeout", (sink.values.last() as Map<*, *>)["failureType"])

        fixture.controller.onCancel()
        fixture.fake.emit(MediaCaptureEvent.Ready(fixture.fake.ready(SessionHandle("session-3"))))
        advanceUntilIdle()
        assertEquals(6, sink.values.size)
    }

    @Test
    fun outboundEventEncodingFailureTerminatesOnlyCurrentSinkAndAllowsRelisten() = runTest {
        val fixture = fixture()
        val first = RecordingEventSink()
        fixture.controller.onListen(mapOf("wireVersion" to 3), first)
        val session = fixture.start("start-1")
        val ready = fixture.fake.ready(SessionHandle(session))
        fixture.fake.emit(
            SessionReady(
                sessionHandle = ready.sessionHandle,
                activeCamera = ready.activeCamera,
                availableCameras = ready.availableCameras,
                switchCameraSupported = ready.switchCameraSupported,
                supportedFlashModes = ready.supportedFlashModes,
                focusPointSupported = ready.focusPointSupported,
                minZoomFactor = Double.NaN,
                maxZoomFactor = ready.maxZoomFactor,
            ).let(MediaCaptureEvent::Ready),
        )
        advanceUntilIdle()

        assertEquals("wire_encoding_failed", first.errorCode)
        assertTrue(first.values.isEmpty())

        val second = RecordingEventSink()
        fixture.controller.onListen(mapOf("wireVersion" to 3), second)
        fixture.fake.emit(MediaCaptureEvent.Ready(ready))
        advanceUntilIdle()

        assertEquals(1, second.values.size)
        assertNull(second.errorCode)
    }

    @Test
    fun activityBoundaryCompletesOnceThenCleansLateSession() = runTest {
        val fixture = fixture()
        val gate = CompletableDeferred<Unit>()
        fixture.fake.startGate = gate
        fixture.fake.startIgnoresCancellation = true
        val result = fixture.callWithoutDrain("start_session", "late-start", startPayload())
        runCurrent()

        fixture.controller.detachOwner(fixture.owner.generation)
        runCurrent()
        assertEquals("bridge_unavailable", result.errorCode)
        assertEquals(1, result.completionCount)

        gate.complete(Unit)
        advanceUntilIdle()
        assertEquals(listOf("session-1"), fixture.fake.cancelledSessions)
        assertEquals(1, result.completionCount)
    }

    @Test
    fun failedLateCleanupRetainsOwnershipAndRetries() = runTest {
        val fixture = fixture()
        val gate = CompletableDeferred<Unit>()
        fixture.fake.startGate = gate
        fixture.fake.startIgnoresCancellation = true
        fixture.fake.cancelFailuresRemaining = 2
        val result = fixture.callWithoutDrain("start_session", "late-retry", startPayload())
        runCurrent()

        fixture.controller.detachOwner(fixture.owner.generation)
        runCurrent()
        gate.complete(Unit)
        advanceUntilIdle()

        assertEquals("bridge_unavailable", result.errorCode)
        assertEquals(listOf("session-1"), fixture.fake.cancelledSessions)
        assertEquals(3, fixture.fake.calls.count { it == "cancel" })
        assertEquals(1, fixture.fake.closeCount)
    }

    @Test
    fun failedPermissionListenerCleanupRetriesBeforeOwnerRetires() = runTest {
        var closeAttempts = 0
        val fixture =
            fixture(
                closeAction = {
                    closeAttempts += 1
                    if (closeAttempts < 3) error("temporary listener removal failure")
                },
            )

        fixture.controller.detachOwner(fixture.owner.generation)
        advanceUntilIdle()

        assertEquals(3, closeAttempts)
        assertEquals(1, fixture.fake.closeCount)
    }

    @Test
    fun requestCannotSlipBetweenOwnerBoundaryAndReservation() = runTest {
        val fixture = fixture()
        fixture.controller.detachOwner(fixture.owner.generation)

        val result = fixture.callWithoutDrain("start_session", "after-detach", startPayload())
        advanceUntilIdle()

        assertEquals("bridge_unavailable", result.errorCode)
        assertTrue(fixture.fake.calls.none { it == "start_session" })
    }

    @Test
    fun engineBoundaryReleasesAdoptedLeaseAndWipesLateThumbnail() = runTest {
        val fixture = fixture()
        val lease = fixture.confirmPhoto()
        val gate = CompletableDeferred<Unit>()
        fixture.fake.thumbnailGate = gate
        fixture.fake.thumbnailIgnoresCancellation = true
        val bytes = fixture.fake.thumbnailBytes
        val result =
            fixture.callWithoutDrain(
                "read_media_thumbnail",
                "late-thumb",
                mapOf("mediaHandle" to lease, "maxPixelEdge" to 128),
            )
        runCurrent()

        fixture.controller.detachEngine()
        runCurrent()
        assertEquals("bridge_unavailable", result.errorCode)
        assertEquals(listOf(lease), fixture.fake.releasedMedia)

        gate.complete(Unit)
        advanceUntilIdle()
        assertTrue(bytes.all { it == 0.toByte() })
        assertEquals(1, result.completionCount)
        assertEquals(1, fixture.fake.closeCount)
        assertEquals(0, fixture.fake.eventSubscriberCount)
    }

    @Test
    fun engineBoundaryCleansDirectConfirmedLeaseThatArrivesLate() = runTest {
        val fixture = fixture()
        val session = fixture.start("late-confirm-start")
        val preview =
            fixture.call("take_photo", "late-confirm-photo", sessionPayload(session))
        val mediaHandle = preview.payloadString("mediaHandle")
        val gate = CompletableDeferred<Unit>()
        fixture.fake.confirmGate = gate
        fixture.fake.confirmIgnoresCancellation = true
        val result =
            fixture.callWithoutDrain(
                "confirm",
                "late-confirm",
                mediaPayload(mediaHandle),
            )
        runCurrent()

        fixture.controller.detachEngine()
        runCurrent()
        gate.complete(Unit)
        advanceUntilIdle()

        assertEquals("bridge_unavailable", result.errorCode)
        assertEquals(listOf(mediaHandle), fixture.fake.releasedMedia)
        assertEquals(1, fixture.fake.closeCount)
        assertEquals(0, fixture.fake.eventSubscriberCount)
    }

    @Test
    fun engineBoundaryCleansPresentationConfirmedLeaseThatArrivesLate() = runTest {
        val fixture = fixture()
        fixture.presenter.completeOnDismiss = false
        val result = fixture.callWithoutDrain("present_capture_flow", "late-engine-flow", startPayload())
        runCurrent()

        fixture.controller.detachEngine()
        runCurrent()
        fixture.presenter.sessions.single().outcome.complete(
            MediaCaptureFlowResult.Confirmed(fixture.fake.confirmed()),
        )
        advanceUntilIdle()

        assertEquals("bridge_unavailable", result.errorCode)
        assertEquals(listOf("flow-media"), fixture.fake.releasedMedia)
        assertEquals(1, fixture.fake.closeCount)
        assertEquals(0, fixture.fake.eventSubscriberCount)
    }

    @Test
    fun deliveredLeaseSurvivesActivityReplacementAndRoutesToOriginalCore() = runTest {
        val fixture = fixture()
        val lease = fixture.confirmPhoto()
        fixture.controller.detachOwner(fixture.owner.generation)
        advanceUntilIdle()

        val nextActivity = Robolectric.buildActivity(BridgeTestActivity::class.java).create().get()
        nextActivity.moveTo(Lifecycle.State.CREATED)
        val nextCore = FakeMediaCapture()
        val nextOwner =
            MediaCaptureBridgeOwner(
                generation = fixture.controller.nextOwnerGeneration(),
                activity = nextActivity,
                lifecycleOwner = nextActivity,
                mediaCapture = nextCore,
                presenter = FakePresentationController(),
                closeAction = {},
                retireAction = {},
            )
        fixture.controller.attachOwner(nextOwner)
        runCurrent()

        fixture.call("release_media", "release-old", mediaPayload(lease))
            .expectType("media_released")
        fixture.call("start_session", "start-new", startPayload()).expectType("session_created")

        assertEquals(listOf(lease), fixture.fake.releasedMedia)
        assertEquals(listOf("start_session"), nextCore.calls)
    }

    @Test
    fun newOwnerCannotReuseMediaHandleAwaitingOldReadRevocation() = runTest {
        val fixture = fixture()
        val oldLease = fixture.confirmPhoto()
        fixture.call("release_media", "release-before-replace", mediaPayload(oldLease))
            .expectType("media_released")
        fixture.controller.detachOwner(fixture.owner.generation)
        advanceUntilIdle()

        val nextActivity = Robolectric.buildActivity(BridgeTestActivity::class.java).create().get()
        nextActivity.moveTo(Lifecycle.State.CREATED)
        val nextCore = FakeMediaCapture()
        val nextOwner =
            MediaCaptureBridgeOwner(
                generation = fixture.controller.nextOwnerGeneration(),
                activity = nextActivity,
                lifecycleOwner = nextActivity,
                mediaCapture = nextCore,
                presenter = FakePresentationController(),
                closeAction = {},
                retireAction = {},
            )
        fixture.controller.attachOwner(nextOwner)
        runCurrent()

        val newSession =
            fixture.call("start_session", "new-owner-start", startPayload())
                .payloadString("sessionHandle")
        val collision =
            fixture.call(
                "take_photo",
                "new-owner-photo",
                sessionPayload(newSession),
            )

        assertEquals("wire_encoding_failed", collision.errorCode)
        assertEquals(listOf(newSession), nextCore.cancelledSessions)
        assertEquals(oldLease, "media-$newSession")
    }

    @Test
    fun presentationMapsThreeOutcomesAndRejectsConcurrentFlow() = runTest {
        val fixture = fixture()
        val first = fixture.callWithoutDrain("present_capture_flow", "flow-1", startPayload())
        runCurrent()
        val conflict = fixture.call("present_capture_flow", "flow-2", startPayload())
        assertEquals("presentation_conflict", conflict.errorCode)

        fixture.presenter.sessions.single().outcome.complete(
            MediaCaptureFlowResult.Confirmed(fixture.fake.confirmed()),
        )
        advanceUntilIdle()
        first.expectType("capture_flow_confirmed")
        fixture.call("release_media", "release-flow", mediaPayload("flow-media"))
            .expectType("media_released")

        val cancelled = fixture.callWithoutDrain("present_capture_flow", "flow-3", startPayload())
        runCurrent()
        fixture.presenter.sessions.last().outcome.complete(MediaCaptureFlowResult.Cancelled)
        advanceUntilIdle()
        cancelled.expectType("capture_flow_cancelled")

        val failed = fixture.callWithoutDrain("present_capture_flow", "flow-4", startPayload())
        runCurrent()
        fixture.presenter.sessions.last().outcome.complete(
            MediaCaptureFlowResult.Failure(MediaCaptureFailure(FailureCode.PERMISSION_DENIED)),
        )
        advanceUntilIdle()
        assertEquals("permission_denied", failed.errorCode)
    }

    @Test
    fun dismissCaptureFlowTargetsOnePresentationAndIsIdempotent() = runTest {
        val fixture = fixture()
        val presentation =
            fixture.callWithoutDrain("present_capture_flow", "flow-to-dismiss", startPayload())
        runCurrent()
        val session = fixture.presenter.sessions.single()

        fixture.callRunningCurrent(
            "dismiss_capture_flow",
            "dismiss-flow-1",
            mapOf("presentationRequestId" to "flow-to-dismiss"),
        ).expectType("capture_flow_dismissed")
        advanceUntilIdle()

        presentation.expectType("capture_flow_cancelled")
        assertEquals(1, presentation.completionCount)
        assertEquals(1, session.dismissCount)
        fixture.callRunningCurrent(
            "dismiss_capture_flow",
            "dismiss-flow-2",
            mapOf("presentationRequestId" to "flow-to-dismiss"),
        ).expectType("capture_flow_dismissed")
        assertEquals(1, session.dismissCount)
    }

    @Test
    fun dismissCaptureFlowCancelsPermissionPreflightBeforeUiCreation() = runTest {
        val permissionResult = CompletableDeferred<FailureCode?>()
        val fixture =
            fixture(
                permissionPreflight = MediaCaptureBridgePermissionPreflight { permissionResult.await() },
            )
        val presentation =
            fixture.callWithoutDrain("present_capture_flow", "preflight-to-dismiss", startPayload())
        runCurrent()

        fixture.callRunningCurrent(
            "dismiss_capture_flow",
            "dismiss-preflight",
            mapOf("presentationRequestId" to "preflight-to-dismiss"),
        ).expectType("capture_flow_dismissed")
        presentation.expectType("capture_flow_cancelled")

        permissionResult.complete(null)
        advanceUntilIdle()
        assertTrue(fixture.presenter.sessions.isEmpty())
        assertEquals(1, presentation.completionCount)
    }

    @Test
    fun presentationCompletesPermissionPreflightBeforeCreatingUi() = runTest {
        var preflightComplete = false
        val fixture =
            fixture(
                permissionPreflight =
                    MediaCaptureBridgePermissionPreflight { options ->
                        assertTrue(options.audioEnabled)
                        assertTrue(MediaType.VIDEO in options.enabledMediaTypes)
                        preflightComplete = true
                        null
                    },
            )
        fixture.presenter.beforePresent = { assertTrue(preflightComplete) }

        val result = fixture.callWithoutDrain("present_capture_flow", "preflight-flow", startPayload())
        runCurrent()

        assertEquals(1, fixture.presenter.sessions.size)
        fixture.presenter.sessions.single().outcome.complete(MediaCaptureFlowResult.Cancelled)
        advanceUntilIdle()
        result.expectType("capture_flow_cancelled")
    }

    @Test
    fun deniedPermissionPreflightDoesNotCreateUi() = runTest {
        val fixture =
            fixture(
                permissionPreflight =
                    MediaCaptureBridgePermissionPreflight {
                        FailureCode.PERMISSION_DENIED
                    },
            )

        val result = fixture.call("present_capture_flow", "denied-preflight", startPayload())

        assertEquals("permission_denied", result.errorCode)
        assertTrue(fixture.presenter.sessions.isEmpty())
    }

    @Test
    fun ownerDetachBeforePermissionPreflightInvalidatesImmediatelyAndSkipsUi() = runTest {
        var preflightCalls = 0
        var invalidationCalls = 0
        val fixture =
            fixture(
                permissionPreflight =
                    MediaCaptureBridgePermissionPreflight {
                        preflightCalls += 1
                        null
                    },
                permissionInvalidationAction = { invalidationCalls += 1 },
            )
        val result = fixture.callWithoutDrain("present_capture_flow", "detach-before-preflight", startPayload())

        fixture.controller.detachOwner(fixture.owner.generation)

        assertEquals(1, invalidationCalls)
        advanceUntilIdle()
        assertEquals(0, preflightCalls)
        assertTrue(fixture.presenter.sessions.isEmpty())
        assertEquals("bridge_unavailable", result.errorCode)
        assertEquals(1, result.completionCount)
    }

    @Test
    fun ownerDetachAfterPermissionResultBeforePresentSkipsStaleActivityUi() = runTest {
        val permissionResult = CompletableDeferred<Unit>()
        var invalidationCalls = 0
        val fixture =
            fixture(
                permissionPreflight =
                    MediaCaptureBridgePermissionPreflight {
                        permissionResult.await()
                        null
                    },
                permissionInvalidationAction = { invalidationCalls += 1 },
            )
        val result = fixture.callWithoutDrain("present_capture_flow", "detach-after-permission", startPayload())
        runCurrent()

        permissionResult.complete(Unit)
        fixture.controller.detachOwner(fixture.owner.generation)

        assertEquals(1, invalidationCalls)
        advanceUntilIdle()
        assertTrue(fixture.presenter.sessions.isEmpty())
        assertEquals("bridge_unavailable", result.errorCode)
        assertEquals(1, result.completionCount)
    }

    @Test
    fun engineDetachDuringPermissionPreflightInvalidatesAndSkipsUi() = runTest {
        val permissionResult = CompletableDeferred<FailureCode?>()
        var invalidationCalls = 0
        val fixture =
            fixture(
                permissionPreflight =
                    MediaCaptureBridgePermissionPreflight {
                        permissionResult.await()
                    },
                permissionInvalidationAction = {
                    invalidationCalls += 1
                    permissionResult.complete(FailureCode.PERMISSION_DENIED)
                },
            )
        val result = fixture.callWithoutDrain("present_capture_flow", "engine-detach-preflight", startPayload())
        runCurrent()

        fixture.controller.detachEngine()

        assertEquals(1, invalidationCalls)
        advanceUntilIdle()
        assertTrue(fixture.presenter.sessions.isEmpty())
        assertEquals("bridge_unavailable", result.errorCode)
        assertEquals(1, result.completionCount)
    }

    @Test
    fun presentationFailureDistinguishesDeadOwnerFromLiveConflict() = runTest {
        val deadOwner = fixture()
        (deadOwner.owner.activity as BridgeTestActivity).moveTo(Lifecycle.State.DESTROYED)
        val unavailable =
            deadOwner.call("present_capture_flow", "dead-owner-flow", startPayload())
        assertEquals("bridge_unavailable", unavailable.errorCode)
        assertTrue(deadOwner.presenter.sessions.isEmpty())

        val liveOwner = fixture()
        liveOwner.presenter.presentFailure = IllegalStateException("already presenting")
        val conflict =
            liveOwner.call("present_capture_flow", "live-owner-conflict", startPayload())
        assertEquals("presentation_conflict", conflict.errorCode)
    }

    @Test
    fun ownerBoundaryDismissesPresentationBeforeBridgeUnavailableCompletion() = runTest {
        val fixture = fixture()
        val result = fixture.callWithoutDrain("present_capture_flow", "flow-1", startPayload())
        runCurrent()
        val session = fixture.presenter.sessions.single()

        fixture.controller.detachOwner(fixture.owner.generation)
        advanceUntilIdle()

        assertEquals(1, session.dismissCount)
        assertEquals("bridge_unavailable", result.errorCode)
        assertEquals(1, result.completionCount)
    }

    @Test
    fun ownerReplacementWaitsForLateConfirmedPresentationCleanup() = runTest {
        val fixture = fixture()
        fixture.presenter.completeOnDismiss = false
        val result = fixture.callWithoutDrain("present_capture_flow", "late-flow", startPayload())
        runCurrent()

        fixture.controller.detachOwner(fixture.owner.generation)
        val nextActivity = Robolectric.buildActivity(BridgeTestActivity::class.java).create().get()
        nextActivity.moveTo(Lifecycle.State.CREATED)
        val nextCore = FakeMediaCapture()
        val nextOwner =
            MediaCaptureBridgeOwner(
                generation = fixture.controller.nextOwnerGeneration(),
                activity = nextActivity,
                lifecycleOwner = nextActivity,
                mediaCapture = nextCore,
                presenter = FakePresentationController(),
                closeAction = {},
                retireAction = {},
            )
        fixture.controller.attachOwner(nextOwner)
        runCurrent()

        val blocked = fixture.call("start_session", "start-during-cleanup", startPayload())
        assertEquals("bridge_unavailable", blocked.errorCode)
        assertTrue(nextCore.calls.isEmpty())

        fixture.fake.releaseFailuresRemaining = 2
        fixture.presenter.sessions.single().outcome.complete(
            MediaCaptureFlowResult.Confirmed(fixture.fake.confirmed()),
        )
        advanceUntilIdle()

        assertEquals("bridge_unavailable", result.errorCode)
        assertEquals(listOf("flow-media"), fixture.fake.releasedMedia)
        assertEquals(3, fixture.fake.calls.count { it == "release_media" })
        fixture.call("start_session", "start-after-cleanup", startPayload())
            .expectType("session_created")
        assertEquals(listOf("start_session"), nextCore.calls)
    }

    @Test
    fun presentationAndDismissAlwaysRunOnMainDispatcher() = runTest {
        val base = StandardTestDispatcher(testScheduler)
        val marker = ThreadLocal<String?>()
        val main = MarkingDispatcher(base, marker, "main")
        val worker = MarkingDispatcher(base, marker, "worker")
        val activity = Robolectric.buildActivity(BridgeTestActivity::class.java).create().get()
        activity.moveTo(Lifecycle.State.CREATED)
        val fake = FakeMediaCapture()
        val session = MainCheckingPresentationSession(marker)
        val controller =
            MediaCaptureBridgeController(
                CoroutineScope(SupervisorJob() + worker),
                main,
                nowMillis = { 0L },
            )
        val owner =
            MediaCaptureBridgeOwner(
                generation = controller.nextOwnerGeneration(),
                activity = activity,
                lifecycleOwner = activity,
                mediaCapture = fake,
                presenter =
                    MediaCaptureBridgePresenter {
                        assertEquals("main", marker.get())
                        session
                    },
                closeAction = {},
                retireAction = {},
            )
        controller.attachOwner(owner)
        runCurrent()
        val result = RecordingResult()
        controller.handleMethod(
            "present_capture_flow",
            envelope("main-thread-flow", startPayload()),
            result,
        )
        runCurrent()

        controller.detachOwner(owner.generation)
        advanceUntilIdle()

        assertEquals("main", session.dismissMarker)
        assertEquals("bridge_unavailable", result.errorCode)
    }

    @Test
    fun resourceIsAdoptedBeforeFlutterSuccessCallback() = runTest {
        val fixture = fixture()
        val chained = RecordingResult()
        chained.onSuccess = { value ->
            val session = ((value as Map<*, *>)["payload"] as Map<*, *>)["sessionHandle"] as String
            fixture.controller.handleMethod(
                "take_photo",
                envelope("chained-photo", sessionPayload(session)),
                chained.followUp,
            )
        }

        fixture.controller.handleMethod(
            "start_session",
            envelope("chained-start", startPayload()),
            chained,
        )
        advanceUntilIdle()

        chained.expectType("session_created")
        chained.followUp.expectType("media_preview")
    }

    @Test
    fun flutterSuccessCallbackFailureCleansAdoptedSession() = runTest {
        val fixture = fixture()
        val result = RecordingResult().also {
            it.onSuccess = { throw IllegalStateException("flutter callback closed") }
        }

        fixture.controller.handleMethod(
            "start_session",
            envelope("callback-failure", startPayload()),
            result,
        )
        advanceUntilIdle()

        assertEquals(1, result.completionCount)
        assertEquals(listOf("session-1"), fixture.fake.cancelledSessions)
    }

    @Test
    fun materializeCommitsPrivateFileAndReleaseKeepsSourceLeaseIndependent() = runTest {
        withTemporaryDirectory { cache ->
            val fixture = fixture(transferStore = testTransferStore(cache), epochMillis = { 1_000L })
            val mediaHandle = fixture.confirmPhoto()

            val materialized =
                fixture.callRunningCurrent(
                    "materialize_media_resource",
                    "materialize-1",
                    mediaPayload(mediaHandle),
                )

            materialized.expectType("materialized_media_resource")
            val exportHandle = materialized.payloadString("exportHandle")
            val fileUri = materialized.payloadString("fileUri")
            assertTrue(fileUri.startsWith("file://${cache.canonicalPath}/app_media_capture_bridge/exports/"))
            assertEquals(301_000L, materialized.payload()["expiresAt"])
            assertTrue(File(java.net.URI(fileUri)).isFile)
            assertTrue(fixture.fake.releasedMedia.isEmpty())

            fixture.callRunningCurrent(
                "release_materialized_media",
                "release-export-1",
                mapOf("exportHandle" to exportHandle),
            ).expectType("materialized_media_released")
            assertFalse(File(java.net.URI(fileUri)).exists())
            assertTrue(fixture.fake.releasedMedia.isEmpty())

            fixture.callRunningCurrent(
                "release_materialized_media",
                "release-export-2",
                mapOf("exportHandle" to exportHandle),
            ).expectType("materialized_media_released")
        }
    }

    @Test
    fun transferCapacityRejectsBeforeCallingCoreAndReleasesAfterDelete() = runTest {
        withTemporaryDirectory { cache ->
            val fixture = fixture(transferStore = testTransferStore(cache))
            val mediaHandle = fixture.confirmPhoto()
            val exports =
                (1..4).map { index ->
                    fixture.callRunningCurrent(
                        "materialize_media_resource",
                        "materialize-$index",
                        mediaPayload(mediaHandle),
                    ).also { it.expectType("materialized_media_resource") }
                }

            val rejected =
                fixture.callRunningCurrent(
                    "materialize_media_resource",
                    "materialize-5",
                    mediaPayload(mediaHandle),
                )
            assertEquals("transfer_store_overloaded", rejected.errorCode)
            assertEquals("active_exports", rejected.errorDetails?.get("capacity"))
            assertEquals(4, fixture.fake.calls.count { it == "copy_confirmed_media_to_sink" })

            fixture.callRunningCurrent(
                "release_materialized_media",
                "release-capacity",
                mapOf("exportHandle" to exports.first().payloadString("exportHandle")),
            ).expectType("materialized_media_released")
            fixture.callRunningCurrent(
                "materialize_media_resource",
                "materialize-6",
                mediaPayload(mediaHandle),
            ).expectType("materialized_media_resource")
        }
    }

    @Test
    fun ttlDeletesTransferAndRejectsExpiredHandle() = runTest {
        withTemporaryDirectory { cache ->
            val fixture = fixture(transferStore = testTransferStore(cache))
            val materialized =
                fixture.callRunningCurrent(
                    "materialize_media_resource",
                    "materialize-ttl",
                    mediaPayload(fixture.confirmPhoto()),
                )
            val exportHandle = materialized.payloadString("exportHandle")
            val file = File(java.net.URI(materialized.payloadString("fileUri")))

            advanceTimeBy(300_000L)
            runCurrent()

            assertFalse(file.exists())
            val release =
                fixture.callRunningCurrent(
                    "release_materialized_media",
                    "release-expired",
                    mapOf("exportHandle" to exportHandle),
                )
            assertEquals("materialized_media_invalid", release.errorCode)
        }
    }

    @Test
    fun engineDetachCleansInflightStagingBeforeCompletingAndDropsLateResult() = runTest {
        withTemporaryDirectory { cache ->
            val fixture = fixture(transferStore = testTransferStore(cache))
            val mediaHandle = fixture.confirmPhoto()
            fixture.fake.exportGate = CompletableDeferred()
            fixture.fake.exportIgnoresCancellation = true
            val result =
                fixture.callWithoutDrain(
                    "materialize_media_resource",
                    "materialize-detach",
                    mediaPayload(mediaHandle),
                )
            runCurrent()

            fixture.controller.detachEngine()
            runCurrent()

            assertEquals("bridge_unavailable", result.errorCode)
            assertEquals(1, result.completionCount)
            assertTrue(
                File(cache, "app_media_capture_bridge/exports").listFiles().orEmpty().isEmpty(),
            )

            fixture.fake.exportGate?.complete(Unit)
            runCurrent()
            assertEquals(1, result.completionCount)
            assertTrue(
                File(cache, "app_media_capture_bridge/exports").listFiles().orEmpty().isEmpty(),
            )
        }
    }

    @Test
    fun releaseDeleteFailureReturnsRedactedErrorAndRetriesWithoutCaller() = runTest {
        withTemporaryDirectory { cache ->
            var deleteFailures = 3
            val store =
                testTransferStore(cache, deleteFile = { file ->
                    if (deleteFailures > 0) {
                        deleteFailures -= 1
                        false
                    } else {
                        file.delete()
                    }
                })
            val fixture = fixture(transferStore = store)
            val materialized =
                fixture.callRunningCurrent(
                    "materialize_media_resource",
                    "materialize-delete-failure",
                    mediaPayload(fixture.confirmPhoto()),
                )
            val exportHandle = materialized.payloadString("exportHandle")
            val file = File(java.net.URI(materialized.payloadString("fileUri")))

            val failed =
                fixture.callWithoutDrain(
                    "release_materialized_media",
                    "release-delete-failure",
                    mapOf("exportHandle" to exportHandle),
            )
            runCurrent()
            advanceUntilIdle()

            assertEquals("transfer_store_unavailable", failed.errorCode)
            assertFalse(failed.errorDetails.toString().contains(cache.absolutePath))
            assertFalse(file.exists())

            fixture.callRunningCurrent(
                "release_materialized_media",
                "release-delete-retry",
                mapOf("exportHandle" to exportHandle),
            ).expectType("materialized_media_released")
            assertFalse(file.exists())
        }
    }

    @Test
    fun ttlDeleteFailureRetriesAndReturnsTransferCapacity() = runTest {
        withTemporaryDirectory { cache ->
            var deleteFailures = 3
            val store =
                testTransferStore(cache, deleteFile = { file ->
                    if (deleteFailures > 0) {
                        deleteFailures -= 1
                        false
                    } else {
                        file.delete()
                    }
                })
            val fixture = fixture(transferStore = store)
            val mediaHandle = fixture.confirmPhoto()
            val exports =
                (1..4).map { index ->
                    fixture.callRunningCurrent(
                        "materialize_media_resource",
                        "materialize-ttl-retry-$index",
                        mediaPayload(mediaHandle),
                    )
                }
            val firstFile = File(java.net.URI(exports.first().payloadString("fileUri")))

            advanceTimeBy(300_000L)
            runCurrent()
            advanceTimeBy(50L)
            runCurrent()

            assertFalse(firstFile.exists())
            fixture.callRunningCurrent(
                "materialize_media_resource",
                "materialize-after-ttl-retry",
                mediaPayload(mediaHandle),
            ).expectType("materialized_media_resource")
        }
    }

    @Test
    fun concurrentReleaseRequestsJoinOneCleanupClaim() = runTest {
        withTemporaryDirectory { cache ->
            var deleteCalls = 0
            val store =
                testTransferStore(cache, deleteFile = { file ->
                    deleteCalls += 1
                    if (deleteCalls == 1) false else file.delete()
                })
            val fixture = fixture(transferStore = store)
            val materialized =
                fixture.callRunningCurrent(
                    "materialize_media_resource",
                    "materialize-concurrent-release",
                    mediaPayload(fixture.confirmPhoto()),
                )
            val payload = mapOf("exportHandle" to materialized.payloadString("exportHandle"))
            val first =
                fixture.callWithoutDrain(
                    "release_materialized_media",
                    "release-concurrent-1",
                    payload,
                )
            runCurrent()
            val second =
                fixture.callWithoutDrain(
                    "release_materialized_media",
                    "release-concurrent-2",
                    payload,
                )
            runCurrent()

            advanceTimeBy(50L)
            runCurrent()

            first.expectType("materialized_media_released")
            second.expectType("materialized_media_released")
            assertEquals(2, deleteCalls)
        }
    }

    @Test
    fun mismatchedLateExportResultIsDeletedAndNeverLeaksLocatorInError() = runTest {
        withTemporaryDirectory { cache ->
            val fixture = fixture(transferStore = testTransferStore(cache))
            fixture.fake.exportResultHandleOverride = MediaHandle("unexpected-media")

            val result =
                fixture.callRunningCurrent(
                    "materialize_media_resource",
                    "materialize-mismatch",
                    mediaPayload(fixture.confirmPhoto()),
                )

            assertEquals("wire_encoding_failed", result.errorCode)
            assertFalse(result.errorDetails.toString().contains(cache.absolutePath))
            assertTrue(
                File(cache, "app_media_capture_bridge/exports").listFiles().orEmpty().isEmpty(),
            )
        }
    }

    private fun TestScope.fixture(
        nowMillis: () -> Long = { 0L },
        epochMillis: () -> Long = nowMillis,
        transferStore: MediaCaptureTransferStore? = null,
        closeAction: () -> Unit = {},
        permissionPreflight: MediaCaptureBridgePermissionPreflight =
            MediaCaptureBridgePermissionPreflight { null },
        permissionInvalidationAction: () -> Unit = {},
    ): Fixture {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val activity = Robolectric.buildActivity(BridgeTestActivity::class.java).create().get()
        activity.moveTo(Lifecycle.State.CREATED)
        val fake = FakeMediaCapture()
        val presenter = FakePresentationController()
        val controller =
            MediaCaptureBridgeController(
                CoroutineScope(SupervisorJob() + dispatcher),
                dispatcher,
                nowMillis,
                epochMillis,
                transferStore,
            )
        val owner =
            MediaCaptureBridgeOwner(
                generation = controller.nextOwnerGeneration(),
                activity = activity,
                lifecycleOwner = activity,
                mediaCapture = fake,
                presenter = presenter,
                closeAction = closeAction,
                retireAction = {},
                permissionPreflight = permissionPreflight,
                permissionInvalidationAction = permissionInvalidationAction,
            )
        controller.attachOwner(owner)
        runCurrent()
        return Fixture(controller, owner, fake, presenter, this)
    }

    private data class Fixture(
        val controller: MediaCaptureBridgeController,
        val owner: MediaCaptureBridgeOwner,
        val fake: FakeMediaCapture,
        val presenter: FakePresentationController,
        val scope: TestScope,
    ) {
        suspend fun start(requestId: String): String {
            val result = call("start_session", requestId, startPayload())
            result.expectType("session_created")
            return result.payloadString("sessionHandle")
        }

        suspend fun confirmPhoto(): String {
            val session = start("start-for-confirm")
            val preview = call("take_photo", "photo-for-confirm", sessionPayload(session))
            val confirmed =
                call(
                    "confirm",
                    "confirm-for-lease",
                    mediaPayload(preview.payloadString("mediaHandle")),
                )
            return confirmed.payloadString("mediaHandle")
        }

        suspend fun call(
            operation: String,
            requestId: String,
            payload: Map<String, Any?>,
        ): RecordingResult =
            callWithoutDrain(operation, requestId, payload).also { scope.advanceUntilIdle() }

        fun callRunningCurrent(
            operation: String,
            requestId: String,
            payload: Map<String, Any?>,
        ): RecordingResult = callWithoutDrain(operation, requestId, payload).also { scope.runCurrent() }

        fun callWithoutDrain(
            operation: String,
            requestId: String,
            payload: Map<String, Any?>,
        ): RecordingResult =
            RecordingResult().also { result ->
                controller.handleMethod(operation, envelope(requestId, payload), result)
            }
    }

    private suspend fun withTemporaryDirectory(block: suspend (File) -> Unit) {
        val directory = Files.createTempDirectory("media-capture-controller-transfer").toFile()
        try {
            block(directory)
        } finally {
            directory.deleteRecursively()
        }
    }
}

internal class RecordingResult : MediaCaptureBridgeResult {
    var successValue: Any? = null
    var errorCode: String? = null
    var errorMessage: String? = null
    var errorDetails: Map<*, *>? = null
    var completionCount = 0
    var onSuccess: ((Any?) -> Unit)? = null
    val followUp = RecordingResultChild()

    override fun success(value: Any?) {
        completionCount += 1
        successValue = value
        onSuccess?.invoke(value)
    }

    override fun error(code: String, message: String, details: Any?) {
        completionCount += 1
        errorCode = code
        errorMessage = message
        errorDetails = details as? Map<*, *>
    }

    fun expectType(type: String) {
        assertNull(errorCode)
        assertEquals(type, (successValue as Map<*, *>)["resultType"])
        assertEquals(1, completionCount)
    }

    fun payload(): Map<*, *> = (successValue as Map<*, *>)["payload"] as Map<*, *>

    fun payloadString(key: String): String = payload()[key] as String
}

internal class RecordingResultChild : MediaCaptureBridgeResult {
    var successValue: Any? = null
    var errorCode: String? = null

    override fun success(value: Any?) {
        successValue = value
    }

    override fun error(code: String, message: String, details: Any?) {
        errorCode = code
    }

    fun expectType(type: String) {
        assertNull(errorCode)
        assertNotNull(successValue)
        assertEquals(type, (successValue as Map<*, *>)["resultType"])
    }
}

internal class RecordingEventSink : MediaCaptureBridgeEventSink {
    val values = mutableListOf<Any?>()
    var errorCode: String? = null
    var ended = false

    override fun success(value: Any?) {
        values += value
    }

    override fun error(code: String, message: String, details: Any?) {
        errorCode = code
    }

    override fun endOfStream() {
        ended = true
    }
}

private class MarkingDispatcher(
    private val delegate: CoroutineDispatcher,
    private val marker: ThreadLocal<String?>,
    private val value: String,
) : CoroutineDispatcher() {
    override fun dispatch(context: CoroutineContext, block: Runnable) {
        delegate.dispatch(context) {
            val previous = marker.get()
            marker.set(value)
            try {
                block.run()
            } finally {
                marker.set(previous)
            }
        }
    }
}

private class MainCheckingPresentationSession(
    private val marker: ThreadLocal<String?>,
) : MediaCaptureBridgePresentationSession {
    private val outcome = CompletableDeferred<MediaCaptureFlowResult>()
    var dismissMarker: String? = null

    override suspend fun awaitResult(): MediaCaptureFlowResult = outcome.await()

    override fun dismiss() {
        dismissMarker = marker.get()
        outcome.complete(MediaCaptureFlowResult.Cancelled)
    }
}

class BridgeTestActivity : Activity(), LifecycleOwner {
    private val registry = LifecycleRegistry(this)

    override val lifecycle: Lifecycle
        get() = registry

    fun moveTo(state: Lifecycle.State) {
        registry.currentState = state
    }
}
