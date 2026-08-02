import MediaCapture
import MediaCaptureAppleRendering
import UIKit

@MainActor
internal final class MediaCaptureChromeView: UIView {
    let renderContainer = UIView()
    let closeButton = MediaCaptureChromeView.makeIconButton(
        symbol: "xmark",
        accessibilityKey: "media_capture_close"
    )
    let flashButton = MediaCaptureChromeView.makeIconButton(
        symbol: "bolt.slash.fill",
        accessibilityKey: "media_capture_flash_off"
    )
    let switchCameraButton = MediaCaptureChromeView.makeIconButton(
        symbol: "arrow.triangle.2.circlepath.camera",
        accessibilityKey: "media_capture_switch_camera"
    )
    let confirmButton = MediaCaptureChromeView.makeIconButton(
        symbol: "paperplane.fill",
        accessibilityKey: "media_capture_confirm"
    )
    let shutterButton = CaptureShutterButton()

    private let controlsBackground = UIView()
    private let focusIndicator = UIView()
    private var controlsHeight: NSLayoutConstraint?
    private(set) weak var renderView: MediaCaptureRenderView?

    var controlsRegionHeight: CGFloat {
        controlsHeight?.constant ?? 0
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isAccessibilityElement = false
        configureHierarchy()
        configureConstraints()
        apply(MediaCaptureUiSnapshot(
            phase: .starting,
            ready: nil,
            flashMode: .off,
            recordingProgress: 0,
            photoEnabled: true,
            videoEnabled: true
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        controlsHeight?.constant = 112 + safeAreaInsets.bottom
    }

    func installRenderView(_ view: MediaCaptureRenderView) {
        renderView?.removeFromSuperview()
        renderContainer.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: renderContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: renderContainer.trailingAnchor),
            view.topAnchor.constraint(equalTo: renderContainer.topAnchor),
            view.bottomAnchor.constraint(equalTo: renderContainer.bottomAnchor),
        ])
        renderView = view
    }

    func removeRenderView() {
        renderView?.removeFromSuperview()
    }

    func apply(_ snapshot: MediaCaptureUiSnapshot) {
        let isPreview: Bool
        let isRecording: Bool
        let isBusy: Bool
        switch snapshot.phase {
        case .preview:
            isPreview = true
            isRecording = false
            isBusy = false
        case .startingRecording, .recording, .stoppingRecording:
            isPreview = false
            isRecording = true
            isBusy = false
        case .live:
            isPreview = false
            isRecording = false
            isBusy = false
        case .starting, .switchingCamera, .capturing, .confirming, .terminal:
            isPreview = false
            isRecording = false
            isBusy = true
        }

        closeButton.setImage(symbolImage(
            isPreview ? "arrow.counterclockwise" : "xmark",
            fallback: isPreview ? "gobackward" : "multiply"
        ), for: .normal)
        closeButton.accessibilityLabel = localized(
            isPreview ? "media_capture_retake" : "media_capture_close"
        )
        confirmButton.isHidden = !isPreview
        shutterButton.isHidden = isPreview
        shutterButton.isUserInteractionEnabled = !isBusy
        shutterButton.setRecording(isRecording, progress: snapshot.recordingProgress)
        shutterButton.configureAccessibility(
            phase: snapshot.phase,
            photoEnabled: snapshot.photoEnabled,
            videoEnabled: snapshot.videoEnabled
        )

        let ready = snapshot.ready
        let canSwitch = (ready?.switchCameraSupported == true) && !isRecording && !isPreview && !isBusy
        let canFlash = (ready?.supportedFlashModes.contains { $0 != .off } == true)
            && !isRecording && !isPreview && !isBusy
        switchCameraButton.isHidden = !canSwitch
        flashButton.isHidden = !canFlash
        flashButton.setImage(
            symbolImage(flashSymbol(snapshot.flashMode), fallback: "bolt"),
            for: .normal
        )
        flashButton.accessibilityLabel = localized(flashAccessibilityKey(snapshot.flashMode))
        closeButton.isEnabled = snapshot.phase != .terminal && snapshot.phase != .confirming
        confirmButton.isEnabled = isPreview && !isBusy
    }

    func beginRecordingProgress(duration: TimeInterval) {
        shutterButton.beginRecordingProgress(duration: duration)
    }

    func showFocus(at point: CGPoint) {
        focusIndicator.center = point
        focusIndicator.alpha = 1
        focusIndicator.transform = CGAffineTransform(scaleX: 1.25, y: 1.25)
        UIView.animate(
            withDuration: 0.18,
            animations: { self.focusIndicator.transform = .identity },
            completion: { _ in
                UIView.animate(withDuration: 0.28, delay: 0.35, options: []) {
                    self.focusIndicator.alpha = 0
                }
            }
        )
    }

    private func configureHierarchy() {
        renderContainer.backgroundColor = .black
        renderContainer.clipsToBounds = true
        controlsBackground.backgroundColor = .black
        focusIndicator.layer.borderWidth = 1.5
        focusIndicator.layer.borderColor = UIColor.white.cgColor
        focusIndicator.layer.cornerRadius = 4
        focusIndicator.alpha = 0
        confirmButton.backgroundColor = UIColor(red: 0, green: 76 / 255, blue: 1, alpha: 1)
        confirmButton.layer.cornerRadius = 24

        [renderContainer, controlsBackground, closeButton, flashButton, switchCameraButton,
         confirmButton, shutterButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        focusIndicator.bounds = CGRect(x: 0, y: 0, width: 54, height: 54)
        addSubview(focusIndicator)
        bringSubviewToFront(closeButton)
        bringSubviewToFront(flashButton)
        bringSubviewToFront(focusIndicator)
    }

    private func configureConstraints() {
        let controlsHeight = controlsBackground.heightAnchor.constraint(
            equalToConstant: 112 + safeAreaInsets.bottom
        )
        self.controlsHeight = controlsHeight
        NSLayoutConstraint.activate([
            controlsBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            controlsBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            controlsBackground.bottomAnchor.constraint(equalTo: bottomAnchor),
            controlsHeight,

            renderContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            renderContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            renderContainer.topAnchor.constraint(equalTo: topAnchor),
            renderContainer.bottomAnchor.constraint(equalTo: controlsBackground.topAnchor),

            closeButton.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 12),
            closeButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.widthAnchor.constraint(equalToConstant: 48),
            closeButton.heightAnchor.constraint(equalToConstant: 48),

            flashButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -12),
            flashButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 12),
            flashButton.widthAnchor.constraint(equalToConstant: 48),
            flashButton.heightAnchor.constraint(equalToConstant: 48),

            shutterButton.centerXAnchor.constraint(equalTo: controlsBackground.centerXAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -16),
            shutterButton.widthAnchor.constraint(equalToConstant: 80),
            shutterButton.heightAnchor.constraint(equalToConstant: 80),

            switchCameraButton.trailingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.trailingAnchor,
                constant: -28
            ),
            switchCameraButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
            switchCameraButton.widthAnchor.constraint(equalToConstant: 48),
            switchCameraButton.heightAnchor.constraint(equalToConstant: 48),

            confirmButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -28),
            confirmButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
            confirmButton.widthAnchor.constraint(equalToConstant: 54),
            confirmButton.heightAnchor.constraint(equalToConstant: 48),
        ])
    }

    private static func makeIconButton(symbol: String, accessibilityKey: String) -> UIButton {
        let button = UIButton(type: .system)
        button.tintColor = .white
        button.setImage(symbolImage(symbol, fallback: "circle"), for: .normal)
        button.accessibilityLabel = localized(accessibilityKey)
        button.adjustsImageWhenHighlighted = true
        return button
    }
}

@MainActor
internal final class CaptureShutterButton: UIControl {
    private static let recordingProgressAnimationKey = "recording_progress"
    private let outerRing = CAShapeLayer()
    private let innerDisc = CAShapeLayer()
    private let progressRing = CAShapeLayer()
    private var animatingRecordingProgress = false
    var primaryAccessibilityHandler: (() -> Bool)?
    var recordingAccessibilityHandler: (() -> Bool)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = localized("media_capture_photo")
        layer.addSublayer(outerRing)
        layer.addSublayer(progressRing)
        layer.addSublayer(innerDisc)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        outerRing.path = UIBezierPath(arcCenter: center, radius: 37, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
        outerRing.fillColor = UIColor.clear.cgColor
        outerRing.strokeColor = UIColor.white.cgColor
        outerRing.lineWidth = 4
        innerDisc.path = UIBezierPath(ovalIn: bounds.insetBy(dx: 9, dy: 9)).cgPath
        progressRing.path = UIBezierPath(
            arcCenter: center,
            radius: 36,
            startAngle: -.pi / 2,
            endAngle: .pi * 1.5,
            clockwise: true
        ).cgPath
        progressRing.fillColor = UIColor.clear.cgColor
        progressRing.strokeColor = UIColor(red: 0, green: 76 / 255, blue: 1, alpha: 1).cgColor
        progressRing.lineWidth = 5
        progressRing.lineCap = .round
    }

    func setRecording(_ recording: Bool, progress: Double) {
        innerDisc.fillColor = (recording ? UIColor.systemRed : UIColor.white).cgColor
        progressRing.isHidden = !recording
        if recording {
            guard !animatingRecordingProgress else { return }
            setProgressWithoutImplicitAnimation(CGFloat(min(max(progress, 0), 1)))
        } else {
            animatingRecordingProgress = false
            progressRing.removeAnimation(forKey: Self.recordingProgressAnimationKey)
            setProgressWithoutImplicitAnimation(0)
        }
    }

    func beginRecordingProgress(duration: TimeInterval) {
        guard duration > 0 else { return }
        let start = progressRing.presentation()?.strokeEnd ?? progressRing.strokeEnd
        let boundedStart = min(max(start, 0), 1)
        let remainingDuration = duration * Double(1 - boundedStart)
        animatingRecordingProgress = true
        progressRing.isHidden = false
        setProgressWithoutImplicitAnimation(1)

        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.fromValue = boundedStart
        animation.toValue = CGFloat(1)
        animation.duration = remainingDuration
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        progressRing.add(animation, forKey: Self.recordingProgressAnimationKey)
    }

    var recordingProgressForTesting: CGFloat {
        progressRing.strokeEnd
    }

    var recordingProgressAnimationForTesting: CABasicAnimation? {
        progressRing.animation(forKey: Self.recordingProgressAnimationKey) as? CABasicAnimation
    }

    private func setProgressWithoutImplicitAnimation(_ progress: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressRing.strokeEnd = progress
        CATransaction.commit()
    }

    override func accessibilityActivate() -> Bool {
        primaryAccessibilityHandler?() ?? false
    }

    func configureAccessibility(
        phase: MediaCaptureUiPhase,
        photoEnabled: Bool,
        videoEnabled: Bool
    ) {
        switch phase {
        case .recording:
            accessibilityLabel = localized("media_capture_stop")
            accessibilityCustomActions = nil
        case .live:
            accessibilityLabel = localized(
                photoEnabled ? "media_capture_photo" : "media_capture_record"
            )
            if photoEnabled, videoEnabled {
                accessibilityCustomActions = [UIAccessibilityCustomAction(
                    name: localized("media_capture_record"),
                    target: self,
                    selector: #selector(performRecordingAccessibilityAction)
                )]
            } else {
                accessibilityCustomActions = nil
            }
        default:
            accessibilityCustomActions = nil
        }
    }

    @objc func performRecordingAccessibilityAction() -> Bool {
        recordingAccessibilityHandler?() ?? false
    }
}

private func localized(_ key: String) -> String {
    NSLocalizedString(key, bundle: .module, comment: "")
}

private func flashSymbol(_ mode: FlashMode) -> String {
    switch mode {
    case .off: return "bolt.slash.fill"
    case .on: return "bolt.fill"
    case .auto: return "bolt.badge.a.fill"
    case .torch: return "flashlight.on.fill"
    }
}

private func symbolImage(_ name: String, fallback: String) -> UIImage? {
    UIImage(systemName: name) ?? UIImage(systemName: fallback)
}

private func flashAccessibilityKey(_ mode: FlashMode) -> String {
    switch mode {
    case .off: return "media_capture_flash_off"
    case .on: return "media_capture_flash_on"
    case .auto: return "media_capture_flash_auto"
    case .torch: return "media_capture_flash_torch"
    }
}
