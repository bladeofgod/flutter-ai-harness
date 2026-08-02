import Foundation
import MediaCapture

public struct MediaCaptureUiConfiguration: Sendable {
    public let sessionOptions: SessionOptions

    public init(sessionOptions: SessionOptions) {
        self.sessionOptions = sessionOptions
    }
}

public enum MediaCaptureFlowResult: Equatable, Sendable {
    case confirmed(ConfirmedMedia)
    case cancelled
    case failure(MediaCaptureFailure)
}

public enum MediaCaptureUiPresentationError: Error, Equatable, Sendable {
    case ownerUnavailable
    case presentationConflict
    case presentationFailed
}

internal enum MediaCaptureUiPhase: Equatable {
    case starting
    case live
    case switchingCamera
    case startingRecording
    case recording
    case stoppingRecording
    case capturing
    case preview(MediaMetadata)
    case confirming
    case terminal
}

internal enum MediaCaptureSurfaceKind: Equatable, Sendable {
    case live(SessionHandle)
    case preview(MediaHandle)
}

internal struct MediaCaptureUiSnapshot: Equatable {
    let phase: MediaCaptureUiPhase
    let ready: SessionReadySnapshot?
    let flashMode: FlashMode
    let recordingProgress: Double
    let photoEnabled: Bool
    let videoEnabled: Bool
}
