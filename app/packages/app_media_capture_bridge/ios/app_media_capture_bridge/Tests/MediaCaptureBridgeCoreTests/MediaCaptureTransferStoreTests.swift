import Foundation
import XCTest
@testable import MediaCapture
@testable import MediaCaptureBridgeCore

final class MediaCaptureTransferStoreTests: XCTestCase {
    func testReservationCommitsBoundedFileAndProducesCanonicalURI() async throws {
        try await withTemporaryDirectory { cache in
            let store = MediaCaptureTransferStore(cacheDirectory: cache)
            XCTAssertTrue(store.prepare())
            XCTAssertTrue(store.isAvailable)
            let metadata = try transferMetadata(byteLength: 4)
            let reservation = try store.createReservation(metadata: metadata)

            try await reservation.mediaSink.begin(
                mediaType: .photo,
                contentType: "image/jpeg",
                byteLength: 4
            )
            try await reservation.mediaSink.write(MediaCopyChunk(Data([1, 2])))
            try await reservation.mediaSink.write(MediaCopyChunk(Data([3, 4])))
            try await reservation.mediaSink.commit(byteLength: 4)

            XCTAssertTrue(reservation.committed)
            let value = try store.fileURI(reservation)
            try MediaCaptureWireCodec.requireCanonicalFileURI(value)
            let file = try XCTUnwrap(URL(string: value))
            XCTAssertEqual(try Data(contentsOf: file), Data([1, 2, 3, 4]))
            XCTAssertTrue(store.delete(reservation))
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        }
    }

    func testLengthDriftCannotCommitAndAbortDeletesStaging() async throws {
        try await withTemporaryDirectory { cache in
            let store = MediaCaptureTransferStore(cacheDirectory: cache)
            let reservation = try store.createReservation(
                metadata: try transferMetadata(byteLength: 4)
            )
            try await reservation.mediaSink.begin(
                mediaType: .photo,
                contentType: "image/jpeg",
                byteLength: 4
            )
            try await reservation.mediaSink.write(MediaCopyChunk(Data([1, 2, 3])))

            do {
                try await reservation.mediaSink.commit(byteLength: 4)
                XCTFail("Expected length drift to fail")
            } catch {
            }
            try await reservation.mediaSink.abort()
            XCTAssertTrue(store.delete(reservation))
        }
    }

    func testSymlinkedTransferParentIsRejectedWithoutFollowingTarget() throws {
        try withTemporaryDirectory { cache in
            try withTemporaryDirectory { outside in
                let parent = cache.appendingPathComponent("app_media_capture_bridge")
                try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: outside)

                let store = MediaCaptureTransferStore(cacheDirectory: cache)

                XCTAssertFalse(store.prepare())
                XCTAssertFalse(store.isAvailable)
                XCTAssertFalse(
                    FileManager.default.fileExists(
                        atPath: outside.appendingPathComponent("exports").path
                    )
                )
            }
        }
    }

    func testStartupSweepDeletesResidueWithoutFollowingChildSymlink() throws {
        try withTemporaryDirectory { cache in
            try withTemporaryDirectory { outside in
                let root = cache
                    .appendingPathComponent("app_media_capture_bridge", isDirectory: true)
                    .appendingPathComponent("exports", isDirectory: true)
                try FileManager.default.createDirectory(
                    at: root,
                    withIntermediateDirectories: true
                )
                let residue = root.appendingPathComponent("old.partial")
                XCTAssertTrue(FileManager.default.createFile(atPath: residue.path, contents: Data([1])))
                let outsideFile = outside.appendingPathComponent("keep.bin")
                XCTAssertTrue(FileManager.default.createFile(atPath: outsideFile.path, contents: Data([2])))
                try FileManager.default.createSymbolicLink(
                    at: root.appendingPathComponent("linked.partial"),
                    withDestinationURL: outsideFile
                )

                let store = MediaCaptureTransferStore(cacheDirectory: cache)

                XCTAssertTrue(store.prepare())
                XCTAssertTrue(store.isAvailable)
                XCTAssertFalse(FileManager.default.fileExists(atPath: residue.path))
                XCTAssertTrue(FileManager.default.fileExists(atPath: outsideFile.path))
            }
        }
    }

    func testConstructionSchedulesRestartSweepWithoutReservation() async throws {
        try await withTemporaryDirectory { cache in
            let root = transferRoot(cache)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let residue = root.appendingPathComponent("restart.partial")
            try Data([1]).write(to: residue)

            let store = MediaCaptureTransferStore(cacheDirectory: cache)
            var preparationCompleted = false
            for _ in 0 ..< 1_000 {
                if !FileManager.default.fileExists(atPath: residue.path), store.isAvailable {
                    preparationCompleted = true
                    break
                }
                try? await Task.sleep(nanoseconds: 1_000_000)
            }

            XCTAssertTrue(preparationCompleted)
            XCTAssertFalse(FileManager.default.fileExists(atPath: residue.path))
            XCTAssertTrue(store.isAvailable)
        }
    }

    func testSecondLiveStoreDoesNotSweepFirstAttachmentTransfer() async throws {
        try await withTemporaryDirectory { cache in
            let firstStore = MediaCaptureTransferStore(cacheDirectory: cache)
            let reservation = try firstStore.createReservation(
                metadata: try transferMetadata(byteLength: 1)
            )
            try await reservation.mediaSink.begin(
                mediaType: .photo,
                contentType: "image/jpeg",
                byteLength: 1
            )
            try await reservation.mediaSink.write(MediaCopyChunk(Data([1])))
            try await reservation.mediaSink.commit(byteLength: 1)
            let file = try XCTUnwrap(URL(string: try firstStore.fileURI(reservation)))

            let secondStore = MediaCaptureTransferStore(cacheDirectory: cache)

            XCTAssertTrue(secondStore.prepare())
            XCTAssertTrue(secondStore.isAvailable)
            XCTAssertEqual(try Data(contentsOf: file), Data([1]))
            XCTAssertTrue(firstStore.delete(reservation))
        }
    }

    func testStagingReplacementCannotRedirectSinkWrite() async throws {
        try await withTemporaryDirectory { cache in
            try await withTemporaryDirectory { outside in
                let store = MediaCaptureTransferStore(cacheDirectory: cache)
                let reservation = try store.createReservation(
                    metadata: try transferMetadata(byteLength: 1)
                )
                let root = transferRoot(cache)
                let staging = root.appendingPathComponent("\(reservation.exportHandle).partial")
                let outsideFile = outside.appendingPathComponent("keep.bin")
                try Data([9]).write(to: outsideFile)
                try FileManager.default.removeItem(at: staging)
                try FileManager.default.createSymbolicLink(at: staging, withDestinationURL: outsideFile)

                do {
                    try await reservation.mediaSink.begin(
                        mediaType: .photo,
                        contentType: "image/jpeg",
                        byteLength: 1
                    )
                    XCTFail("Expected replaced staging entry to fail closed")
                } catch {
                }
                try? await reservation.mediaSink.abort()

                XCTAssertEqual(try Data(contentsOf: outsideFile), Data([9]))
                XCTAssertTrue(store.delete(reservation))
            }
        }
    }

    func testFinalReplacementCannotBeOverwrittenByCommit() async throws {
        try await withTemporaryDirectory { cache in
            try await withTemporaryDirectory { outside in
                let store = MediaCaptureTransferStore(cacheDirectory: cache)
                let reservation = try store.createReservation(
                    metadata: try transferMetadata(byteLength: 1)
                )
                try await reservation.mediaSink.begin(
                    mediaType: .photo,
                    contentType: "image/jpeg",
                    byteLength: 1
                )
                try await reservation.mediaSink.write(MediaCopyChunk(Data([1])))
                let final = transferRoot(cache)
                    .appendingPathComponent("\(reservation.exportHandle).jpg")
                let outsideFile = outside.appendingPathComponent("keep.bin")
                try Data([9]).write(to: outsideFile)
                try FileManager.default.createSymbolicLink(at: final, withDestinationURL: outsideFile)

                do {
                    try await reservation.mediaSink.commit(byteLength: 1)
                    XCTFail("Expected exclusive commit to reject a replacement")
                } catch {
                }
                try? await reservation.mediaSink.abort()

                XCTAssertEqual(try Data(contentsOf: outsideFile), Data([9]))
                XCTAssertTrue(store.delete(reservation))
            }
        }
    }

    func testRootReplacementCannotRedirectCommitOrURI() async throws {
        try await withTemporaryDirectory { cache in
            try await withTemporaryDirectory { outside in
                let store = MediaCaptureTransferStore(cacheDirectory: cache)
                let reservation = try store.createReservation(
                    metadata: try transferMetadata(byteLength: 1)
                )
                let root = transferRoot(cache)
                let heldRoot = root.deletingLastPathComponent()
                    .appendingPathComponent("exports-held", isDirectory: true)
                try FileManager.default.moveItem(at: root, to: heldRoot)
                try FileManager.default.createSymbolicLink(at: root, withDestinationURL: outside)

                try await reservation.mediaSink.begin(
                    mediaType: .photo,
                    contentType: "image/jpeg",
                    byteLength: 1
                )
                try await reservation.mediaSink.write(MediaCopyChunk(Data([1])))
                try await reservation.mediaSink.commit(byteLength: 1)

                XCTAssertThrowsError(try store.fileURI(reservation))
                XCTAssertTrue((try FileManager.default.contentsOfDirectory(atPath: outside.path)).isEmpty)
                XCTAssertTrue(store.delete(reservation))
                XCTAssertTrue((try FileManager.default.contentsOfDirectory(atPath: heldRoot.path)).isEmpty)
            }
        }
    }

    func testClosedGenerationRejectsNewReservationsAndURIExposure() async throws {
        try withTemporaryDirectory { cache in
            let store = MediaCaptureTransferStore(cacheDirectory: cache)
            let reservation = try store.createReservation(
                metadata: try transferMetadata(byteLength: 1)
            )
            store.closeGeneration()

            XCTAssertFalse(store.isAvailable)
            XCTAssertThrowsError(try store.createReservation(metadata: reservation.metadata))
            XCTAssertThrowsError(try store.fileURI(reservation))
            XCTAssertTrue(store.delete(reservation))
        }
    }

    private func transferMetadata(byteLength: Int) throws -> MediaMetadata {
        try MediaMetadata(
            mediaHandle: MediaHandle(rawValue: "media_transfer"),
            mediaType: .photo,
            pixelWidth: 2,
            pixelHeight: 2,
            durationMilliseconds: nil,
            orientationDegrees: 0,
            byteLength: byteLength
        )
    }

    private func transferRoot(_ cache: URL) -> URL {
        cache
            .appendingPathComponent("app_media_capture_bridge", isDirectory: true)
            .appendingPathComponent("exports", isDirectory: true)
    }

    private func withTemporaryDirectory(
        _ body: (URL) async throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory)
    }

    private func withTemporaryDirectory(
        _ body: (URL) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}
