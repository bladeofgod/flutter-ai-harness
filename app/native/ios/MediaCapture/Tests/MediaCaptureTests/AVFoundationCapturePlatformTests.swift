import XCTest
@testable import MediaCapture

final class AVFoundationCapturePlatformTests: XCTestCase {
    func testConfigurationIsCommittedBeforeSessionStarts() {
        var calls: [String] = []

        configureCaptureSession(
            beginConfiguration: { calls.append("begin") },
            applyConfiguration: { calls.append("apply") },
            commitConfiguration: { calls.append("commit") },
            isRunning: {
                calls.append("isRunning")
                return false
            },
            startRunning: { calls.append("start") }
        )

        XCTAssertEqual(calls, ["begin", "apply", "commit", "isRunning", "start"])
    }

    func testFailedConfigurationIsCommittedWithoutStartingSession() {
        enum ExpectedFailure: Error { case apply }
        var calls: [String] = []

        XCTAssertThrowsError(try configureCaptureSession(
            beginConfiguration: { calls.append("begin") },
            applyConfiguration: {
                calls.append("apply")
                throw ExpectedFailure.apply
            },
            commitConfiguration: { calls.append("commit") },
            isRunning: {
                calls.append("isRunning")
                return false
            },
            startRunning: { calls.append("start") }
        ))

        XCTAssertEqual(calls, ["begin", "apply", "commit"])
    }
}
