import XCTest
@testable import MediaCaptureUI

final class CaptureGestureControllerTests: XCTestCase {
    func testTapProducesPhotoAndLongPressProducesRecordingSequence() {
        var gesture = CaptureGestureController()

        gesture.begin(atY: 100)
        XCTAssertEqual(gesture.end(), .takePhoto)

        gesture.begin(atY: 100)
        XCTAssertEqual(gesture.activateLongPress(videoEnabled: true), .startRecording)
        XCTAssertEqual(gesture.move(toY: 40), .updateZoom(verticalDelta: 60))
        XCTAssertEqual(gesture.move(toY: 30), .updateZoom(verticalDelta: 10))
        XCTAssertEqual(gesture.end(), .stopRecording)
    }

    func testDisabledVideoAndCancellationDoNotStartRecording() {
        var gesture = CaptureGestureController()
        gesture.begin(atY: 80)
        XCTAssertEqual(gesture.activateLongPress(videoEnabled: false), .none)
        XCTAssertEqual(gesture.cancel(), .none)
        XCTAssertEqual(gesture.end(), .none)
    }
}
