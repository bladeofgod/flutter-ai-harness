import XCTest
@testable import MediaCapture

final class PackageSmokeTests: XCTestCase {
    func testPublicFailureUsesStableIdentifier() {
        XCTAssertEqual(
            MediaCaptureFailure(.sessionInvalid).id.rawValue,
            "session_invalid"
        )
    }
}
