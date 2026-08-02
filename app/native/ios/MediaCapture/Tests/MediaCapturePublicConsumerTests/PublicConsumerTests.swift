import MediaCapture
import MediaCaptureAppleRendering
import UIKit
import XCTest

final class PublicConsumerTests: XCTestCase {
    func testConsumerCompilesAgainstPackageProductWithoutFlutterOrWireTypes() throws {
        let options = try SessionOptions(
            enabledMediaTypes: [.photo, .video],
            preferredCamera: .rear,
            audioEnabled: false,
            maxVideoDurationMilliseconds: 5_000
        )
        let handle = try SessionHandle(rawValue: "consumer_owned_opaque_handle")

        XCTAssertEqual(options.preferredCamera, .rear)
        XCTAssertEqual(handle.rawValue, "consumer_owned_opaque_handle")
        XCTAssertEqual(MediaCaptureFailure(.mediaInvalid).id.rawValue, "media_invalid")
        XCTAssertEqual(
            MediaCaptureFailure(.mediaExportTimedOut).id.rawValue,
            "media_export_timed_out"
        )
        let sink: any MediaCopySink = PublicConsumerSink()
        XCTAssertNotNil(sink)
        XCTAssertNotNil(MediaCaptureCore.self)
    }

    @MainActor
    func testIndependentPackageCanUseBothProductsAndConcreteSurface() throws {
        let owner = MediaCaptureRenderSurfaceOwner(ownerGeneration: 1)
        let view = try MediaCaptureRenderSurfaceFactory.make(owner: owner)

        XCTAssertNotNil(view.layer)
        XCTAssertTrue(view.surfaceOwner === owner)
    }
}

private struct PublicConsumerSink: MediaCopySink {
    func begin(mediaType: MediaType, contentType: String, byteLength: Int) async throws {}
    func write(_ chunk: MediaCopyChunk) async throws {
        _ = try chunk.copyBytes()
    }
    func commit(byteLength: Int) async throws {}
    func abort() async throws {}
}
