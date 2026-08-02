import MediaCapture
import UIKit
import XCTest
@testable import MediaCaptureUI

@MainActor
final class MediaCaptureUiPresenterTests: XCTestCase {
    func testPresenterRejectsOwnerOutsideWindow() throws {
        let core = try FakeMediaCaptureService()
        let presenter = MediaCaptureUiPresenter(
            presentingViewController: UIViewController(),
            core: core
        )
        let configuration = MediaCaptureUiConfiguration(sessionOptions: try SessionOptions(
            enabledMediaTypes: [.photo],
            audioEnabled: false,
            maxVideoDurationMilliseconds: 5_000
        ))

        XCTAssertThrowsError(try presenter.present(configuration: configuration)) { error in
            XCTAssertEqual(error as? MediaCaptureUiPresentationError, .ownerUnavailable)
        }
    }

    func testLifecycleObservationFiltersConfiguredObjectIdentityAndRebinds() {
        let center = NotificationCenter()
        let firstScene = NSObject()
        let secondScene = NSObject()
        var backgroundCount = 0
        var foregroundCount = 0
        var observation: MediaCaptureLifecycleObservation? = MediaCaptureLifecycleObservation(
            sceneObject: firstScene,
            notificationCenter: center,
            didEnterBackground: { backgroundCount += 1 },
            willEnterForeground: { foregroundCount += 1 }
        )

        center.post(name: UIScene.didEnterBackgroundNotification, object: secondScene)
        XCTAssertEqual(backgroundCount, 0)
        center.post(name: UIScene.didEnterBackgroundNotification, object: firstScene)
        XCTAssertEqual(backgroundCount, 1)

        observation = MediaCaptureLifecycleObservation(
            sceneObject: secondScene,
            notificationCenter: center,
            didEnterBackground: { backgroundCount += 1 },
            willEnterForeground: { foregroundCount += 1 }
        )
        center.post(name: UIScene.willEnterForegroundNotification, object: firstScene)
        XCTAssertEqual(foregroundCount, 0)
        center.post(name: UIScene.willEnterForegroundNotification, object: secondScene)
        XCTAssertEqual(foregroundCount, 1)
        XCTAssertTrue(observation?.matches(sceneObject: secondScene) == true)

        observation?.invalidate()
        center.post(name: UIScene.didEnterBackgroundNotification, object: secondScene)
        center.post(name: UIScene.willEnterForegroundNotification, object: secondScene)
        XCTAssertEqual(backgroundCount, 1)
        XCTAssertEqual(foregroundCount, 1)
    }

    func testPublicPresenterRejectsConcurrentFlowAndSceneLifecycleReattaches() async throws {
        let core = try FakeMediaCaptureService(mediaType: .video)
        let owner = UIViewController()
        let window = makeVisibleWindow(rootViewController: owner)
        let dismissal = DismissalTestDriver()
        let presenter = MediaCaptureUiPresenter(
            presentingViewController: owner,
            core: core,
            dismissalAction: dismissal.perform
        )
        let configuration = MediaCaptureUiConfiguration(
            sessionOptions: try SessionOptions(
                enabledMediaTypes: [.video],
                audioEnabled: false,
                maxVideoDurationMilliseconds: 5_000
            )
        )

        let flow = try presenter.present(configuration: configuration)
        XCTAssertThrowsError(try presenter.present(configuration: configuration))
        let capture = try XCTUnwrap(owner.presentedViewController as? MediaCaptureViewController)
        capture.beginAppearanceTransition(true, animated: false)
        capture.endAppearanceTransition()
        let started = await presenterEventually { await core.snapshot().startCount == 1 }
        XCTAssertTrue(started)
        core.emit(.sessionReady(presenterReadySnapshot(sessionHandle: core.sessionHandle)))
        let attached = await presenterEventually {
            await core.snapshot().liveAttachGenerations.count == 1
        }
        XCTAssertTrue(attached)
        let recordingActionAccepted = await presenterEventually {
            capture.activatePrimaryAccessibilityAction()
        }
        XCTAssertTrue(recordingActionAccepted)
        let recording = await presenterEventually {
            await core.snapshot().startRecordingCount == 1
        }
        XCTAssertTrue(recording)
        let stopActionAccepted = await presenterEventually {
            capture.activatePrimaryAccessibilityAction()
        }
        XCTAssertTrue(stopActionAccepted)
        let stopped = await presenterEventually {
            await core.snapshot().stopRecordingCount == 1
        }
        XCTAssertTrue(stopped)

        capture.view.setNeedsLayout()
        capture.view.layoutIfNeeded()
        if let scene = capture.observedLifecycleSceneForTesting {
            NotificationCenter.default.post(
                name: UIScene.didEnterBackgroundNotification,
                object: scene
            )
        } else {
            NotificationCenter.default.post(
                name: UIApplication.didEnterBackgroundNotification,
                object: nil
            )
        }
        let backgrounded = await presenterEventually {
            await core.snapshot().backgroundCount == 1
        }
        XCTAssertTrue(backgrounded)

        if let scene = capture.observedLifecycleSceneForTesting {
            NotificationCenter.default.post(
                name: UIScene.willEnterForegroundNotification,
                object: scene
            )
        } else {
            NotificationCenter.default.post(
                name: UIApplication.willEnterForegroundNotification,
                object: nil
            )
        }
        let reattached = await presenterEventually {
            await core.snapshot().previewAttachGenerations.count == 2
        }
        XCTAssertTrue(reattached)

        flow.dismiss()
        let resultTask = Task { try await flow.awaitResult() }
        let dismissalStarted = await presenterEventually { dismissal.callCount == 1 }
        XCTAssertTrue(dismissalStarted)
        XCTAssertThrowsError(try MediaCapturePresentationRegistry.acquire(owner: owner))
        dismissal.complete()
        let result = try await resultTask.value
        XCTAssertEqual(result, .cancelled)
        let nextReservation = try MediaCapturePresentationRegistry.acquire(owner: owner)
        MediaCapturePresentationRegistry.release(
            ownerIdentifier: nextReservation.ownerIdentifier,
            token: nextReservation.token
        )
        window.isHidden = true
    }

    func testBlockedDismissalCompletesResultButPoisonsSlotUntilCompletion() async throws {
        let core = try FakeMediaCaptureService()
        let owner = UIViewController()
        let window = makeVisibleWindow(rootViewController: owner)
        let dismissal = DismissalTestDriver()
        let presenter = MediaCaptureUiPresenter(
            presentingViewController: owner,
            core: core,
            leaseCleanupOwner: MediaCaptureLeaseCleanupOwner(
                retryDelayNanoseconds: 10_000_000
            ),
            settleTimeoutNanoseconds: 2_000_000,
            dismissalAction: dismissal.perform
        )
        let configuration = MediaCaptureUiConfiguration(sessionOptions: try SessionOptions(
            enabledMediaTypes: [.photo],
            audioEnabled: false,
            maxVideoDurationMilliseconds: 5_000
        ))
        let flow = try presenter.present(configuration: configuration)
        let capture = try XCTUnwrap(owner.presentedViewController as? MediaCaptureViewController)
        capture.beginAppearanceTransition(true, animated: false)
        capture.endAppearanceTransition()
        let started = await presenterEventually { await core.snapshot().startCount == 1 }
        XCTAssertTrue(started)
        core.emit(.sessionReady(presenterReadySnapshot(sessionHandle: core.sessionHandle)))
        let attached = await presenterEventually {
            await core.snapshot().liveAttachGenerations.count == 1
        }
        XCTAssertTrue(attached)

        flow.dismiss()
        let result = try await flow.awaitResult()

        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(dismissal.callCount, 1)
        XCTAssertThrowsError(try MediaCapturePresentationRegistry.acquire(owner: owner))
        dismissal.complete()
        var recoveredReservation: MediaCapturePresentationRegistry.Reservation?
        let recovered = await presenterEventually {
            do {
                recoveredReservation = try MediaCapturePresentationRegistry.acquire(owner: owner)
                return true
            } catch {
                return false
            }
        }
        XCTAssertTrue(recovered)
        if let recoveredReservation {
            MediaCapturePresentationRegistry.release(
                ownerIdentifier: recoveredReservation.ownerIdentifier,
                token: recoveredReservation.token
            )
        }
        window.isHidden = true
    }

    func testMixedModeExposesVoiceOverRecordingCustomAction() async throws {
        let core = try FakeMediaCaptureService()
        let owner = UIViewController()
        let window = makeVisibleWindow(rootViewController: owner)
        let presenter = MediaCaptureUiPresenter(
            presentingViewController: owner,
            core: core,
            dismissalAction: { _, completion in completion() }
        )
        let flow = try presenter.present(configuration: MediaCaptureUiConfiguration(
            sessionOptions: try SessionOptions(
                enabledMediaTypes: [.photo, .video],
                audioEnabled: false,
                maxVideoDurationMilliseconds: 5_000
            )
        ))
        let capture = try XCTUnwrap(owner.presentedViewController as? MediaCaptureViewController)
        capture.beginAppearanceTransition(true, animated: false)
        capture.endAppearanceTransition()
        let started = await presenterEventually { await core.snapshot().startCount == 1 }
        XCTAssertTrue(started)
        core.emit(.sessionReady(presenterReadySnapshot(sessionHandle: core.sessionHandle)))
        let attached = await presenterEventually {
            await core.snapshot().liveAttachGenerations.count == 1
        }
        XCTAssertTrue(attached)
        let recordingActionAccepted = await presenterEventually {
            capture.activateRecordingAccessibilityActionForTesting()
        }
        XCTAssertTrue(recordingActionAccepted)
        let recording = await presenterEventually {
            await core.snapshot().startRecordingCount == 1
        }
        XCTAssertTrue(recording)

        flow.dismiss()
        _ = try await flow.awaitResult()
        window.isHidden = true
    }

    func testCancellingPublicResultWaiterCleansUpFlowAndPropagatesCancellation() async {
        let core: FakeMediaCaptureService
        do {
            core = try FakeMediaCaptureService()
        } catch {
            return XCTFail("Core fixture setup failed: \(error)")
        }
        let owner = UIViewController()
        let window = makeVisibleWindow(rootViewController: owner)
        let presenter = MediaCaptureUiPresenter(
            presentingViewController: owner,
            core: core,
            dismissalAction: { _, completion in completion() }
        )
        let flow: MediaCaptureFlowSession
        do {
            flow = try presenter.present(configuration: MediaCaptureUiConfiguration(
                sessionOptions: try SessionOptions(
                    enabledMediaTypes: [.photo],
                    audioEnabled: false,
                    maxVideoDurationMilliseconds: 5_000
                )
            ))
        } catch {
            return XCTFail("Presentation setup failed: \(error)")
        }
        guard let capture = owner.presentedViewController as? MediaCaptureViewController else {
            return XCTFail("Expected MediaCaptureViewController")
        }
        capture.beginAppearanceTransition(true, animated: false)
        capture.endAppearanceTransition()
        let started = await presenterEventually { await core.snapshot().startCount == 1 }
        XCTAssertTrue(started)
        core.emit(.sessionReady(presenterReadySnapshot(sessionHandle: core.sessionHandle)))
        let attached = await presenterEventually {
            await core.snapshot().liveAttachGenerations.count == 1
        }
        XCTAssertTrue(attached)

        let resultTask = Task { @MainActor in
            do {
                return Result<MediaCaptureFlowResult, Error>.success(
                    try await flow.awaitResult()
                )
            } catch {
                return .failure(error)
            }
        }
        let waiterRegistered = await presenterEventually {
            flow.resultWaiterRegisteredForTesting
        }
        XCTAssertTrue(waiterRegistered)
        resultTask.cancel()

        switch await resultTask.value {
        case .success:
            XCTFail("Cancelling the public waiter must throw CancellationError")
            return
        case let .failure(error) where error is CancellationError:
            break
        case let .failure(error):
            XCTFail(
                "Unexpected public waiter error \(String(reflecting: type(of: error))): \(error)"
            )
            return
        }
        let cleanedUp = await presenterEventually {
            let snapshot = await core.snapshot()
            return snapshot.cancelCount == 1
                && snapshot.liveDetachCount == 1
                && snapshot.eventTerminationCount == 1
        }
        XCTAssertTrue(cleanedUp)
        var nextReservation: MediaCapturePresentationRegistry.Reservation?
        let slotReleased = await presenterEventually {
            do {
                nextReservation = try MediaCapturePresentationRegistry.acquire(owner: owner)
                return true
            } catch {
                return false
            }
        }
        XCTAssertTrue(slotReleased)
        if let nextReservation {
            MediaCapturePresentationRegistry.release(
                ownerIdentifier: nextReservation.ownerIdentifier,
                token: nextReservation.token
            )
        }
        window.isHidden = true
    }
}

@MainActor
private final class DismissalTestDriver {
    private var completion: (@MainActor @Sendable () -> Void)?
    private(set) var callCount = 0

    func perform(
        _ viewController: UIViewController,
        completion: @escaping @MainActor @Sendable () -> Void
    ) {
        callCount += 1
        self.completion = completion
    }

    func complete() {
        let completion = completion
        self.completion = nil
        completion?()
    }
}

@MainActor
private func makeVisibleWindow(rootViewController: UIViewController) -> UIWindow {
    let frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    let window: UIWindow
    if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
        window = UIWindow(windowScene: scene)
        window.frame = frame
    } else {
        window = UIWindow(frame: frame)
    }
    window.rootViewController = rootViewController
    window.makeKeyAndVisible()
    rootViewController.view.layoutIfNeeded()
    return window
}

private func presenterReadySnapshot(sessionHandle: SessionHandle) -> SessionReadySnapshot {
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

@MainActor
private func presenterEventually(
    attempts: Int = 300,
    _ predicate: @MainActor () async -> Bool
) async -> Bool {
    for _ in 0 ..< attempts {
        if await predicate() { return true }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return false
}
