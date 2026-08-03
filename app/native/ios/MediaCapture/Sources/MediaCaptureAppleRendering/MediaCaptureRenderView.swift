import AVFoundation
import MediaCapture
import UIKit

@MainActor
public enum MediaCaptureRenderSurfaceFactory {
    public static func make(
        owner: MediaCaptureRenderSurfaceOwner
    ) throws -> MediaCaptureRenderView {
        let view = MediaCaptureRenderView(surfaceOwner: owner)
        let endpoint = view.makeMountEndpoint()
        try owner.install(endpoint: endpoint)
        view.mountEndpoint = endpoint
        return view
    }
}

@MainActor
public final class MediaCaptureRenderView: UIView, @unchecked Sendable {
    public let surfaceOwner: MediaCaptureRenderSurfaceOwner

    package var mountEndpoint: MediaCaptureRenderMountEndpoint?
    private var mountedContent: MountedContent?
    private var attachmentContext: RenderAttachmentContext?
    private let devicePointConverter: ((AVCaptureVideoPreviewLayer, CGPoint) -> CGPoint)?

    package init(
        surfaceOwner: MediaCaptureRenderSurfaceOwner,
        devicePointConverter: ((AVCaptureVideoPreviewLayer, CGPoint) -> CGPoint)? = nil
    ) {
        self.surfaceOwner = surfaceOwner
        self.devicePointConverter = devicePointConverter
        super.init(frame: .zero)
        clipsToBounds = true
        backgroundColor = .black
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    deinit {
        if let mountEndpoint {
            surfaceOwner.surfaceDestroyed(endpointIdentifier: mountEndpoint.identity)
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        mountedContent?.layer.frame = bounds
    }

    public func captureDevicePoint(fromViewPoint viewPoint: CGPoint) -> CGPoint? {
        guard bounds.contains(viewPoint) else { return nil }
        return mountedContent?.captureDevicePoint(fromLayerPoint: viewPoint)
    }

    package func makeMountEndpoint() -> MediaCaptureRenderMountEndpoint {
        MediaCaptureRenderMountEndpoint(
            identity: ObjectIdentifier(self),
            backingAvailable: { [weak self] in self != nil },
            mount: { [weak self] source, context, callbackGate in
                guard let self else { throw MediaCaptureFailure(.invalidArgument) }
                return try await self.mount(
                    source: source,
                    context: context,
                    callbackGate: callbackGate
                )
            },
            attached: { [weak self] context in
                self?.attachmentContext = context
            },
            revoked: { [weak self] context in
                guard self?.attachmentContext == context else { return }
                self?.attachmentContext = nil
            },
            detached: { _ in }
        )
    }

    package func mount(
        source: MediaCaptureRenderSource,
        context: RenderAttachmentContext,
        callbackGate: MediaCaptureRenderCallbackGate
    ) async throws -> MediaCaptureRenderBinding {
        guard let binding = await callbackGate.performMountIfActive({
            mountedContent?.revoke()
            mountedContent?.detach()

            let content = MountedContent(
                source: source,
                frame: bounds,
                devicePointConverter: devicePointConverter
            )
            layer.addSublayer(content.layer)
            mountedContent = content

            return MediaCaptureRenderBinding(
                callbackGate: callbackGate,
                revoke: { [weak self, content] in
                    content.revoke()
                    if self?.mountedContent === content {
                        self?.attachmentContext = nil
                    }
                },
                detach: { [weak self, content] in
                    content.detach()
                    if self?.mountedContent === content {
                        self?.mountedContent = nil
                        self?.attachmentContext = nil
                    }
                }
            )
        }) else {
            throw MediaCaptureFailure(.attachmentGenerationRetired)
        }
        return binding
    }

    package var mountedLayer: CALayer? {
        mountedContent?.layer
    }

    package func ownsLiveSession(_ session: AVCaptureSession) -> Bool {
        mountedContent?.liveSession === session
    }

    package func ownsVideoPlayer(_ player: AVPlayer) -> Bool {
        mountedContent?.player === player
    }

    package var mountedPlayer: AVPlayer? {
        mountedContent?.player
    }

    package var hasDecodedPhotoContent: Bool {
        mountedContent?.photoLayer?.contents != nil
    }
}

@MainActor
private final class MountedContent {
    let layer: CALayer
    private(set) var liveSession: AVCaptureSession?
    private(set) var player: AVPlayer?
    let photoLayer: CALayer?

    private let previewLayer: AVCaptureVideoPreviewLayer?
    private let playerLayer: AVPlayerLayer?
    private var revoked = false
    private var detached = false

    private let devicePointConverter: ((AVCaptureVideoPreviewLayer, CGPoint) -> CGPoint)?

    init(
        source: MediaCaptureRenderSource,
        frame: CGRect,
        devicePointConverter: ((AVCaptureVideoPreviewLayer, CGPoint) -> CGPoint)?
    ) {
        self.devicePointConverter = devicePointConverter
        switch source {
        case let .live(session):
            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = frame
            layer = previewLayer
            liveSession = session
            player = nil
            photoLayer = nil
            self.previewLayer = previewLayer
            playerLayer = nil
        case let .photo(image):
            let photoLayer = CALayer()
            photoLayer.contents = image
            photoLayer.contentsGravity = .resizeAspect
            photoLayer.frame = frame
            layer = photoLayer
            liveSession = nil
            player = nil
            self.photoLayer = photoLayer
            previewLayer = nil
            playerLayer = nil
        case let .video(url):
            let player = AVPlayer(url: url)
            let playerLayer = AVPlayerLayer(player: player)
            playerLayer.videoGravity = .resizeAspect
            playerLayer.frame = frame
            layer = playerLayer
            liveSession = nil
            self.player = player
            photoLayer = nil
            previewLayer = nil
            self.playerLayer = playerLayer
            player.play()
        }
    }

    func captureDevicePoint(fromLayerPoint point: CGPoint) -> CGPoint? {
        guard !revoked, liveSession != nil, let previewLayer else { return nil }
        if let devicePointConverter {
            return devicePointConverter(previewLayer, point)
        }
        return previewLayer.captureDevicePointConverted(fromLayerPoint: point)
    }

    func revoke() {
        guard !revoked else { return }
        revoked = true
        previewLayer?.session = nil
        liveSession = nil
        player?.pause()
        playerLayer?.player = nil
        player = nil
    }

    func detach() {
        guard !detached else { return }
        detached = true
        revoke()
        layer.removeFromSuperlayer()
        photoLayer?.contents = nil
    }
}
