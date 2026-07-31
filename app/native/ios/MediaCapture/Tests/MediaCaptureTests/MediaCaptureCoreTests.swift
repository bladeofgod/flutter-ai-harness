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
        let preview = try await fixture.core.stopRecording(sessionHandle: session)
        let repeatedStop = try await fixture.core.stopRecording(sessionHandle: session)
        XCTAssertEqual(preview.mediaType, .video)
        XCTAssertEqual(repeatedStop, preview)
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
}
