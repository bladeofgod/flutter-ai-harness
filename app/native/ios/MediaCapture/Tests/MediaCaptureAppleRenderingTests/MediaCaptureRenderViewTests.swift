import AVFoundation
import CoreGraphics
import MediaCapture
import MediaCaptureAppleRendering
import XCTest

@MainActor
final class MediaCaptureRenderViewTests: XCTestCase {
    func testFactoryCreatesOneConcreteFreshSurfacePerOwner() throws {
        let firstOwner = MediaCaptureRenderSurfaceOwner(ownerGeneration: 1)
        let secondOwner = MediaCaptureRenderSurfaceOwner(ownerGeneration: 2)

        let first = try MediaCaptureRenderSurfaceFactory.make(owner: firstOwner)
        let second = try MediaCaptureRenderSurfaceFactory.make(owner: secondOwner)

        XCTAssertFalse(first === second)
        XCTAssertThrowsError(try MediaCaptureRenderSurfaceFactory.make(owner: firstOwner))
        XCTAssertThrowsError(
            try MediaCaptureRenderSurfaceFactory.make(
                owner: MediaCaptureRenderSurfaceOwner(ownerGeneration: 0)
            )
        )
    }

    func testConcreteSurfaceDeinitInvalidatesBackingEndpoint() throws {
        let owner = MediaCaptureRenderSurfaceOwner(ownerGeneration: 1)
        var view: MediaCaptureRenderView? = try MediaCaptureRenderSurfaceFactory.make(owner: owner)
        weak let weakView = view

        XCTAssertNotNil(owner.endpointSnapshot())
        view = nil

        XCTAssertNil(weakView)
        XCTAssertNil(owner.endpointSnapshot())
    }

    func testLiveSourceMountsPreviewLayerAndCleanupDisconnectsIt() async throws {
        let session = AVCaptureSession()
        let view = try makeView(generation: 1)
        let binding = try await mount(source: .live(session), in: view, generation: 1)

        XCTAssertTrue(view.mountedLayer is AVCaptureVideoPreviewLayer)
        XCTAssertTrue(view.mountedLayer?.superlayer === view.layer)
        XCTAssertTrue(view.ownsLiveSession(session))

        await binding.revoke()
        XCTAssertFalse(view.ownsLiveSession(session))
        await binding.detach()
        XCTAssertNil(view.mountedLayer)
        XCTAssertTrue(view.layer.sublayers?.isEmpty ?? true)
    }

    func testPhotoSourceMountsDecodedContentAndCleanupClearsIt() async throws {
        let view = try makeView(generation: 2)
        let image = try XCTUnwrap(makeImage())
        let binding = try await mount(source: .photo(image), in: view, generation: 2)

        XCTAssertTrue(view.hasDecodedPhotoContent)
        XCTAssertTrue(view.mountedLayer?.superlayer === view.layer)

        await binding.revoke()
        XCTAssertTrue(view.hasDecodedPhotoContent)
        await binding.detach()
        XCTAssertNil(view.mountedLayer)
        XCTAssertFalse(view.hasDecodedPhotoContent)
    }

    func testVideoSourceMountsPlayerLayerAndCleanupClearsPlayer() async throws {
        let view = try makeView(generation: 3)
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("render-test.mov")
        let binding = try await mount(source: .video(url), in: view, generation: 3)
        let player = try XCTUnwrap(view.mountedPlayer)

        XCTAssertTrue(view.mountedLayer is AVPlayerLayer)
        XCTAssertTrue(view.ownsVideoPlayer(player))

        await binding.revoke()
        XCTAssertNil(view.mountedPlayer)
        await binding.detach()
        XCTAssertNil(view.mountedLayer)
    }

    func testInvalidationAfterAsyncValidationDropsQueuedMutation() async {
        let validationStarted = AsyncLatch()
        let releaseValidation = AsyncLatch()
        let gate = MediaCaptureRenderCallbackGate(
            mountBody: { true },
            activeBody: {
                await validationStarted.signal()
                await releaseValidation.wait()
                return true
            }
        )
        var mutationCount = 0
        let mutation = Task { @MainActor in
            await gate.performIfActive { mutationCount += 1 }
        }

        await validationStarted.wait()
        gate.invalidate()
        await releaseValidation.signal()

        let mutationPerformed = await mutation.value
        XCTAssertFalse(mutationPerformed)
        XCTAssertEqual(mutationCount, 0)
    }

    private func makeView(generation: Int64) throws -> MediaCaptureRenderView {
        try MediaCaptureRenderSurfaceFactory.make(
            owner: MediaCaptureRenderSurfaceOwner(ownerGeneration: generation)
        )
    }

    private func mount(
        source: MediaCaptureRenderSource,
        in view: MediaCaptureRenderView,
        generation: Int64
    ) async throws -> MediaCaptureRenderBinding {
        let endpoint = try XCTUnwrap(view.mountEndpoint)
        return try await endpoint.mount(
            source: source,
            context: RenderAttachmentContext(
                kind: source.isLive ? .livePreview : .unconfirmedPreview,
                ownerGeneration: generation
            ),
            callbackGate: MediaCaptureRenderCallbackGate(
                mountBody: { true },
                activeBody: { true }
            )
        )
    }

    private func makeImage() -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytes: [UInt8] = [255, 0, 0, 255]
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}

private actor AsyncLatch {
    private var signaled = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if signaled { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func signal() {
        guard !signaled else { return }
        signaled = true
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}

private extension MediaCaptureRenderSource {
    var isLive: Bool {
        switch self {
        case .live:
            return true
        case .photo, .video:
            return false
        }
    }
}
