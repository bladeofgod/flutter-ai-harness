import Foundation

internal enum CaptureGestureAction: Equatable {
    case none
    case takePhoto
    case startRecording
    case updateZoom(verticalDelta: Double)
    case stopRecording
}

internal struct CaptureGestureController {
    private(set) var isPressed = false
    private(set) var isRecordingGesture = false
    private var lastY: Double = 0

    mutating func begin(atY y: Double) {
        isPressed = true
        isRecordingGesture = false
        lastY = y
    }

    mutating func activateLongPress(videoEnabled: Bool) -> CaptureGestureAction {
        guard isPressed, videoEnabled, !isRecordingGesture else { return .none }
        isRecordingGesture = true
        return .startRecording
    }

    mutating func move(toY y: Double) -> CaptureGestureAction {
        guard isPressed, isRecordingGesture else { return .none }
        let delta = lastY - y
        lastY = y
        return .updateZoom(verticalDelta: delta)
    }

    mutating func end() -> CaptureGestureAction {
        guard isPressed else { return .none }
        isPressed = false
        if isRecordingGesture {
            isRecordingGesture = false
            return .stopRecording
        }
        return .takePhoto
    }

    mutating func cancel() -> CaptureGestureAction {
        guard isPressed else { return .none }
        isPressed = false
        if isRecordingGesture {
            isRecordingGesture = false
            return .stopRecording
        }
        return .none
    }
}
