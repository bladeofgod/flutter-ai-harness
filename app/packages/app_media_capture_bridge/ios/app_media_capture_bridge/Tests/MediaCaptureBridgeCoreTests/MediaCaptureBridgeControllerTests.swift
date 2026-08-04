import MediaCapture
import XCTest
@testable import MediaCaptureBridgeCore

@MainActor
final class MediaCaptureBridgeControllerTests: XCTestCase {
    func testFirstRequestWaitsUntilEventCollectionIsRegistered() async {
        let core = FakeMediaCaptureCore()
        await core.configureEventRegistrationBlocked(true)
        let owner = PresentationOwnerBox()
        let controller = makeController(core: core, owner: owner)
        let pending = CompletionProbe()
        controller.handle(
            operation: "start_session",
            arguments: requestEnvelope(requestId: "collector_start", payload: startPayload()),
            completion: pending
        )

        await Task.yield()
        await Task.yield()
        let registeredBeforeUnblock = await core.isEventRegistrationCompleted()
        let snapshotBeforeUnblock = await core.snapshot()
        XCTAssertFalse(registeredBeforeUnblock)
        XCTAssertFalse(snapshotBeforeUnblock.operations.contains("start_session"))

        await core.unblockEventRegistration()
        let outcome = await pending.value()
        XCTAssertEqual(resultType(outcome), "session_created")
        let registeredAfterUnblock = await core.isEventRegistrationCompleted()
        XCTAssertTrue(registeredAfterUnblock)
    }

    func testEngineDetachCompletesRequestWaitingForEventCollection() async {
        let core = FakeMediaCaptureCore()
        await core.configureEventRegistrationBlocked(true)
        let owner = PresentationOwnerBox()
        let controller = makeController(core: core, owner: owner)
        let pending = CompletionProbe()
        controller.handle(
            operation: "start_session",
            arguments: requestEnvelope(requestId: "collector_detach", payload: startPayload()),
            completion: pending
        )
        await Task.yield()

        controller.detachEngine()
        let outcome = await pending.value()
        XCTAssertEqual(failure(outcome)?.details["lifecycleReason"], "engine_detached")
        XCTAssertEqual(pending.completionCount, 1)
        let snapshot = await core.snapshot()
        XCTAssertFalse(snapshot.operations.contains("start_session"))
        await core.unblockEventRegistration()
    }

    func testDirectOperationsCoverFullBaseLifecycleOnMainActor() async throws {
        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        let controller = makeController(core: core, owner: owner)

        await assertResultType(controller, operation: "start_session", requestId: "start_1", payload: startPayload(), expected: "session_created")
        await assertResultType(controller, operation: "switch_camera", requestId: "switch_1", payload: sessionPayload("session_1"), expected: "control_applied")
        await assertResultType(controller, operation: "set_flash_mode", requestId: "flash_1", payload: ["sessionHandle": "session_1", "flashMode": "auto"], expected: "control_applied")
        await assertResultType(controller, operation: "set_focus_point", requestId: "focus_1", payload: ["sessionHandle": "session_1", "normalizedX": 0.25, "normalizedY": 0.75], expected: "control_applied")
        await assertResultType(controller, operation: "set_zoom", requestId: "zoom_1", payload: ["sessionHandle": "session_1", "zoomFactor": 2.0], expected: "control_applied")
        await assertResultType(controller, operation: "take_photo", requestId: "photo_1_request", payload: sessionPayload("session_1"), expected: "media_preview")
        await assertResultType(controller, operation: "retake", requestId: "retake_1", payload: mediaPayload("photo_1"), expected: "retake_ready")
        await assertResultType(controller, operation: "take_photo", requestId: "photo_2_request", payload: sessionPayload("session_1"), expected: "media_preview")
        await assertResultType(controller, operation: "confirm", requestId: "confirm_1", payload: mediaPayload("photo_2"), expected: "confirmed_media")
        await assertResultType(controller, operation: "read_media_thumbnail", requestId: "thumbnail_1", payload: ["mediaHandle": "photo_2", "maxPixelEdge": 64], expected: "media_thumbnail")
        await assertResultType(controller, operation: "release_media", requestId: "release_1", payload: mediaPayload("photo_2"), expected: "media_released")

        await assertResultType(controller, operation: "start_session", requestId: "start_2", payload: startPayload(), expected: "session_created")
        await assertResultType(controller, operation: "start_recording", requestId: "record_1", payload: sessionPayload("session_2"), expected: "recording_started")
        await assertResultType(controller, operation: "stop_recording", requestId: "stop_1", payload: sessionPayload("session_2"), expected: "media_preview")
        await assertResultType(controller, operation: "cancel", requestId: "cancel_1", payload: sessionPayload("session_2"), expected: "session_cancelled")

        let snapshot = await core.snapshot()
        XCTAssertEqual(
            Set(snapshot.operations),
            [
                "start_session", "switch_camera", "set_flash_mode", "set_focus_point", "set_zoom",
                "take_photo", "retake", "confirm", "read_media_thumbnail", "release_media",
                "start_recording", "stop_recording", "cancel",
            ]
        )
    }

    func testListenerGenerationRejectsConcurrentListenerAndEndsOnDetach() async throws {
        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        let controller = makeController(core: core, owner: owner)
        _ = await invoke(controller, operation: "start_session", requestId: "start_listener", payload: startPayload())

        let first = EventSinkProbe()
        controller.onListen(arguments: ["wireVersion": 3], sink: first)
        let duplicate = EventSinkProbe()
        controller.onListen(arguments: ["wireVersion": 3], sink: duplicate)
        XCTAssertEqual(duplicate.failures.first?.code, "listener_already_active")

        let session = try SessionHandle(rawValue: "session_1")
        await core.emit(
            .sessionReady(
                SessionReadySnapshot(
                    sessionHandle: session,
                    activeCamera: .rear,
                    availableCameras: [.rear],
                    switchCameraSupported: false,
                    supportedFlashModes: [.off],
                    focusPointSupported: true,
                    minimumZoomFactor: 1,
                    maximumZoomFactor: 3
                )
            )
        )
        let firstDelivered = await waitUntil { first.values.count == 1 }
        XCTAssertTrue(firstDelivered)

        controller.onCancel()
        let second = EventSinkProbe()
        controller.onListen(arguments: ["wireVersion": 3], sink: second)
        await core.emit(.sessionFailed(sessionHandle: session, failure: MediaCaptureFailure(.permissionDenied)))
        let secondDelivered = await waitUntil { second.values.count == 1 }
        XCTAssertTrue(secondDelivered)
        XCTAssertEqual(first.values.count, 1)

        controller.detachEngine()
        let streamEnded = await waitUntil { second.endCount == 1 }
        XCTAssertTrue(streamEnded)
        let detachedSnapshot = await core.snapshot()
        XCTAssertTrue(detachedSnapshot.closed)
    }

    func testUnsupportedStartupIsDirectFailure() async {
        let core = FakeMediaCaptureCore()
        await core.configureNextStartupFailure(MediaCaptureFailure(.unsupportedCapability))
        let owner = PresentationOwnerBox()
        let controller = makeController(core: core, owner: owner)
        let sink = EventSinkProbe()
        controller.onListen(arguments: ["wireVersion": 3], sink: sink)

        let outcome = await invoke(
            controller,
            operation: "start_session",
            requestId: "unsupported_start",
            payload: startPayload()
        )

        XCTAssertEqual(failure(outcome)?.code, "unsupported_capability")
        XCTAssertTrue(sink.values.isEmpty)
        XCTAssertTrue(sink.failures.isEmpty)
        let snapshot = await core.snapshot()
        XCTAssertTrue(snapshot.cancelled.contains("session_1"))
    }

    func testSessionTimeoutFollowsSessionCreatedAndKeepsListenerActive() async {
        let core = FakeMediaCaptureCore()
        await core.configureNextStartupFailure(MediaCaptureFailure(.sessionTimeout))
        let owner = PresentationOwnerBox()
        let controller = makeController(core: core, owner: owner)
        let sink = EventSinkProbe()
        controller.onListen(arguments: ["wireVersion": 3], sink: sink)

        let outcome = await invoke(
            controller,
            operation: "start_session",
            requestId: "timeout_start",
            payload: startPayload()
        )
        XCTAssertEqual(resultType(outcome), "session_created")
        let timeoutDelivered = await waitUntil { sink.values.count == 1 }
        XCTAssertTrue(timeoutDelivered)
        XCTAssertEqual(sink.values.first?["failureType"] as? String, "session_timeout")
        XCTAssertTrue(sink.failures.isEmpty)

        controller.onCancel()
        let replacement = EventSinkProbe()
        controller.onListen(arguments: ["wireVersion": 3], sink: replacement)
        XCTAssertTrue(replacement.failures.isEmpty)
    }

    func testPreviewEventAdoptsMediaForConfirm() async throws {
        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        let controller = makeController(core: core, owner: owner)
        _ = await invoke(controller, operation: "start_session", requestId: "event_start", payload: startPayload())
        let sink = EventSinkProbe()
        controller.onListen(arguments: ["wireVersion": 3], sink: sink)
        let metadata = try media(
            handle: "event_photo",
            type: .photo,
            durationMilliseconds: nil
        )
        await core.emit(
            .mediaPreviewReady(
                sessionHandle: try SessionHandle(rawValue: "session_1"),
                metadata: metadata
            )
        )
        let previewDelivered = await waitUntil { sink.values.count == 1 }
        XCTAssertTrue(previewDelivered)

        let confirmed = await invoke(
            controller,
            operation: "confirm",
            requestId: "event_confirm",
            payload: mediaPayload("event_photo")
        )
        XCTAssertEqual(resultType(confirmed), "confirmed_media")
    }

    func testLeaseExpiryAndReadRevocationDeliverDuringPresentation() async {
        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        let controller = makeController(core: core, owner: owner)
        _ = await invoke(controller, operation: "start_session", requestId: "lease_start", payload: startPayload())
        _ = await invoke(controller, operation: "take_photo", requestId: "lease_photo", payload: sessionPayload("session_1"))
        _ = await invoke(controller, operation: "confirm", requestId: "lease_confirm", payload: mediaPayload("photo_1"))
        let sink = EventSinkProbe()
        controller.onListen(arguments: ["wireVersion": 3], sink: sink)
        let flow = CompletionProbe()
        controller.handle(
            operation: "present_capture_flow",
            arguments: requestEnvelope(requestId: "lease_event_flow", payload: startPayload()),
            completion: flow
        )
        let presented = await waitUntil { owner.presenter.sessions.count == 1 }
        XCTAssertTrue(presented)
        let handle = try? MediaHandle(rawValue: "photo_1")
        guard let handle else {
            XCTFail("Expected valid test media handle")
            return
        }

        await core.emit(.mediaLeaseExpired(handle))
        await core.emit(.mediaReadRevoked(handle))
        let delivered = await waitUntil { sink.values.count == 2 }
        XCTAssertTrue(delivered)
        XCTAssertEqual(sink.values[0]["eventType"] as? String, "media_lease_expired")
        XCTAssertEqual(sink.values[1]["eventType"] as? String, "media_read_revoked")

        owner.presenter.sessions[0].resolve(.cancelled)
        _ = await flow.value()
    }

    func testExplicitReleaseKeepsLeaseTrackedUntilReadRevocation() async throws {
        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        let controller = makeController(core: core, owner: owner)

        _ = await invoke(
            controller,
            operation: "start_session",
            requestId: "release_start",
            payload: startPayload()
        )
        _ = await invoke(
            controller,
            operation: "take_photo",
            requestId: "release_photo",
            payload: sessionPayload("session_1")
        )
        _ = await invoke(
            controller,
            operation: "confirm",
            requestId: "release_confirm",
            payload: mediaPayload("photo_1")
        )
        let released = await invoke(
            controller,
            operation: "release_media",
            requestId: "release_media",
            payload: mediaPayload("photo_1")
        )
        XCTAssertEqual(resultType(released), "media_released")

        let sink = EventSinkProbe()
        controller.onListen(arguments: ["wireVersion": 3], sink: sink)
        let handle = try MediaHandle(rawValue: "photo_1")
        await core.emit(.mediaReadRevoked(handle))
        let delivered = await waitUntil { sink.values.count == 1 }
        XCTAssertTrue(delivered)
        XCTAssertEqual(sink.values[0]["eventType"] as? String, "media_read_revoked")

        await core.emit(.mediaReadRevoked(handle))
        await Task.yield()
        XCTAssertEqual(sink.values.count, 1)
    }

    func testDuplicateTombstoneCapacityAndExactOnceCompletion() async {
        let core = FakeMediaCaptureCore()
        await core.configureStartDelay(nanoseconds: 500_000_000, ignoreCancellation: false)
        let owner = PresentationOwnerBox()
        let controller = makeController(core: core, owner: owner)
        var probes: [CompletionProbe] = []

        let first = CompletionProbe()
        probes.append(first)
        controller.handle(
            operation: "start_session",
            arguments: requestEnvelope(requestId: "duplicate_id", payload: startPayload()),
            completion: first
        )
        let duplicate = CompletionProbe()
        controller.handle(
            operation: "start_session",
            arguments: requestEnvelope(requestId: "duplicate_id", payload: startPayload()),
            completion: duplicate
        )
        let duplicateOutcome = await duplicate.value()
        XCTAssertEqual(failure(duplicateOutcome)?.code, "duplicate_request")

        for index in 1 ..< 32 {
            let probe = CompletionProbe()
            probes.append(probe)
            controller.handle(
                operation: "start_session",
                arguments: requestEnvelope(requestId: "capacity_\(index)", payload: startPayload()),
                completion: probe
            )
        }
        let overloaded = CompletionProbe()
        controller.handle(
            operation: "start_session",
            arguments: requestEnvelope(requestId: "capacity_overflow", payload: startPayload()),
            completion: overloaded
        )
        let overloadedOutcome = await overloaded.value()
        XCTAssertEqual(failure(overloadedOutcome)?.code, "bridge_overloaded")
        XCTAssertTrue(overloaded.completedOnMainThread)

        controller.detachEngine()
        _ = await first.value()
        let allCompleted = await waitUntil { probes.allSatisfy { $0.completionCount == 1 } }
        XCTAssertTrue(allCompleted)
    }

    func testCompletedTombstoneCapacityRejectsRequest4097() async {
        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        let controller = makeController(core: core, owner: owner)

        for index in 0 ..< 4_096 {
            let outcome = await invoke(
                controller,
                operation: "dismiss_capture_flow",
                requestId: "tombstone_\(index)",
                payload: ["presentationRequestId": "unknown_flow"]
            )
            if resultType(outcome) != "capture_flow_dismissed" {
                XCTFail("Expected tombstone request \(index) to complete")
                return
            }
        }
        let overflow = await invoke(
            controller,
            operation: "dismiss_capture_flow",
            requestId: "tombstone_overflow",
            payload: ["presentationRequestId": "unknown_flow"]
        )
        XCTAssertEqual(failure(overflow)?.code, "bridge_overloaded")
        XCTAssertEqual(
            failure(overflow)?.details["capacity"],
            "completed_request_tombstones"
        )
    }

    func testPresentationThreeOutcomesConflictAndDismissAreDistinct() async throws {
        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        let controller = makeController(core: core, owner: owner)

        let first = CompletionProbe()
        controller.handle(
            operation: "present_capture_flow",
            arguments: requestEnvelope(requestId: "flow_confirm", payload: startPayload()),
            completion: first
        )
        let firstPresented = await waitUntil { owner.presenter.sessions.count == 1 }
        XCTAssertTrue(firstPresented)
        let conflict = await invoke(
            controller,
            operation: "present_capture_flow",
            requestId: "flow_conflict",
            payload: startPayload()
        )
        XCTAssertEqual(failure(conflict)?.code, "presentation_conflict")
        let confirmed = MediaCaptureConfirmedValue(
            metadata: try media(handle: "flow_media", type: .photo, durationMilliseconds: nil),
            leaseExpiresAt: Date(timeIntervalSince1970: 2_000_000_000)
        )
        owner.presenter.sessions[0].resolve(.confirmed(confirmed))
        let firstOutcome = await first.value()
        XCTAssertEqual(resultType(firstOutcome), "capture_flow_confirmed")
        _ = await invoke(controller, operation: "release_media", requestId: "release_flow", payload: mediaPayload("flow_media"))

        let cancelled = CompletionProbe()
        controller.handle(
            operation: "present_capture_flow",
            arguments: requestEnvelope(requestId: "flow_cancel", payload: startPayload()),
            completion: cancelled
        )
        let secondPresented = await waitUntil { owner.presenter.sessions.count == 2 }
        XCTAssertTrue(secondPresented)
        owner.presenter.sessions[1].resolve(.cancelled)
        let cancelledOutcome = await cancelled.value()
        XCTAssertEqual(resultType(cancelledOutcome), "capture_flow_cancelled")

        let failed = CompletionProbe()
        controller.handle(
            operation: "present_capture_flow",
            arguments: requestEnvelope(requestId: "flow_failure", payload: startPayload()),
            completion: failed
        )
        let thirdPresented = await waitUntil { owner.presenter.sessions.count == 3 }
        XCTAssertTrue(thirdPresented)
        owner.presenter.sessions[2].resolve(.failure(MediaCaptureFailure(.permissionDenied)))
        let failedOutcome = await failed.value()
        XCTAssertEqual(failure(failedOutcome)?.code, "permission_denied")

        let dismissed = CompletionProbe()
        controller.handle(
            operation: "present_capture_flow",
            arguments: requestEnvelope(requestId: "flow_dismiss", payload: startPayload()),
            completion: dismissed
        )
        let fourthPresented = await waitUntil { owner.presenter.sessions.count == 4 }
        XCTAssertTrue(fourthPresented)
        owner.presenter.sessions[3].autoResolveDismiss = false
        let dismissProbe = CompletionProbe()
        controller.handle(
            operation: "dismiss_capture_flow",
            arguments: requestEnvelope(
                requestId: "dismiss_1",
                payload: ["presentationRequestId": "flow_dismiss"]
            ),
            completion: dismissProbe
        )
        let dismissStarted = await waitUntil { owner.presenter.sessions[3].dismissCount == 1 }
        XCTAssertTrue(dismissStarted)
        XCTAssertEqual(dismissed.completionCount, 0)
        XCTAssertEqual(dismissProbe.completionCount, 0)
        owner.presenter.sessions[3].resolve(.cancelled)
        let dismissOutcome = await dismissProbe.value()
        XCTAssertEqual(resultType(dismissOutcome), "capture_flow_dismissed")
        let dismissedOutcome = await dismissed.value()
        XCTAssertEqual(resultType(dismissedOutcome), "capture_flow_cancelled")
        XCTAssertEqual(owner.presenter.sessions[3].dismissCount, 1)
        _ = await invoke(
            controller,
            operation: "dismiss_capture_flow",
            requestId: "dismiss_2",
            payload: ["presentationRequestId": "flow_dismiss"]
        )
        XCTAssertEqual(owner.presenter.sessions[3].dismissCount, 1)
    }

    func testPresentationPreflightsPermissionsBeforeCreatingUi() async {
        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        owner.presenter.preflightFailure = MediaCaptureFailure(.permissionPermanentlyDenied)
        let controller = makeController(core: core, owner: owner)

        let outcome = await invoke(
            controller,
            operation: "present_capture_flow",
            requestId: "preflight_denied",
            payload: startPayload()
        )

        XCTAssertEqual(failure(outcome)?.code, "permission_permanently_denied")
        XCTAssertEqual(owner.presenter.preflightCount, 1)
        XCTAssertTrue(owner.presenter.sessions.isEmpty)
        let snapshot = await core.snapshot()
        XCTAssertFalse(snapshot.operations.contains("start_session"))
    }

    func testPresentationRejectsMissingCameraHardwareBeforeCreatingUi() async {
        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        let permissions = PermissionServiceProbe()
        permissions.setAvailable(false, for: .camera)
        owner.presenter.permissionPreflight = MediaCapturePermissionPreflight(
            service: permissions
        )
        let controller = makeController(core: core, owner: owner)

        let outcome = await invoke(
            controller,
            operation: "present_capture_flow",
            requestId: "camera_unavailable",
            payload: startPayload()
        )

        XCTAssertEqual(failure(outcome)?.code, "unsupported_capability")
        XCTAssertTrue(owner.presenter.sessions.isEmpty)
        XCTAssertTrue(permissions.requestedResources().isEmpty)
    }

    func testMicrophoneHardwareIsConditionalAndCheckedBeforeCreatingUi() async throws {
        let permissions = PermissionServiceProbe()
        permissions.setAvailable(false, for: .microphone)
        let preflight = MediaCapturePermissionPreflight(service: permissions)
        let photoOnly = try SessionOptions(
            enabledMediaTypes: [.photo],
            audioEnabled: true,
            maxVideoDurationMilliseconds: 15_000
        )
        try await preflight.authorize(options: photoOnly)

        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        owner.presenter.permissionPreflight = preflight
        let controller = makeController(core: core, owner: owner)
        let outcome = await invoke(
            controller,
            operation: "present_capture_flow",
            requestId: "microphone_unavailable",
            payload: startPayload()
        )

        XCTAssertEqual(failure(outcome)?.code, "unsupported_capability")
        XCTAssertTrue(owner.presenter.sessions.isEmpty)
        XCTAssertTrue(permissions.requestedResources().isEmpty)
    }

    func testDismissBeforePresentationTaskStartsDoesNotCreateUi() async {
        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        let controller = makeController(core: core, owner: owner)
        let presentation = CompletionProbe()
        let dismissal = CompletionProbe()

        controller.handle(
            operation: "present_capture_flow",
            arguments: requestEnvelope(requestId: "prestart_flow", payload: startPayload()),
            completion: presentation
        )
        controller.handle(
            operation: "dismiss_capture_flow",
            arguments: requestEnvelope(
                requestId: "prestart_dismiss",
                payload: ["presentationRequestId": "prestart_flow"]
            ),
            completion: dismissal
        )

        let presentationOutcome = await presentation.value()
        let dismissalOutcome = await dismissal.value()
        XCTAssertEqual(resultType(presentationOutcome), "capture_flow_cancelled")
        XCTAssertEqual(resultType(dismissalOutcome), "capture_flow_dismissed")
        XCTAssertTrue(owner.presenter.sessions.isEmpty)
    }

    func testDismissWinsAgainstConfirmedOutcomeAndReleasesMedia() async throws {
        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        let controller = makeController(core: core, owner: owner)
        let presentation = CompletionProbe()
        controller.handle(
            operation: "present_capture_flow",
            arguments: requestEnvelope(requestId: "confirm_dismiss_flow", payload: startPayload()),
            completion: presentation
        )
        let presented = await waitUntil { owner.presenter.sessions.count == 1 }
        XCTAssertTrue(presented)
        let confirmed = MediaCaptureConfirmedValue(
            metadata: try media(
                handle: "dismissed_media",
                type: .photo,
                durationMilliseconds: nil
            ),
            leaseExpiresAt: Date(timeIntervalSince1970: 2_000_000_000)
        )
        owner.presenter.sessions[0].resolve(.confirmed(confirmed))
        let dismissal = CompletionProbe()
        controller.handle(
            operation: "dismiss_capture_flow",
            arguments: requestEnvelope(
                requestId: "confirm_dismiss_request",
                payload: ["presentationRequestId": "confirm_dismiss_flow"]
            ),
            completion: dismissal
        )

        let presentationOutcome = await presentation.value()
        let dismissalOutcome = await dismissal.value()
        let snapshot = await core.snapshot()
        XCTAssertEqual(resultType(presentationOutcome), "capture_flow_cancelled")
        XCTAssertEqual(resultType(dismissalOutcome), "capture_flow_dismissed")
        XCTAssertTrue(snapshot.released.contains("dismissed_media"))
    }

    func testOwnerCleanupBlocksNewPresentationUntilLateConfirmedMediaIsReleased() async throws {
        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        let controller = makeController(core: core, owner: owner)
        let presentation = CompletionProbe()
        controller.handle(
            operation: "present_capture_flow",
            arguments: requestEnvelope(requestId: "owner_late_flow", payload: startPayload()),
            completion: presentation
        )
        let presented = await waitUntil { owner.presenter.sessions.count == 1 }
        XCTAssertTrue(presented)
        owner.presenter.sessions[0].autoResolveDismiss = false
        controller.ownerDestroyed(owner.identity)
        let dismissStarted = await waitUntil { owner.presenter.sessions[0].dismissCount == 1 }
        XCTAssertTrue(dismissStarted)

        let conflict = await invoke(
            controller,
            operation: "present_capture_flow",
            requestId: "owner_cleanup_conflict",
            payload: startPayload()
        )
        XCTAssertEqual(failure(conflict)?.code, "presentation_conflict")
        let confirmed = MediaCaptureConfirmedValue(
            metadata: try media(
                handle: "owner_late_media",
                type: .photo,
                durationMilliseconds: nil
            ),
            leaseExpiresAt: Date(timeIntervalSince1970: 2_000_000_000)
        )
        owner.presenter.sessions[0].resolve(.confirmed(confirmed))

        let presentationOutcome = await presentation.value()
        XCTAssertEqual(
            failure(presentationOutcome)?.details["lifecycleReason"],
            "view_controller_destroyed"
        )
        let released = await waitUntil {
            (await core.snapshot()).released.contains("owner_late_media")
        }
        XCTAssertTrue(released)
    }

    func testOwnerBoundaryPrecedesLateCleanupAndEngineDetachReleasesLease() async throws {
        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        let controller = makeController(core: core, owner: owner)
        _ = await invoke(controller, operation: "start_session", requestId: "owned_session", payload: startPayload())
        _ = await invoke(controller, operation: "take_photo", requestId: "owned_photo", payload: sessionPayload("session_1"))
        _ = await invoke(controller, operation: "confirm", requestId: "owned_confirm", payload: mediaPayload("photo_1"))

        await core.configureStartDelay(nanoseconds: 5_000_000, ignoreCancellation: true)
        let late = CompletionProbe()
        controller.handle(
            operation: "start_session",
            arguments: requestEnvelope(requestId: "late_start", payload: startPayload()),
            completion: late
        )
        await Task.yield()
        owner.presentationAvailable = false
        owner.alive = false
        controller.ownerDestroyed(owner.identity)
        let boundaryFailure = failure(await late.value())
        XCTAssertEqual(boundaryFailure?.details["lifecycleReason"], "view_controller_destroyed")
        let lateCleaned = await waitUntil {
            let snapshot = await core.snapshot()
            return snapshot.cancelled.contains("session_2")
        }
        XCTAssertTrue(lateCleaned)
        let ownerDestroyedSnapshot = await core.snapshot()
        XCTAssertFalse(ownerDestroyedSnapshot.released.contains("photo_1"))

        controller.detachEngine()
        let engineCleaned = await waitUntil {
            let snapshot = await core.snapshot()
            return snapshot.released.contains("photo_1") && snapshot.closed
        }
        XCTAssertTrue(engineCleaned)
    }

    func testOwnerLivenessLossWithoutSceneDisconnectCompletesAndCleansLateSession() async {
        let core = FakeMediaCaptureCore()
        await core.configureStartDelay(nanoseconds: 5_000_000, ignoreCancellation: false)
        let owner = PresentationOwnerBox()
        let controller = makeController(core: core, owner: owner)
        let pending = CompletionProbe()
        controller.handle(
            operation: "start_session",
            arguments: requestEnvelope(requestId: "owner_lost_start", payload: startPayload()),
            completion: pending
        )
        owner.alive = false

        let outcome = await pending.value()
        XCTAssertEqual(failure(outcome)?.details["lifecycleReason"], "view_controller_destroyed")
        XCTAssertEqual(pending.completionCount, 1)
        let cleaned = await waitUntil {
            (await core.snapshot()).cancelled.contains("session_1")
        }
        XCTAssertTrue(cleaned)
    }

    func testOwnerLivenessBoundaryWaitsForAllConcurrentLateCleanup() async {
        let core = FakeMediaCaptureCore()
        await core.configureStartDelay(nanoseconds: 5_000_000, ignoreCancellation: true)
        let owner = PresentationOwnerBox()
        let controller = makeController(core: core, owner: owner)
        let first = CompletionProbe()
        let second = CompletionProbe()
        controller.handle(
            operation: "start_session",
            arguments: requestEnvelope(requestId: "owner_concurrent_1", payload: startPayload()),
            completion: first
        )
        controller.handle(
            operation: "start_session",
            arguments: requestEnvelope(requestId: "owner_concurrent_2", payload: startPayload()),
            completion: second
        )
        let bothStarted = await waitUntil {
            (await core.snapshot()).operations.filter { $0 == "start_session" }.count == 2
        }
        XCTAssertTrue(bothStarted)
        owner.alive = false

        let firstOutcome = await first.value()
        XCTAssertEqual(failure(firstOutcome)?.details["lifecycleReason"], "view_controller_destroyed")
        let snapshotAtCallback = await core.snapshot()
        XCTAssertEqual(Set(snapshotAtCallback.cancelled), ["session_1", "session_2"])
        let secondOutcome = await second.value()
        XCTAssertEqual(failure(secondOutcome)?.details["lifecycleReason"], "view_controller_destroyed")
        XCTAssertEqual(first.completionCount, 1)
        XCTAssertEqual(second.completionCount, 1)
    }

    func testOwnerLivenessLossOverridesNativeFailureAndCleansExistingSession() async {
        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        let controller = makeController(core: core, owner: owner)
        _ = await invoke(
            controller,
            operation: "start_session",
            requestId: "existing_owner_session",
            payload: startPayload()
        )
        await core.configureStartDelay(nanoseconds: 5_000_000, ignoreCancellation: false)
        await core.configureNextStartError(MediaCaptureFailure(.invalidState))
        let pending = CompletionProbe()
        controller.handle(
            operation: "start_session",
            arguments: requestEnvelope(requestId: "owner_lost_failure", payload: startPayload()),
            completion: pending
        )
        owner.alive = false

        let outcome = await pending.value()
        XCTAssertEqual(failure(outcome)?.code, "bridge_unavailable")
        XCTAssertEqual(failure(outcome)?.details["lifecycleReason"], "view_controller_destroyed")
        XCTAssertEqual(pending.completionCount, 1)
        let cleaned = await waitUntil {
            (await core.snapshot()).cancelled.contains("session_1")
        }
        XCTAssertTrue(cleaned)
    }

    func testIdleOwnerMonitorCleansAdoptedSessionAfterHierarchyLoss() async {
        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        let controller = makeController(
            core: core,
            owner: owner,
            ownerPollNanoseconds: 1_000_000
        )
        let created = await invoke(
            controller,
            operation: "start_session",
            requestId: "idle_owner_start",
            payload: startPayload()
        )
        XCTAssertEqual(resultType(created), "session_created")

        owner.alive = false

        let cleaned = await waitUntil {
            (await core.snapshot()).cancelled.contains("session_1")
        }
        XCTAssertTrue(cleaned)
    }

    func testPreviewThumbnailOwnerLossOverridesSuccessAndClearsBytes() async {
        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        let controller = makeController(
            core: core,
            owner: owner,
            ownerPollNanoseconds: 1_000_000_000
        )
        _ = await invoke(controller, operation: "start_session", requestId: "thumb_owner_start", payload: startPayload())
        _ = await invoke(controller, operation: "take_photo", requestId: "thumb_owner_photo", payload: sessionPayload("session_1"))
        await core.configureThumbnailDelay(nanoseconds: 5_000_000, ignoreCancellation: true)
        let thumbnail = CompletionProbe()
        controller.handle(
            operation: "read_media_thumbnail",
            arguments: requestEnvelope(
                requestId: "thumb_owner_read",
                payload: ["mediaHandle": "photo_1", "maxPixelEdge": 64]
            ),
            completion: thumbnail
        )
        let started = await waitUntil {
            (await core.snapshot()).operations.contains("read_media_thumbnail")
        }
        XCTAssertTrue(started)
        owner.alive = false

        let outcome = await thumbnail.value()
        XCTAssertEqual(failure(outcome)?.details["lifecycleReason"], "view_controller_destroyed")
        let cleaned = await waitUntil {
            let cleared = await core.lastThumbnailIsCleared()
            let snapshot = await core.snapshot()
            return cleared && snapshot.cancelled.contains("session_1")
        }
        XCTAssertTrue(cleaned)
    }

    func testPreviewThumbnailOwnerLossOverridesEncodingFailure() async throws {
        let core = FakeMediaCaptureCore()
        await core.setThumbnail(
            MediaCaptureThumbnailValue(
                mediaHandle: try MediaHandle(rawValue: "ignored"),
                data: Data([0x00]),
                pixelWidth: 2,
                pixelHeight: 2,
                mediaType: .photo,
                posterFrameMilliseconds: nil,
                contentType: "image/jpeg",
                orientationDegrees: 0
            )
        )
        let owner = PresentationOwnerBox()
        let controller = makeController(
            core: core,
            owner: owner,
            ownerPollNanoseconds: 1_000_000_000
        )
        _ = await invoke(controller, operation: "start_session", requestId: "thumb_failure_start", payload: startPayload())
        _ = await invoke(controller, operation: "take_photo", requestId: "thumb_failure_photo", payload: sessionPayload("session_1"))
        await core.configureThumbnailDelay(nanoseconds: 5_000_000, ignoreCancellation: true)
        let thumbnail = CompletionProbe()
        controller.handle(
            operation: "read_media_thumbnail",
            arguments: requestEnvelope(
                requestId: "thumb_failure_read",
                payload: ["mediaHandle": "photo_1", "maxPixelEdge": 64]
            ),
            completion: thumbnail
        )
        let started = await waitUntil {
            (await core.snapshot()).operations.contains("read_media_thumbnail")
        }
        XCTAssertTrue(started)
        owner.alive = false

        let outcome = await thumbnail.value()
        XCTAssertEqual(failure(outcome)?.details["lifecycleReason"], "view_controller_destroyed")
        let cleaned = await waitUntil {
            (await core.snapshot()).cancelled.contains("session_1")
        }
        XCTAssertTrue(cleaned)
    }

    func testPreviewReleaseOwnerLossUsesOwnerBoundary() async {
        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        let controller = makeController(
            core: core,
            owner: owner,
            ownerPollNanoseconds: 1_000_000_000
        )
        _ = await invoke(controller, operation: "start_session", requestId: "release_owner_start", payload: startPayload())
        _ = await invoke(controller, operation: "take_photo", requestId: "release_owner_photo", payload: sessionPayload("session_1"))
        await core.configureReleaseDelay(nanoseconds: 5_000_000, ignoreCancellation: true)
        let release = CompletionProbe()
        controller.handle(
            operation: "release_media",
            arguments: requestEnvelope(
                requestId: "release_owner_request",
                payload: mediaPayload("photo_1")
            ),
            completion: release
        )
        let started = await waitUntil {
            (await core.snapshot()).operations.contains("release_media")
        }
        XCTAssertTrue(started)
        owner.alive = false

        let outcome = await release.value()
        XCTAssertEqual(failure(outcome)?.details["lifecycleReason"], "view_controller_destroyed")
        let cleaned = await waitUntil {
            (await core.snapshot()).cancelled.contains("session_1")
        }
        XCTAssertTrue(cleaned)
    }

    func testBackgroundedSceneKeepsPendingRequestAndSessionAlive() async {
        let core = FakeMediaCaptureCore()
        await core.configureStartDelay(nanoseconds: 20_000_000, ignoreCancellation: false)
        let owner = PresentationOwnerBox()
        let controller = makeController(core: core, owner: owner)
        let pending = CompletionProbe()
        controller.handle(
            operation: "start_session",
            arguments: requestEnvelope(requestId: "background_start", payload: startPayload()),
            completion: pending
        )
        await Task.yield()
        owner.presentationAvailable = false

        let outcome = await pending.value()
        XCTAssertEqual(resultType(outcome), "session_created")
        let snapshot = await core.snapshot()
        XCTAssertTrue(snapshot.cancelled.isEmpty)
    }

    func testEngineDetachReleasesLateConfirmedLeaseBeforeClosingCore() async {
        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        let controller = makeController(core: core, owner: owner)
        _ = await invoke(controller, operation: "start_session", requestId: "late_lease_start", payload: startPayload())
        _ = await invoke(controller, operation: "take_photo", requestId: "late_lease_photo", payload: sessionPayload("session_1"))
        await core.configureConfirmDelay(nanoseconds: 20_000_000, ignoreCancellation: true)
        let confirm = CompletionProbe()
        controller.handle(
            operation: "confirm",
            arguments: requestEnvelope(
                requestId: "late_lease_confirm",
                payload: mediaPayload("photo_1")
            ),
            completion: confirm
        )
        await Task.yield()

        controller.detachEngine()
        let outcome = await confirm.value()
        XCTAssertEqual(failure(outcome)?.details["lifecycleReason"], "engine_detached")
        let drained = await waitUntil { (await core.snapshot()).closed }
        XCTAssertTrue(drained)
        let snapshot = await core.snapshot()
        let operations = snapshot.operations
        let releaseIndex = operations.lastIndex(of: "release_media")
        let closeIndex = operations.lastIndex(of: "close")
        XCTAssertNotNil(releaseIndex)
        XCTAssertNotNil(closeIndex)
        if let releaseIndex, let closeIndex {
            XCTAssertLessThan(releaseIndex, closeIndex)
        }
    }

    func testEngineDetachClearsLateThumbnailCopy() async {
        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        let controller = makeController(core: core, owner: owner)
        _ = await invoke(controller, operation: "start_session", requestId: "late_thumb_start", payload: startPayload())
        _ = await invoke(controller, operation: "take_photo", requestId: "late_thumb_photo", payload: sessionPayload("session_1"))
        _ = await invoke(controller, operation: "confirm", requestId: "late_thumb_confirm", payload: mediaPayload("photo_1"))
        await core.configureThumbnailDelay(nanoseconds: 20_000_000, ignoreCancellation: true)
        let thumbnail = CompletionProbe()
        controller.handle(
            operation: "read_media_thumbnail",
            arguments: requestEnvelope(
                requestId: "late_thumbnail",
                payload: ["mediaHandle": "photo_1", "maxPixelEdge": 64]
            ),
            completion: thumbnail
        )
        await Task.yield()

        controller.detachEngine()
        let outcome = await thumbnail.value()
        XCTAssertEqual(failure(outcome)?.details["lifecycleReason"], "engine_detached")
        let thumbnailCleared = await core.lastThumbnailIsCleared()
        XCTAssertTrue(thumbnailCleared)
    }

    func testDetachAndOwnerDestroyCompleteWhenOperationIgnoresCancellation() async {
        let detachCore = FakeMediaCaptureCore()
        await detachCore.configureNeverCompleteStart(true)
        let detachOwner = PresentationOwnerBox()
        let detachController = makeController(
            core: detachCore,
            owner: detachOwner,
            drainTimeoutNanoseconds: 1_000_000
        )
        let detached = CompletionProbe()
        detachController.handle(
            operation: "start_session",
            arguments: requestEnvelope(requestId: "never_detach", payload: startPayload()),
            completion: detached
        )
        let detachStarted = await waitUntil {
            (await detachCore.snapshot()).operations.contains("start_session")
        }
        XCTAssertTrue(detachStarted)
        detachController.detachEngine()
        let detachOutcome = await detached.value()
        XCTAssertEqual(
            failure(detachOutcome)?.details["lifecycleReason"],
            "engine_detached"
        )
        let closed = await waitUntil { (await detachCore.snapshot()).closed }
        XCTAssertTrue(closed)
        await detachCore.unblockNeverCompleteStart()

        let ownerCore = FakeMediaCaptureCore()
        await ownerCore.configureNeverCompleteStart(true)
        let owner = PresentationOwnerBox()
        let ownerController = makeController(
            core: ownerCore,
            owner: owner,
            drainTimeoutNanoseconds: 1_000_000
        )
        let destroyed = CompletionProbe()
        ownerController.handle(
            operation: "start_session",
            arguments: requestEnvelope(requestId: "never_owner", payload: startPayload()),
            completion: destroyed
        )
        let ownerStarted = await waitUntil {
            (await ownerCore.snapshot()).operations.contains("start_session")
        }
        XCTAssertTrue(ownerStarted)
        ownerController.ownerDestroyed(owner.identity)
        let ownerOutcome = await destroyed.value()
        XCTAssertEqual(
            failure(ownerOutcome)?.details["lifecycleReason"],
            "view_controller_destroyed"
        )
        let blocked = await invoke(
            ownerController,
            operation: "present_capture_flow",
            requestId: "blocked_during_retained_cleanup",
            payload: startPayload()
        )
        XCTAssertEqual(failure(blocked)?.code, "presentation_conflict")
        await ownerCore.unblockNeverCompleteStart()
    }

    func testDetachReleasesControllerWhileNativeStartRemainsSuspended() async {
        let core = FakeMediaCaptureCore()
        await core.configureNeverCompleteStart(true)
        let owner = PresentationOwnerBox()
        var controller: MediaCaptureBridgeController? = makeController(
            core: core,
            owner: owner,
            drainTimeoutNanoseconds: 1_000_000
        )
        let weakController = WeakReference(controller)
        let completion = CompletionProbe()
        controller?.handle(
            operation: "start_session",
            arguments: requestEnvelope(requestId: "deinit_detach", payload: startPayload()),
            completion: completion
        )
        let started = await waitUntil {
            (await core.snapshot()).operations.contains("start_session")
        }
        XCTAssertTrue(started)
        controller?.detachEngine()
        let outcome = await completion.value()
        XCTAssertEqual(
            failure(outcome)?.details["lifecycleReason"],
            "engine_detached"
        )
        controller = nil

        let released = await waitUntil { weakController.value == nil }
        XCTAssertTrue(released)
        await core.unblockNeverCompleteStart()
    }

    func testOwnerBoundaryReleasesControllerWhenPresentationAwaitNeverSettles() async {
        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        var controller: MediaCaptureBridgeController? = makeController(
            core: core,
            owner: owner,
            drainTimeoutNanoseconds: 1_000_000
        )
        let weakController = WeakReference(controller)
        let presentation = CompletionProbe()
        controller?.handle(
            operation: "present_capture_flow",
            arguments: requestEnvelope(
                requestId: "blocked_presentation_boundary",
                payload: startPayload()
            ),
            completion: presentation
        )
        let presented = await waitUntil { owner.presenter.sessions.count == 1 }
        XCTAssertTrue(presented)
        owner.presenter.sessions[0].autoResolveDismiss = false

        controller?.ownerDestroyed(owner.identity)

        let outcome = await presentation.value()
        XCTAssertEqual(
            failure(outcome)?.details["lifecycleReason"],
            "view_controller_destroyed"
        )
        controller = nil
        let released = await waitUntil { weakController.value == nil }
        XCTAssertTrue(released)
        owner.presenter.sessions[0].resolve(.cancelled)
    }

    func testOwnerBoundaryKeepsPresentationPoisonedUntilBlockedCancelSettles() async {
        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        let controller = makeController(
            core: core,
            owner: owner,
            drainTimeoutNanoseconds: 1_000_000
        )
        _ = await invoke(
            controller,
            operation: "start_session",
            requestId: "blocked_owner_cancel_start",
            payload: startPayload()
        )
        await core.configureNeverCompleteCleanup(cancel: true)

        controller.ownerDestroyed(owner.identity)

        let cancelStarted = await waitUntil {
            (await core.snapshot()).operations.contains("cancel")
        }
        XCTAssertTrue(cancelStarted)
        let blocked = await invoke(
            controller,
            operation: "present_capture_flow",
            requestId: "blocked_owner_cancel_conflict",
            payload: startPayload()
        )
        XCTAssertEqual(failure(blocked)?.code, "presentation_conflict")

        await core.unblockCleanup()
        let cleaned = await waitUntil {
            (await core.snapshot()).cancelled.contains("session_1")
        }
        XCTAssertTrue(cleaned)
        var next: CompletionProbe?
        for attempt in 0 ..< 200 {
            let candidate = CompletionProbe()
            controller.handle(
                operation: "present_capture_flow",
                arguments: requestEnvelope(
                    requestId: "blocked_owner_cancel_recovered_\(attempt)",
                    payload: startPayload()
                ),
                completion: candidate
            )
            if candidate.completionCount == 0 {
                next = candidate
                break
            }
            let candidateOutcome = await candidate.value()
            XCTAssertEqual(failure(candidateOutcome)?.code, "presentation_conflict")
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        guard let next else {
            return XCTFail("Expected owner cleanup to reopen presentation")
        }
        let presented = await waitUntil { owner.presenter.sessions.count == 1 }
        guard presented else {
            return XCTFail("Expected presentation after owner cleanup settled")
        }
        owner.presenter.sessions[0].resolve(.cancelled)
        let nextOutcome = await next.value()
        XCTAssertEqual(resultType(nextOutcome), "capture_flow_cancelled")
    }

    func testEngineDetachIsBoundedWhenCancelReleaseAndCloseNeverSettle() async {
        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        var controller: MediaCaptureBridgeController? = makeController(
            core: core,
            owner: owner,
            drainTimeoutNanoseconds: 1_000_000
        )
        do {
            guard let setupController = controller else {
                XCTFail("Expected controller")
                return
            }
            _ = await invoke(setupController, operation: "start_session", requestId: "blocked_cleanup_lease_start", payload: startPayload())
            _ = await invoke(setupController, operation: "take_photo", requestId: "blocked_cleanup_photo", payload: sessionPayload("session_1"))
            _ = await invoke(setupController, operation: "confirm", requestId: "blocked_cleanup_confirm", payload: mediaPayload("photo_1"))
            _ = await invoke(setupController, operation: "start_session", requestId: "blocked_cleanup_active", payload: startPayload())
        }
        let sink = EventSinkProbe()
        controller?.onListen(arguments: ["wireVersion": 3], sink: sink)
        await core.configureNeverCompleteCleanup(cancel: true, release: true, close: true)
        let weakController = WeakReference(controller)

        controller?.detachEngine()

        let ended = await waitUntil { sink.endCount == 1 }
        XCTAssertTrue(ended)
        let allCleanupStarted = await waitUntil {
            let operations = await core.snapshot().operations
            return operations.contains("cancel") &&
                operations.contains("release_media") &&
                operations.contains("close")
        }
        XCTAssertTrue(allCleanupStarted)
        controller = nil
        let released = await waitUntil { weakController.value == nil }
        XCTAssertTrue(released)
        await core.unblockCleanup()
    }

    func testTombstonesExpireUsingMonotonicClock() async {
        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        let clock = MonotonicClockProbe(1_000)
        let controller = makeController(
            core: core,
            owner: owner,
            monotonicMilliseconds: { clock.now() }
        )
        let first = await invoke(
            controller,
            operation: "start_session",
            requestId: "monotonic_request",
            payload: startPayload()
        )
        XCTAssertEqual(resultType(first), "session_created")
        let duplicate = await invoke(
            controller,
            operation: "start_session",
            requestId: "monotonic_request",
            payload: startPayload()
        )
        XCTAssertEqual(failure(duplicate)?.code, "duplicate_request")

        clock.advance(by: 300_001)
        let afterExpiry = await invoke(
            controller,
            operation: "start_session",
            requestId: "monotonic_request",
            payload: startPayload()
        )
        XCTAssertEqual(resultType(afterExpiry), "session_created")
    }

    func testResourceIsAdoptedBeforeSuccessCallbackCanIssueNestedRead() async {
        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        let controller = makeController(core: core, owner: owner)
        _ = await invoke(controller, operation: "start_session", requestId: "adopt_start", payload: startPayload())
        _ = await invoke(controller, operation: "take_photo", requestId: "adopt_photo", payload: sessionPayload("session_1"))

        let nested = CompletionProbe()
        let outer = CompletionProbe { _ in
            controller.handle(
                operation: "read_media_thumbnail",
                arguments: requestEnvelope(
                    requestId: "nested_thumbnail",
                    payload: ["mediaHandle": "photo_1", "maxPixelEdge": 64]
                ),
                completion: nested
            )
        }
        controller.handle(
            operation: "confirm",
            arguments: requestEnvelope(requestId: "adopt_confirm", payload: mediaPayload("photo_1")),
            completion: outer
        )
        let outerOutcome = await outer.value()
        let nestedOutcome = await nested.value()
        XCTAssertEqual(resultType(outerOutcome), "confirmed_media")
        XCTAssertEqual(resultType(nestedOutcome), "media_thumbnail")
        XCTAssertEqual(outer.completionCount, 1)
        XCTAssertEqual(nested.completionCount, 1)
    }

    func testMaterializeCommitsPrivateFileAndReleaseKeepsSourceLeaseIndependent() async throws {
        let cache = try temporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }
        let store = MediaCaptureTransferStore(cacheDirectory: cache)
        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        let controller = makeController(
            core: core,
            owner: owner,
            transferStore: store,
            epochMilliseconds: { 1_000 }
        )
        _ = await invoke(controller, operation: "start_session", requestId: "transfer_start", payload: startPayload())
        _ = await invoke(controller, operation: "take_photo", requestId: "transfer_photo", payload: sessionPayload("session_1"))
        _ = await invoke(controller, operation: "confirm", requestId: "transfer_confirm", payload: mediaPayload("photo_1"))

        let materialized = await invoke(
            controller,
            operation: "materialize_media_resource",
            requestId: "transfer_materialize",
            payload: mediaPayload("photo_1")
        )

        XCTAssertEqual(resultType(materialized), "materialized_media_resource")
        guard case let .success(envelope) = materialized,
              let payload = envelope["payload"] as? [String: Any],
              let exportHandle = payload["exportHandle"] as? String,
              let fileURI = payload["fileUri"] as? String,
              let file = URL(string: fileURI)
        else {
            return XCTFail("Expected materialized payload")
        }
        XCTAssertEqual(payload["expiresAt"] as? Int64, 301_000)
        XCTAssertEqual((try Data(contentsOf: file)).count, 4_096)
        let beforeRelease = await core.snapshot()
        XCTAssertFalse(beforeRelease.released.contains("photo_1"))

        let released = await invoke(
            controller,
            operation: "release_materialized_media",
            requestId: "transfer_release",
            payload: ["exportHandle": exportHandle]
        )
        XCTAssertEqual(resultType(released), "materialized_media_released")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let repeated = await invoke(
            controller,
            operation: "release_materialized_media",
            requestId: "transfer_release_again",
            payload: ["exportHandle": exportHandle]
        )
        XCTAssertEqual(resultType(repeated), "materialized_media_released")
        let afterExportRelease = await core.snapshot()
        XCTAssertFalse(afterExportRelease.released.contains("photo_1"))

        let sourceReleased = await invoke(
            controller,
            operation: "release_media",
            requestId: "transfer_source_release",
            payload: mediaPayload("photo_1")
        )
        XCTAssertEqual(resultType(sourceReleased), "media_released")
    }

    func testMaterializeVideoPreservesMediaMetadataAndReleasesPrivateFile() async throws {
        let cache = try temporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }
        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        let controller = makeController(
            core: core,
            owner: owner,
            transferStore: MediaCaptureTransferStore(cacheDirectory: cache)
        )
        _ = await invoke(controller, operation: "start_session", requestId: "video_start", payload: startPayload())
        _ = await invoke(controller, operation: "start_recording", requestId: "video_record", payload: sessionPayload("session_1"))
        _ = await invoke(controller, operation: "stop_recording", requestId: "video_stop", payload: sessionPayload("session_1"))
        _ = await invoke(controller, operation: "confirm", requestId: "video_confirm", payload: mediaPayload("video_1"))

        let materialized = await invoke(
            controller,
            operation: "materialize_media_resource",
            requestId: "video_materialize",
            payload: mediaPayload("video_1")
        )

        XCTAssertEqual(resultType(materialized), "materialized_media_resource")
        guard case let .success(envelope) = materialized,
              let payload = envelope["payload"] as? [String: Any],
              let exportHandle = payload["exportHandle"] as? String,
              let fileURI = payload["fileUri"] as? String,
              let file = URL(string: fileURI)
        else {
            return XCTFail("Expected materialized video payload")
        }
        XCTAssertEqual(payload["mediaType"] as? String, "video")
        XCTAssertEqual(payload["contentType"] as? String, "video/mp4")
        XCTAssertEqual(payload["durationMillis"] as? Int64, 1_200)
        XCTAssertEqual(payload["byteLength"] as? Int64, 4_096)
        XCTAssertEqual(file.pathExtension, "mp4")
        XCTAssertEqual(try Data(contentsOf: file), Data(repeating: 0x56, count: 4_096))

        let released = await invoke(
            controller,
            operation: "release_materialized_media",
            requestId: "video_release",
            payload: ["exportHandle": exportHandle]
        )
        XCTAssertEqual(resultType(released), "materialized_media_released")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let afterExportRelease = await core.snapshot()
        XCTAssertFalse(afterExportRelease.released.contains("video_1"))
    }

    func testTransferCapacityRejectsFifthExportBeforeCallingCore() async throws {
        let cache = try temporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }
        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        let controller = makeController(
            core: core,
            owner: owner,
            transferStore: MediaCaptureTransferStore(cacheDirectory: cache)
        )

        for index in 1 ... 5 {
            _ = await invoke(
                controller,
                operation: "start_session",
                requestId: "capacity_start_\(index)",
                payload: startPayload()
            )
            _ = await invoke(
                controller,
                operation: "take_photo",
                requestId: "capacity_photo_\(index)",
                payload: sessionPayload("session_\(index)")
            )
            _ = await invoke(
                controller,
                operation: "confirm",
                requestId: "capacity_confirm_\(index)",
                payload: mediaPayload("photo_\(index)")
            )
        }
        for index in 1 ... 4 {
            let outcome = await invoke(
                controller,
                operation: "materialize_media_resource",
                requestId: "capacity_materialize_\(index)",
                payload: mediaPayload("photo_\(index)")
            )
            XCTAssertEqual(resultType(outcome), "materialized_media_resource")
        }

        let rejected = await invoke(
            controller,
            operation: "materialize_media_resource",
            requestId: "capacity_materialize_5",
            payload: mediaPayload("photo_5")
        )

        XCTAssertEqual(failure(rejected)?.code, "transfer_store_overloaded")
        XCTAssertEqual(failure(rejected)?.details["capacity"], "active_exports")
        let operations = await core.snapshot().operations
        XCTAssertEqual(operations.filter { $0 == "materialize_media_resource" }.count, 4)
    }

    func testMediaAboveFileLimitUsesCapabilityFailureAfterUnifiedReservation() async throws {
        let cache = try temporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }
        let core = FakeMediaCaptureCore()
        await core.configureCapturedMediaByteLength(MediaCaptureTransferStore.maximumFileBytes + 1)
        let owner = PresentationOwnerBox()
        let controller = makeController(
            core: core,
            owner: owner,
            transferStore: MediaCaptureTransferStore(cacheDirectory: cache)
        )
        _ = await invoke(controller, operation: "start_session", requestId: "too_large_start", payload: startPayload())
        _ = await invoke(controller, operation: "take_photo", requestId: "too_large_photo", payload: sessionPayload("session_1"))
        _ = await invoke(controller, operation: "confirm", requestId: "too_large_confirm", payload: mediaPayload("photo_1"))

        let outcome = await invoke(
            controller,
            operation: "materialize_media_resource",
            requestId: "too_large_materialize",
            payload: mediaPayload("photo_1")
        )

        XCTAssertEqual(failure(outcome)?.code, "media_export_too_large")
        XCTAssertEqual(failure(outcome)?.details["capabilityFailureId"], "media_export_too_large")
        let operations = await core.snapshot().operations
        XCTAssertEqual(operations.filter { $0 == "materialize_media_resource" }.count, 1)
        let exports = cache
            .appendingPathComponent("app_media_capture_bridge", isDirectory: true)
            .appendingPathComponent("exports", isDirectory: true)
        let residue = (try? FileManager.default.contentsOfDirectory(atPath: exports.path)) ?? []
        XCTAssertTrue(residue.isEmpty)
    }

    func testOversizedFifthExportIsRejectedByTransferCapacityBeforeCore() async throws {
        let cache = try temporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }
        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        let controller = makeController(
            core: core,
            owner: owner,
            transferStore: MediaCaptureTransferStore(cacheDirectory: cache)
        )
        for index in 1 ... 4 {
            _ = await invoke(controller, operation: "start_session", requestId: "oversized_start_\(index)", payload: startPayload())
            _ = await invoke(controller, operation: "take_photo", requestId: "oversized_photo_\(index)", payload: sessionPayload("session_\(index)"))
            _ = await invoke(controller, operation: "confirm", requestId: "oversized_confirm_\(index)", payload: mediaPayload("photo_\(index)"))
            let result = await invoke(
                controller,
                operation: "materialize_media_resource",
                requestId: "oversized_materialize_\(index)",
                payload: mediaPayload("photo_\(index)")
            )
            XCTAssertEqual(resultType(result), "materialized_media_resource")
        }
        await core.configureCapturedMediaByteLength(MediaCaptureTransferStore.maximumFileBytes + 1)
        _ = await invoke(controller, operation: "start_session", requestId: "oversized_start_5", payload: startPayload())
        _ = await invoke(controller, operation: "take_photo", requestId: "oversized_photo_5", payload: sessionPayload("session_5"))
        _ = await invoke(controller, operation: "confirm", requestId: "oversized_confirm_5", payload: mediaPayload("photo_5"))

        let rejected = await invoke(
            controller,
            operation: "materialize_media_resource",
            requestId: "oversized_materialize_5",
            payload: mediaPayload("photo_5")
        )

        XCTAssertEqual(failure(rejected)?.code, "transfer_store_overloaded")
        XCTAssertEqual(failure(rejected)?.details["capacity"], "active_exports")
        let operations = await core.snapshot().operations
        XCTAssertEqual(operations.filter { $0 == "materialize_media_resource" }.count, 4)
    }

    func testSinkWriteFailureIsMappedAndReleasesTransferCapacity() async throws {
        let cache = try temporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }
        let writer = TransferWritePermissionProbe()
        let store = MediaCaptureTransferStore(
            cacheDirectory: cache,
            writePermission: { writer.permit() }
        )
        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        let controller = makeController(core: core, owner: owner, transferStore: store)
        _ = await invoke(controller, operation: "start_session", requestId: "write_start", payload: startPayload())
        _ = await invoke(controller, operation: "take_photo", requestId: "write_photo", payload: sessionPayload("session_1"))
        _ = await invoke(controller, operation: "confirm", requestId: "write_confirm", payload: mediaPayload("photo_1"))
        writer.rejectNextWrite()

        let failed = await invoke(
            controller,
            operation: "materialize_media_resource",
            requestId: "write_materialize_failed",
            payload: mediaPayload("photo_1")
        )

        XCTAssertEqual(failure(failed)?.code, "media_export_write_failed")
        let exports = cache
            .appendingPathComponent("app_media_capture_bridge", isDirectory: true)
            .appendingPathComponent("exports", isDirectory: true)
        XCTAssertTrue((try FileManager.default.contentsOfDirectory(atPath: exports.path)).isEmpty)
        let retry = await invoke(
            controller,
            operation: "materialize_media_resource",
            requestId: "write_materialize_retry",
            payload: mediaPayload("photo_1")
        )
        XCTAssertEqual(resultType(retry), "materialized_media_resource")
        let sourceStillLeased = await invoke(
            controller,
            operation: "read_media_thumbnail",
            requestId: "write_thumbnail",
            payload: ["mediaHandle": "photo_1", "maxPixelEdge": 64]
        )
        XCTAssertEqual(resultType(sourceStillLeased), "media_thumbnail")
    }

    func testTransferTTLDeadlineStartsBeforeBlockingFlutterCompletion() async throws {
        let cache = try temporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }
        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        let controller = makeController(
            core: core,
            owner: owner,
            transferStore: MediaCaptureTransferStore(cacheDirectory: cache),
            transferTTLNanoseconds: 300_000_000
        )
        _ = await invoke(controller, operation: "start_session", requestId: "deadline_start", payload: startPayload())
        _ = await invoke(controller, operation: "take_photo", requestId: "deadline_photo", payload: sessionPayload("session_1"))
        _ = await invoke(controller, operation: "confirm", requestId: "deadline_confirm", payload: mediaPayload("photo_1"))
        let callbackGate = DispatchSemaphore(value: 0)
        let completion = CompletionProbe { _ in callbackGate.wait() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) {
            callbackGate.signal()
        }

        controller.handle(
            operation: "materialize_media_resource",
            arguments: requestEnvelope(
                requestId: "deadline_materialize",
                payload: mediaPayload("photo_1")
            ),
            completion: completion
        )
        let outcome = await completion.value()
        guard case let .success(envelope) = outcome,
              let payload = envelope["payload"] as? [String: Any],
              let fileURI = payload["fileUri"] as? String,
              let file = URL(string: fileURI)
        else {
            return XCTFail("Expected materialized payload")
        }
        let deletedBeforeANewTTLWindow = await waitUntil(iterations: 150) {
            !FileManager.default.fileExists(atPath: file.path)
        }

        XCTAssertTrue(completion.completedOnMainThread)
        XCTAssertTrue(deletedBeforeANewTTLWindow)
    }

    func testTransferTTLDeletesFileAndInvalidatesHandle() async throws {
        let cache = try temporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }
        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        let controller = makeController(
            core: core,
            owner: owner,
            transferStore: MediaCaptureTransferStore(cacheDirectory: cache),
            transferTTLNanoseconds: 2_000_000
        )
        _ = await invoke(controller, operation: "start_session", requestId: "ttl_start", payload: startPayload())
        _ = await invoke(controller, operation: "take_photo", requestId: "ttl_photo", payload: sessionPayload("session_1"))
        _ = await invoke(controller, operation: "confirm", requestId: "ttl_confirm", payload: mediaPayload("photo_1"))
        let materialized = await invoke(
            controller,
            operation: "materialize_media_resource",
            requestId: "ttl_materialize",
            payload: mediaPayload("photo_1")
        )
        guard case let .success(envelope) = materialized,
              let payload = envelope["payload"] as? [String: Any],
              let exportHandle = payload["exportHandle"] as? String,
              let fileURI = payload["fileUri"] as? String,
              let file = URL(string: fileURI)
        else {
            return XCTFail("Expected materialized payload")
        }

        let deleted = await waitUntil(iterations: 1_000) {
            !FileManager.default.fileExists(atPath: file.path)
        }
        XCTAssertTrue(deleted)
        let release = await invoke(
            controller,
            operation: "release_materialized_media",
            requestId: "ttl_release",
            payload: ["exportHandle": exportHandle]
        )
        XCTAssertEqual(failure(release)?.code, "materialized_media_invalid")
    }

    func testEngineDetachDeletesActiveTransferBeforeCompletingBoundary() async throws {
        let cache = try temporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }
        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        let controller = makeController(
            core: core,
            owner: owner,
            transferStore: MediaCaptureTransferStore(cacheDirectory: cache)
        )
        _ = await invoke(controller, operation: "start_session", requestId: "detach_transfer_start", payload: startPayload())
        _ = await invoke(controller, operation: "take_photo", requestId: "detach_transfer_photo", payload: sessionPayload("session_1"))
        _ = await invoke(controller, operation: "confirm", requestId: "detach_transfer_confirm", payload: mediaPayload("photo_1"))
        let materialized = await invoke(
            controller,
            operation: "materialize_media_resource",
            requestId: "detach_transfer_materialize",
            payload: mediaPayload("photo_1")
        )
        guard case let .success(envelope) = materialized,
              let payload = envelope["payload"] as? [String: Any],
              let fileURI = payload["fileUri"] as? String,
              let file = URL(string: fileURI)
        else {
            return XCTFail("Expected materialized payload")
        }

        controller.detachEngine()

        let deleted = await waitUntil(iterations: 1_000) {
            !FileManager.default.fileExists(atPath: file.path)
        }
        XCTAssertTrue(deleted)
    }

    func testLateExportAfterDetachFailsOnceAndLeavesNoTransferResidue() async throws {
        let cache = try temporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }
        let core = FakeMediaCaptureCore()
        await core.configureExportDelay(nanoseconds: 100_000_000, ignoreCancellation: true)
        let owner = PresentationOwnerBox()
        let controller = makeController(
            core: core,
            owner: owner,
            transferStore: MediaCaptureTransferStore(cacheDirectory: cache),
            drainTimeoutNanoseconds: 2_000_000
        )
        _ = await invoke(controller, operation: "start_session", requestId: "late_export_start", payload: startPayload())
        _ = await invoke(controller, operation: "take_photo", requestId: "late_export_photo", payload: sessionPayload("session_1"))
        _ = await invoke(controller, operation: "confirm", requestId: "late_export_confirm", payload: mediaPayload("photo_1"))
        let completion = CompletionProbe()
        controller.handle(
            operation: "materialize_media_resource",
            arguments: requestEnvelope(
                requestId: "late_export_materialize",
                payload: mediaPayload("photo_1")
            ),
            completion: completion
        )
        let started = await waitUntil {
            await core.snapshot().operations.contains("materialize_media_resource")
        }
        XCTAssertTrue(started)

        controller.detachEngine()
        let outcome = await completion.value()

        XCTAssertEqual(failure(outcome)?.details["lifecycleReason"], "engine_detached")
        XCTAssertEqual(completion.completionCount, 1)
        let exports = cache
            .appendingPathComponent("app_media_capture_bridge", isDirectory: true)
            .appendingPathComponent("exports", isDirectory: true)
        let cleaned = await waitUntil(iterations: 2_000) {
            let residue = (try? FileManager.default.contentsOfDirectory(atPath: exports.path)) ?? []
            return residue.isEmpty
        }
        XCTAssertTrue(cleaned)
    }

    func testExportResultMismatchAndCapabilityFailureDeleteTransferTargets() async throws {
        let cache = try temporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }
        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        let controller = makeController(
            core: core,
            owner: owner,
            transferStore: MediaCaptureTransferStore(cacheDirectory: cache)
        )
        _ = await invoke(controller, operation: "start_session", requestId: "mismatch_start", payload: startPayload())
        _ = await invoke(controller, operation: "take_photo", requestId: "mismatch_photo", payload: sessionPayload("session_1"))
        _ = await invoke(controller, operation: "confirm", requestId: "mismatch_confirm", payload: mediaPayload("photo_1"))
        await core.configureExportResultLengthMismatch(true)

        let mismatch = await invoke(
            controller,
            operation: "materialize_media_resource",
            requestId: "mismatch_materialize",
            payload: mediaPayload("photo_1")
        )
        XCTAssertEqual(failure(mismatch)?.code, "wire_encoding_failed")

        await core.configureExportResultLengthMismatch(false)
        await core.configureExportFailureAfterBegin(MediaCaptureFailure(.mediaExportWriteFailed))
        let failed = await invoke(
            controller,
            operation: "materialize_media_resource",
            requestId: "failed_materialize",
            payload: mediaPayload("photo_1")
        )
        XCTAssertEqual(failure(failed)?.code, "media_export_write_failed")
        XCTAssertEqual(failure(failed)?.details["capabilityFailureId"], "media_export_write_failed")
        XCTAssertFalse(failure(failed)?.details.values.contains { $0.contains("/") } ?? true)

        let exports = cache
            .appendingPathComponent("app_media_capture_bridge", isDirectory: true)
            .appendingPathComponent("exports", isDirectory: true)
        XCTAssertTrue((try FileManager.default.contentsOfDirectory(atPath: exports.path)).isEmpty)
        let sourceStillLeased = await invoke(
            controller,
            operation: "read_media_thumbnail",
            requestId: "mismatch_thumbnail",
            payload: ["mediaHandle": "photo_1", "maxPixelEdge": 64]
        )
        XCTAssertEqual(resultType(sourceStillLeased), "media_thumbnail")
    }

    func testConcurrentReleaseRequestsJoinOneDeletionClaim() async throws {
        let cache = try temporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }
        let deletion = BlockingTransferDeleteProbe()
        let store = MediaCaptureTransferStore(
            cacheDirectory: cache,
            deletePermission: { deletion.permit($0) }
        )
        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        let controller = makeController(core: core, owner: owner, transferStore: store)
        _ = await invoke(controller, operation: "start_session", requestId: "join_start", payload: startPayload())
        _ = await invoke(controller, operation: "take_photo", requestId: "join_photo", payload: sessionPayload("session_1"))
        _ = await invoke(controller, operation: "confirm", requestId: "join_confirm", payload: mediaPayload("photo_1"))
        let materialized = await invoke(
            controller,
            operation: "materialize_media_resource",
            requestId: "join_materialize",
            payload: mediaPayload("photo_1")
        )
        guard case let .success(envelope) = materialized,
              let payload = envelope["payload"] as? [String: Any],
              let exportHandle = payload["exportHandle"] as? String
        else {
            return XCTFail("Expected materialized payload")
        }
        deletion.blockNextDeletion()
        let first = CompletionProbe()
        controller.handle(
            operation: "release_materialized_media",
            arguments: requestEnvelope(requestId: "join_release_1", payload: ["exportHandle": exportHandle]),
            completion: first
        )
        let deletionStarted = await waitUntil(iterations: 1_000) { deletion.isBlocked }
        XCTAssertTrue(deletionStarted)
        let second = CompletionProbe()
        controller.handle(
            operation: "release_materialized_media",
            arguments: requestEnvelope(requestId: "join_release_2", payload: ["exportHandle": exportHandle]),
            completion: second
        )
        await Task.yield()
        deletion.unblock()

        let firstOutcome = await first.value()
        let secondOutcome = await second.value()
        XCTAssertEqual(resultType(firstOutcome), "materialized_media_released")
        XCTAssertEqual(resultType(secondOutcome), "materialized_media_released")
        XCTAssertEqual(deletion.deletionCount, 1)
    }

    func testDeleteFailureRetainsCapacityUntilBackgroundCleanupSucceeds() async throws {
        let cache = try temporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }
        let deletion = FailingTransferDeleteProbe(failures: 3)
        let store = MediaCaptureTransferStore(
            cacheDirectory: cache,
            deletePermission: { deletion.permit($0) }
        )
        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        let controller = makeController(core: core, owner: owner, transferStore: store)
        _ = await invoke(controller, operation: "start_session", requestId: "retry_start", payload: startPayload())
        _ = await invoke(controller, operation: "take_photo", requestId: "retry_photo", payload: sessionPayload("session_1"))
        _ = await invoke(controller, operation: "confirm", requestId: "retry_confirm", payload: mediaPayload("photo_1"))
        let materialized = await invoke(
            controller,
            operation: "materialize_media_resource",
            requestId: "retry_materialize",
            payload: mediaPayload("photo_1")
        )
        guard case let .success(envelope) = materialized,
              let payload = envelope["payload"] as? [String: Any],
              let exportHandle = payload["exportHandle"] as? String,
              let fileURI = payload["fileUri"] as? String,
              let file = URL(string: fileURI)
        else {
            return XCTFail("Expected materialized payload")
        }

        let first = await invoke(
            controller,
            operation: "release_materialized_media",
            requestId: "retry_release",
            payload: ["exportHandle": exportHandle]
        )
        XCTAssertEqual(failure(first)?.code, "transfer_store_unavailable")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        let eventuallyDeleted = await waitUntil(iterations: 2_000) {
            !FileManager.default.fileExists(atPath: file.path)
        }
        XCTAssertTrue(eventuallyDeleted)
        var repeatedReleased = false
        for attempt in 0 ..< 100 {
            let repeated = await invoke(
                controller,
                operation: "release_materialized_media",
                requestId: "retry_release_again_\(attempt)",
                payload: ["exportHandle": exportHandle]
            )
            if resultType(repeated) == "materialized_media_released" {
                repeatedReleased = true
                break
            }
            XCTAssertEqual(failure(repeated)?.code, "transfer_store_unavailable")
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(repeatedReleased)
    }

    func testActiveByteBudgetRejectsBeforeThirdCapabilityExport() async throws {
        let cache = try temporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }
        let core = FakeMediaCaptureCore()
        let owner = PresentationOwnerBox()
        let controller = makeController(
            core: core,
            owner: owner,
            transferStore: MediaCaptureTransferStore(cacheDirectory: cache),
            maximumActiveTransferBytes: 8_192
        )
        for index in 1 ... 2 {
            _ = await invoke(controller, operation: "start_session", requestId: "bytes_start_\(index)", payload: startPayload())
            _ = await invoke(controller, operation: "take_photo", requestId: "bytes_photo_\(index)", payload: sessionPayload("session_\(index)"))
            _ = await invoke(controller, operation: "confirm", requestId: "bytes_confirm_\(index)", payload: mediaPayload("photo_\(index)"))
            let result = await invoke(
                controller,
                operation: "materialize_media_resource",
                requestId: "bytes_materialize_\(index)",
                payload: mediaPayload("photo_\(index)")
            )
            XCTAssertEqual(resultType(result), "materialized_media_resource")
        }
        await core.configureCapturedMediaByteLength(1)
        _ = await invoke(controller, operation: "start_session", requestId: "bytes_start_3", payload: startPayload())
        _ = await invoke(controller, operation: "take_photo", requestId: "bytes_photo_3", payload: sessionPayload("session_3"))
        _ = await invoke(controller, operation: "confirm", requestId: "bytes_confirm_3", payload: mediaPayload("photo_3"))

        let rejected = await invoke(
            controller,
            operation: "materialize_media_resource",
            requestId: "bytes_materialize_3",
            payload: mediaPayload("photo_3")
        )
        XCTAssertEqual(failure(rejected)?.code, "transfer_store_overloaded")
        XCTAssertEqual(failure(rejected)?.details["capacity"], "active_export_bytes")
        let operations = await core.snapshot().operations
        XCTAssertEqual(operations.filter { $0 == "materialize_media_resource" }.count, 2)
    }

    private func temporaryCacheDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }
}

private final class BlockingTransferDeleteProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let release = DispatchSemaphore(value: 0)
    private var shouldBlock = false
    private var blocked = false
    private var count = 0

    var deletionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    var isBlocked: Bool {
        lock.lock()
        defer { lock.unlock() }
        return blocked
    }

    func blockNextDeletion() {
        lock.lock()
        shouldBlock = true
        lock.unlock()
    }

    func permit(_: URL) -> Bool {
        lock.lock()
        let block = shouldBlock
        shouldBlock = false
        count += 1
        if block { blocked = true }
        lock.unlock()
        if block {
            release.wait()
        }
        return true
    }

    func unblock() {
        release.signal()
    }
}

private final class FailingTransferDeleteProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var failuresRemaining: Int

    init(failures: Int) {
        failuresRemaining = failures
    }

    func permit(_: URL) -> Bool {
        lock.lock()
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            lock.unlock()
            return false
        }
        lock.unlock()
        return true
    }
}

private final class TransferWritePermissionProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var rejectNext = false

    func rejectNextWrite() {
        lock.lock()
        rejectNext = true
        lock.unlock()
    }

    func permit() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if rejectNext {
            rejectNext = false
            return false
        }
        return true
    }
}
