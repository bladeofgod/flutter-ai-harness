import XCTest
@testable import MediaCapture

final class MediaCaptureCoreTests: XCTestCase {
    func testCameraPermissionIsRequestedOnlyAfterExplicitStart() async throws {
        let fixture = CoreFixture()
        await fixture.platform.setCameraPermission(.notDetermined)
        let requestedBeforeStart = await fixture.platform.requestedPermissions
        XCTAssertTrue(requestedBeforeStart.isEmpty)
        _ = try await fixture.startReadySession(mediaTypes: [.photo])
        let requested = await fixture.platform.requestedPermissions
        XCTAssertEqual(requested, [.camera])
        await fixture.core.close()
    }

    func testRestrictedPermissionProducesStableTerminalEvent() async throws {
        let fixture = CoreFixture()
        await fixture.platform.setCameraPermission(.restricted)
        let stream = await fixture.core.events()
        let created = try await fixture.core.startSession(options: SessionOptions(
            enabledMediaTypes: [.photo],
            audioEnabled: false,
            maxVideoDurationMilliseconds: 1_000
        ))
        for await event in stream {
            if case let .sessionFailed(handle, failure) = event,
               handle == created.sessionHandle {
                XCTAssertEqual(failure.id, .permissionRestricted)
                break
            }
        }
        await fixture.core.close()
    }

    func testPermanentlyDeniedPermissionProducesStableTerminalEvent() async throws {
        let fixture = CoreFixture()
        await fixture.platform.setCameraPermission(.permanentlyDenied)
        let stream = await fixture.core.events()
        let created = try await fixture.core.startSession(options: SessionOptions(
            enabledMediaTypes: [.photo],
            audioEnabled: false,
            maxVideoDurationMilliseconds: 1_000
        ))

        for await event in stream {
            if case let .sessionFailed(handle, failure) = event,
               handle == created.sessionHandle {
                XCTAssertEqual(failure.id, .permissionPermanentlyDenied)
                break
            }
        }
        await fixture.core.close()
    }

    func testPhotoFlowDoesNotRequestMicrophoneAndConfirmedReadIsCallbackScoped() async throws {
        let fixture = CoreFixture()
        let session = try await fixture.startReadySession(mediaTypes: [.photo])
        let preview = try await fixture.core.takePhoto(sessionHandle: session)
        let confirmed = try await fixture.core.confirm(mediaHandle: preview.mediaHandle)

        XCTAssertEqual(confirmed.metadata.mediaType, .photo)
        XCTAssertNil(confirmed.metadata.durationMilliseconds)
        let bytes = try await fixture.core.withMediaRead(mediaHandle: preview.mediaHandle) {
            try await $0.readAll()
        }
        XCTAssertFalse(bytes.isEmpty)
        let expiredAccess = try await fixture.core.withMediaRead(mediaHandle: preview.mediaHandle) { $0 }
        let escapedReadFailure = await captureFailure {
            _ = try await expiredAccess.readAll()
        }
        XCTAssertEqual(escapedReadFailure?.id, .invalidState)
        let requested = await fixture.platform.requestedPermissions
        XCTAssertFalse(requested.contains(.microphone))
        await fixture.core.close()
    }

    @MainActor
    func testMicrophoneIsRequestedOnlyWhenAudioRecordingStarts() async throws {
        let fixture = CoreFixture()
        await fixture.platform.setMicrophonePermission(.notDetermined)
        let session = try await fixture.startReadySession(mediaTypes: [.video], audioEnabled: true)
        let requestedBeforeRecording = await fixture.platform.requestedPermissions
        XCTAssertFalse(requestedBeforeRecording.contains(.microphone))

        let started = try await fixture.core.startRecording(sessionHandle: session)
        XCTAssertTrue(started.audioIncluded)
        let requestedAfterRecording = await fixture.platform.requestedPermissions
        XCTAssertTrue(requestedAfterRecording.contains(.microphone))
        let live = FakeRenderTarget(ownerGeneration: 1)
        _ = try await fixture.core.attachLivePreview(
            sessionHandle: session,
            surfaceOwner: live.surfaceOwner
        )
        let binding = try XCTUnwrap(live.bindings.first)
        let revokeGate = TestAsyncGate()
        binding.revokeGate = revokeGate
        let stop = Task {
            try await fixture.core.stopRecording(sessionHandle: session)
        }
        let platformStopStarted = await waitUntil {
            await fixture.platform.stopRecordingStarted
        }
        let revokeStarted = await waitUntil {
            await MainActor.run { binding.revokeStarted }
        }
        XCTAssertTrue(platformStopStarted)
        XCTAssertTrue(revokeStarted)
        revokeGate.release()
        let preview = try await stop.value
        let repeatedStop = try await fixture.core.stopRecording(sessionHandle: session)
        XCTAssertEqual(preview.mediaType, .video)
        XCTAssertEqual(repeatedStop, preview)
        let configuredAfterFirstStop = await fixture.platform.configuredRecordingAudio
        XCTAssertEqual(configuredAfterFirstStop, [true, false])
        let audioActiveAfterFirstStop = await fixture.platform.recordingAudioActive
        XCTAssertFalse(audioActiveAfterFirstStop)
        let releaseCountAfterFirstStop = await fixture.platform.recordingAudioReleaseCount
        XCTAssertEqual(releaseCountAfterFirstStop, 1)

        _ = try await fixture.core.retake(mediaHandle: preview.mediaHandle)
        _ = try await fixture.core.startRecording(sessionHandle: session)
        _ = try await fixture.core.stopRecording(sessionHandle: session)
        let configuredAfterRetake = await fixture.platform.configuredRecordingAudio
        XCTAssertEqual(configuredAfterRetake, [true, false, true, false])
        let audioActiveAfterRetake = await fixture.platform.recordingAudioActive
        XCTAssertFalse(audioActiveAfterRetake)
        let releaseCountAfterRetake = await fixture.platform.recordingAudioReleaseCount
        XCTAssertEqual(releaseCountAfterRetake, 2)
        await fixture.core.close()
    }

    func testRecordingStartFailureReleasesConfiguredMicrophoneInput() async throws {
        let fixture = CoreFixture()
        let session = try await fixture.startReadySession(mediaTypes: [.video], audioEnabled: true)
        await fixture.platform.configureStartRecordingFailure(.resourceInUse)

        let failure = await captureFailure {
            _ = try await fixture.core.startRecording(sessionHandle: session)
        }

        XCTAssertEqual(failure?.id, .resourceInUse)
        let configuredAudio = await fixture.platform.configuredRecordingAudio
        XCTAssertEqual(configuredAudio, [true, false])
        let audioActive = await fixture.platform.recordingAudioActive
        XCTAssertFalse(audioActive)
        let releaseCount = await fixture.platform.recordingAudioReleaseCount
        XCTAssertEqual(releaseCount, 1)
        await fixture.core.close()
    }

    func testCancellingRecordingStartReleasesMicrophoneInputOnce() async throws {
        let fixture = CoreFixture()
        let session = try await fixture.startReadySession(mediaTypes: [.video], audioEnabled: true)
        let startGate = TestAsyncGate()
        await fixture.platform.configureStartRecordingGate(startGate)

        let start = Task {
            try await fixture.core.startRecording(sessionHandle: session)
        }
        let startReachedPlatform = await waitUntil { await fixture.platform.startRecordingStarted }
        XCTAssertTrue(startReachedPlatform)

        start.cancel()
        startGate.release()
        do {
            _ = try await start.value
            XCTFail("Cancelled recording start must throw CancellationError")
        } catch is CancellationError {
        }

        let audioActive = await fixture.platform.recordingAudioActive
        let releaseCount = await fixture.platform.recordingAudioReleaseCount
        XCTAssertFalse(audioActive)
        XCTAssertEqual(releaseCount, 1)
        await fixture.core.close()
    }

    func testStopRecordingFailureReleasesMicrophoneInputOnce() async throws {
        let fixture = CoreFixture()
        let session = try await fixture.startReadySession(mediaTypes: [.video], audioEnabled: true)
        _ = try await fixture.core.startRecording(sessionHandle: session)
        await fixture.platform.configureStopRecording(failure: .interrupted)

        let failure = await captureFailure {
            _ = try await fixture.core.stopRecording(sessionHandle: session)
        }

        XCTAssertEqual(failure?.id, .systemInterrupted)
        let audioActive = await fixture.platform.recordingAudioActive
        let releaseCount = await fixture.platform.recordingAudioReleaseCount
        XCTAssertFalse(audioActive)
        XCTAssertEqual(releaseCount, 1)
        await fixture.core.close()
    }

    func testConcurrentCancelAndStopReleaseMicrophoneInputOnce() async throws {
        let fixture = CoreFixture()
        let session = try await fixture.startReadySession(mediaTypes: [.video], audioEnabled: true)
        _ = try await fixture.core.startRecording(sessionHandle: session)
        let stopGate = TestAsyncGate()
        await fixture.platform.configureStopRecording(gate: stopGate)

        let stop = Task {
            try await fixture.core.stopRecording(sessionHandle: session)
        }
        let stopReachedPlatform = await waitUntil { await fixture.platform.stopRecordingStarted }
        XCTAssertTrue(stopReachedPlatform)

        let cancelledSession = try await fixture.core.cancel(sessionHandle: session)
        XCTAssertEqual(cancelledSession, session)
        stopGate.release()
        let stopFailure = await captureFailure {
            _ = try await stop.value
        }

        XCTAssertEqual(stopFailure?.id, .systemInterrupted)
        let audioActive = await fixture.platform.recordingAudioActive
        let releaseCount = await fixture.platform.recordingAudioReleaseCount
        XCTAssertFalse(audioActive)
        XCTAssertEqual(releaseCount, 1)
        await fixture.core.close()
    }

    func testRetakeCommitsReadyStateBeforeAsynchronousFileDeletion() async throws {
        let fixture = CoreFixture()
        let session = try await fixture.startReadySession(mediaTypes: [.photo])
        let preview = try await fixture.core.takePhoto(sessionHandle: session)
        let deleteGate = TestAsyncGate()
        await fixture.files.configureDeleteGate(deleteGate)

        let retake = Task {
            try await fixture.core.retake(mediaHandle: preview.mediaHandle)
        }
        let deleteStarted = await waitUntil { await fixture.files.deleteStarted }
        XCTAssertTrue(deleteStarted)

        await fixture.core.displayRotationChanged()
        let nextPreview = try await fixture.core.takePhoto(sessionHandle: session)
        XCTAssertNotEqual(nextPreview.mediaHandle, preview.mediaHandle)
        let oldMediaFailure = await captureFailure {
            _ = try await fixture.core.confirm(mediaHandle: preview.mediaHandle)
        }
        XCTAssertEqual(oldMediaFailure?.id, .invalidState)

        deleteGate.release()
        let retakeSession = try await retake.value
        XCTAssertEqual(retakeSession, session)
        await fixture.core.close()
    }

    func testMutedRecordingNeverRequestsMicrophone() async throws {
        let fixture = CoreFixture()
        await fixture.platform.setMicrophonePermission(.notDetermined)
        let session = try await fixture.startReadySession(
            mediaTypes: [.video],
            audioEnabled: false
        )

        let started = try await fixture.core.startRecording(sessionHandle: session)

        XCTAssertFalse(started.audioIncluded)
        let requested = await fixture.platform.requestedPermissions
        XCTAssertFalse(requested.contains(.microphone))
        let configuredAudio = await fixture.platform.configuredRecordingAudio
        XCTAssertEqual(configuredAudio, [false])
        _ = try await fixture.core.stopRecording(sessionHandle: session)
        await fixture.core.close()
    }

    func testRecordingDeadlineAutomaticallyCreatesPreview() async throws {
        let fixture = CoreFixture()
        let session = try await fixture.startReadySession(
            mediaTypes: [.video],
            maxVideoDurationMilliseconds: 1_000
        )
        let stream = await fixture.core.events()
        let previewTask = Task { () throws -> MediaMetadata in
            for await event in stream {
                if case let .mediaPreviewReady(eventSession, metadata) = event,
                   eventSession == session {
                    return metadata
                }
            }
            throw MediaCaptureFailure(.systemInterrupted)
        }

        _ = try await fixture.core.startRecording(sessionHandle: session)
        fixture.clock.advance(by: 1)
        let stopped = await waitUntil { await fixture.platform.recording == false }
        XCTAssertTrue(stopped)
        guard stopped else {
            previewTask.cancel()
            await fixture.core.close()
            return
        }
        let preview = try await previewTask.value

        XCTAssertEqual(preview.mediaType, .video)
        let repeatedStop = try await fixture.core.stopRecording(sessionHandle: session)
        XCTAssertEqual(repeatedStop, preview)
        await fixture.core.close()
    }

    func testRetakeDeletesPreviewAndReturnsSessionToReady() async throws {
        let fixture = CoreFixture()
        let session = try await fixture.startReadySession(mediaTypes: [.photo])
        let firstPreview = try await fixture.core.takePhoto(sessionHandle: session)

        let returnedSession = try await fixture.core.retake(mediaHandle: firstPreview.mediaHandle)
        XCTAssertEqual(returnedSession, session)
        let deleted = await fixture.files.deletedReferences.count
        XCTAssertEqual(deleted, 1)

        let repeatedFailure = await captureFailure {
            _ = try await fixture.core.retake(mediaHandle: firstPreview.mediaHandle)
        }
        XCTAssertEqual(repeatedFailure?.id, .invalidState)
        let secondPreview = try await fixture.core.takePhoto(sessionHandle: session)
        XCTAssertNotEqual(secondPreview.mediaHandle, firstPreview.mediaHandle)
        await fixture.core.close()
    }

    func testSwitchCameraSucceedsAndKeepsSessionReady() async throws {
        let fixture = CoreFixture()
        let session = try await fixture.startReadySession(mediaTypes: [.photo])
        let stream = await fixture.core.events()
        let eventTask = Task<SessionReadySnapshot?, Never> {
            for await event in stream {
                if case let .sessionReady(snapshot) = event { return snapshot }
            }
            return nil
        }

        let returnedSession = try await fixture.core.switchCamera(sessionHandle: session)

        XCTAssertEqual(returnedSession, session)
        let snapshot = await eventTask.value
        XCTAssertEqual(snapshot?.activeCamera, .front)
        XCTAssertEqual(snapshot?.supportedFlashModes, [.off, .on, .auto])
        XCTAssertEqual(snapshot?.maximumZoomFactor, 3)
        let callCount = await fixture.platform.switchCameraCallCount
        XCTAssertEqual(callCount, 1)
        _ = try await fixture.core.takePhoto(sessionHandle: session)
        await fixture.core.close()
    }

    func testSwitchCameraResetsPhotoFlashModeToNewCapabilityDefault() async throws {
        let fixture = CoreFixture()
        let session = try await fixture.startReadySession(mediaTypes: [.photo])
        _ = try await fixture.core.setFlashMode(sessionHandle: session, mode: .on)

        _ = try await fixture.core.switchCamera(sessionHandle: session)
        _ = try await fixture.core.takePhoto(sessionHandle: session)

        let capturedModes = await fixture.platform.capturedPhotoFlashModes
        XCTAssertEqual(capturedModes, [.off])
        await fixture.core.close()
    }

    func testSwitchCameraCommitsSnapshotAfterCallerCancellationAtPlatformBoundary() async throws {
        let fixture = CoreFixture()
        let session = try await fixture.startReadySession(mediaTypes: [.photo])
        let stream = await fixture.core.events()
        let eventTask = Task<SessionReadySnapshot?, Never> {
            for await event in stream {
                if case let .sessionReady(snapshot) = event { return snapshot }
            }
            return nil
        }
        let gate = TestAsyncGate()
        await fixture.platform.configureSwitchCameraGate(gate)
        let operation = Task {
            try await fixture.core.switchCamera(sessionHandle: session)
        }
        let switchStarted = await waitUntil {
            await fixture.platform.switchCameraStarted
        }
        XCTAssertTrue(switchStarted)

        operation.cancel()
        gate.release()

        let returnedSession = try await operation.value
        XCTAssertEqual(returnedSession, session)
        let snapshot = await eventTask.value
        XCTAssertEqual(snapshot?.activeCamera, .front)
        XCTAssertEqual(snapshot?.supportedFlashModes, [.off, .on, .auto])
        XCTAssertEqual(snapshot?.maximumZoomFactor, 3)
        _ = try await fixture.core.takePhoto(sessionHandle: session)
        await fixture.core.close()
    }

    func testSwitchCameraCommitsSnapshotAcrossConcurrentDisplayRotation() async throws {
        let fixture = CoreFixture()
        let session = try await fixture.startReadySession(mediaTypes: [.photo])
        let stream = await fixture.core.events()
        let eventTask = Task<SessionReadySnapshot?, Never> {
            for await event in stream {
                if case let .sessionReady(snapshot) = event { return snapshot }
            }
            return nil
        }
        let gate = TestAsyncGate()
        await fixture.platform.configureSwitchCameraGate(gate)
        let operation = Task {
            try await fixture.core.switchCamera(sessionHandle: session)
        }
        let switchStarted = await waitUntil {
            await fixture.platform.switchCameraStarted
        }
        XCTAssertTrue(switchStarted)

        await fixture.core.displayRotationChanged()
        gate.release()

        let returnedSession = try await operation.value
        XCTAssertEqual(returnedSession, session)
        let snapshot = await eventTask.value
        XCTAssertEqual(snapshot?.activeCamera, .front)
        XCTAssertEqual(snapshot?.maximumZoomFactor, 3)
        _ = try await fixture.core.takePhoto(sessionHandle: session)
        await fixture.core.close()
    }

    func testSwitchCameraRejectsUnsupportedSessionWithoutCallingPlatform() async throws {
        let fixture = CoreFixture()
        await fixture.platform.setAvailableCameras([.rear])
        let session = try await fixture.startReadySession(mediaTypes: [.photo])

        let failure = await captureFailure {
            _ = try await fixture.core.switchCamera(sessionHandle: session)
        }

        XCTAssertEqual(failure?.id, .unsupportedCapability)
        let callCount = await fixture.platform.switchCameraCallCount
        XCTAssertEqual(callCount, 0)
        _ = try await fixture.core.takePhoto(sessionHandle: session)
        await fixture.core.close()
    }

    func testSingleActiveSessionAndIdempotentCancellation() async throws {
        let fixture = CoreFixture()
        let session = try await fixture.startReadySession(mediaTypes: [.photo])
        let conflict = await captureFailure {
            _ = try await fixture.core.startSession(options: SessionOptions(
                enabledMediaTypes: [.photo],
                audioEnabled: false,
                maxVideoDurationMilliseconds: 1_000
            ))
        }
        XCTAssertEqual(conflict?.id, .sessionConflict)
        let firstCancellation = try await fixture.core.cancel(sessionHandle: session)
        let repeatedCancellation = try await fixture.core.cancel(sessionHandle: session)
        XCTAssertEqual(firstCancellation, session)
        XCTAssertEqual(repeatedCancellation, session)

        _ = try await fixture.startReadySession(mediaTypes: [.photo])
        await fixture.core.close()
    }

    func testReleaseAndExpiryDenyNewReadsThenDeleteAfterGrace() async throws {
        let fixture = CoreFixture(configuration: MediaCaptureConfiguration(
            previewTimeToLive: 10,
            mediaLeaseTimeToLive: 20,
            readGracePeriod: 5,
            tombstoneTimeToLive: 3
        ))
        let confirmed = try await fixture.confirmedPhoto()
        let handle = confirmed.metadata.mediaHandle
        let firstRelease = try await fixture.core.releaseMedia(mediaHandle: handle)
        let repeatedRelease = try await fixture.core.releaseMedia(mediaHandle: handle)
        XCTAssertEqual(firstRelease, handle)
        XCTAssertEqual(repeatedRelease, handle)
        let readFailure = await captureFailure {
            _ = try await fixture.core.withMediaRead(mediaHandle: handle) { _ in 1 }
        }
        XCTAssertEqual(readFailure?.id, .invalidState)

        fixture.clock.advance(by: 5)
        await fixture.core.processDeadlines()
        let deletedAfterGrace = await fixture.files.deletedReferences.count
        XCTAssertEqual(deletedAfterGrace, 1)
        let releasedTombstone = try await fixture.core.releaseMedia(mediaHandle: handle)
        XCTAssertEqual(releasedTombstone, handle)
        fixture.clock.advance(by: 4)
        await fixture.core.processDeadlines()
        let expiredTombstone = await captureFailure {
            _ = try await fixture.core.releaseMedia(mediaHandle: handle)
        }
        XCTAssertEqual(expiredTombstone?.id, .mediaInvalid)
        await fixture.core.close()
    }

    func testReleaseDuringConfirmTeardownRetriesAfterConfirmedLeaseSettles() async throws {
        let fixture = CoreFixture()
        let session = try await fixture.startReadySession(mediaTypes: [.photo])
        let preview = try await fixture.core.takePhoto(sessionHandle: session)
        let stopGate = TestAsyncGate()
        await fixture.platform.configureStopSession(stopGate)
        let confirmation = Task {
            try await fixture.core.confirm(mediaHandle: preview.mediaHandle)
        }
        let teardownStarted = await waitUntil {
            await fixture.platform.stopSessionStarted
        }
        XCTAssertTrue(teardownStarted)

        let transientFailure = await captureFailure {
            _ = try await fixture.core.releaseMedia(mediaHandle: preview.mediaHandle)
        }
        XCTAssertEqual(transientFailure?.id, .invalidState)

        stopGate.release()
        let confirmed = try await confirmation.value
        XCTAssertEqual(confirmed.metadata.mediaHandle, preview.mediaHandle)
        let released = try await fixture.core.releaseMedia(mediaHandle: preview.mediaHandle)
        XCTAssertEqual(released, preview.mediaHandle)
        await fixture.core.close()
    }

    func testReleaseAfterRetakeIsPermanentlyInvalid() async throws {
        let fixture = CoreFixture()
        let session = try await fixture.startReadySession(mediaTypes: [.photo])
        let preview = try await fixture.core.takePhoto(sessionHandle: session)

        _ = try await fixture.core.retake(mediaHandle: preview.mediaHandle)
        let failure = await captureFailure {
            _ = try await fixture.core.releaseMedia(mediaHandle: preview.mediaHandle)
        }

        XCTAssertEqual(failure?.id, .mediaInvalid)
        await fixture.core.close()
    }

    func testReleaseDuringRestartIsTransientThenBecomesPermanentlyInvalid() async throws {
        let fixture = CoreFixture()
        let confirmed = try await fixture.confirmedPhoto()
        let stopGate = TestAsyncGate()
        await fixture.platform.configureStopSession(stopGate)
        let restart = Task { await fixture.core.appRestarted() }
        let restartStarted = await waitUntil {
            await fixture.platform.stopSessionStarted
        }
        XCTAssertTrue(restartStarted)

        let transientFailure = await captureFailure {
            _ = try await fixture.core.releaseMedia(
                mediaHandle: confirmed.metadata.mediaHandle
            )
        }
        XCTAssertEqual(transientFailure?.id, .invalidState)

        stopGate.release()
        await restart.value
        let permanentFailure = await captureFailure {
            _ = try await fixture.core.releaseMedia(
                mediaHandle: confirmed.metadata.mediaHandle
            )
        }
        XCTAssertEqual(permanentFailure?.id, .mediaInvalid)
        await fixture.core.close()
    }

    func testReleaseAfterCoreCloseIsPermanentlyInvalid() async throws {
        let fixture = CoreFixture()
        let confirmed = try await fixture.confirmedPhoto()
        await fixture.core.close()

        let failure = await captureFailure {
            _ = try await fixture.core.releaseMedia(
                mediaHandle: confirmed.metadata.mediaHandle
            )
        }
        XCTAssertEqual(failure?.id, .mediaInvalid)
    }

    func testLeaseExpiryUsesExpiryGraceWithoutRefreshingLease() async throws {
        let fixture = CoreFixture(configuration: MediaCaptureConfiguration(
            previewTimeToLive: 10,
            mediaLeaseTimeToLive: 5,
            readGracePeriod: 2,
            tombstoneTimeToLive: 3
        ))
        let confirmed = try await fixture.confirmedPhoto()
        fixture.clock.advance(by: 5)
        await fixture.core.processDeadlines()
        let failure = await captureFailure {
            _ = try await fixture.core.readMediaThumbnail(
                mediaHandle: confirmed.metadata.mediaHandle,
                maximumPixelEdge: 128
            )
        }
        XCTAssertEqual(failure?.id, .invalidState)
        let releaseFailure = await captureFailure {
            _ = try await fixture.core.releaseMedia(
                mediaHandle: confirmed.metadata.mediaHandle
            )
        }
        XCTAssertEqual(releaseFailure?.id, .mediaInvalid)
        await fixture.core.close()
    }

    func testPreviewTimeoutDeletesMediaAndFailsSession() async throws {
        let fixture = CoreFixture(configuration: MediaCaptureConfiguration(
            previewTimeToLive: 2,
            mediaLeaseTimeToLive: 10,
            readGracePeriod: 2,
            tombstoneTimeToLive: 3
        ))
        let session = try await fixture.startReadySession(mediaTypes: [.photo])
        let preview = try await fixture.core.takePhoto(sessionHandle: session)
        fixture.clock.advance(by: 2)
        await fixture.core.processDeadlines()
        let deletedAfterTimeout = await fixture.files.deletedReferences.count
        XCTAssertEqual(deletedAfterTimeout, 1)
        let failure = await captureFailure {
            _ = try await fixture.core.confirm(mediaHandle: preview.mediaHandle)
        }
        XCTAssertEqual(failure?.id, .invalidState)
        await fixture.core.close()
    }

    func testInvalidInputDoesNotChangeReadyState() async throws {
        let fixture = CoreFixture()
        let session = try await fixture.startReadySession()
        let focusFailure = await captureFailure {
            _ = try await fixture.core.setFocusPoint(
                sessionHandle: session,
                normalizedX: .nan,
                normalizedY: 0.5
            )
        }
        XCTAssertEqual(focusFailure?.id, .invalidArgument)
        _ = try await fixture.core.setZoomFactor(sessionHandle: session, factor: 2)
        await fixture.core.close()
    }

    func testPlatformInterruptionIsNotMappedToUserCancellation() async throws {
        let fixture = CoreFixture()
        let session = try await fixture.startReadySession()
        let stream = await fixture.core.events()
        fixture.platform.interrupt()
        for await event in stream {
            if case let .sessionFailed(handle, failure) = event, handle == session {
                XCTAssertEqual(failure.id, .systemInterrupted)
                break
            }
        }
        let cancelFailure = await captureFailure {
            _ = try await fixture.core.cancel(sessionHandle: session)
        }
        XCTAssertEqual(cancelFailure?.id, .invalidState)
        await fixture.core.close()
    }
}

private extension FakeCapturePlatform {
    func setCameraPermission(_ state: PermissionState) {
        cameraPermission = state
    }

    func setMicrophonePermission(_ state: PermissionState) {
        microphonePermission = state
    }

    func setAvailableCameras(_ cameras: [CameraPosition]) {
        availableCameras = cameras
    }
}
