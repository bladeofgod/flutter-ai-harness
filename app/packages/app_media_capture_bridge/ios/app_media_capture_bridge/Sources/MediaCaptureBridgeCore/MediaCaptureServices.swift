import AVFoundation
import MediaCapture
import MediaCaptureUI
import UIKit

package final class MediaCaptureProductionEnvironment: @unchecked Sendable {
    private let core: MediaCaptureCore
    package let service: any MediaCaptureCoreServicing
    package let transferStore: MediaCaptureTransferStore?

    package init() {
        let core = MediaCaptureCore()
        self.core = core
        service = LiveMediaCaptureCoreService(core: core)
        transferStore = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first.map {
            MediaCaptureTransferStore(cacheDirectory: $0)
        }
    }

    @MainActor
    package func presentationOwner(
        viewController: UIViewController,
        identity: ObjectIdentifier
    ) -> MediaCapturePresentationOwner {
        MediaCapturePresentationOwner(
            identity: identity,
            presenter: LiveMediaCapturePresenter(viewController: viewController, core: core)
        )
    }
}

private final class LiveMediaCaptureCoreService: MediaCaptureCoreServicing, @unchecked Sendable {
    private let core: MediaCaptureCore

    init(core: MediaCaptureCore) {
        self.core = core
    }

    func events() async -> AsyncStream<MediaCaptureEvent> { await core.events() }
    func startSession(options: SessionOptions) async throws -> SessionHandle {
        try await core.startSession(options: options).sessionHandle
    }
    func takePhoto(sessionHandle: SessionHandle) async throws -> MediaMetadata {
        try await core.takePhoto(sessionHandle: sessionHandle)
    }
    func startRecording(sessionHandle: SessionHandle) async throws -> MediaCaptureRecordingValue {
        let value = try await core.startRecording(sessionHandle: sessionHandle)
        return MediaCaptureRecordingValue(
            sessionHandle: value.sessionHandle,
            audioIncluded: value.audioIncluded
        )
    }
    func stopRecording(sessionHandle: SessionHandle) async throws -> MediaMetadata {
        try await core.stopRecording(sessionHandle: sessionHandle)
    }
    func switchCamera(sessionHandle: SessionHandle) async throws -> SessionHandle {
        try await core.switchCamera(sessionHandle: sessionHandle)
    }
    func setFlashMode(sessionHandle: SessionHandle, mode: FlashMode) async throws -> SessionHandle {
        try await core.setFlashMode(sessionHandle: sessionHandle, mode: mode)
    }
    func setFocusPoint(
        sessionHandle: SessionHandle,
        normalizedX: Double,
        normalizedY: Double
    ) async throws -> SessionHandle {
        try await core.setFocusPoint(
            sessionHandle: sessionHandle,
            normalizedX: normalizedX,
            normalizedY: normalizedY
        )
    }
    func setZoomFactor(sessionHandle: SessionHandle, factor: Double) async throws -> SessionHandle {
        try await core.setZoomFactor(sessionHandle: sessionHandle, factor: factor)
    }
    func retake(mediaHandle: MediaHandle) async throws -> SessionHandle {
        try await core.retake(mediaHandle: mediaHandle)
    }
    func confirm(mediaHandle: MediaHandle) async throws -> MediaCaptureConfirmedValue {
        let value = try await core.confirm(mediaHandle: mediaHandle)
        return MediaCaptureConfirmedValue(
            metadata: value.metadata,
            leaseExpiresAt: value.leaseExpiresAt
        )
    }
    func cancel(sessionHandle: SessionHandle) async throws -> SessionHandle {
        try await core.cancel(sessionHandle: sessionHandle)
    }
    func releaseMedia(mediaHandle: MediaHandle) async throws -> MediaHandle {
        try await core.releaseMedia(mediaHandle: mediaHandle)
    }
    func readMediaThumbnail(
        mediaHandle: MediaHandle,
        maxPixelEdge: Int
    ) async throws -> MediaCaptureThumbnailValue {
        let value = try await core.readMediaThumbnail(
            mediaHandle: mediaHandle,
            maximumPixelEdge: maxPixelEdge
        )
        return MediaCaptureThumbnailValue(
            mediaHandle: value.mediaHandle,
            data: value.data,
            pixelWidth: value.pixelWidth,
            pixelHeight: value.pixelHeight,
            mediaType: value.mediaType,
            posterFrameMilliseconds: value.posterFrameMilliseconds,
            contentType: value.contentType,
            orientationDegrees: value.orientationDegrees
        )
    }
    func copyConfirmedMediaToSink(
        mediaHandle: MediaHandle,
        sink: any MediaCopySink,
        maximumLength: Int
    ) async throws -> MediaExportResult {
        try await core.copyConfirmedMediaToSink(
            mediaHandle: mediaHandle,
            sink: sink,
            maximumLength: maximumLength
        )
    }
    func close() async { await core.close() }
}

package struct LiveMediaCaptureThumbnailEncoder: MediaCaptureThumbnailEncoding {
    package init() {}

    package func encode(
        value: MediaCaptureThumbnailValue,
        maxPixelEdge: Int
    ) async throws -> MediaCaptureEncodedThumbnail {
        try await Task.detached {
            try MediaCaptureWireCodec.encodeThumbnail(
                value: value,
                maxPixelEdge: maxPixelEdge
            )
        }.value
    }
}

private struct LiveMediaCapturePermissionService: MediaCapturePermissionServicing {
    func isHardwareAvailable(_ resource: MediaCapturePreflightResource) -> Bool {
        AVCaptureDevice.default(for: mediaType(resource)) != nil
    }

    func authorizationState(
        for resource: MediaCapturePreflightResource
    ) -> MediaCapturePreflightAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: mediaType(resource)) {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        @unknown default:
            return .unsupported
        }
    }

    func requestAuthorization(
        for resource: MediaCapturePreflightResource
    ) async -> MediaCapturePreflightAuthorization {
        let type = mediaType(resource)
        let granted = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: type) { value in
                continuation.resume(returning: value)
            }
        }
        return granted ? .authorized : authorizationState(for: resource)
    }

    private func mediaType(_ resource: MediaCapturePreflightResource) -> AVMediaType {
        switch resource {
        case .camera:
            return .video
        case .microphone:
            return .audio
        }
    }
}

@MainActor
private final class LiveMediaCapturePresenter: MediaCapturePresenting {
    private weak var viewController: UIViewController?
    private let core: MediaCaptureCore
    private let permissionPreflight: MediaCapturePermissionPreflight

    init(viewController: UIViewController, core: MediaCaptureCore) {
        self.viewController = viewController
        self.core = core
        permissionPreflight = MediaCapturePermissionPreflight(
            service: LiveMediaCapturePermissionService()
        )
    }

    func preflight(options: SessionOptions) async throws {
        try await permissionPreflight.authorize(options: options)
    }

    func present(options: SessionOptions) throws -> any MediaCapturePresentationSession {
        guard let viewController else {
            throw MediaCaptureUiPresentationError.ownerUnavailable
        }
        let session = try MediaCaptureUiPresenter(
            presentingViewController: viewController,
            core: core
        ).present(configuration: MediaCaptureUiConfiguration(sessionOptions: options))
        return LiveMediaCapturePresentationSession(session: session)
    }

}

@MainActor
private final class LiveMediaCapturePresentationSession: MediaCapturePresentationSession {
    private let session: MediaCaptureFlowSession

    init(session: MediaCaptureFlowSession) {
        self.session = session
    }

    func awaitResult() async throws -> MediaCapturePresentationResult {
        switch try await session.awaitResult() {
        case let .confirmed(media):
            return .confirmed(
                MediaCaptureConfirmedValue(
                    metadata: media.metadata,
                    leaseExpiresAt: media.leaseExpiresAt
                )
            )
        case .cancelled:
            return .cancelled
        case let .failure(failure):
            return .failure(failure)
        }
    }

    func dismiss() {
        session.dismiss()
    }
}
