import CoreGraphics
import Foundation
import ImageIO
import MobileCoreServices
import XCTest
@testable import MediaCapture

final class ThumbnailTests: XCTestCase {
    func testJPEGRetryWipesRejectedCandidateBeforeReturningSuccess() throws {
        let encoder = RecordingSensitiveJPEGEncoder(byteCounts: [600_000, 128])
        let cancellation = CancellationSignal()
        let result = try AppleImageProcessor.boundedJPEG(
            from: try makeTestImage(edge: 64),
            maximumPixelEdge: 64,
            cancellation: cancellation,
            encoder: encoder
        )
        XCTAssertEqual(encoder.buffers.count, 2)
        XCTAssertTrue(encoder.buffers[0].isEmpty)
        XCTAssertFalse(result.buffer.isEmpty)
        result.buffer.wipe()
        XCTAssertTrue(encoder.buffers[1].isEmpty)
    }

    func testJPEGPostEncodeCancellationWipesCandidate() throws {
        let cancellation = CancellationSignal()
        let encoder = RecordingSensitiveJPEGEncoder(
            byteCounts: [128],
            cancelAfterEncoding: cancellation
        )
        XCTAssertThrowsError(try AppleImageProcessor.boundedJPEG(
            from: try makeTestImage(edge: 64),
            maximumPixelEdge: 64,
            cancellation: cancellation,
            encoder: encoder
        )) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(encoder.buffers.count, 1)
        XCTAssertTrue(encoder.buffers[0].isEmpty)
    }

    func testJPEGExhaustedRetriesWipeEveryCandidate() throws {
        let encoder = RecordingSensitiveJPEGEncoder(byteCounts: [])
        XCTAssertThrowsError(try AppleImageProcessor.boundedJPEG(
            from: try makeTestImage(edge: 64),
            maximumPixelEdge: 64,
            cancellation: CancellationSignal(),
            encoder: encoder
        ))
        XCTAssertGreaterThan(encoder.buffers.count, 1)
        XCTAssertTrue(encoder.buffers.allSatisfy(\.isEmpty))
    }

    func testBoundsAndCallerCopySurviveSourceRelease() async throws {
        let fixture = CoreFixture()
        let confirmed = try await fixture.confirmedPhoto()
        let handle = confirmed.metadata.mediaHandle
        let invalid = await captureFailure {
            _ = try await fixture.core.readMediaThumbnail(
                mediaHandle: handle,
                maximumPixelEdge: 63
            )
        }
        XCTAssertEqual(invalid?.id, .invalidArgument)

        let thumbnail = try await fixture.core.readMediaThumbnail(
            mediaHandle: handle,
            maximumPixelEdge: 128
        )
        let committedBytes = thumbnail.data
        XCTAssertEqual(thumbnail.mediaHandle, handle)
        _ = try await fixture.core.releaseMedia(mediaHandle: handle)
        XCTAssertEqual(thumbnail.contentType, "image/jpeg")
        XCTAssertEqual(thumbnail.orientationDegrees, 0)
        XCTAssertLessThanOrEqual(thumbnail.byteLength, 524_288)
        XCTAssertEqual(thumbnail.data, committedBytes)
        await fixture.core.close()
    }

    func testPerMediaOverloadAndReleaseWinsInFlightGeneration() async throws {
        let generator = BlockingThumbnailGenerator()
        let fixture = CoreFixture(thumbnailGenerator: generator)
        let confirmed = try await fixture.confirmedPhoto()
        let handle = confirmed.metadata.mediaHandle
        let first = Task {
            try await fixture.core.readMediaThumbnail(
                mediaHandle: handle,
                maximumPixelEdge: 128
            )
        }
        let firstStarted = await waitUntil { generator.started }
        XCTAssertTrue(firstStarted)

        let overload = await captureFailure {
            _ = try await fixture.core.readMediaThumbnail(
                mediaHandle: handle,
                maximumPixelEdge: 128
            )
        }
        XCTAssertEqual(overload?.id, .thumbnailOverloaded)
        _ = try await fixture.core.releaseMedia(mediaHandle: handle)
        do {
            _ = try await first.value
            XCTFail("Release must win before result commit")
        } catch let failure as MediaCaptureFailure {
            XCTAssertEqual(failure.id, .invalidState)
        }
        let releaseCancellationObserved = await waitUntil { generator.cancellationCount == 1 }
        XCTAssertTrue(releaseCancellationObserved)
        await fixture.core.close()
    }

    func testTaskCancellationPropagatesCancellationErrorAfterCleanup() async throws {
        let generator = BlockingThumbnailGenerator()
        let fixture = CoreFixture(thumbnailGenerator: generator)
        let confirmed = try await fixture.confirmedPhoto()
        let task = Task {
            try await fixture.core.readMediaThumbnail(
                mediaHandle: confirmed.metadata.mediaHandle,
                maximumPixelEdge: 128
            )
        }
        let cancellationStarted = await waitUntil { generator.started }
        XCTAssertTrue(cancellationStarted)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("CancellationError expected")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected cancellation error: \(error)")
        }
        let taskCancellationObserved = await waitUntil { generator.cancellationCount == 1 }
        XCTAssertTrue(taskCancellationObserved)
        await fixture.core.close()
    }

    func testModuleRejectsThirdConcurrentJobBeforeSourceAccess() async throws {
        let generator = BlockingThumbnailGenerator()
        let fixture = CoreFixture(thumbnailGenerator: generator)
        let firstMedia = try await fixture.confirmedPhoto().metadata.mediaHandle
        let secondMedia = try await fixture.confirmedPhoto().metadata.mediaHandle
        let thirdMedia = try await fixture.confirmedPhoto().metadata.mediaHandle
        let first = Task {
            try await fixture.core.readMediaThumbnail(
                mediaHandle: firstMedia,
                maximumPixelEdge: 128
            )
        }
        let second = Task {
            try await fixture.core.readMediaThumbnail(
                mediaHandle: secondMedia,
                maximumPixelEdge: 128
            )
        }
        let twoJobsStarted = await waitUntil { generator.startCount >= 2 }
        XCTAssertTrue(twoJobsStarted)
        let overload = await captureFailure {
            _ = try await fixture.core.readMediaThumbnail(
                mediaHandle: thirdMedia,
                maximumPixelEdge: 128
            )
        }
        XCTAssertEqual(overload?.id, .thumbnailOverloaded)
        _ = try await fixture.core.releaseMedia(mediaHandle: firstMedia)
        _ = try await fixture.core.releaseMedia(mediaHandle: secondMedia)
        _ = try? await first.value
        _ = try? await second.value
        await fixture.core.close()
    }

    func testInvalidGeneratedBufferIsWipedBeforeFailureDelivery() async throws {
        let generator = InvalidThumbnailGenerator()
        let fixture = CoreFixture(thumbnailGenerator: generator)
        let confirmed = try await fixture.confirmedPhoto()
        let failure = await captureFailure {
            _ = try await fixture.core.readMediaThumbnail(
                mediaHandle: confirmed.metadata.mediaHandle,
                maximumPixelEdge: 128
            )
        }
        XCTAssertEqual(failure?.id, .thumbnailGenerationFailed)
        XCTAssertEqual(generator.buffer?.isEmpty, true)
        await fixture.core.close()
    }

    func testRestartCancelsWorkerBeforeReturningMediaInvalid() async throws {
        let generator = BlockingThumbnailGenerator()
        let fixture = CoreFixture(thumbnailGenerator: generator)
        let confirmed = try await fixture.confirmedPhoto()
        let read = Task {
            try await fixture.core.readMediaThumbnail(
                mediaHandle: confirmed.metadata.mediaHandle,
                maximumPixelEdge: 128
            )
        }
        let restartWorkerStarted = await waitUntil { generator.started }
        XCTAssertTrue(restartWorkerStarted)
        await fixture.core.appRestarted()
        do {
            _ = try await read.value
            XCTFail("Restart must invalidate the in-flight media job")
        } catch let failure as MediaCaptureFailure {
            XCTAssertEqual(failure.id, .mediaInvalid)
        }
        XCTAssertEqual(generator.cancellationCount, 1)
        await fixture.core.close()
    }

    func testPosterSelectionPrefersTargetOrAfterThenNearestBefore() {
        XCTAssertEqual(
            PosterFrameSelector.selectedIndex(
                targetMilliseconds: 1_000,
                candidateMilliseconds: [900, 1_200, 1_100]
            ),
            2
        )
        XCTAssertEqual(
            PosterFrameSelector.selectedIndex(
                targetMilliseconds: 1_000,
                candidateMilliseconds: [700, 950, 800]
            ),
            1
        )
        XCTAssertEqual(
            PosterFrameSelector.selectedIndex(
                targetMilliseconds: 1_000,
                candidateMilliseconds: [1_100, 1_100]
            ),
            0
        )
    }

    func testVideoThumbnailReceivesBoundedDecodeRequestAndDeterministicPosterTarget() async throws {
        let generator = RecordingThumbnailGenerator()
        let fixture = CoreFixture(thumbnailGenerator: generator)
        let session = try await fixture.startReadySession(mediaTypes: [.video])
        _ = try await fixture.core.startRecording(sessionHandle: session)
        let preview = try await fixture.core.stopRecording(sessionHandle: session)
        let confirmed = try await fixture.core.confirm(mediaHandle: preview.mediaHandle)
        let thumbnail = try await fixture.core.readMediaThumbnail(
            mediaHandle: confirmed.metadata.mediaHandle,
            maximumPixelEdge: 512
        )
        XCTAssertEqual(generator.request?.0, 512)
        XCTAssertEqual(generator.request?.1, .video)
        XCTAssertEqual(thumbnail.posterFrameMilliseconds, 750)
        XCTAssertLessThanOrEqual(thumbnail.pixelWidth * thumbnail.pixelHeight, 1_048_576)
        await fixture.core.close()
    }

    func testApplePhotoThumbnailIsBoundedJPEGWithoutExifOrGPS() async throws {
        let sourceData = try jpegWithMetadata()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        try sourceData.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let access = try MediaSourceAccess(fileURL: url)
        let stored = StoredMedia(
            reference: StoredMediaReference(),
            mediaType: .photo,
            pixelWidth: 32,
            pixelHeight: 16,
            durationMilliseconds: nil,
            orientationDegrees: 0,
            byteLength: sourceData.count,
            contentType: "image/jpeg"
        )
        let generated = try await AppleThumbnailGenerator().generate(
            from: access,
            media: stored,
            maximumPixelEdge: 64,
            cancellation: CancellationSignal()
        )
        XCTAssertLessThanOrEqual(generated.pixelWidth, 64)
        XCTAssertLessThanOrEqual(generated.pixelHeight, 64)
        let generatedData = generated.buffer.copy()
        defer { generated.buffer.wipe() }
        XCTAssertLessThanOrEqual(generatedData.count, 524_288)
        guard let imageSource = CGImageSourceCreateWithData(generatedData as CFData, nil) else {
            return XCTFail("Generated JPEG could not be decoded")
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        XCTAssertNil(properties?[kCGImagePropertyExifDictionary])
        XCTAssertNil(properties?[kCGImagePropertyGPSDictionary])
    }

    private func jpegWithMetadata() throws -> Data {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: 32,
                  height: 16,
                  bitsPerComponent: 8,
                  bytesPerRow: 32 * 4,
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
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "private-device"],
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 31.2],
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw MediaCaptureFailure(.encodingFailed)
        }
        return data as Data
    }
}

private final class RecordingSensitiveJPEGEncoder: SensitiveJPEGEncoding {
    private var byteCounts: [Int]
    private let cancelAfterEncoding: CancellationSignal?
    private(set) var buffers: [SensitiveDataBuffer] = []

    init(byteCounts: [Int], cancelAfterEncoding: CancellationSignal? = nil) {
        self.byteCounts = byteCounts
        self.cancelAfterEncoding = cancelAfterEncoding
    }

    func encode(_ image: CGImage, quality: Double) throws -> SensitiveDataBuffer {
        let count = byteCounts.isEmpty ? 600_000 : byteCounts.removeFirst()
        let buffer = SensitiveDataBuffer(Data(repeating: 0x5a, count: count))
        buffers.append(buffer)
        cancelAfterEncoding?.cancel()
        return buffer
    }
}

private func makeTestImage(edge: Int) throws -> CGImage {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil,
              width: edge,
              height: edge,
              bitsPerComponent: 8,
              bytesPerRow: edge * 4,
              space: colorSpace,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ),
          let image = context.makeImage()
    else {
        throw MediaCaptureFailure(.thumbnailGenerationFailed)
    }
    return image
}
