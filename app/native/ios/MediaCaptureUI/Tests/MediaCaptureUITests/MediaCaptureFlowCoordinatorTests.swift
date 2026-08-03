import MediaCapture
import UIKit
import XCTest
@testable import MediaCaptureUI

@MainActor
final class MediaCaptureFlowCoordinatorTests: XCTestCase {
    func testFocusUsesRenderDevicePointConversion() async throws {
        var converterInput: CGPoint?
        let expectedDevicePoint = CGPoint(x: 0.72, y: 0.31)
        let fixture = try await makeReadyFixture(
            enabled: [.photo],
            devicePointConverter: { _, point in
                converterInput = point
                return expectedDevicePoint
            }
        )
        fixture.viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        fixture.viewController.view.layoutIfNeeded()
        let renderPoint = CGPoint(x: 52, y: 96)

        XCTAssertTrue(fixture.viewController.focus(atRenderPoint: renderPoint))
        let focusDelivered = await eventually {
            await fixture.core.snapshot().focusPoints.count == 1
        }
        XCTAssertTrue(focusDelivered)

        let snapshot = await fixture.core.snapshot()
        XCTAssertEqual(converterInput, renderPoint)
        XCTAssertEqual(snapshot.focusPoints, [FakeMediaCaptureService.FocusPoint(
            x: Double(expectedDevicePoint.x),
            y: Double(expectedDevicePoint.y)
        )])
        XCTAssertFalse(fixture.viewController.focus(atRenderPoint: CGPoint(x: -1, y: 96)))
        let finalFocusCount = await fixture.core.snapshot().focusCount
        XCTAssertEqual(finalFocusCount, 1)
    }

    func testPhotoPreviewConfirmCompletesAfterSurfaceCleanup() async throws {
        let fixture = try await makeReadyFixture(enabled: [.photo])

        fixture.coordinator.takePhoto()
        let previewReady = await eventually {
            await fixture.core.snapshot().previewAttachGenerations.count == 1
        }
        XCTAssertTrue(previewReady)
        fixture.coordinator.confirm()
        let result = await fixture.coordinator.awaitResult()

        let confirmedMedia = fixture.core.confirmedMedia
        XCTAssertEqual(result, .confirmed(confirmedMedia))
        let snapshot = await fixture.core.snapshot()
        XCTAssertEqual(snapshot.photoCount, 1)
        XCTAssertEqual(snapshot.previewDetachCount, 1)
        XCTAssertEqual(snapshot.cancelCount, 0)
        XCTAssertEqual(fixture.slotReleaseCount(), 1)
    }

    func testDismissIsCancelledAndExactlyOnce() async throws {
        let fixture = try await makeReadyFixture(enabled: [.photo, .video])

        fixture.coordinator.dismissByCaller()
        fixture.coordinator.ownerWasDestroyed()
        let result = await fixture.coordinator.awaitResult()

        XCTAssertEqual(result, .cancelled)
        let cancelCount = await fixture.core.snapshot().cancelCount
        XCTAssertEqual(cancelCount, 1)
        XCTAssertEqual(fixture.slotReleaseCount(), 1)
    }

    func testSessionFailureIsNotReportedAsCancellation() async throws {
        let fixture = try await makeReadyFixture(enabled: [.photo])
        let failure = MediaCaptureFailure(.systemInterrupted)

        fixture.core.emit(.sessionFailed(
            sessionHandle: fixture.core.sessionHandle,
            failure: failure
        ))
        let result = await fixture.coordinator.awaitResult()

        XCTAssertEqual(result, .failure(failure))
        XCTAssertEqual(fixture.slotReleaseCount(), 1)
    }

    func testUnexpectedEventStreamCompletionFailsAndCleansUpSession() async throws {
        let fixture = try await makeReadyFixture(enabled: [.photo])

        fixture.core.finishEvents()
        let result = await fixture.coordinator.awaitResult()

        XCTAssertEqual(result, .failure(MediaCaptureFailure(.systemInterrupted)))
        let snapshot = await fixture.core.snapshot()
        XCTAssertEqual(snapshot.cancelCount, 1)
        XCTAssertEqual(fixture.slotReleaseCount(), 1)
    }

    func testReleaseBeforeRecordingStartStopsImmediatelyAfterStart() async throws {
        let fixture = try await makeReadyFixture(enabled: [.video], mediaType: .video)
        let gate = AsyncTestGate()
        await fixture.core.configureStartRecordingGate(gate)

        fixture.coordinator.startRecording()
        let startReady = await eventually {
            await fixture.core.snapshot().startRecordingCount == 1
        }
        XCTAssertTrue(startReady)
        fixture.coordinator.stopRecording()
        gate.release()

        let previewReady = await eventually {
            let snapshot = await fixture.core.snapshot()
            return snapshot.stopRecordingCount == 1 && snapshot.previewAttachGenerations.count == 1
        }
        XCTAssertTrue(previewReady)
        fixture.coordinator.dismissByCaller()
        _ = await fixture.coordinator.awaitResult()
    }

    func testReleaseDuringBlockedZoomStopsAfterZoomSettles() async throws {
        let fixture = try await makeReadyFixture(enabled: [.video], mediaType: .video)
        fixture.coordinator.startRecording()
        let recordingReady = await eventually {
            await fixture.core.snapshot().startRecordingCount == 1
        }
        XCTAssertTrue(recordingReady)
        await Task.yield()
        let zoomGate = AsyncTestGate()
        await fixture.core.configureZoomGate(zoomGate)

        fixture.coordinator.updateZoom(verticalDelta: 60)
        let zoomStarted = await eventually { await fixture.core.snapshot().zoomFactors.count == 1 }
        XCTAssertTrue(zoomStarted)
        fixture.coordinator.stopRecording()
        let stoppedTooEarly = await fixture.core.snapshot().stopRecordingCount
        XCTAssertEqual(stoppedTooEarly, 0)
        zoomGate.release()

        let stopped = await eventually {
            let snapshot = await fixture.core.snapshot()
            return snapshot.stopRecordingCount == 1 && snapshot.previewAttachGenerations.count == 1
        }
        XCTAssertTrue(stopped)
        let zoomFactors = await fixture.core.snapshot().zoomFactors
        XCTAssertEqual(zoomFactors.count, 1)
        let zoomFactor = try XCTUnwrap(zoomFactors.first)
        XCTAssertEqual(zoomFactor, 2, accuracy: 0.001)
        fixture.coordinator.dismissByCaller()
        _ = await fixture.coordinator.awaitResult()
    }

    func testRotationWaitsForInFlightPhotoAndRecoversLiveSurface() async throws {
        let fixture = try await makeReadyFixture(enabled: [.photo])
        let photoGate = AsyncTestGate()
        await fixture.core.configurePhotoGate(photoGate)
        fixture.coordinator.takePhoto()
        let photoStarted = await eventually { await fixture.core.snapshot().photoCount == 1 }
        XCTAssertTrue(photoStarted)

        fixture.coordinator.displayRotationChanged()
        try? await Task.sleep(nanoseconds: 10_000_000)
        let rotationBeforeRelease = await fixture.core.snapshot().rotationCount
        XCTAssertEqual(rotationBeforeRelease, 0)
        photoGate.release()

        let recovered = await eventually {
            let snapshot = await fixture.core.snapshot()
            return snapshot.rotationCount == 1 && snapshot.previewAttachGenerations.count == 1
        }
        XCTAssertTrue(recovered)
        fixture.coordinator.dismissByCaller()
        _ = await fixture.coordinator.awaitResult()
    }

    func testBackgroundWaitsForInFlightPhotoThenForegroundReattaches() async throws {
        let fixture = try await makeReadyFixture(enabled: [.photo])
        let photoGate = AsyncTestGate()
        await fixture.core.configurePhotoGate(photoGate)
        fixture.coordinator.takePhoto()
        let photoStarted = await eventually { await fixture.core.snapshot().photoCount == 1 }
        XCTAssertTrue(photoStarted)

        fixture.coordinator.appDidEnterBackground()
        try? await Task.sleep(nanoseconds: 10_000_000)
        let backgroundBeforeRelease = await fixture.core.snapshot().backgroundCount
        XCTAssertEqual(backgroundBeforeRelease, 0)
        photoGate.release()
        let backgrounded = await eventually { await fixture.core.snapshot().backgroundCount == 1 }
        XCTAssertTrue(backgrounded)
        fixture.coordinator.appWillEnterForeground()
        let reattached = await eventually {
            await fixture.core.snapshot().previewAttachGenerations.count == 1
        }
        XCTAssertTrue(reattached)
        fixture.coordinator.dismissByCaller()
        _ = await fixture.coordinator.awaitResult()
    }

    func testSwitchCameraAppliesNewCapabilitiesBeforeActionsResume() async throws {
        let fixture = try await makeReadyFixture(enabled: [.video], mediaType: .video)

        fixture.coordinator.switchCamera()
        let switched = await eventually {
            let snapshot = await fixture.core.snapshot()
            return snapshot.switchCameraCount == 1
                && snapshot.liveAttachGenerations.count == 2
                && fixture.coordinator.actionTransactionAvailable
        }
        XCTAssertTrue(switched)

        XCTAssertFalse(fixture.coordinator.focus(normalizedX: 0.5, normalizedY: 0.5))
        fixture.coordinator.cycleFlash()
        try? await Task.sleep(nanoseconds: 10_000_000)
        var snapshot = await fixture.core.snapshot()
        XCTAssertEqual(snapshot.focusCount, 0)
        XCTAssertTrue(snapshot.flashModes.isEmpty)

        fixture.coordinator.startRecording()
        let recording = await eventually {
            await fixture.core.snapshot().startRecordingCount == 1
                && fixture.coordinator.actionTransactionAvailable
        }
        XCTAssertTrue(recording)
        fixture.coordinator.updateZoom(verticalDelta: 180)
        let zoomed = await eventually {
            await fixture.core.snapshot().zoomFactors.count == 1
        }
        XCTAssertTrue(zoomed)
        snapshot = await fixture.core.snapshot()
        XCTAssertEqual(snapshot.zoomFactors, [2])

        fixture.coordinator.dismissByCaller()
        _ = await fixture.coordinator.awaitResult()
    }

    func testRotationWaitsForCommittedCameraSwitchSnapshotBeforeRestoringLive() async throws {
        let fixture = try await makeReadyFixture(enabled: [.photo])
        let switchGate = AsyncTestGate()
        await fixture.core.configureSwitchCameraGate(switchGate)

        fixture.coordinator.switchCamera()
        let switchStarted = await eventually {
            await fixture.core.snapshot().switchCameraCount == 1
        }
        XCTAssertTrue(switchStarted)
        fixture.coordinator.displayRotationChanged()
        switchGate.release()

        let recovered = await eventually {
            let snapshot = await fixture.core.snapshot()
            return snapshot.rotationCount == 1
                && snapshot.liveAttachGenerations.count == 2
                && fixture.coordinator.actionTransactionAvailable
        }
        XCTAssertTrue(recovered)
        XCTAssertFalse(fixture.coordinator.focus(normalizedX: 0.5, normalizedY: 0.5))
        XCTAssertTrue(fixture.coordinator.takePhoto())
        let photoStarted = await eventually {
            await fixture.core.snapshot().photoCount == 1
        }
        XCTAssertTrue(photoStarted)

        fixture.coordinator.dismissByCaller()
        _ = await fixture.coordinator.awaitResult()
    }

    func testRotationReplaysDequeuedCameraSnapshotWhileSwitchActionStillReturns() async throws {
        let fixture = try await makeReadyFixture(enabled: [.photo])
        let returnGate = AsyncTestGate()
        await fixture.core.configureSwitchCameraReturnGate(returnGate)

        fixture.coordinator.switchCamera()
        let eventWasDequeued = await eventually {
            fixture.coordinator.eventTransactionInFlight
        }
        XCTAssertTrue(eventWasDequeued)
        fixture.coordinator.displayRotationChanged()
        returnGate.release()

        let recovered = await eventually {
            let snapshot = await fixture.core.snapshot()
            return snapshot.rotationCount == 1
                && snapshot.liveAttachGenerations.count == 2
                && fixture.coordinator.actionTransactionAvailable
        }
        XCTAssertTrue(recovered)
        XCTAssertFalse(fixture.coordinator.focus(normalizedX: 0.5, normalizedY: 0.5))
        XCTAssertTrue(fixture.coordinator.takePhoto())

        fixture.coordinator.dismissByCaller()
        _ = await fixture.coordinator.awaitResult()
    }

    func testRetakeSuccessDuringBackgroundRestoresFreshLiveSurface() async throws {
        let fixture = try await makeReadyFixture(enabled: [.photo])
        fixture.coordinator.takePhoto()
        let previewReady = await eventually {
            await fixture.core.snapshot().previewAttachGenerations.count == 1
        }
        XCTAssertTrue(previewReady)
        let retakeGate = AsyncTestGate()
        await fixture.core.configureRetakeGate(retakeGate)
        fixture.coordinator.retake()
        let retakeStarted = await eventually {
            await fixture.core.snapshot().retakeCount == 1
        }
        XCTAssertTrue(retakeStarted)

        fixture.coordinator.appDidEnterBackground()
        retakeGate.release()
        let backgrounded = await eventually {
            await fixture.core.snapshot().backgroundCount == 1
        }
        XCTAssertTrue(backgrounded)
        fixture.coordinator.appWillEnterForeground()
        let liveRestored = await eventually {
            let snapshot = await fixture.core.snapshot()
            return snapshot.liveAttachGenerations.count == 2
                && snapshot.previewAttachGenerations.count == 1
        }
        XCTAssertTrue(liveRestored)

        fixture.coordinator.dismissByCaller()
        _ = await fixture.coordinator.awaitResult()
    }

    func testRotationWaitsForInFlightEventSurfaceAttach() async throws {
        let core = try FakeMediaCaptureService()
        let gate = AsyncTestGate()
        await core.configureLiveAttachGate(gate)
        let fixture = try await makeStartedFixture(core: core, enabled: [.photo])
        core.emit(.sessionReady(makeReadySnapshot(sessionHandle: core.sessionHandle)))
        let attachStarted = await eventually { await core.snapshot().liveAttachGenerations.count == 1 }
        XCTAssertTrue(attachStarted)

        fixture.coordinator.displayRotationChanged()
        try? await Task.sleep(nanoseconds: 10_000_000)
        let rotationBeforeRelease = await core.snapshot().rotationCount
        XCTAssertEqual(rotationBeforeRelease, 0)
        gate.release()
        let recovered = await eventually {
            let snapshot = await core.snapshot()
            return snapshot.rotationCount == 1 && snapshot.liveAttachGenerations.count == 2
        }
        XCTAssertTrue(recovered)
        fixture.coordinator.dismissByCaller()
        _ = await fixture.coordinator.awaitResult()
    }

    func testLifecycleClosesActionAdmissionAndQueuesLaterEvent() async throws {
        let fixture = try await makeReadyFixture(enabled: [.photo])
        let rotationGate = AsyncTestGate()
        await fixture.core.configureRotationGate(rotationGate)

        fixture.coordinator.displayRotationChanged()
        let rotationStarted = await eventually {
            await fixture.core.snapshot().rotationCount == 1
        }
        XCTAssertTrue(rotationStarted)

        fixture.coordinator.takePhoto()
        fixture.core.emit(.sessionReady(makeReadySnapshot(
            sessionHandle: fixture.core.sessionHandle
        )))
        try? await Task.sleep(nanoseconds: 20_000_000)
        let snapshot = await fixture.core.snapshot()
        XCTAssertEqual(snapshot.photoCount, 0)
        XCTAssertEqual(snapshot.liveAttachGenerations.count, 1)

        rotationGate.release()
        let queuedEventHandled = await eventually {
            await fixture.core.snapshot().liveAttachGenerations.count == 3
        }
        XCTAssertTrue(queuedEventHandled)

        let photoActionAccepted = await eventually {
            fixture.coordinator.takePhoto()
        }
        XCTAssertTrue(photoActionAccepted)
        let photoStarted = await eventually {
            await fixture.core.snapshot().photoCount == 1
        }
        XCTAssertTrue(photoStarted)
        fixture.coordinator.dismissByCaller()
        _ = await fixture.coordinator.awaitResult()
    }

    func testRotationAndForegroundUseStrictlyNewSurfaceGenerations() async throws {
        let fixture = try await makeReadyFixture(enabled: [.photo])
        let firstSnapshot = await fixture.core.snapshot()
        let first = try XCTUnwrap(firstSnapshot.liveAttachGenerations.last)

        fixture.coordinator.displayRotationChanged()
        let rotationReady = await eventually {
            await fixture.core.snapshot().liveAttachGenerations.count == 2
        }
        XCTAssertTrue(rotationReady)
        let secondSnapshot = await fixture.core.snapshot()
        let second = try XCTUnwrap(secondSnapshot.liveAttachGenerations.last)
        XCTAssertGreaterThan(second, first)

        fixture.coordinator.appDidEnterBackground()
        let backgroundReady = await eventually {
            await fixture.core.snapshot().backgroundCount == 1
        }
        XCTAssertTrue(backgroundReady)
        fixture.coordinator.appWillEnterForeground()
        let foregroundReady = await eventually {
            await fixture.core.snapshot().liveAttachGenerations.count == 3
        }
        XCTAssertTrue(foregroundReady)
        let thirdSnapshot = await fixture.core.snapshot()
        let third = try XCTUnwrap(thirdSnapshot.liveAttachGenerations.last)
        XCTAssertGreaterThan(third, second)
        fixture.coordinator.dismissByCaller()
        _ = await fixture.coordinator.awaitResult()
    }

    func testOwnerDestroyReleasesConfirmedLeaseThatReturnsLate() async throws {
        let fixture = try await makeReadyFixture(enabled: [.photo])
        fixture.coordinator.takePhoto()
        let previewReady = await eventually {
            await fixture.core.snapshot().previewAttachGenerations.count == 1
        }
        XCTAssertTrue(previewReady)
        let gate = AsyncTestGate()
        await fixture.core.configureConfirmGate(gate)

        fixture.coordinator.confirm()
        await Task.yield()
        fixture.coordinator.ownerWasDestroyed()
        gate.release()
        let result = await fixture.coordinator.awaitResult()

        XCTAssertEqual(result, .failure(MediaCaptureFailure(.systemInterrupted)))
        let snapshot = await fixture.core.snapshot()
        let previewMetadata = fixture.core.previewMetadata
        XCTAssertEqual(snapshot.releaseHandles, [previewMetadata.mediaHandle])
        XCTAssertEqual(fixture.slotReleaseCount(), 1)
    }

    func testTerminalTimeoutCompletesResultButHoldsSlotUntilLateConfirmCleanup() async throws {
        let cleanupOwner = MediaCaptureLeaseCleanupOwner(retryDelayNanoseconds: 2_000_000)
        let fixture = try await makeReadyFixture(
            enabled: [.photo],
            cleanupOwner: cleanupOwner,
            settleTimeoutNanoseconds: 2_000_000
        )
        fixture.coordinator.takePhoto()
        let previewReady = await eventually {
            await fixture.core.snapshot().previewAttachGenerations.count == 1
        }
        XCTAssertTrue(previewReady)
        let confirmGate = AsyncTestGate()
        await fixture.core.configureConfirmGate(confirmGate)
        fixture.coordinator.confirm()
        let confirmStarted = await eventually {
            await fixture.core.snapshot().confirmAttemptCount == 1
        }
        XCTAssertTrue(confirmStarted)

        fixture.coordinator.ownerWasDestroyed()
        let result = await fixture.coordinator.awaitResult()

        XCTAssertEqual(result, .failure(MediaCaptureFailure(.systemInterrupted)))
        XCTAssertEqual(fixture.slotReleaseCount(), 0)
        confirmGate.release()
        let recovered = await eventually {
            let snapshot = await fixture.core.snapshot()
            return fixture.slotReleaseCount() == 1 && snapshot.releaseHandles.count == 1
        }
        XCTAssertTrue(recovered)
    }

    func testCancelFailurePoisonsSlotUntilProcessCleanupRecovers() async throws {
        let cleanupOwner = MediaCaptureLeaseCleanupOwner(retryDelayNanoseconds: 100_000_000)
        let fixture = try await makeReadyFixture(
            enabled: [.photo],
            cleanupOwner: cleanupOwner,
            settleTimeoutNanoseconds: 20_000_000
        )
        await fixture.core.configureCleanupFailures(cancel: 1, release: 0, liveDetach: 0)

        fixture.coordinator.dismissByCaller()
        let result = await fixture.coordinator.awaitResult()

        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(fixture.slotReleaseCount(), 0)
        let recovered = await eventually(attempts: 400) {
            let snapshot = await fixture.core.snapshot()
            return fixture.slotReleaseCount() == 1 && snapshot.cancelAttemptCount == 2
        }
        XCTAssertTrue(recovered)
    }

    func testDetachFailureAlonePoisonsSlotUntilProcessCleanupRecovers() async throws {
        let cleanupOwner = MediaCaptureLeaseCleanupOwner(retryDelayNanoseconds: 100_000_000)
        let fixture = try await makeReadyFixture(
            enabled: [.photo],
            cleanupOwner: cleanupOwner,
            settleTimeoutNanoseconds: 20_000_000
        )
        await fixture.core.configureCleanupFailures(cancel: 0, release: 0, liveDetach: 1)

        fixture.coordinator.dismissByCaller()
        let result = await fixture.coordinator.awaitResult()

        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(fixture.slotReleaseCount(), 0)
        let recovered = await eventually(attempts: 400) {
            let snapshot = await fixture.core.snapshot()
            return fixture.slotReleaseCount() == 1 && snapshot.liveDetachCount == 2
        }
        XCTAssertTrue(recovered)
    }

    func testBlockedDetachDoesNotBlockResultAndKeepsSlotUntilSettled() async throws {
        let fixture = try await makeReadyFixture(
            enabled: [.photo],
            cleanupOwner: MediaCaptureLeaseCleanupOwner(retryDelayNanoseconds: 10_000_000),
            settleTimeoutNanoseconds: 2_000_000
        )
        let detachGate = AsyncTestGate()
        await fixture.core.configureLiveDetachGate(detachGate)

        fixture.coordinator.dismissByCaller()
        let result = await fixture.coordinator.awaitResult()

        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(fixture.slotReleaseCount(), 0)
        detachGate.release()
        let settled = await eventually {
            fixture.slotReleaseCount() == 1
        }
        XCTAssertTrue(settled)
    }

    func testBlockedCancelDoesNotBlockResultAndKeepsSlotUntilSettled() async throws {
        let fixture = try await makeReadyFixture(
            enabled: [.photo],
            cleanupOwner: MediaCaptureLeaseCleanupOwner(retryDelayNanoseconds: 10_000_000),
            settleTimeoutNanoseconds: 2_000_000
        )
        let cancelGate = AsyncTestGate()
        await fixture.core.configureCancelGate(cancelGate)

        fixture.coordinator.dismissByCaller()
        let result = await fixture.coordinator.awaitResult()

        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(fixture.slotReleaseCount(), 0)
        cancelGate.release()
        let settled = await eventually {
            fixture.slotReleaseCount() == 1
        }
        XCTAssertTrue(settled)
    }

    func testLateStartedSessionCancellationFailureIsAdopted() async throws {
        let core = try FakeMediaCaptureService()
        let startGate = AsyncTestGate()
        await core.configureStartSessionGate(startGate)
        await core.configureCleanupFailures(cancel: 1, release: 0, liveDetach: 0)
        let fixture = try await makeStartedFixture(
            core: core,
            enabled: [.photo],
            cleanupOwner: MediaCaptureLeaseCleanupOwner(retryDelayNanoseconds: 10_000_000),
            settleTimeoutNanoseconds: 2_000_000
        )

        fixture.coordinator.dismissByCaller()
        let result = await fixture.coordinator.awaitResult()
        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(fixture.slotReleaseCount(), 0)

        startGate.release()
        let recovered = await eventually(attempts: 400) {
            let snapshot = await core.snapshot()
            return fixture.slotReleaseCount() == 1 && snapshot.cancelAttemptCount == 2
        }
        XCTAssertTrue(recovered)
    }

    func testLateLeaseReleaseFailureKeepsSlotUntilRetrySucceeds() async throws {
        let cleanupOwner = MediaCaptureLeaseCleanupOwner(retryDelayNanoseconds: 100_000_000)
        let fixture = try await makeReadyFixture(
            enabled: [.photo],
            cleanupOwner: cleanupOwner,
            settleTimeoutNanoseconds: 2_000_000
        )
        fixture.coordinator.takePhoto()
        let previewReady = await eventually {
            await fixture.core.snapshot().previewAttachGenerations.count == 1
        }
        XCTAssertTrue(previewReady)
        let confirmGate = AsyncTestGate()
        await fixture.core.configureConfirmGate(confirmGate)
        await fixture.core.configureCleanupFailures(cancel: 0, release: 1, liveDetach: 0)
        fixture.coordinator.confirm()
        let confirmStarted = await eventually {
            await fixture.core.snapshot().confirmAttemptCount == 1
        }
        XCTAssertTrue(confirmStarted)
        fixture.coordinator.ownerWasDestroyed()
        _ = await fixture.coordinator.awaitResult()
        confirmGate.release()

        let firstReleaseFailed = await eventually {
            await fixture.core.snapshot().releaseAttemptCount == 1
        }
        XCTAssertTrue(firstReleaseFailed)
        XCTAssertEqual(fixture.slotReleaseCount(), 0)
        let recovered = await eventually(attempts: 400) {
            let snapshot = await fixture.core.snapshot()
            return fixture.slotReleaseCount() == 1 && snapshot.releaseAttemptCount == 2
        }
        XCTAssertTrue(recovered)
    }

    func testPermanentLateLeaseFailureStopsRetryAndReleasesSlot() async throws {
        let cleanupOwner = MediaCaptureLeaseCleanupOwner(retryDelayNanoseconds: 2_000_000)
        let fixture = try await makeReadyFixture(
            enabled: [.photo],
            cleanupOwner: cleanupOwner,
            settleTimeoutNanoseconds: 2_000_000
        )
        fixture.coordinator.takePhoto()
        let previewReady = await eventually {
            await fixture.core.snapshot().previewAttachGenerations.count == 1
        }
        XCTAssertTrue(previewReady)
        let confirmGate = AsyncTestGate()
        await fixture.core.configureConfirmGate(confirmGate)
        await fixture.core.configureReleaseFailures([.mediaInvalid])
        fixture.coordinator.confirm()
        let confirmStarted = await eventually {
            await fixture.core.snapshot().confirmAttemptCount == 1
        }
        XCTAssertTrue(confirmStarted)

        fixture.coordinator.ownerWasDestroyed()
        _ = await fixture.coordinator.awaitResult()
        confirmGate.release()

        let settled = await eventually {
            let snapshot = await fixture.core.snapshot()
            return fixture.slotReleaseCount() == 1 && snapshot.releaseAttemptCount == 1
        }
        XCTAssertTrue(settled)
        try? await Task.sleep(nanoseconds: 20_000_000)
        let finalSnapshot = await fixture.core.snapshot()
        XCTAssertEqual(finalSnapshot.releaseAttemptCount, 1)
    }

    func testUnexpectedInitialLateLeaseFailureStopsRetryAndReleasesSlot() async throws {
        let cleanupOwner = MediaCaptureLeaseCleanupOwner(retryDelayNanoseconds: 2_000_000)
        let fixture = try await makeReadyFixture(
            enabled: [.photo],
            cleanupOwner: cleanupOwner,
            settleTimeoutNanoseconds: 2_000_000
        )
        fixture.coordinator.takePhoto()
        let previewReady = await eventually {
            await fixture.core.snapshot().previewAttachGenerations.count == 1
        }
        XCTAssertTrue(previewReady)
        let confirmGate = AsyncTestGate()
        await fixture.core.configureConfirmGate(confirmGate)
        await fixture.core.configureReleaseFailureSequence([.unexpected])
        fixture.coordinator.confirm()
        let confirmStarted = await eventually {
            await fixture.core.snapshot().confirmAttemptCount == 1
        }
        XCTAssertTrue(confirmStarted)

        fixture.coordinator.ownerWasDestroyed()
        _ = await fixture.coordinator.awaitResult()
        confirmGate.release()

        let settled = await eventually {
            let snapshot = await fixture.core.snapshot()
            return fixture.slotReleaseCount() == 1 && snapshot.releaseAttemptCount == 1
        }
        XCTAssertTrue(settled)
        try? await Task.sleep(nanoseconds: 20_000_000)
        let finalSnapshot = await fixture.core.snapshot()
        XCTAssertEqual(finalSnapshot.releaseAttemptCount, 1)
    }

    func testUnexpectedAdoptedLateLeaseFailureStopsRetryAndReleasesSlot() async throws {
        let cleanupOwner = MediaCaptureLeaseCleanupOwner(retryDelayNanoseconds: 2_000_000)
        let fixture = try await makeReadyFixture(
            enabled: [.photo],
            cleanupOwner: cleanupOwner,
            settleTimeoutNanoseconds: 2_000_000
        )
        fixture.coordinator.takePhoto()
        let previewReady = await eventually {
            await fixture.core.snapshot().previewAttachGenerations.count == 1
        }
        XCTAssertTrue(previewReady)
        let confirmGate = AsyncTestGate()
        await fixture.core.configureConfirmGate(confirmGate)
        await fixture.core.configureReleaseFailureSequence([
            .media(.invalidState),
            .unexpected,
        ])
        fixture.coordinator.confirm()
        let confirmStarted = await eventually {
            await fixture.core.snapshot().confirmAttemptCount == 1
        }
        XCTAssertTrue(confirmStarted)

        fixture.coordinator.ownerWasDestroyed()
        _ = await fixture.coordinator.awaitResult()
        confirmGate.release()

        let settled = await eventually(attempts: 400) {
            let snapshot = await fixture.core.snapshot()
            return fixture.slotReleaseCount() == 1 && snapshot.releaseAttemptCount == 2
        }
        XCTAssertTrue(settled)
        try? await Task.sleep(nanoseconds: 20_000_000)
        let finalSnapshot = await fixture.core.snapshot()
        XCTAssertEqual(finalSnapshot.releaseAttemptCount, 2)
    }

    func testMediaReleaseCleanupRetriesOnlyInvalidState() {
        XCTAssertTrue(MediaCaptureLeaseCleanupOwner.isRetryableMediaReleaseFailure(
            MediaCaptureFailure(.invalidState)
        ))
        XCTAssertFalse(MediaCaptureLeaseCleanupOwner.isRetryableMediaReleaseFailure(
            MediaCaptureFailure(.mediaInvalid)
        ))
        XCTAssertFalse(MediaCaptureLeaseCleanupOwner.isRetryableMediaReleaseFailure(
            MediaCaptureFailure(.invalidArgument)
        ))
        XCTAssertFalse(MediaCaptureLeaseCleanupOwner.isRetryableMediaReleaseFailure(
            MediaCaptureFailure(.systemInterrupted)
        ))
    }

    func testBlockedLateLeaseReleaseDoesNotBlockResultAndKeepsSlotUntilSettled() async throws {
        let fixture = try await makeReadyFixture(
            enabled: [.photo],
            cleanupOwner: MediaCaptureLeaseCleanupOwner(retryDelayNanoseconds: 10_000_000),
            settleTimeoutNanoseconds: 2_000_000
        )
        fixture.coordinator.takePhoto()
        let previewReady = await eventually {
            await fixture.core.snapshot().previewAttachGenerations.count == 1
        }
        XCTAssertTrue(previewReady)
        let confirmGate = AsyncTestGate()
        let releaseGate = AsyncTestGate()
        await fixture.core.configureConfirmGate(confirmGate)
        await fixture.core.configureReleaseGate(releaseGate)
        fixture.coordinator.confirm()
        let confirmStarted = await eventually {
            await fixture.core.snapshot().confirmAttemptCount == 1
        }
        XCTAssertTrue(confirmStarted)

        fixture.coordinator.ownerWasDestroyed()
        let result = await fixture.coordinator.awaitResult()
        XCTAssertEqual(result, .failure(MediaCaptureFailure(.systemInterrupted)))
        confirmGate.release()
        let releaseStarted = await eventually {
            await fixture.core.snapshot().releaseAttemptCount == 1
        }
        XCTAssertTrue(releaseStarted)
        XCTAssertEqual(fixture.slotReleaseCount(), 0)

        releaseGate.release()
        let settled = await eventually {
            fixture.slotReleaseCount() == 1
        }
        XCTAssertTrue(settled)
    }

    func testAutomaticPreviewEventDuringRecordingAttachesOnce() async throws {
        let fixture = try await makeReadyFixture(enabled: [.video], mediaType: .video)
        fixture.coordinator.startRecording()
        let recordingReady = await eventually {
            await fixture.core.snapshot().startRecordingCount == 1
        }
        XCTAssertTrue(recordingReady)
        fixture.core.emit(.mediaPreviewReady(
            sessionHandle: fixture.core.sessionHandle,
            metadata: fixture.core.previewMetadata
        ))
        let previewReady = await eventually {
            await fixture.core.snapshot().previewAttachGenerations.count == 1
        }
        XCTAssertTrue(previewReady)
        fixture.coordinator.dismissByCaller()
        _ = await fixture.coordinator.awaitResult()
    }

    func testAutomaticPreviewWaitsForBlockedZoomWithoutTerminalFailure() async throws {
        let fixture = try await makeReadyFixture(enabled: [.video], mediaType: .video)
        fixture.coordinator.startRecording()
        let recordingReady = await eventually {
            await fixture.core.snapshot().startRecordingCount == 1
        }
        XCTAssertTrue(recordingReady)
        await Task.yield()
        let zoomGate = AsyncTestGate()
        await fixture.core.configureZoomGate(zoomGate)
        fixture.coordinator.updateZoom(verticalDelta: 30)
        let zoomStarted = await eventually { await fixture.core.snapshot().zoomFactors.count == 1 }
        XCTAssertTrue(zoomStarted)

        fixture.core.emit(.mediaPreviewReady(
            sessionHandle: fixture.core.sessionHandle,
            metadata: fixture.core.previewMetadata
        ))
        try? await Task.sleep(nanoseconds: 10_000_000)
        let previewCountBeforeZoomSettles = await fixture.core.snapshot().previewAttachGenerations.count
        XCTAssertEqual(previewCountBeforeZoomSettles, 0)
        zoomGate.release()
        let previewReady = await eventually {
            await fixture.core.snapshot().previewAttachGenerations.count == 1
        }
        XCTAssertTrue(previewReady)
        fixture.coordinator.dismissByCaller()
        let result = await fixture.coordinator.awaitResult()
        XCTAssertEqual(result, .cancelled)
    }

    func testEventOperationTimeoutCancelsParentSubscription() async throws {
        let fixture = try await makeReadyFixture(
            enabled: [.video],
            mediaType: .video,
            settleTimeoutNanoseconds: 2_000_000
        )
        fixture.coordinator.startRecording()
        let recordingReady = await eventually {
            await fixture.core.snapshot().startRecordingCount == 1
        }
        XCTAssertTrue(recordingReady)
        let actionReady = await eventually {
            fixture.coordinator.actionTransactionAvailable
        }
        XCTAssertTrue(actionReady)
        let zoomGate = AsyncTestGate()
        await fixture.core.configureZoomGate(zoomGate)
        fixture.coordinator.updateZoom(verticalDelta: 30)
        let zoomStarted = await eventually {
            await fixture.core.snapshot().zoomFactors.count == 1
        }
        XCTAssertTrue(zoomStarted)

        fixture.core.emit(.mediaPreviewReady(
            sessionHandle: fixture.core.sessionHandle,
            metadata: fixture.core.previewMetadata
        ))
        let result = await fixture.coordinator.awaitResult()

        XCTAssertEqual(result, .failure(MediaCaptureFailure(.systemInterrupted)))
        let subscriptionEnded = await eventually {
            await fixture.core.snapshot().eventTerminationCount == 1
        }
        XCTAssertTrue(subscriptionEnded)
        zoomGate.release()
    }

    func testUnsupportedFocusDoesNotCallCore() async throws {
        let fixture = try await makeReadyFixture(enabled: [.photo])
        fixture.core.emit(.sessionReady(SessionReadySnapshot(
            sessionHandle: fixture.core.sessionHandle,
            activeCamera: .rear,
            availableCameras: [.rear],
            switchCameraSupported: false,
            supportedFlashModes: [.off],
            focusPointSupported: false,
            minimumZoomFactor: 1,
            maximumZoomFactor: 1
        )))
        let snapshotApplied = await eventually {
            await fixture.core.snapshot().liveAttachGenerations.count == 2
        }
        XCTAssertTrue(snapshotApplied)

        XCTAssertFalse(fixture.coordinator.focus(normalizedX: 0.5, normalizedY: 0.5))
        let focusCount = await fixture.core.snapshot().focusCount
        XCTAssertEqual(focusCount, 0)
        fixture.coordinator.dismissByCaller()
        _ = await fixture.coordinator.awaitResult()
    }

    func testStartPermissionFailureIsNotReportedAsCancellation() async throws {
        let failure = MediaCaptureFailure(.permissionDenied)
        let core = try FakeMediaCaptureService(startFailure: failure)
        let completion = MediaCaptureFlowCompletion()
        let releaseCounter = LockedCounter()
        let coordinator = MediaCaptureFlowCoordinator(
            core: core,
            configuration: MediaCaptureUiConfiguration(sessionOptions: try makeSessionOptions([.photo])),
            initialSurfaceGeneration: 1,
            completion: completion,
            releasePresentationSlot: { releaseCounter.increment() }
        )
        coordinator.beginIfNeeded()

        let result = await coordinator.awaitResult()

        XCTAssertEqual(result, .failure(failure))
        let snapshot = await core.snapshot()
        XCTAssertEqual(snapshot.cancelCount, 0)
        XCTAssertEqual(releaseCounter.value(), 1)
    }

    func testDuplicatePreviewEventAttachesOnlyOnce() async throws {
        let fixture = try await makeReadyFixture(enabled: [.video], mediaType: .video)
        let event = MediaCaptureEvent.mediaPreviewReady(
            sessionHandle: fixture.core.sessionHandle,
            metadata: fixture.core.previewMetadata
        )

        fixture.core.emit(event)
        fixture.core.emit(event)
        let previewReady = await eventually {
            await fixture.core.snapshot().previewAttachGenerations.count == 1
        }
        XCTAssertTrue(previewReady)
        try? await Task.sleep(nanoseconds: 20_000_000)
        let snapshot = await fixture.core.snapshot()
        XCTAssertEqual(snapshot.previewAttachGenerations.count, 1)
        fixture.coordinator.dismissByCaller()
        _ = await fixture.coordinator.awaitResult()
    }

    func testViewControllerDeinitTriggersSystemInterruptionCleanup() async throws {
        let core = try FakeMediaCaptureService()
        let completion = MediaCaptureFlowCompletion()
        let releaseCounter = LockedCounter()
        let coordinator = MediaCaptureFlowCoordinator(
            core: core,
            configuration: MediaCaptureUiConfiguration(sessionOptions: try makeSessionOptions([.photo])),
            initialSurfaceGeneration: 2,
            completion: completion,
            releasePresentationSlot: { releaseCounter.increment() }
        )
        var viewController: MediaCaptureViewController? = MediaCaptureViewController(
            coordinator: coordinator
        )
        let weakViewController = WeakBox(viewController)
        if let viewController {
            coordinator.install(viewController: viewController)
            viewController.loadViewIfNeeded()
        }
        coordinator.beginIfNeeded()
        let started = await eventually { await core.snapshot().startCount == 1 }
        XCTAssertTrue(started)

        viewController = nil

        XCTAssertNil(weakViewController.value)
        let result = await coordinator.awaitResult()
        XCTAssertEqual(result, .failure(MediaCaptureFailure(.systemInterrupted)))
        let snapshot = await core.snapshot()
        XCTAssertEqual(snapshot.cancelCount, 1)
        XCTAssertEqual(releaseCounter.value(), 1)
    }

    func testPresentationRegistryRejectsConcurrentOwnerAndAdvancesGeneration() throws {
        let owner = UIViewController()
        let first = try MediaCapturePresentationRegistry.acquire(owner: owner)

        XCTAssertThrowsError(try MediaCapturePresentationRegistry.acquire(owner: owner))
        MediaCapturePresentationRegistry.release(
            ownerIdentifier: first.ownerIdentifier,
            token: UUID()
        )
        XCTAssertThrowsError(try MediaCapturePresentationRegistry.acquire(owner: owner))

        MediaCapturePresentationRegistry.release(
            ownerIdentifier: first.ownerIdentifier,
            token: first.token
        )
        let second = try MediaCapturePresentationRegistry.acquire(owner: owner)
        XCTAssertGreaterThan(second.generation, first.generation)
        MediaCapturePresentationRegistry.release(
            ownerIdentifier: second.ownerIdentifier,
            token: second.token
        )
    }

    func testCancellableCompletionCancelledBeforeWaiterRegistrationRunsCleanup() async {
        let completion = MediaCaptureFlowCompletion()
        let cancellationCounter = LockedCounter()
        let resultTask = Task {
            try await completion.cancellableValue(onCancel: {
                cancellationCounter.increment()
            })
        }

        resultTask.cancel()

        do {
            _ = try await resultTask.value
            XCTFail("Cancellation before waiter registration must throw CancellationError")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(cancellationCounter.value(), 1)
        XCTAssertEqual(completion.cancellableWaiterCount, 0)
    }

    func testCancellableCompletionReturnsExistingResultToCancelledCaller() async throws {
        let completion = MediaCaptureFlowCompletion()
        let cancellationCounter = LockedCounter()
        XCTAssertTrue(completion.complete(.cancelled))
        let resultTask = Task {
            try await completion.cancellableValue(onCancel: {
                cancellationCounter.increment()
            })
        }

        resultTask.cancel()

        let result = try await resultTask.value
        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(cancellationCounter.value(), 0)
        XCTAssertEqual(completion.cancellableWaiterCount, 0)
    }

    func testCancellingOneCompletionWaiterDoesNotRemoveAnotherWaiter() async throws {
        let completion = MediaCaptureFlowCompletion()
        let cancellationCounter = LockedCounter()
        let firstTask = Task {
            try await completion.cancellableValue(onCancel: {
                cancellationCounter.increment()
            })
        }
        let secondTask = Task {
            try await completion.cancellableValue(onCancel: {
                cancellationCounter.increment()
            })
        }
        let bothRegistered = await eventually {
            completion.cancellableWaiterCount == 2
        }
        XCTAssertTrue(bothRegistered)

        firstTask.cancel()

        do {
            _ = try await firstTask.value
            XCTFail("The cancelled waiter must throw CancellationError")
        } catch is CancellationError {
        }
        let firstRemoved = await eventually {
            completion.cancellableWaiterCount == 1
        }
        XCTAssertTrue(firstRemoved)
        XCTAssertEqual(cancellationCounter.value(), 1)

        let expectedResult = MediaCaptureFlowResult.failure(
            MediaCaptureFailure(.systemInterrupted)
        )
        XCTAssertTrue(completion.complete(expectedResult))
        let secondResult = try await secondTask.value
        XCTAssertEqual(secondResult, expectedResult)
        XCTAssertEqual(completion.cancellableWaiterCount, 0)
    }

    private func makeReadyFixture(
        enabled: Set<MediaType>,
        mediaType: MediaType = .photo,
        cleanupOwner: MediaCaptureLeaseCleanupOwner = .shared,
        settleTimeoutNanoseconds: UInt64 = 5_000_000_000,
        devicePointConverter: MediaCaptureDevicePointConverter? = nil
    ) async throws -> CoordinatorFixture {
        let core = try FakeMediaCaptureService(mediaType: mediaType)
        let fixture = try await makeStartedFixture(
            core: core,
            enabled: enabled,
            cleanupOwner: cleanupOwner,
            settleTimeoutNanoseconds: settleTimeoutNanoseconds,
            devicePointConverter: devicePointConverter
        )
        core.emit(.sessionReady(makeReadySnapshot(sessionHandle: core.sessionHandle)))
        let livePreviewReady = await eventually {
            await core.snapshot().liveAttachGenerations.count == 1
        }
        XCTAssertTrue(livePreviewReady)
        let actionReady = await eventually {
            fixture.coordinator.actionTransactionAvailable
        }
        XCTAssertTrue(actionReady)
        return fixture
    }

    private func makeStartedFixture(
        core: FakeMediaCaptureService,
        enabled: Set<MediaType>,
        cleanupOwner: MediaCaptureLeaseCleanupOwner = .shared,
        settleTimeoutNanoseconds: UInt64 = 5_000_000_000,
        devicePointConverter: MediaCaptureDevicePointConverter? = nil
    ) async throws -> CoordinatorFixture {
        let options = try makeSessionOptions(enabled)
        let releaseCounter = LockedCounter()
        let completion = MediaCaptureFlowCompletion()
        let coordinator = MediaCaptureFlowCoordinator(
            core: core,
            configuration: MediaCaptureUiConfiguration(sessionOptions: options),
            initialSurfaceGeneration: 10,
            completion: completion,
            leaseCleanupOwner: cleanupOwner,
            settleTimeoutNanoseconds: settleTimeoutNanoseconds,
            releasePresentationSlot: { releaseCounter.increment() }
        )
        let viewController = MediaCaptureViewController(
            coordinator: coordinator,
            devicePointConverter: devicePointConverter
        )
        coordinator.install(viewController: viewController)
        viewController.loadViewIfNeeded()
        coordinator.beginIfNeeded()
        let sessionStarted = await eventually { await core.snapshot().startCount == 1 }
        XCTAssertTrue(sessionStarted)
        return CoordinatorFixture(
            core: core,
            coordinator: coordinator,
            viewController: viewController,
            slotReleaseCount: releaseCounter.value
        )
    }
}

private func makeSessionOptions(_ enabled: Set<MediaType>) throws -> SessionOptions {
    try SessionOptions(
        enabledMediaTypes: enabled,
        audioEnabled: false,
        maxVideoDurationMilliseconds: 5_000
    )
}

@MainActor
private struct CoordinatorFixture {
    let core: FakeMediaCaptureService
    let coordinator: MediaCaptureFlowCoordinator
    let viewController: MediaCaptureViewController
    let slotReleaseCount: () -> Int
}

private func makeReadySnapshot(sessionHandle: SessionHandle) -> SessionReadySnapshot {
    SessionReadySnapshot(
        sessionHandle: sessionHandle,
        activeCamera: .rear,
        availableCameras: [.rear, .front],
        switchCameraSupported: true,
        supportedFlashModes: [.off, .on, .auto],
        focusPointSupported: true,
        minimumZoomFactor: 1,
        maximumZoomFactor: 4
    )
}

@MainActor
private func eventually(
    attempts: Int = 200,
    _ predicate: @MainActor () async -> Bool
) async -> Bool {
    for _ in 0 ..< attempts {
        if await predicate() { return true }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return false
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: () -> Int {
        { [weak self] in
            guard let self else { return 0 }
            lock.lock()
            defer { lock.unlock() }
            return count
        }
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

private final class WeakBox<Value: AnyObject> {
    weak var value: Value?

    init(_ value: Value?) {
        self.value = value
    }
}
