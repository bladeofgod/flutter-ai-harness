import MediaCapture
import MediaCaptureAppleRendering
import UIKit

@MainActor
internal final class MediaCaptureLifecycleObservation {
    private final class ActionRelay: Sendable {
        private let didEnterBackground: @MainActor @Sendable () -> Void
        private let willEnterForeground: @MainActor @Sendable () -> Void

        init(
            didEnterBackground: @escaping @MainActor @Sendable () -> Void,
            willEnterForeground: @escaping @MainActor @Sendable () -> Void
        ) {
            self.didEnterBackground = didEnterBackground
            self.willEnterForeground = willEnterForeground
        }

        @MainActor
        func enterBackground() {
            didEnterBackground()
        }

        @MainActor
        func enterForeground() {
            willEnterForeground()
        }
    }

    private(set) weak var sceneObject: AnyObject?
    private let notificationCenter: NotificationCenter
    private var observers: [NSObjectProtocol] = []

    init(
        sceneObject: AnyObject?,
        notificationCenter: NotificationCenter = .default,
        didEnterBackground: @escaping @MainActor @Sendable () -> Void,
        willEnterForeground: @escaping @MainActor @Sendable () -> Void
    ) {
        self.sceneObject = sceneObject
        self.notificationCenter = notificationCenter
        let relay = ActionRelay(
            didEnterBackground: didEnterBackground,
            willEnterForeground: willEnterForeground
        )
        if let sceneObject {
            observers = [
                notificationCenter.addObserver(
                    forName: UIScene.didEnterBackgroundNotification,
                    object: sceneObject,
                    queue: .main
                ) { _ in
                    MainActor.assumeIsolated { relay.enterBackground() }
                },
                notificationCenter.addObserver(
                    forName: UIScene.willEnterForegroundNotification,
                    object: sceneObject,
                    queue: .main
                ) { _ in
                    MainActor.assumeIsolated { relay.enterForeground() }
                },
            ]
        } else {
            observers = [
                notificationCenter.addObserver(
                    forName: UIApplication.didEnterBackgroundNotification,
                    object: nil,
                    queue: .main
                ) { _ in MainActor.assumeIsolated { relay.enterBackground() } },
                notificationCenter.addObserver(
                    forName: UIApplication.willEnterForegroundNotification,
                    object: nil,
                    queue: .main
                ) { _ in MainActor.assumeIsolated { relay.enterForeground() } },
            ]
        }
    }

    func matches(sceneObject: AnyObject?) -> Bool {
        self.sceneObject === sceneObject
    }

    func invalidate() {
        let tokens = observers
        observers.removeAll()
        tokens.forEach(notificationCenter.removeObserver)
    }

    deinit {
        MainActor.assumeIsolated {
            invalidate()
        }
    }
}

@MainActor
internal final class MediaCaptureViewController: UIViewController {
    private let chromeView: MediaCaptureChromeView
    private let coordinator: MediaCaptureFlowCoordinator
    private var gestureController = CaptureGestureController()
    private var snapshot = MediaCaptureUiSnapshot(
        phase: .starting,
        ready: nil,
        flashMode: .off,
        recordingProgress: 0,
        photoEnabled: true,
        videoEnabled: true
    )
    private var expectedDismissal = false
    private var lifecycleObservation: MediaCaptureLifecycleObservation?

    init(
        coordinator: MediaCaptureFlowCoordinator,
        devicePointConverter: MediaCaptureDevicePointConverter? = nil
    ) {
        self.coordinator = coordinator
        if let devicePointConverter {
            chromeView = MediaCaptureChromeView(devicePointConverter: devicePointConverter)
        } else {
            chromeView = MediaCaptureChromeView()
        }
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalPresentationCapturesStatusBarAppearance = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    override var prefersStatusBarHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .bottom }

    override func loadView() {
        view = chromeView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureActions()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshLifecycleObservationIfNeeded()
        coordinator.beginIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        refreshLifecycleObservationIfNeeded()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard !expectedDismissal,
              isBeingDismissed || navigationController?.isBeingDismissed == true
        else { return }
        coordinator.ownerWasDestroyed()
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.coordinator.displayRotationChanged()
        }
    }

    deinit {
        MainActor.assumeIsolated {
            coordinator.ownerWasDestroyed()
        }
    }

    func installRenderView(_ view: MediaCaptureRenderView) {
        chromeView.installRenderView(view)
    }

    func removeRenderView() {
        chromeView.removeRenderView()
    }

    func apply(_ snapshot: MediaCaptureUiSnapshot) {
        self.snapshot = snapshot
        chromeView.apply(snapshot)
    }

    func beginRecordingProgress(duration: TimeInterval) {
        chromeView.beginRecordingProgress(duration: duration)
    }

    func markExpectedDismissal() {
        expectedDismissal = true
    }

    func activatePrimaryAccessibilityAction() -> Bool {
        chromeView.shutterButton.accessibilityActivate()
    }

    func activateRecordingAccessibilityActionForTesting() -> Bool {
        chromeView.shutterButton.performRecordingAccessibilityAction()
    }

    var observedLifecycleSceneForTesting: UIWindowScene? {
        lifecycleObservation?.sceneObject as? UIWindowScene
    }

    private func configureActions() {
        chromeView.closeButton.addTarget(self, action: #selector(closePressed), for: .touchUpInside)
        chromeView.confirmButton.addTarget(self, action: #selector(confirmPressed), for: .touchUpInside)
        chromeView.switchCameraButton.addTarget(
            self,
            action: #selector(switchCameraPressed),
            for: .touchUpInside
        )
        chromeView.flashButton.addTarget(self, action: #selector(flashPressed), for: .touchUpInside)
        chromeView.shutterButton.primaryAccessibilityHandler = { [weak self] in
            self?.activatePrimaryShutterAction() ?? false
        }
        chromeView.shutterButton.recordingAccessibilityHandler = { [weak self] in
            self?.activateRecordingAccessibilityAction() ?? false
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(shutterTapped(_:)))
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(shutterLongPressed(_:)))
        longPress.minimumPressDuration = 0.35
        longPress.allowableMovement = 160
        tap.require(toFail: longPress)
        chromeView.shutterButton.addGestureRecognizer(tap)
        chromeView.shutterButton.addGestureRecognizer(longPress)

        let focus = UITapGestureRecognizer(target: self, action: #selector(focusTapped(_:)))
        focus.cancelsTouchesInView = false
        chromeView.renderContainer.addGestureRecognizer(focus)
    }

    @objc private func closePressed() {
        if case .preview = snapshot.phase {
            coordinator.retake()
        } else {
            coordinator.dismissByCaller()
        }
    }

    @objc private func confirmPressed() {
        coordinator.confirm()
    }

    @objc private func switchCameraPressed() {
        coordinator.switchCamera()
    }

    @objc private func flashPressed() {
        coordinator.cycleFlash()
    }

    @objc private func shutterTapped(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        let point = recognizer.location(in: chromeView.shutterButton)
        gestureController.begin(atY: point.y)
        perform(gestureController.end())
    }

    @objc private func shutterLongPressed(_ recognizer: UILongPressGestureRecognizer) {
        let point = recognizer.location(in: chromeView.shutterButton)
        switch recognizer.state {
        case .began:
            gestureController.begin(atY: point.y)
            perform(gestureController.activateLongPress(
                videoEnabled: coordinator.videoCaptureEnabled
            ))
        case .changed:
            perform(gestureController.move(toY: point.y))
        case .ended:
            perform(gestureController.end())
        case .cancelled, .failed:
            perform(gestureController.cancel())
        default:
            break
        }
    }

    @objc private func focusTapped(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        let point = recognizer.location(in: chromeView.renderContainer)
        focus(atRenderPoint: point)
    }

    @discardableResult
    func focus(atRenderPoint point: CGPoint) -> Bool {
        guard let devicePoint = chromeView.captureDevicePoint(fromRenderPoint: point) else {
            return false
        }
        if coordinator.focus(
            normalizedX: min(max(Double(devicePoint.x), 0), 1),
            normalizedY: min(max(Double(devicePoint.y), 0), 1)
        ) {
            chromeView.showFocus(at: point)
            return true
        }
        return false
    }

    private func perform(_ action: CaptureGestureAction) {
        switch action {
        case .none:
            break
        case .takePhoto:
            _ = coordinator.takePhoto()
        case .startRecording:
            _ = coordinator.startRecording()
        case let .updateZoom(verticalDelta):
            coordinator.updateZoom(verticalDelta: verticalDelta)
        case .stopRecording:
            _ = coordinator.stopRecording()
        }
    }

    private func activatePrimaryShutterAction() -> Bool {
        if snapshot.phase == .recording {
            return coordinator.stopRecording()
        }
        guard snapshot.phase == .live else { return false }
        if snapshot.photoEnabled {
            return coordinator.takePhoto()
        } else if snapshot.videoEnabled {
            return coordinator.startRecording()
        } else {
            return false
        }
    }

    private func activateRecordingAccessibilityAction() -> Bool {
        guard snapshot.phase == .live, snapshot.videoEnabled else { return false }
        return coordinator.startRecording()
    }

    private func refreshLifecycleObservationIfNeeded() {
        let scene = viewIfLoaded?.window?.windowScene
        if lifecycleObservation?.matches(sceneObject: scene) == true { return }
        lifecycleObservation?.invalidate()
        lifecycleObservation = MediaCaptureLifecycleObservation(
            sceneObject: scene,
            didEnterBackground: { [weak self] in self?.coordinator.appDidEnterBackground() },
            willEnterForeground: { [weak self] in self?.coordinator.appWillEnterForeground() }
        )
    }
}
