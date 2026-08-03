import MediaCapture
import UIKit
import XCTest
@testable import MediaCaptureUI

@MainActor
final class MediaCaptureChromeViewTests: XCTestCase {
    func testControlsKeepAccessibleTargetsOnNarrowAndLandscapeLayouts() {
        for size in [CGSize(width: 320, height: 568), CGSize(width: 812, height: 375)] {
            let view = MediaCaptureChromeView(frame: CGRect(origin: .zero, size: size))
            view.setNeedsLayout()
            view.layoutIfNeeded()

            XCTAssertGreaterThanOrEqual(view.closeButton.bounds.width, 48)
            XCTAssertGreaterThanOrEqual(view.closeButton.bounds.height, 48)
            XCTAssertGreaterThanOrEqual(view.confirmButton.bounds.height, 48)
            XCTAssertEqual(view.shutterButton.bounds.size, CGSize(width: 80, height: 80))
            XCTAssertNotNil(view.closeButton.accessibilityLabel)
            XCTAssertNotNil(view.switchCameraButton.accessibilityLabel)
        }
    }

    func testRecordingHidesSideActionsAndPreviewExposesRetakeAndConfirm() throws {
        let view = MediaCaptureChromeView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let session = try SessionHandle(rawValue: String(repeating: "s", count: 32))
        let ready = makeChromeReadySnapshot(sessionHandle: session)

        view.apply(MediaCaptureUiSnapshot(
            phase: .recording,
            ready: ready,
            flashMode: .off,
            recordingProgress: 0.4,
            photoEnabled: true,
            videoEnabled: true
        ))
        XCTAssertTrue(view.flashButton.isHidden)
        XCTAssertTrue(view.switchCameraButton.isHidden)
        XCTAssertFalse(view.shutterButton.isHidden)
        XCTAssertEqual(view.shutterButton.recordingProgressForTesting, 0.4, accuracy: 0.001)

        view.beginRecordingProgress(duration: 15)
        let progressAnimation = try XCTUnwrap(
            view.shutterButton.recordingProgressAnimationForTesting
        )
        XCTAssertEqual(progressAnimation.duration, 9, accuracy: 0.001)
        XCTAssertNotNil(progressAnimation.timingFunction)

        view.apply(MediaCaptureUiSnapshot(
            phase: .stoppingRecording,
            ready: ready,
            flashMode: .off,
            recordingProgress: 0.4,
            photoEnabled: true,
            videoEnabled: true
        ))
        XCTAssertFalse(view.shutterButton.isUserInteractionEnabled)
        XCTAssertNil(view.shutterButton.recordingProgressAnimationForTesting)
        XCTAssertEqual(view.shutterButton.recordingProgressForTesting, 0)

        let metadata = try MediaMetadata(
            mediaHandle: MediaHandle(rawValue: String(repeating: "m", count: 32)),
            mediaType: .photo,
            pixelWidth: 100,
            pixelHeight: 100,
            durationMilliseconds: nil,
            orientationDegrees: 0,
            byteLength: 100
        )
        view.apply(MediaCaptureUiSnapshot(
            phase: .preview(metadata),
            ready: ready,
            flashMode: .off,
            recordingProgress: 0,
            photoEnabled: true,
            videoEnabled: true
        ))
        XCTAssertTrue(view.shutterButton.isHidden)
        XCTAssertFalse(view.confirmButton.isHidden)
        XCTAssertFalse(view.closeButton.accessibilityLabel?.isEmpty ?? true)
        XCTAssertNil(view.shutterButton.recordingProgressAnimationForTesting)
        XCTAssertEqual(view.shutterButton.recordingProgressForTesting, 0)
    }

    func testShutterProvidesPrimaryAndRecordingAccessibilityActions() throws {
        let view = MediaCaptureChromeView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let session = try SessionHandle(rawValue: String(repeating: "s", count: 32))
        var primaryCount = 0
        var recordingCount = 0
        view.shutterButton.primaryAccessibilityHandler = {
            primaryCount += 1
            return true
        }
        view.shutterButton.recordingAccessibilityHandler = {
            recordingCount += 1
            return true
        }
        view.apply(MediaCaptureUiSnapshot(
            phase: .live,
            ready: makeChromeReadySnapshot(sessionHandle: session),
            flashMode: .off,
            recordingProgress: 0,
            photoEnabled: true,
            videoEnabled: true
        ))

        XCTAssertTrue(view.shutterButton.accessibilityActivate())
        XCTAssertTrue(view.shutterButton.performRecordingAccessibilityAction())
        XCTAssertEqual(primaryCount, 1)
        XCTAssertEqual(recordingCount, 1)
        XCTAssertEqual(view.shutterButton.accessibilityCustomActions?.count, 1)
        XCTAssertNotNil(view.closeButton.image(for: .normal))
        XCTAssertNotNil(view.switchCameraButton.image(for: .normal))
    }

    func testBottomControlRegionIncludesSafeAreaInset() {
        let view = MediaCaptureChromeView()
        let host = UIViewController()
        host.view = view
        host.additionalSafeAreaInsets.bottom = 34
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()

        view.frame = window.bounds
        view.setNeedsLayout()
        view.layoutIfNeeded()

        XCTAssertGreaterThanOrEqual(view.controlsRegionHeight, 146)
        window.isHidden = true
    }
}

private func makeChromeReadySnapshot(sessionHandle: SessionHandle) -> SessionReadySnapshot {
    SessionReadySnapshot(
        sessionHandle: sessionHandle,
        activeCamera: .rear,
        availableCameras: [.rear, .front],
        switchCameraSupported: true,
        supportedFlashModes: [.off, .on],
        focusPointSupported: true,
        minimumZoomFactor: 1,
        maximumZoomFactor: 4
    )
}
