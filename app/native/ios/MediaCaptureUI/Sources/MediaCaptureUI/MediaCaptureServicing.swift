import MediaCapture

internal protocol MediaCaptureServicing: AnyObject, Sendable {
    func events() async -> AsyncStream<MediaCaptureEvent>
    func startSession(options: SessionOptions) async throws -> SessionCreated
    func takePhoto(sessionHandle: SessionHandle) async throws -> MediaMetadata
    func startRecording(sessionHandle: SessionHandle) async throws -> RecordingStarted
    func stopRecording(sessionHandle: SessionHandle) async throws -> MediaMetadata
    func switchCamera(sessionHandle: SessionHandle) async throws -> SessionHandle
    func setFlashMode(sessionHandle: SessionHandle, mode: FlashMode) async throws -> SessionHandle
    func setFocusPoint(
        sessionHandle: SessionHandle,
        normalizedX: Double,
        normalizedY: Double
    ) async throws -> SessionHandle
    func setZoomFactor(sessionHandle: SessionHandle, factor: Double) async throws -> SessionHandle
    func retake(mediaHandle: MediaHandle) async throws -> SessionHandle
    func confirm(mediaHandle: MediaHandle) async throws -> ConfirmedMedia
    func cancel(sessionHandle: SessionHandle) async throws -> SessionHandle
    func releaseMedia(mediaHandle: MediaHandle) async throws -> MediaHandle
    func attachLivePreview(
        sessionHandle: SessionHandle,
        surfaceOwner: MediaCaptureRenderSurfaceOwner
    ) async throws -> RenderAttachmentResult
    func detachLivePreview(
        sessionHandle: SessionHandle,
        surfaceOwner: MediaCaptureRenderSurfaceOwner
    ) async throws -> RenderAttachmentResult
    func attachUnconfirmedPreviewRender(
        mediaHandle: MediaHandle,
        surfaceOwner: MediaCaptureRenderSurfaceOwner
    ) async throws -> RenderAttachmentResult
    func detachUnconfirmedPreviewRender(
        mediaHandle: MediaHandle,
        surfaceOwner: MediaCaptureRenderSurfaceOwner
    ) async throws -> RenderAttachmentResult
    func displayRotationChanged() async
    func appDidEnterBackground() async
}

internal final class MediaCaptureCoreService: MediaCaptureServicing, @unchecked Sendable {
    private let core: MediaCaptureCore

    init(core: MediaCaptureCore) {
        self.core = core
    }

    func events() async -> AsyncStream<MediaCaptureEvent> { await core.events() }
    func startSession(options: SessionOptions) async throws -> SessionCreated {
        try await core.startSession(options: options)
    }
    func takePhoto(sessionHandle: SessionHandle) async throws -> MediaMetadata {
        try await core.takePhoto(sessionHandle: sessionHandle)
    }
    func startRecording(sessionHandle: SessionHandle) async throws -> RecordingStarted {
        try await core.startRecording(sessionHandle: sessionHandle)
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
    func confirm(mediaHandle: MediaHandle) async throws -> ConfirmedMedia {
        try await core.confirm(mediaHandle: mediaHandle)
    }
    func cancel(sessionHandle: SessionHandle) async throws -> SessionHandle {
        try await core.cancel(sessionHandle: sessionHandle)
    }
    func releaseMedia(mediaHandle: MediaHandle) async throws -> MediaHandle {
        try await core.releaseMedia(mediaHandle: mediaHandle)
    }
    func attachLivePreview(
        sessionHandle: SessionHandle,
        surfaceOwner: MediaCaptureRenderSurfaceOwner
    ) async throws -> RenderAttachmentResult {
        try await core.attachLivePreview(sessionHandle: sessionHandle, surfaceOwner: surfaceOwner)
    }
    func detachLivePreview(
        sessionHandle: SessionHandle,
        surfaceOwner: MediaCaptureRenderSurfaceOwner
    ) async throws -> RenderAttachmentResult {
        try await core.detachLivePreview(sessionHandle: sessionHandle, surfaceOwner: surfaceOwner)
    }
    func attachUnconfirmedPreviewRender(
        mediaHandle: MediaHandle,
        surfaceOwner: MediaCaptureRenderSurfaceOwner
    ) async throws -> RenderAttachmentResult {
        try await core.attachUnconfirmedPreviewRender(
            mediaHandle: mediaHandle,
            surfaceOwner: surfaceOwner
        )
    }
    func detachUnconfirmedPreviewRender(
        mediaHandle: MediaHandle,
        surfaceOwner: MediaCaptureRenderSurfaceOwner
    ) async throws -> RenderAttachmentResult {
        try await core.detachUnconfirmedPreviewRender(
            mediaHandle: mediaHandle,
            surfaceOwner: surfaceOwner
        )
    }
    func displayRotationChanged() async { await core.displayRotationChanged() }
    func appDidEnterBackground() async { await core.appDidEnterBackground() }
}
