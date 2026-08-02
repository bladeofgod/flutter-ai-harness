import Foundation
import XCTest
@testable import MediaCapture

final class MediaExportTests: XCTestCase {
    func testConfirmedJPEGStreamsInBoundedSequentialChunks() async throws {
        let fixture = ExportFixture()
        let confirmed = try await fixture.confirmedMedia(
            ExportSourceSpec(actualLength: 600_123, mediaType: .photo)
        )
        let sink = RecordingMediaCopySink()

        let result = try await fixture.core.copyConfirmedMediaToSink(
            mediaHandle: confirmed.metadata.mediaHandle,
            sink: sink,
            maximumLength: 1_000_000
        )

        XCTAssertEqual(result.mediaHandle, confirmed.metadata.mediaHandle)
        XCTAssertEqual(result.mediaType, .photo)
        XCTAssertEqual(result.contentType, "image/jpeg")
        XCTAssertEqual(result.byteLength, 600_123)
        XCTAssertEqual(sink.writtenBytes, 600_123)
        XCTAssertEqual(sink.writeCount, 5)
        XCTAssertLessThanOrEqual(sink.maximumChunkBytes, 131_072)
        XCTAssertTrue(sink.sequenceIsValid)
        XCTAssertEqual(sink.commitCount, 1)
        XCTAssertEqual(sink.abortCount, 0)
        XCTAssertEqual(fixture.executor.executionCount, 6)
        let retainedChunk = try XCTUnwrap(sink.retainedChunk)
        XCTAssertThrowsError(try retainedChunk.copyBytes()) { error in
            XCTAssertEqual((error as? MediaCaptureFailure)?.id, .invalidState)
        }
        await fixture.core.close()
    }

    func testProductionExportExecutorRunsFileWorkOffMainThread() async throws {
        let executor = DispatchMediaExportExecutor()
        let ranOnMainThread = try await executor.execute {
            Thread.isMainThread
        }
        XCTAssertFalse(ranOnMainThread)
    }

    func testConfirmedVideoExportsAsMP4() async throws {
        let fixture = ExportFixture()
        let confirmed = try await fixture.confirmedMedia(
            ExportSourceSpec(actualLength: 300_000, mediaType: .video)
        )
        let sink = RecordingMediaCopySink()

        let result = try await fixture.core.copyConfirmedMediaToSink(
            mediaHandle: confirmed.metadata.mediaHandle,
            sink: sink,
            maximumLength: 52_428_800
        )

        XCTAssertEqual(result.mediaType, .video)
        XCTAssertEqual(result.contentType, "video/mp4")
        XCTAssertEqual(result.byteLength, 300_000)
        XCTAssertTrue(sink.sequenceIsValid)
        await fixture.core.close()
    }

    func testCapacityRejectsConflictAndFifthJobBeforeOpeningSourceOrSink() async throws {
        let fixture = ExportFixture()
        var handles: [MediaHandle] = []
        for _ in 0 ..< 5 {
            let confirmed = try await fixture.confirmedMedia(
                ExportSourceSpec(actualLength: 300_000, mediaType: .photo)
            )
            handles.append(confirmed.metadata.mediaHandle)
        }
        let gate = TestAsyncGate()
        let sinks = (0 ..< 4).map { _ in RecordingMediaCopySink(writeGate: gate) }
        let exports = zip(handles.prefix(4), sinks).map { handle, sink in
            Task {
                try await fixture.core.copyConfirmedMediaToSink(
                    mediaHandle: handle,
                    sink: sink,
                    maximumLength: 52_428_800
                )
            }
        }
        let allWritesStarted = await waitUntil { sinks.allSatisfy(\.writeStarted) }
        XCTAssertTrue(allWritesStarted)
        let reservation = await fixture.core.exportReservationSnapshot()
        XCTAssertEqual(reservation.jobCount, 4)
        XCTAssertEqual(reservation.reservedWorkingBytes, 1_048_576)
        let activeBuffers = fixture.bufferTracker.snapshot
        XCTAssertLessThanOrEqual(activeBuffers.maximumJobBytes, 262_144)
        XCTAssertLessThanOrEqual(activeBuffers.maximumModuleBytes, 1_048_576)
        XCTAssertFalse(activeBuffers.accountingUnderflowed)

        let conflictSink = RecordingMediaCopySink()
        let conflict = await exportFailure {
            try await fixture.core.copyConfirmedMediaToSink(
                mediaHandle: handles[0],
                sink: conflictSink,
                maximumLength: 52_428_800
            )
        }
        XCTAssertEqual(conflict, .mediaExportConflict)
        XCTAssertEqual(conflictSink.beginCount, 0)

        let openCountBeforeOverload = await fixture.files.openCount
        let overloadSink = RecordingMediaCopySink()
        let overload = await exportFailure {
            try await fixture.core.copyConfirmedMediaToSink(
                mediaHandle: handles[4],
                sink: overloadSink,
                maximumLength: 52_428_800
            )
        }
        XCTAssertEqual(overload, .mediaExportOverloaded)
        XCTAssertEqual(overloadSink.beginCount, 0)
        let openCountAfterOverload = await fixture.files.openCount
        XCTAssertEqual(openCountAfterOverload, openCountBeforeOverload)

        gate.release()
        for export in exports {
            _ = try await export.value
        }
        let releasedBuffers = fixture.bufferTracker.snapshot
        XCTAssertEqual(releasedBuffers.activeModuleBytes, 0)
        XCTAssertFalse(releasedBuffers.accountingUnderflowed)
        await fixture.core.close()
    }

    func testLengthGuardsRejectDeclaredOversizeTruncationAndGrowth() async throws {
        let fixture = ExportFixture()
        let oversized = try await fixture.confirmedMedia(
            ExportSourceSpec(actualLength: 20_000, declaredLength: 20_000, mediaType: .photo)
        )
        let untouched = RecordingMediaCopySink()
        let openCount = await fixture.files.openCount
        await assertExportFailure(.mediaExportTooLarge) {
            try await fixture.core.copyConfirmedMediaToSink(
                mediaHandle: oversized.metadata.mediaHandle,
                sink: untouched,
                maximumLength: 10_000
            )
        }
        XCTAssertEqual(untouched.beginCount, 0)
        let openCountAfterRejection = await fixture.files.openCount
        XCTAssertEqual(openCountAfterRejection, openCount)

        let truncated = try await fixture.confirmedMedia(
            ExportSourceSpec(actualLength: 10_000, declaredLength: 12_000, mediaType: .photo)
        )
        let truncatedSink = RecordingMediaCopySink()
        await assertExportFailure(.mediaExportTooLarge) {
            try await fixture.core.copyConfirmedMediaToSink(
                mediaHandle: truncated.metadata.mediaHandle,
                sink: truncatedSink,
                maximumLength: 52_428_800
            )
        }
        XCTAssertEqual(truncatedSink.abortCount, 1)

        let growing = try await fixture.confirmedMedia(
            ExportSourceSpec(actualLength: 12_001, declaredLength: 12_000, mediaType: .photo)
        )
        let growingSink = RecordingMediaCopySink()
        await assertExportFailure(.mediaExportTooLarge) {
            try await fixture.core.copyConfirmedMediaToSink(
                mediaHandle: growing.metadata.mediaHandle,
                sink: growingSink,
                maximumLength: 52_428_800
            )
        }
        XCTAssertEqual(growingSink.abortCount, 1)
        await fixture.core.close()
    }

    func testFailuresUseClosedExportTaxonomyAndAbortOnce() async throws {
        let fixture = ExportFixture()
        let unknown = try MediaHandle(rawValue: String(repeating: "u", count: 32))
        await assertExportFailure(.mediaInvalid) {
            try await fixture.core.copyConfirmedMediaToSink(
                mediaHandle: unknown,
                sink: RecordingMediaCopySink(),
                maximumLength: 10
            )
        }

        let preview = try await fixture.previewMedia(
            ExportSourceSpec(actualLength: 1_024, mediaType: .photo)
        )
        await assertExportFailure(.invalidState) {
            try await fixture.core.copyConfirmedMediaToSink(
                mediaHandle: preview.mediaHandle,
                sink: RecordingMediaCopySink(),
                maximumLength: 52_428_800
            )
        }
        _ = try await fixture.core.confirm(mediaHandle: preview.mediaHandle)
        await assertExportFailure(.invalidArgument) {
            try await fixture.core.copyConfirmedMediaToSink(
                mediaHandle: preview.mediaHandle,
                sink: RecordingMediaCopySink(),
                maximumLength: 0
            )
        }
        await assertExportFailure(.invalidArgument) {
            try await fixture.core.copyConfirmedMediaToSink(
                mediaHandle: preview.mediaHandle,
                sink: RecordingMediaCopySink(),
                maximumLength: 52_428_801
            )
        }

        let invalidContent = try await fixture.confirmedMedia(
            ExportSourceSpec(
                actualLength: 1_024,
                mediaType: .photo,
                contentType: "application/octet-stream"
            )
        )
        let invalidContentSink = RecordingMediaCopySink()
        await assertExportFailure(.invalidState) {
            try await fixture.core.copyConfirmedMediaToSink(
                mediaHandle: invalidContent.metadata.mediaHandle,
                sink: invalidContentSink,
                maximumLength: 52_428_800
            )
        }
        XCTAssertEqual(invalidContentSink.beginCount, 0)

        let begin = try await fixture.confirmedMedia(
            ExportSourceSpec(actualLength: 1_024, mediaType: .photo)
        )
        let beginSink = RecordingMediaCopySink(failure: .begin)
        await assertExportFailure(.mediaExportSinkRejected) {
            try await fixture.core.copyConfirmedMediaToSink(
                mediaHandle: begin.metadata.mediaHandle,
                sink: beginSink,
                maximumLength: 52_428_800
            )
        }
        XCTAssertEqual(beginSink.abortCount, 0)

        let write = try await fixture.confirmedMedia(
            ExportSourceSpec(actualLength: 1_024, mediaType: .photo)
        )
        let writeSink = RecordingMediaCopySink(failure: .write)
        await assertExportFailure(.mediaExportWriteFailed) {
            try await fixture.core.copyConfirmedMediaToSink(
                mediaHandle: write.metadata.mediaHandle,
                sink: writeSink,
                maximumLength: 52_428_800
            )
        }
        XCTAssertEqual(writeSink.abortCount, 1)

        let commit = try await fixture.confirmedMedia(
            ExportSourceSpec(actualLength: 1_024, mediaType: .photo)
        )
        let commitSink = RecordingMediaCopySink(failure: .commit)
        await assertExportFailure(.mediaExportSinkRejected) {
            try await fixture.core.copyConfirmedMediaToSink(
                mediaHandle: commit.metadata.mediaHandle,
                sink: commitSink,
                maximumLength: 52_428_800
            )
        }
        XCTAssertEqual(commitSink.abortCount, 1)

        let read = try await fixture.confirmedMedia(
            ExportSourceSpec(
                actualLength: 1_024,
                mediaType: .photo,
                failReadAtCall: 1
            )
        )
        let readSink = RecordingMediaCopySink()
        await assertExportFailure(.mediaExportReadFailed) {
            try await fixture.core.copyConfirmedMediaToSink(
                mediaHandle: read.metadata.mediaHandle,
                sink: readSink,
                maximumLength: 52_428_800
            )
        }
        XCTAssertEqual(readSink.abortCount, 1)

        let abort = try await fixture.confirmedMedia(
            ExportSourceSpec(actualLength: 1_024, mediaType: .photo)
        )
        let abortSink = RecordingMediaCopySink(failure: .write, abortFails: true)
        await assertExportFailure(.mediaExportWriteFailed) {
            try await fixture.core.copyConfirmedMediaToSink(
                mediaHandle: abort.metadata.mediaHandle,
                sink: abortSink,
                maximumLength: 52_428_800
            )
        }
        XCTAssertEqual(abortSink.abortCount, 1)
        await fixture.core.close()
    }

    func testCallerCancellationAbortsCancellableSinkAndAllowsRetry() async throws {
        let fixture = ExportFixture()
        let confirmed = try await fixture.confirmedMedia(
            ExportSourceSpec(actualLength: 300_000, mediaType: .photo)
        )
        let sink = RecordingMediaCopySink(neverReturnFromWrite: true)
        let export = Task {
            try await fixture.core.copyConfirmedMediaToSink(
                mediaHandle: confirmed.metadata.mediaHandle,
                sink: sink,
                maximumLength: 52_428_800
            )
        }
        let writeStarted = await waitUntil { sink.writeStarted }
        XCTAssertTrue(writeStarted)
        export.cancel()
        await assertExportFailure(.mediaExportCancelled, task: export)
        XCTAssertEqual(sink.abortCount, 1)

        let retry = RecordingMediaCopySink()
        _ = try await fixture.core.copyConfirmedMediaToSink(
            mediaHandle: confirmed.metadata.mediaHandle,
            sink: retry,
            maximumLength: 52_428_800
        )
        XCTAssertEqual(retry.commitCount, 1)
        await fixture.core.close()
    }

    func testDeadlineAbortsOnceAndLateWorkCannotCommit() async throws {
        let fixture = ExportFixture()
        let confirmed = try await fixture.confirmedMedia(
            ExportSourceSpec(actualLength: 300_000, mediaType: .photo)
        )
        let sink = RecordingMediaCopySink(neverReturnFromWrite: true)
        let export = Task {
            try await fixture.core.copyConfirmedMediaToSink(
                mediaHandle: confirmed.metadata.mediaHandle,
                sink: sink,
                maximumLength: 52_428_800
            )
        }
        let writeStarted = await waitUntil { sink.writeStarted }
        XCTAssertTrue(writeStarted)
        fixture.clock.advance(by: 120)
        await assertExportFailure(.mediaExportTimedOut, task: export)
        XCTAssertEqual(sink.abortCount, 1)
        XCTAssertEqual(sink.commitCount, 0)
        await fixture.core.close()
    }

    func testReleaseExpiryAndCloseWinActiveExportWithStableFailures() async throws {
        let releaseFixture = ExportFixture()
        let released = try await releaseFixture.confirmedMedia(
            ExportSourceSpec(actualLength: 300_000, mediaType: .photo)
        )
        let releaseSink = RecordingMediaCopySink(neverReturnFromWrite: true)
        let releaseExport = Task {
            try await releaseFixture.core.copyConfirmedMediaToSink(
                mediaHandle: released.metadata.mediaHandle,
                sink: releaseSink,
                maximumLength: 52_428_800
            )
        }
        let releaseWriteStarted = await waitUntil { releaseSink.writeStarted }
        XCTAssertTrue(releaseWriteStarted)
        _ = try await releaseFixture.core.releaseMedia(mediaHandle: released.metadata.mediaHandle)
        await assertExportFailure(.invalidState, task: releaseExport)
        XCTAssertEqual(releaseSink.abortCount, 1)
        await releaseFixture.core.close()

        let expiryFixture = ExportFixture(configuration: MediaCaptureConfiguration(
            previewTimeToLive: 10,
            mediaLeaseTimeToLive: 5,
            readGracePeriod: 2,
            tombstoneTimeToLive: 3
        ))
        let expired = try await expiryFixture.confirmedMedia(
            ExportSourceSpec(actualLength: 300_000, mediaType: .photo)
        )
        let expirySink = RecordingMediaCopySink(neverReturnFromWrite: true)
        let expiryExport = Task {
            try await expiryFixture.core.copyConfirmedMediaToSink(
                mediaHandle: expired.metadata.mediaHandle,
                sink: expirySink,
                maximumLength: 52_428_800
            )
        }
        let expiryWriteStarted = await waitUntil { expirySink.writeStarted }
        XCTAssertTrue(expiryWriteStarted)
        expiryFixture.clock.advance(by: 5)
        await expiryFixture.core.processDeadlines()
        await assertExportFailure(.invalidState, task: expiryExport)
        XCTAssertEqual(expirySink.abortCount, 1)
        await expiryFixture.core.close()

        let closeFixture = ExportFixture()
        let closed = try await closeFixture.confirmedMedia(
            ExportSourceSpec(actualLength: 300_000, mediaType: .photo)
        )
        let closeSink = RecordingMediaCopySink(neverReturnFromWrite: true)
        let closeExport = Task {
            try await closeFixture.core.copyConfirmedMediaToSink(
                mediaHandle: closed.metadata.mediaHandle,
                sink: closeSink,
                maximumLength: 52_428_800
            )
        }
        let closeWriteStarted = await waitUntil { closeSink.writeStarted }
        XCTAssertTrue(closeWriteStarted)
        await closeFixture.core.close()
        await assertExportFailure(.systemInterrupted, task: closeExport)
        XCTAssertEqual(closeSink.abortCount, 1)
    }

    func testCommitPhaseTerminalTriggersKeepFirstFailureAndAbortLateSuccess() async throws {
        for trigger in ExportCommitRaceTrigger.allCases {
            let configuration = trigger == .expiry
                ? MediaCaptureConfiguration(
                    previewTimeToLive: 10,
                    mediaLeaseTimeToLive: 5,
                    readGracePeriod: 2,
                    tombstoneTimeToLive: 3
                )
                : MediaCaptureConfiguration()
            let fixture = ExportFixture(configuration: configuration)
            let confirmed = try await fixture.confirmedMedia(
                ExportSourceSpec(actualLength: 20_000, mediaType: .photo)
            )
            let commitGate = CancellableTestAsyncGate()
            let sink = RecordingMediaCopySink(commitGate: commitGate)
            let export = Task {
                try await fixture.core.copyConfirmedMediaToSink(
                    mediaHandle: confirmed.metadata.mediaHandle,
                    sink: sink,
                    maximumLength: 52_428_800
                )
            }
            let commitStarted = await waitUntil { sink.commitStarted }
            XCTAssertTrue(commitStarted, "trigger: \(trigger)")

            let expectedFailure: MediaCaptureFailure.ID
            let terminalTask: Task<Void, Never>?
            switch trigger {
            case .callerCancellation:
                expectedFailure = .mediaExportCancelled
                terminalTask = nil
                export.cancel()
            case .deadline:
                expectedFailure = .mediaExportTimedOut
                terminalTask = nil
                fixture.clock.advance(by: 120)
            case .release:
                expectedFailure = .invalidState
                terminalTask = Task {
                    _ = try? await fixture.core.releaseMedia(
                        mediaHandle: confirmed.metadata.mediaHandle
                    )
                }
            case .expiry:
                expectedFailure = .invalidState
                fixture.clock.advance(by: 5)
                terminalTask = Task { await fixture.core.processDeadlines() }
            case .restart:
                expectedFailure = .systemInterrupted
                terminalTask = Task { await fixture.core.appRestarted() }
            case .close:
                expectedFailure = .systemInterrupted
                terminalTask = Task { await fixture.core.close() }
            }

            let cancellationObserved = await waitUntil { sink.commitCancellationObserved }
            XCTAssertTrue(cancellationObserved, "trigger: \(trigger)")
            await assertExportFailure(expectedFailure, task: export)
            if let terminalTask {
                await terminalTask.value
            }
            XCTAssertEqual(sink.commitSuccessCount, 0, "trigger: \(trigger)")
            XCTAssertEqual(sink.abortCount, 1, "trigger: \(trigger)")
            XCTAssertEqual(fixture.bufferTracker.snapshot.activeModuleBytes, 0)
            await fixture.core.close()
        }
    }

    func testCommitReturnWinsLateReleaseAndCallerCancellation() async throws {
        for trigger in PostCommitReturnTrigger.allCases {
            let commitReturned = CommitReturnedObserver()
            let fixture = ExportFixture(exportCommitReturned: {
                await commitReturned.wait()
            })
            let confirmed = try await fixture.confirmedMedia(
                ExportSourceSpec(actualLength: 20_000, mediaType: .photo)
            )
            let sink = RecordingMediaCopySink()
            let export = Task {
                try await fixture.core.copyConfirmedMediaToSink(
                    mediaHandle: confirmed.metadata.mediaHandle,
                    sink: sink,
                    maximumLength: 52_428_800
                )
            }
            let reachedReturnWindow = await waitUntil { commitReturned.wasReached }
            XCTAssertTrue(reachedReturnWindow, "trigger: \(trigger)")

            let release: Task<MediaHandle, Error>?
            switch trigger {
            case .release:
                release = Task {
                    try await fixture.core.releaseMedia(mediaHandle: confirmed.metadata.mediaHandle)
                }
            case .callerCancellation:
                release = nil
                export.cancel()
            }
            let cancellationRegistered = await waitUntil { commitReturned.cancellationObserved }
            XCTAssertTrue(cancellationRegistered, "trigger: \(trigger)")
            commitReturned.resume()

            let result = try await export.value
            XCTAssertEqual(result.mediaHandle, confirmed.metadata.mediaHandle, "trigger: \(trigger)")
            if let release { _ = try await release.value }
            XCTAssertEqual(sink.commitSuccessCount, 1, "trigger: \(trigger)")
            XCTAssertEqual(sink.abortCount, 0, "trigger: \(trigger)")
            XCTAssertEqual(
                fixture.bufferTracker.snapshot.activeModuleBytes,
                0,
                "trigger: \(trigger)"
            )
            await fixture.core.close()
        }
    }

    func testSpontaneousCancellationUsesPhaseSpecificExportFailure() async throws {
        let fixture = ExportFixture()

        let begin = try await fixture.confirmedMedia(
            ExportSourceSpec(actualLength: 1_024, mediaType: .photo)
        )
        let beginSink = RecordingMediaCopySink(failure: .beginCancellation)
        await assertExportFailure(.mediaExportSinkRejected) {
            try await fixture.core.copyConfirmedMediaToSink(
                mediaHandle: begin.metadata.mediaHandle,
                sink: beginSink,
                maximumLength: 52_428_800
            )
        }
        XCTAssertEqual(beginSink.abortCount, 0)

        let write = try await fixture.confirmedMedia(
            ExportSourceSpec(actualLength: 1_024, mediaType: .photo)
        )
        let writeSink = RecordingMediaCopySink(failure: .writeCancellation)
        await assertExportFailure(.mediaExportWriteFailed) {
            try await fixture.core.copyConfirmedMediaToSink(
                mediaHandle: write.metadata.mediaHandle,
                sink: writeSink,
                maximumLength: 52_428_800
            )
        }
        XCTAssertEqual(writeSink.abortCount, 1)

        let commit = try await fixture.confirmedMedia(
            ExportSourceSpec(actualLength: 1_024, mediaType: .photo)
        )
        let commitSink = RecordingMediaCopySink(failure: .commitCancellation)
        await assertExportFailure(.mediaExportSinkRejected) {
            try await fixture.core.copyConfirmedMediaToSink(
                mediaHandle: commit.metadata.mediaHandle,
                sink: commitSink,
                maximumLength: 52_428_800
            )
        }
        XCTAssertEqual(commitSink.abortCount, 1)

        let read = try await fixture.confirmedMedia(
            ExportSourceSpec(
                actualLength: 1_024,
                mediaType: .photo,
                cancelReadAtCall: 1
            )
        )
        let readSink = RecordingMediaCopySink()
        await assertExportFailure(.mediaExportReadFailed) {
            try await fixture.core.copyConfirmedMediaToSink(
                mediaHandle: read.metadata.mediaHandle,
                sink: readSink,
                maximumLength: 52_428_800
            )
        }
        XCTAssertEqual(readSink.abortCount, 1)
        await fixture.core.close()
    }

    func testSourceCloseWipesChunkReturnedByLateRead() async throws {
        let backend = CloseRaceExportSourceBackend()
        let observer = DiscardedChunkObserver()
        let source = MediaSourceAccess(
            backend: backend,
            discardedChunkObserver: { byteCount, allBytesZero in
                observer.record(byteCount: byteCount, allBytesZero: allBytesZero)
            }
        )
        let read = Task { try source.readChunk(maximumLength: 1_024) }
        let readStarted = await waitUntil { backend.didStartReading }
        XCTAssertTrue(readStarted)

        source.close()
        do {
            _ = try await read.value
            XCTFail("Expected the closed source to reject the late chunk")
        } catch {
            XCTAssertEqual((error as? MediaCaptureFailure)?.id, .invalidState)
        }
        XCTAssertEqual(observer.byteCount, 1_024)
        XCTAssertTrue(observer.allBytesZero)
    }

    func testFailureWinnerDropsDataHeldByExecutorBeforeSinkWrite() async throws {
        let deliveryGate = TestAsyncGate()
        let executor = DeliveryGatedMediaExportExecutor(deliveryGate: deliveryGate)
        let fixture = ExportFixture(exportExecutor: executor)
        let confirmed = try await fixture.confirmedMedia(
            ExportSourceSpec(actualLength: 20_000, mediaType: .photo)
        )
        let sink = RecordingMediaCopySink()
        let export = Task {
            try await fixture.core.copyConfirmedMediaToSink(
                mediaHandle: confirmed.metadata.mediaHandle,
                sink: sink,
                maximumLength: 52_428_800
            )
        }
        let dataHeld = await waitUntil { executor.deliveryStarted }
        XCTAssertTrue(dataHeld)

        let release = Task {
            try await fixture.core.releaseMedia(mediaHandle: confirmed.metadata.mediaHandle)
        }
        let cancellationObserved = await waitUntil { executor.cancellationObserved }
        XCTAssertTrue(cancellationObserved)
        deliveryGate.release()

        await assertExportFailure(.invalidState, task: export)
        _ = try await release.value
        XCTAssertEqual(sink.beginCount, 1)
        XCTAssertEqual(sink.writeCount, 0)
        XCTAssertEqual(sink.commitCount, 0)
        XCTAssertEqual(sink.abortCount, 1)
        let buffers = fixture.bufferTracker.snapshot
        XCTAssertEqual(buffers.activeModuleBytes, 0)
        XCTAssertFalse(buffers.accountingUnderflowed)
        await fixture.core.close()
    }

    func testSuccessfulExportKeepsLeaseActiveUntilExplicitRelease() async throws {
        let fixture = ExportFixture()
        let confirmed = try await fixture.confirmedMedia(
            ExportSourceSpec(actualLength: 20_000, mediaType: .photo)
        )
        _ = try await fixture.core.copyConfirmedMediaToSink(
            mediaHandle: confirmed.metadata.mediaHandle,
            sink: RecordingMediaCopySink(),
            maximumLength: 52_428_800
        )
        let secondSink = RecordingMediaCopySink()
        _ = try await fixture.core.copyConfirmedMediaToSink(
            mediaHandle: confirmed.metadata.mediaHandle,
            sink: secondSink,
            maximumLength: 52_428_800
        )
        XCTAssertEqual(secondSink.commitCount, 1)
        _ = try await fixture.core.releaseMedia(mediaHandle: confirmed.metadata.mediaHandle)
        await assertExportFailure(.invalidState) {
            try await fixture.core.copyConfirmedMediaToSink(
                mediaHandle: confirmed.metadata.mediaHandle,
                sink: RecordingMediaCopySink(),
                maximumLength: 52_428_800
            )
        }
        await fixture.core.close()
    }

    func testExactFiftyMiBBoundaryUsesBoundedGeneratedChunks() async throws {
        let fixture = ExportFixture()
        let maximum = 52_428_800
        let confirmed = try await fixture.confirmedMedia(
            ExportSourceSpec(actualLength: maximum, mediaType: .photo)
        )
        let sink = RecordingMediaCopySink()
        let result = try await fixture.core.copyConfirmedMediaToSink(
            mediaHandle: confirmed.metadata.mediaHandle,
            sink: sink,
            maximumLength: maximum
        )
        XCTAssertEqual(result.byteLength, maximum)
        XCTAssertEqual(sink.writtenBytes, maximum)
        XCTAssertEqual(sink.writeCount, 400)
        XCTAssertLessThanOrEqual(sink.maximumChunkBytes, 131_072)

        let overBoundary = try await fixture.confirmedMedia(
            ExportSourceSpec(actualLength: maximum + 1, mediaType: .photo)
        )
        let untouched = RecordingMediaCopySink()
        await assertExportFailure(.mediaExportTooLarge) {
            try await fixture.core.copyConfirmedMediaToSink(
                mediaHandle: overBoundary.metadata.mediaHandle,
                sink: untouched,
                maximumLength: maximum
            )
        }
        XCTAssertEqual(untouched.beginCount, 0)
        await fixture.core.close()
    }
}

private struct ExportSourceSpec: Sendable {
    let actualLength: Int
    let declaredLength: Int
    let mediaType: MediaType
    let contentType: String
    let failReadAtCall: Int?
    let cancelReadAtCall: Int?

    init(
        actualLength: Int,
        declaredLength: Int? = nil,
        mediaType: MediaType,
        contentType: String? = nil,
        failReadAtCall: Int? = nil,
        cancelReadAtCall: Int? = nil
    ) {
        self.actualLength = actualLength
        self.declaredLength = declaredLength ?? actualLength
        self.mediaType = mediaType
        self.contentType = contentType ?? (mediaType == .photo ? "image/jpeg" : "video/mp4")
        self.failReadAtCall = failReadAtCall
        self.cancelReadAtCall = cancelReadAtCall
    }
}

private struct ExportFixture {
    let core: MediaCaptureCore
    let platform: FakeCapturePlatform
    let files: ExportTestFileStore
    let clock: ManualClock
    let executor: RecordingMediaExportExecutor
    let bufferTracker: ExportBufferTracker

    init(
        configuration: MediaCaptureConfiguration = MediaCaptureConfiguration(),
        exportExecutor selectedExportExecutor: (any MediaExportExecuting)? = nil,
        exportCommitReturned: (@Sendable () async -> Void)? = nil
    ) {
        platform = FakeCapturePlatform()
        files = ExportTestFileStore()
        clock = ManualClock()
        executor = RecordingMediaExportExecutor()
        bufferTracker = ExportBufferTracker()
        core = MediaCaptureCore(
            configuration: configuration,
            platform: platform,
            fileStore: files,
            clock: clock,
            handleGenerator: SequentialHandleGenerator(),
            thumbnailGenerator: ImmediateThumbnailGenerator(),
            exportExecutor: selectedExportExecutor ?? executor,
            exportBufferAccounting: bufferTracker,
            exportCommitReturned: exportCommitReturned
        )
    }

    func confirmedMedia(_ spec: ExportSourceSpec) async throws -> ConfirmedMedia {
        let preview = try await previewMedia(spec)
        return try await core.confirm(mediaHandle: preview.mediaHandle)
    }

    func previewMedia(_ spec: ExportSourceSpec) async throws -> MediaMetadata {
        await files.enqueue(spec)
        let stream = await core.events()
        let created = try await core.startSession(options: SessionOptions(
            enabledMediaTypes: [spec.mediaType],
            audioEnabled: false,
            maxVideoDurationMilliseconds: 5_000
        ))
        var ready = false
        for await event in stream {
            if case let .sessionReady(snapshot) = event,
               snapshot.sessionHandle == created.sessionHandle {
                ready = true
                break
            }
        }
        guard ready else { throw MediaCaptureFailure(.systemInterrupted) }
        switch spec.mediaType {
        case .photo:
            return try await core.takePhoto(sessionHandle: created.sessionHandle)
        case .video:
            _ = try await core.startRecording(sessionHandle: created.sessionHandle)
            return try await core.stopRecording(sessionHandle: created.sessionHandle)
        }
    }
}

private final class CommitReturnedObserver: @unchecked Sendable {
    private let lock = NSLock()
    private let gate = TestAsyncGate()
    private var reached = false
    private var cancelled = false

    var wasReached: Bool {
        lock.lock()
        defer { lock.unlock() }
        return reached
    }

    var cancellationObserved: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func wait() async {
        markReached()
        await withTaskCancellationHandler {
            await gate.wait()
        } onCancel: {
            self.lock.lock()
            self.cancelled = true
            self.lock.unlock()
        }
    }

    func resume() {
        gate.release()
    }

    private func markReached() {
        lock.lock()
        reached = true
        lock.unlock()
    }
}

private final class RecordingMediaExportExecutor: MediaExportExecuting, @unchecked Sendable {
    private let lock = NSLock()
    private var executions = 0

    var executionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return executions
    }

    func execute<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        recordExecution()
        return try operation()
    }

    private func recordExecution() {
        lock.lock()
        executions += 1
        lock.unlock()
    }
}

private final class DeliveryGatedMediaExportExecutor: MediaExportExecuting, @unchecked Sendable {
    private let lock = NSLock()
    private let deliveryGate: TestAsyncGate
    private var storedDeliveryStarted = false
    private var storedCancellationObserved = false

    init(deliveryGate: TestAsyncGate) {
        self.deliveryGate = deliveryGate
    }

    var deliveryStarted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedDeliveryStarted
    }

    var cancellationObserved: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedCancellationObserved
    }

    func execute<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        let result = try operation()
        markDeliveryStarted()
        await withTaskCancellationHandler {
            await deliveryGate.wait()
        } onCancel: {
            self.lock.lock()
            self.storedCancellationObserved = true
            self.lock.unlock()
        }
        return result
    }

    private func markDeliveryStarted() {
        lock.lock()
        storedDeliveryStarted = true
        lock.unlock()
    }
}

private final class CancellableTestAsyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var open = false
    private var cancelled = false
    private var waiter: CheckedContinuation<Void, Error>?

    func wait() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if open {
                    lock.unlock()
                    continuation.resume()
                } else if cancelled || Task.isCancelled {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiter = continuation
                    lock.unlock()
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    func release() {
        lock.lock()
        open = true
        let waiter = waiter
        self.waiter = nil
        lock.unlock()
        waiter?.resume()
    }

    private func cancel() {
        lock.lock()
        cancelled = true
        let waiter = waiter
        self.waiter = nil
        lock.unlock()
        waiter?.resume(throwing: CancellationError())
    }
}

private actor ExportTestFileStore: MediaFileStoring {
    private var queued: [ExportSourceSpec] = []
    private var sources: [StoredMediaReference: ExportSourceSpec] = [:]
    private(set) var openCount = 0

    func enqueue(_ spec: ExportSourceSpec) {
        queued.append(spec)
    }

    func removeTemporaryResidue() async {}

    func recordingDestination() async throws -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
    }

    func storePhoto(_ photo: CapturedPhoto) async throws -> StoredMedia {
        try storeNext(expectedType: .photo)
    }

    func finalizeRecording(at destination: URL) async throws -> StoredMedia {
        try? FileManager.default.removeItem(at: destination)
        return try storeNext(expectedType: .video)
    }

    func discardRecording(at destination: URL) async {
        try? FileManager.default.removeItem(at: destination)
    }

    func openSource(_ reference: StoredMediaReference) async throws -> MediaSourceAccess {
        guard let spec = sources[reference] else {
            throw MediaCaptureFailure(.mediaInvalid)
        }
        openCount += 1
        return MediaSourceAccess(backend: GeneratedExportSourceBackend(spec: spec))
    }

    func previewRenderSource(_ media: StoredMedia) async throws -> MediaCaptureRenderSource {
        throw MediaCaptureFailure(.invalidState)
    }

    func delete(_ reference: StoredMediaReference) async {
        sources.removeValue(forKey: reference)
    }

    private func storeNext(expectedType: MediaType) throws -> StoredMedia {
        guard !queued.isEmpty else { throw MediaCaptureFailure(.encodingFailed) }
        let spec = queued.removeFirst()
        guard spec.mediaType == expectedType else {
            throw MediaCaptureFailure(.encodingFailed)
        }
        let reference = StoredMediaReference()
        sources[reference] = spec
        return StoredMedia(
            reference: reference,
            mediaType: spec.mediaType,
            pixelWidth: 120,
            pixelHeight: 80,
            durationMilliseconds: spec.mediaType == .video ? 1_000 : nil,
            orientationDegrees: 0,
            byteLength: spec.declaredLength,
            contentType: spec.contentType
        )
    }
}

private final class GeneratedExportSourceBackend: MediaSourceBackend, @unchecked Sendable {
    private let lock = NSLock()
    private let spec: ExportSourceSpec
    private var offset = 0
    private var readCalls = 0
    private var closed = false

    init(spec: ExportSourceSpec) {
        self.spec = spec
    }

    func readChunk(maximumLength: Int) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { throw MediaCaptureFailure(.invalidState) }
        readCalls += 1
        if readCalls == spec.cancelReadAtCall {
            throw CancellationError()
        }
        if readCalls == spec.failReadAtCall {
            throw MediaCaptureFailure(.mediaExportReadFailed)
        }
        guard offset < spec.actualLength else { return nil }
        let count = min(maximumLength, spec.actualLength - offset)
        let start = offset
        offset += count
        return Data((0 ..< count).map { UInt8((start + $0) % 251) })
    }

    func close() {
        lock.lock()
        closed = true
        lock.unlock()
    }
}

private enum SinkFailure {
    case begin
    case write
    case commit
    case beginCancellation
    case writeCancellation
    case commitCancellation
}

private enum SinkTestError: Error {
    case rejected
}

private enum ExportCommitRaceTrigger: String, CaseIterable {
    case callerCancellation
    case deadline
    case release
    case expiry
    case restart
    case close
}

private enum PostCommitReturnTrigger: String, CaseIterable {
    case release
    case callerCancellation
}

private final class ExportBufferTracker: MediaExportBufferAccounting, @unchecked Sendable {
    struct Snapshot {
        let activeModuleBytes: Int
        let maximumModuleBytes: Int
        let maximumJobBytes: Int
        let accountingUnderflowed: Bool
    }

    private let lock = NSLock()
    private var activeByJob: [UUID: Int] = [:]
    private var activeModuleBytes = 0
    private var maximumModuleBytes = 0
    private var maximumJobBytes = 0
    private var accountingUnderflowed = false

    var snapshot: Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            activeModuleBytes: activeModuleBytes,
            maximumModuleBytes: maximumModuleBytes,
            maximumJobBytes: maximumJobBytes,
            accountingUnderflowed: accountingUnderflowed
        )
    }

    func allocationChanged(jobIdentifier: UUID, delta: Int) {
        lock.lock()
        let nextJobBytes = (activeByJob[jobIdentifier] ?? 0) + delta
        let nextModuleBytes = activeModuleBytes + delta
        if nextJobBytes < 0 || nextModuleBytes < 0 {
            accountingUnderflowed = true
        }
        activeByJob[jobIdentifier] = max(0, nextJobBytes)
        activeModuleBytes = max(0, nextModuleBytes)
        maximumJobBytes = max(maximumJobBytes, nextJobBytes)
        maximumModuleBytes = max(maximumModuleBytes, nextModuleBytes)
        if activeByJob[jobIdentifier] == 0 {
            activeByJob.removeValue(forKey: jobIdentifier)
        }
        lock.unlock()
    }
}

private final class DiscardedChunkObserver: @unchecked Sendable {
    private let lock = NSLock()
    private var storedByteCount = 0
    private var storedAllBytesZero = false

    var byteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedByteCount
    }

    var allBytesZero: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedAllBytesZero
    }

    func record(byteCount: Int, allBytesZero: Bool) {
        lock.lock()
        storedByteCount = byteCount
        storedAllBytesZero = allBytesZero
        lock.unlock()
    }
}

private final class CloseRaceExportSourceBackend: MediaSourceBackend, @unchecked Sendable {
    private let condition = NSCondition()
    private var reading = false
    private var closed = false

    var didStartReading: Bool {
        condition.lock()
        defer { condition.unlock() }
        return reading
    }

    func readChunk(maximumLength: Int) throws -> Data? {
        condition.lock()
        reading = true
        condition.broadcast()
        while !closed {
            condition.wait()
        }
        condition.unlock()
        return Data(repeating: 0x5a, count: maximumLength)
    }

    func close() {
        condition.lock()
        closed = true
        condition.broadcast()
        condition.unlock()
    }
}

private final class RecordingMediaCopySink: MediaCopySink, @unchecked Sendable {
    private let lock = NSLock()
    private let failure: SinkFailure?
    private let abortFails: Bool
    private let neverReturnFromWrite: Bool
    private let writeGate: TestAsyncGate?
    private let commitGate: CancellableTestAsyncGate?
    private var expectedOffset = 0
    private var storedBeginCount = 0
    private var storedWriteCount = 0
    private var storedCommitCount = 0
    private var storedCommitSuccessCount = 0
    private var storedAbortCount = 0
    private var storedWrittenBytes = 0
    private var storedMaximumChunkBytes = 0
    private var storedSequenceIsValid = true
    private var storedWriteStarted = false
    private var storedCommitStarted = false
    private var storedCommitCancellationObserved = false
    private var storedRetainedChunk: MediaCopyChunk?

    init(
        failure: SinkFailure? = nil,
        abortFails: Bool = false,
        neverReturnFromWrite: Bool = false,
        writeGate: TestAsyncGate? = nil,
        commitGate: CancellableTestAsyncGate? = nil
    ) {
        self.failure = failure
        self.abortFails = abortFails
        self.neverReturnFromWrite = neverReturnFromWrite
        self.writeGate = writeGate
        self.commitGate = commitGate
    }

    var beginCount: Int { locked { storedBeginCount } }
    var writeCount: Int { locked { storedWriteCount } }
    var commitCount: Int { locked { storedCommitCount } }
    var commitSuccessCount: Int { locked { storedCommitSuccessCount } }
    var abortCount: Int { locked { storedAbortCount } }
    var writtenBytes: Int { locked { storedWrittenBytes } }
    var maximumChunkBytes: Int { locked { storedMaximumChunkBytes } }
    var sequenceIsValid: Bool { locked { storedSequenceIsValid } }
    var writeStarted: Bool { locked { storedWriteStarted } }
    var commitStarted: Bool { locked { storedCommitStarted } }
    var commitCancellationObserved: Bool { locked { storedCommitCancellationObserved } }
    var retainedChunk: MediaCopyChunk? { locked { storedRetainedChunk } }

    func begin(mediaType: MediaType, contentType: String, byteLength: Int) async throws {
        mutate { storedBeginCount += 1 }
        if failure == .beginCancellation { throw CancellationError() }
        if failure == .begin { throw SinkTestError.rejected }
    }

    func write(_ chunk: MediaCopyChunk) async throws {
        let bytes = try chunk.copyBytes()
        mutate {
            storedWriteStarted = true
            storedWriteCount += 1
            storedWrittenBytes += bytes.count
            storedMaximumChunkBytes = max(storedMaximumChunkBytes, bytes.count)
            storedRetainedChunk = chunk
            for byte in bytes {
                if byte != UInt8(expectedOffset % 251) {
                    storedSequenceIsValid = false
                }
                expectedOffset += 1
            }
        }
        if let writeGate { await writeGate.wait() }
        if neverReturnFromWrite {
            try await Task.sleep(nanoseconds: UInt64.max)
        }
        if failure == .writeCancellation { throw CancellationError() }
        if failure == .write { throw SinkTestError.rejected }
    }

    func commit(byteLength: Int) async throws {
        mutate {
            storedCommitStarted = true
            storedCommitCount += 1
        }
        if let commitGate {
            try await withTaskCancellationHandler {
                try await commitGate.wait()
            } onCancel: {
                self.mutate { self.storedCommitCancellationObserved = true }
            }
        }
        if failure == .commitCancellation { throw CancellationError() }
        if failure == .commit { throw SinkTestError.rejected }
        mutate { storedCommitSuccessCount += 1 }
    }

    func abort() async throws {
        mutate { storedAbortCount += 1 }
        if abortFails { throw SinkTestError.rejected }
    }

    private func mutate(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        body()
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private func exportFailure(
    _ operation: () async throws -> MediaExportResult
) async -> MediaCaptureFailure.ID? {
    do {
        _ = try await operation()
        return nil
    } catch let failure as MediaCaptureFailure {
        return failure.id
    } catch {
        return nil
    }
}

private func assertExportFailure(
    _ expected: MediaCaptureFailure.ID,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ operation: () async throws -> MediaExportResult
) async {
    let actual = await exportFailure(operation)
    XCTAssertEqual(actual, expected, file: file, line: line)
}

private func assertExportFailure(
    _ expected: MediaCaptureFailure.ID,
    task: Task<MediaExportResult, Error>,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    let actual = await exportFailure(task)
    XCTAssertEqual(actual, expected, file: file, line: line)
}

private func exportFailure(
    _ task: Task<MediaExportResult, Error>
) async -> MediaCaptureFailure.ID? {
    do {
        _ = try await task.value
        return nil
    } catch let failure as MediaCaptureFailure {
        return failure.id
    } catch {
        return nil
    }
}
