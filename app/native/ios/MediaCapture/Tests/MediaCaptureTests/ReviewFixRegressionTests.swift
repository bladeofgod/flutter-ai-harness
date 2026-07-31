@preconcurrency import AVFoundation
import CoreGraphics
import ImageIO
import MobileCoreServices
import XCTest
@testable import MediaCapture

final class ReviewFixRegressionTests: XCTestCase {
    func testOperationCompletionIsExactlyOnce() async throws {
        let completion = OperationCompletion<Int>()
        XCTAssertTrue(completion.resolve(.success(7)))
        XCTAssertFalse(completion.resolve(.failure(PlatformFailure.interrupted)))
        let value = try await completion.value()
        XCTAssertEqual(value, 7)
    }

    func testProductionCancellableAwaiterWaitsForBottomCompletionBeforeCancellation() async throws {
        let completion = OperationCompletion<Int>()
        let cancellation = CancellationSignal()
        let finished = LockedFlag()
        let task = Task {
            defer { finished.set() }
            return try await CancellableOperationAwaiter.value(completion) {
                cancellation.cancel()
            }
        }
        task.cancel()
        let cancellationRequested = await waitUntil { cancellation.isCancelled }
        XCTAssertTrue(cancellationRequested)
        await Task.yield()
        XCTAssertFalse(finished.value)
        XCTAssertTrue(completion.resolve(.success(9)))
        do {
            _ = try await task.value
            XCTFail("Cancellation must win after the bottom operation completes")
        } catch is CancellationError {
        }
        XCTAssertTrue(finished.value)
        XCTAssertFalse(completion.resolve(.success(10)))
    }

    func testProductionPhotoDelegateCancellationWaitsForFinalCaptureCallback() async throws {
        let delegate = PhotoCaptureDelegate(identifier: UUID())
        let cancellation = CancellationSignal()
        let finished = LockedFlag()
        let task = Task {
            defer { finished.set() }
            return try await delegate.value {
                cancellation.cancel()
                delegate.requestCancellation()
            }
        }
        task.cancel()
        let cancellationRequested = await waitUntil { cancellation.isCancelled }
        XCTAssertTrue(cancellationRequested)
        await Task.yield()
        XCTAssertFalse(finished.value)
        delegate.recordProcessedResult(.success(CapturedPhoto(encodedData: Data([1]))))
        delegate.finishCapture(error: nil)
        do {
            _ = try await task.value
            XCTFail("Photo cancellation must win after final capture callback")
        } catch is CancellationError {
        }
    }

    func testProductionMovieDelegateCancellationWaitsForFinalRecordingCallback() async throws {
        let delegate = MovieCaptureDelegate()
        let cancellation = CancellationSignal()
        let finished = LockedFlag()
        let task = Task {
            defer { finished.set() }
            return try await delegate.value {
                cancellation.cancel()
            }
        }
        task.cancel()
        let cancellationRequested = await waitUntil { cancellation.isCancelled }
        XCTAssertTrue(cancellationRequested)
        await Task.yield()
        XCTAssertFalse(finished.value)
        delegate.finishRecording(error: nil)
        do {
            try await task.value
            XCTFail("Movie cancellation must win after final recording callback")
        } catch is CancellationError {
        }
    }

    func testProductionExportCancellationWaitsForExportCompletion() async throws {
        let cancellation = CancellationSignal()
        let finished = LockedFlag()
        let operation = CancellableExportOperation {
            cancellation.cancel()
        }
        let task = Task {
            defer { finished.set() }
            try await operation.value()
        }
        task.cancel()
        let cancellationRequested = await waitUntil { cancellation.isCancelled }
        XCTAssertTrue(cancellationRequested)
        await Task.yield()
        XCTAssertFalse(finished.value)
        XCTAssertTrue(operation.resolve(.success(())))
        do {
            try await task.value
            XCTFail("Export cancellation must win after export completion")
        } catch is CancellationError {
        }
        XCTAssertFalse(operation.resolve(.success(())))
    }

    func testAVFoundationCloseExplicitlyRemovesObservers() async {
        let platform = AVFoundationCapturePlatform()
        XCTAssertEqual(platform.registeredObserverCount(), 2)
        await platform.close()
        XCTAssertEqual(platform.registeredObserverCount(), 0)
    }

    func testSecureGeneratorProducesUniqueOpaqueHandles() throws {
        let generator = SecureHandleGenerator()
        let values = try Set((0 ..< 512).map { _ in try generator.nextHandle() })
        XCTAssertEqual(values.count, 512)
        XCTAssertTrue(values.allSatisfy { !$0.isEmpty && $0.utf8.count <= 128 })
        XCTAssertTrue(values.allSatisfy { value in
            value.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
            }
        })
    }

    func testControlRaceCannotReviveCancelledSession() async throws {
        let fixture = CoreFixture()
        let session = try await fixture.startReadySession()
        let gate = TestAsyncGate()
        await fixture.platform.configureFlash(gate: gate, failure: nil)
        let control = Task {
            try await fixture.core.setFlashMode(sessionHandle: session, mode: .on)
        }
        let controlStarted = await waitUntil { await fixture.platform.hasStartedFlashCall }
        XCTAssertTrue(controlStarted)
        _ = try await fixture.core.cancel(sessionHandle: session)
        gate.release()
        do {
            _ = try await control.value
            XCTFail("Cancelled session must not be revived by a stale control result")
        } catch let failure as MediaCaptureFailure {
            XCTAssertEqual(failure.id, .invalidState)
        }
        let repeatedCancel = try await fixture.core.cancel(sessionHandle: session)
        XCTAssertEqual(repeatedCancel, session)
        await fixture.core.close()
    }

    func testControlFailureIsMappedToOperationAllowlistAndTerminatesSession() async throws {
        let fixture = CoreFixture()
        let session = try await fixture.startReadySession()
        await fixture.platform.configureFlash(gate: nil, failure: .resourceInUse)
        let failure = await captureFailure {
            _ = try await fixture.core.setFlashMode(sessionHandle: session, mode: .on)
        }
        XCTAssertEqual(failure?.id, .systemInterrupted)
        let cancelFailure = await captureFailure {
            _ = try await fixture.core.cancel(sessionHandle: session)
        }
        XCTAssertEqual(cancelFailure?.id, .invalidState)
        await fixture.core.close()
    }

    @MainActor
    func testConfirmRaceCannotOverwriteConcurrentCancellation() async throws {
        let fixture = CoreFixture()
        let session = try await fixture.startReadySession(mediaTypes: [.photo])
        let preview = try await fixture.core.takePhoto(sessionHandle: session)
        let target = FakeRenderTarget(ownerGeneration: 1)
        _ = try await fixture.core.attachUnconfirmedPreviewRender(
            mediaHandle: preview.mediaHandle,
            surfaceOwner: target.surfaceOwner
        )
        let binding = try XCTUnwrap(target.bindings.first)
        let gate = TestAsyncGate()
        binding.revokeGate = gate
        let confirm = Task {
            try await fixture.core.confirm(mediaHandle: preview.mediaHandle)
        }
        let revokeStarted = await waitUntil {
            await MainActor.run { binding.revokeStarted }
        }
        XCTAssertTrue(revokeStarted)
        let cancellation = Task {
            try await fixture.core.cancel(sessionHandle: session)
        }
        gate.release()
        let cancelled = try await cancellation.value
        XCTAssertEqual(cancelled, session)
        do {
            _ = try await confirm.value
            XCTFail("Stale confirm must not overwrite cancellation")
        } catch let failure as MediaCaptureFailure {
            XCTAssertEqual(failure.id, .invalidState)
        }
        await fixture.core.close()
    }

    func testInvalidReadySnapshotDoesNotExposeEncodingFailure() async throws {
        let fixture = CoreFixture()
        await fixture.platform.useInvalidReadySnapshot()
        let stream = await fixture.core.events()
        let created = try await fixture.core.startSession(options: SessionOptions(
            enabledMediaTypes: [.photo],
            audioEnabled: false,
            maxVideoDurationMilliseconds: 1_000
        ))
        for await event in stream {
            if case let .sessionFailed(handle, failure) = event,
               handle == created.sessionHandle {
                XCTAssertEqual(failure.id, .systemInterrupted)
                break
            }
        }
        await fixture.core.close()
    }

    func testUnavailableCameraPreservesUnsupportedCapability() async throws {
        let fixture = CoreFixture()
        await fixture.platform.configurePrepareFailure(.unsupported)
        let stream = await fixture.core.events()
        let created = try await fixture.core.startSession(options: try testSessionOptions())
        for await event in stream {
            if case let .sessionFailed(handle, failure) = event,
               handle == created.sessionHandle {
                XCTAssertEqual(failure.id, .unsupportedCapability)
                break
            }
        }
        await fixture.core.close()
    }

    func testNewSessionIsRejectedUntilConfirmTeardownCompletes() async throws {
        let fixture = CoreFixture()
        let session = try await fixture.startReadySession(mediaTypes: [.photo])
        let preview = try await fixture.core.takePhoto(sessionHandle: session)
        let gate = TestAsyncGate()
        await fixture.platform.configureStopSession(gate)
        let confirm = Task {
            try await fixture.core.confirm(mediaHandle: preview.mediaHandle)
        }
        let stopStarted = await waitUntil { await fixture.platform.stopSessionStarted }
        XCTAssertTrue(stopStarted)
        await assertStartRejectedDuringTeardown(fixture)
        gate.release()
        _ = try await confirm.value
        _ = try await fixture.startReadySession(mediaTypes: [.photo])
        await fixture.core.close()
    }

    func testNewSessionIsRejectedUntilCancelTeardownCompletes() async throws {
        let fixture = CoreFixture()
        let session = try await fixture.startReadySession(mediaTypes: [.photo])
        let gate = TestAsyncGate()
        await fixture.platform.configureStopSession(gate)
        let cancellation = Task {
            try await fixture.core.cancel(sessionHandle: session)
        }
        let stopStarted = await waitUntil { await fixture.platform.stopSessionStarted }
        XCTAssertTrue(stopStarted)
        await assertStartRejectedDuringTeardown(fixture)
        gate.release()
        _ = try await cancellation.value
        _ = try await fixture.startReadySession(mediaTypes: [.photo])
        await fixture.core.close()
    }

    func testNewSessionIsRejectedUntilFailureTeardownCompletes() async throws {
        let fixture = CoreFixture()
        let session = try await fixture.startReadySession(mediaTypes: [.photo])
        let stream = await fixture.core.events()
        let failureEvent = Task<MediaCaptureFailure?, Never> {
            for await event in stream {
                if case let .sessionFailed(handle, failure) = event, handle == session {
                    return failure
                }
            }
            return nil
        }
        let gate = TestAsyncGate()
        await fixture.platform.configureStopSession(gate)
        fixture.platform.interrupt()
        let stopStarted = await waitUntil { await fixture.platform.stopSessionStarted }
        XCTAssertTrue(stopStarted)
        await assertStartRejectedDuringTeardown(fixture)
        gate.release()
        let deliveredFailure = await failureEvent.value
        XCTAssertEqual(deliveredFailure?.id, .systemInterrupted)
        _ = try await fixture.startReadySession(mediaTypes: [.photo])
        await fixture.core.close()
    }

    func testNewSessionIsRejectedUntilRestartTeardownCompletes() async throws {
        let fixture = CoreFixture()
        _ = try await fixture.startReadySession(mediaTypes: [.photo])
        let gate = TestAsyncGate()
        await fixture.platform.configureStopSession(gate)
        let restart = Task { await fixture.core.appRestarted() }
        let stopStarted = await waitUntil { await fixture.platform.stopSessionStarted }
        XCTAssertTrue(stopStarted)
        await assertStartRejectedDuringTeardown(fixture)
        gate.release()
        await restart.value
        _ = try await fixture.startReadySession(mediaTypes: [.photo])
        await fixture.core.close()
    }

    func testRecordingCancellationDiscardsPartialDestination() async throws {
        let fixture = CoreFixture()
        let session = try await fixture.startReadySession(mediaTypes: [.video])
        _ = try await fixture.core.startRecording(sessionHandle: session)
        _ = try await fixture.core.cancel(sessionHandle: session)
        let discardedCount = await fixture.files.discardedRecordings.count
        XCTAssertEqual(discardedCount, 1)
        await fixture.core.close()
    }

    func testProductionFileStorePhysicallyDeletesMediaAndPartialRecording() async throws {
        let store = AppleMediaFileStore()
        await store.removeTemporaryResidue()
        let stored = try await store.storePhoto(CapturedPhoto(
            encodedData: try makeProductionJPEG()
        ))
        let source = try await store.openSource(stored.reference)
        let mediaURL = try XCTUnwrap(source.fileURL)
        source.close()
        XCTAssertTrue(FileManager.default.fileExists(atPath: mediaURL.path))
        await store.delete(stored.reference)
        XCTAssertFalse(FileManager.default.fileExists(atPath: mediaURL.path))

        let recordingURL = try await store.recordingDestination()
        try Data([1, 2, 3]).write(to: recordingURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recordingURL.path))
        await store.discardRecording(at: recordingURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordingURL.path))
        await store.removeTemporaryResidue()
    }

    func testReadGraceRevokesBlockingReadBeforeDeletionEvent() async throws {
        let fixture = CoreFixture(configuration: MediaCaptureConfiguration(
            previewTimeToLive: 10,
            mediaLeaseTimeToLive: 20,
            readGracePeriod: 2,
            tombstoneTimeToLive: 3
        ))
        let confirmed = try await fixture.confirmedPhoto()
        let backend = BlockingSourceBackend()
        await fixture.files.useReadBackend(backend)
        let read = Task {
            try await fixture.core.withMediaRead(mediaHandle: confirmed.metadata.mediaHandle) {
                try await $0.readAll()
            }
        }
        let readStarted = await waitUntil { backend.didStartReading }
        XCTAssertTrue(readStarted)
        _ = try await fixture.core.releaseMedia(mediaHandle: confirmed.metadata.mediaHandle)
        fixture.clock.advance(by: 2)
        await fixture.core.processDeadlines()
        XCTAssertTrue(backend.isClosed)
        do {
            _ = try await read.value
            XCTFail("Read must be revoked at grace expiry")
        } catch let failure as MediaCaptureFailure {
            XCTAssertEqual(failure.id, .invalidState)
        }
        await fixture.core.close()
    }

    func testReleaseDuringSourceOpenRejectsLateReadAndClosesSource() async throws {
        let fixture = CoreFixture()
        let confirmed = try await fixture.confirmedPhoto()
        let backend = BlockingSourceBackend()
        let openGate = TestAsyncGate()
        await fixture.files.useReadBackend(backend)
        await fixture.files.blockSourceOpen(on: openGate)

        let read = Task {
            await captureFailure {
                _ = try await fixture.core.withMediaRead(
                    mediaHandle: confirmed.metadata.mediaHandle
                ) { _ in () }
            }
        }
        let openStarted = await waitUntil { await fixture.files.openSourceStarted }
        XCTAssertTrue(openStarted)

        _ = try await fixture.core.releaseMedia(mediaHandle: confirmed.metadata.mediaHandle)
        openGate.release()

        let failure = await read.value
        XCTAssertEqual(failure?.id, .invalidState)
        XCTAssertTrue(backend.isClosed)
        await fixture.core.close()
    }

    func testLeaseExpiryDuringSourceOpenRejectsLateReadAndClosesSource() async throws {
        let fixture = CoreFixture(configuration: MediaCaptureConfiguration(
            previewTimeToLive: 10,
            mediaLeaseTimeToLive: 2,
            readGracePeriod: 2,
            tombstoneTimeToLive: 3
        ))
        let confirmed = try await fixture.confirmedPhoto()
        let backend = BlockingSourceBackend()
        let openGate = TestAsyncGate()
        await fixture.files.useReadBackend(backend)
        await fixture.files.blockSourceOpen(on: openGate)

        let read = Task {
            await captureFailure {
                _ = try await fixture.core.withMediaRead(
                    mediaHandle: confirmed.metadata.mediaHandle
                ) { _ in () }
            }
        }
        let openStarted = await waitUntil { await fixture.files.openSourceStarted }
        XCTAssertTrue(openStarted)

        fixture.clock.advance(by: 2)
        openGate.release()

        let failure = await read.value
        XCTAssertEqual(failure?.id, .invalidState)
        XCTAssertTrue(backend.isClosed)
        await fixture.core.close()
    }

    func testProductionFileHandleSerializesReadAndClose() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data(repeating: 0x2a, count: 2 * 1_024 * 1_024).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let backend = try FileHandleSourceBackend(url: url)
        let started = LockedFlag()
        let read = Task {
            do {
                while let chunk = try backend.readChunk(maximumLength: 1) {
                    started.set()
                    if chunk.isEmpty { return false }
                }
                return true
            } catch let failure as MediaCaptureFailure {
                return failure.id == .invalidState
            } catch {
                return false
            }
        }
        let readStarted = await waitUntil { started.value }
        XCTAssertTrue(readStarted)
        backend.close()
        let readWasSerialized = await read.value
        XCTAssertTrue(readWasSerialized)
        XCTAssertThrowsError(try backend.readChunk(maximumLength: 1)) { error in
            XCTAssertEqual((error as? MediaCaptureFailure)?.id, .invalidState)
        }
    }

    func testDeadlineTasksAreRemovedAtTerminalCleanup() async throws {
        let fixture = CoreFixture(configuration: MediaCaptureConfiguration(
            previewTimeToLive: 2,
            mediaLeaseTimeToLive: 4,
            readGracePeriod: 2,
            tombstoneTimeToLive: 2
        ))
        let session = try await fixture.startReadySession(mediaTypes: [.photo])
        _ = try await fixture.core.takePhoto(sessionHandle: session)
        let scheduledCount = await fixture.core.pendingDeadlineTaskCount()
        XCTAssertEqual(scheduledCount, 1)
        _ = try await fixture.core.cancel(sessionHandle: session)
        let terminalCount = await fixture.core.pendingDeadlineTaskCount()
        XCTAssertEqual(terminalCount, 0)
        await fixture.core.close()
    }
}

private extension FakeCapturePlatform {
    func configureFlash(gate: TestAsyncGate?, failure: PlatformFailure?) {
        flashGate = gate
        flashFailure = failure
    }

    var hasStartedFlashCall: Bool { flashCallStarted }

    func useInvalidReadySnapshot() {
        invalidReadySnapshot = true
    }

    func configurePrepareFailure(_ failure: PlatformFailure?) {
        prepareFailure = failure
    }

    func configureStopSession(_ gate: TestAsyncGate?) {
        stopSessionGate = gate
        stopSessionStarted = false
    }
}

private func testSessionOptions() throws -> SessionOptions {
    try SessionOptions(
        enabledMediaTypes: [.photo],
        audioEnabled: false,
        maxVideoDurationMilliseconds: 1_000
    )
}

private func assertStartRejectedDuringTeardown(_ fixture: CoreFixture) async {
    let failure = await captureFailure {
        _ = try await fixture.core.startSession(options: try testSessionOptions())
    }
    XCTAssertEqual(failure?.id, .resourceInUse)
}

private func makeProductionJPEG() throws -> Data {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil,
              width: 8,
              height: 8,
              bitsPerComponent: 8,
              bytesPerRow: 8 * 4,
              space: colorSpace,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ),
          let image = context.makeImage()
    else {
        throw MediaCaptureFailure(.encodingFailed)
    }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, kUTTypeJPEG, 1, nil) else {
        throw MediaCaptureFailure(.encodingFailed)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw MediaCaptureFailure(.encodingFailed)
    }
    return data as Data
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = false

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func set() {
        lock.lock()
        storedValue = true
        lock.unlock()
    }
}

private extension FakeMediaFileStore {
    func useReadBackend(_ backend: any MediaSourceBackend) {
        readBackend = backend
    }

    func blockSourceOpen(on gate: TestAsyncGate) {
        openSourceGate = gate
    }
}
