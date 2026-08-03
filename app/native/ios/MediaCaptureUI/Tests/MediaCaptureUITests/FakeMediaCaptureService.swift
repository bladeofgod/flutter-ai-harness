import Foundation
@testable import MediaCapture
@testable import MediaCaptureUI

actor FakeMediaCaptureService: MediaCaptureServicing {
    struct FocusPoint: Sendable, Equatable {
        let x: Double
        let y: Double
    }

    enum ReleaseFailure: Sendable {
        case media(MediaCaptureFailure.ID)
        case unexpected
    }

    struct UnexpectedReleaseError: Error {}

    struct Snapshot: Sendable {
        let startCount: Int
        let photoCount: Int
        let startRecordingCount: Int
        let stopRecordingCount: Int
        let cancelCount: Int
        let releaseHandles: [MediaHandle]
        let liveAttachGenerations: [Int64]
        let previewAttachGenerations: [Int64]
        let liveDetachCount: Int
        let previewDetachCount: Int
        let backgroundCount: Int
        let rotationCount: Int
        let zoomFactors: [Double]
        let focusCount: Int
        let focusPoints: [FocusPoint]
        let switchCameraCount: Int
        let retakeCount: Int
        let flashModes: [FlashMode]
        let cancelAttemptCount: Int
        let releaseAttemptCount: Int
        let confirmAttemptCount: Int
        let eventTerminationCount: Int
    }

    nonisolated let eventStream: AsyncStream<MediaCaptureEvent>
    nonisolated let eventContinuation: AsyncStream<MediaCaptureEvent>.Continuation
    nonisolated let eventTerminationState: EventTerminationState

    let sessionHandle: SessionHandle
    let previewMetadata: MediaMetadata
    let confirmedMedia: ConfirmedMedia
    let startFailure: MediaCaptureFailure?
    var startSessionGate: AsyncTestGate?
    var startRecordingGate: AsyncTestGate?
    var confirmGate: AsyncTestGate?
    var photoGate: AsyncTestGate?
    var retakeGate: AsyncTestGate?
    var switchCameraGate: AsyncTestGate?
    var switchCameraReturnGate: AsyncTestGate?
    var zoomGate: AsyncTestGate?
    var liveAttachGate: AsyncTestGate?
    var liveDetachGate: AsyncTestGate?
    var cancelGate: AsyncTestGate?
    var releaseGate: AsyncTestGate?
    var rotationGate: AsyncTestGate?
    var cancelFailuresRemaining = 0
    var releaseFailuresRemaining = 0
    var releaseFailures: [ReleaseFailure] = []
    var liveDetachFailuresRemaining = 0

    private var startCount = 0
    private var photoCount = 0
    private var startRecordingCount = 0
    private var stopRecordingCount = 0
    private var cancelCount = 0
    private var releaseHandles: [MediaHandle] = []
    private var liveAttachGenerations: [Int64] = []
    private var previewAttachGenerations: [Int64] = []
    private var liveDetachCount = 0
    private var previewDetachCount = 0
    private var backgroundCount = 0
    private var rotationCount = 0
    private var zoomFactors: [Double] = []
    private var focusCount = 0
    private var focusPoints: [FocusPoint] = []
    private var switchCameraCount = 0
    private var retakeCount = 0
    private var flashModes: [FlashMode] = []
    private var cancelAttemptCount = 0
    private var releaseAttemptCount = 0
    private var confirmAttemptCount = 0

    init(
        mediaType: MediaType = .photo,
        startFailure: MediaCaptureFailure? = nil
    ) throws {
        let pair = AsyncStream<MediaCaptureEvent>.makeStream()
        let terminationState = EventTerminationState()
        eventStream = pair.stream
        eventContinuation = pair.continuation
        eventTerminationState = terminationState
        pair.continuation.onTermination = { _ in terminationState.increment() }
        sessionHandle = try SessionHandle(rawValue: String(repeating: "s", count: 32))
        let mediaHandle = try MediaHandle(rawValue: String(repeating: "m", count: 32))
        previewMetadata = try MediaMetadata(
            mediaHandle: mediaHandle,
            mediaType: mediaType,
            pixelWidth: 120,
            pixelHeight: 80,
            durationMilliseconds: mediaType == .video ? 1_000 : nil,
            orientationDegrees: 0,
            byteLength: 1_024
        )
        confirmedMedia = ConfirmedMedia(
            metadata: previewMetadata,
            leaseExpiresAt: Date(timeIntervalSince1970: 2_000)
        )
        self.startFailure = startFailure
    }

    nonisolated func emit(_ event: MediaCaptureEvent) {
        eventContinuation.yield(event)
    }

    nonisolated func finishEvents() {
        eventContinuation.finish()
    }

    func events() async -> AsyncStream<MediaCaptureEvent> { eventStream }

    func startSession(options: SessionOptions) async throws -> SessionCreated {
        startCount += 1
        if let startSessionGate { await startSessionGate.wait() }
        if let startFailure { throw startFailure }
        return SessionCreated(sessionHandle: sessionHandle)
    }

    func takePhoto(sessionHandle: SessionHandle) async throws -> MediaMetadata {
        photoCount += 1
        if let photoGate { await photoGate.wait() }
        return previewMetadata
    }

    func startRecording(sessionHandle: SessionHandle) async throws -> RecordingStarted {
        startRecordingCount += 1
        if let startRecordingGate { await startRecordingGate.wait() }
        return RecordingStarted(sessionHandle: sessionHandle, audioIncluded: false)
    }

    func stopRecording(sessionHandle: SessionHandle) async throws -> MediaMetadata {
        stopRecordingCount += 1
        return previewMetadata
    }

    func switchCamera(sessionHandle: SessionHandle) async throws -> SessionHandle {
        switchCameraCount += 1
        if let switchCameraGate { await switchCameraGate.wait() }
        eventContinuation.yield(.sessionReady(SessionReadySnapshot(
            sessionHandle: sessionHandle,
            activeCamera: .front,
            availableCameras: [.rear, .front],
            switchCameraSupported: true,
            supportedFlashModes: [.off],
            focusPointSupported: false,
            minimumZoomFactor: 1,
            maximumZoomFactor: 2
        )))
        if let switchCameraReturnGate { await switchCameraReturnGate.wait() }
        return sessionHandle
    }
    func setFlashMode(sessionHandle: SessionHandle, mode: FlashMode) async throws -> SessionHandle {
        flashModes.append(mode)
        return sessionHandle
    }
    func setFocusPoint(
        sessionHandle: SessionHandle,
        normalizedX: Double,
        normalizedY: Double
    ) async throws -> SessionHandle {
        focusCount += 1
        focusPoints.append(FocusPoint(x: normalizedX, y: normalizedY))
        return sessionHandle
    }
    func setZoomFactor(sessionHandle: SessionHandle, factor: Double) async throws -> SessionHandle {
        zoomFactors.append(factor)
        if let zoomGate { await zoomGate.wait() }
        return sessionHandle
    }

    func retake(mediaHandle: MediaHandle) async throws -> SessionHandle {
        retakeCount += 1
        if let retakeGate { await retakeGate.wait() }
        return sessionHandle
    }

    func confirm(mediaHandle: MediaHandle) async throws -> ConfirmedMedia {
        confirmAttemptCount += 1
        if let confirmGate { await confirmGate.wait() }
        return confirmedMedia
    }

    func cancel(sessionHandle: SessionHandle) async throws -> SessionHandle {
        cancelAttemptCount += 1
        if let cancelGate { await cancelGate.wait() }
        if cancelFailuresRemaining > 0 {
            cancelFailuresRemaining -= 1
            throw MediaCaptureFailure(.systemInterrupted)
        }
        cancelCount += 1
        return sessionHandle
    }

    func releaseMedia(mediaHandle: MediaHandle) async throws -> MediaHandle {
        releaseAttemptCount += 1
        if let releaseGate { await releaseGate.wait() }
        if !releaseFailures.isEmpty {
            switch releaseFailures.removeFirst() {
            case let .media(failureId):
                throw MediaCaptureFailure(failureId)
            case .unexpected:
                throw UnexpectedReleaseError()
            }
        }
        if releaseFailuresRemaining > 0 {
            releaseFailuresRemaining -= 1
            throw MediaCaptureFailure(.invalidState)
        }
        releaseHandles.append(mediaHandle)
        return mediaHandle
    }

    func attachLivePreview(
        sessionHandle: SessionHandle,
        surfaceOwner: MediaCaptureRenderSurfaceOwner
    ) async throws -> RenderAttachmentResult {
        liveAttachGenerations.append(surfaceOwner.ownerGeneration)
        if let liveAttachGate { await liveAttachGate.wait() }
        return RenderAttachmentResult(kind: .livePreview, ownerGeneration: surfaceOwner.ownerGeneration)
    }

    func detachLivePreview(
        sessionHandle: SessionHandle,
        surfaceOwner: MediaCaptureRenderSurfaceOwner
    ) async throws -> RenderAttachmentResult {
        liveDetachCount += 1
        if let liveDetachGate { await liveDetachGate.wait() }
        if liveDetachFailuresRemaining > 0 {
            liveDetachFailuresRemaining -= 1
            throw MediaCaptureFailure(.systemInterrupted)
        }
        return RenderAttachmentResult(kind: .livePreview, ownerGeneration: surfaceOwner.ownerGeneration)
    }

    func attachUnconfirmedPreviewRender(
        mediaHandle: MediaHandle,
        surfaceOwner: MediaCaptureRenderSurfaceOwner
    ) async throws -> RenderAttachmentResult {
        previewAttachGenerations.append(surfaceOwner.ownerGeneration)
        return RenderAttachmentResult(
            kind: .unconfirmedPreview,
            ownerGeneration: surfaceOwner.ownerGeneration
        )
    }

    func detachUnconfirmedPreviewRender(
        mediaHandle: MediaHandle,
        surfaceOwner: MediaCaptureRenderSurfaceOwner
    ) async throws -> RenderAttachmentResult {
        previewDetachCount += 1
        return RenderAttachmentResult(
            kind: .unconfirmedPreview,
            ownerGeneration: surfaceOwner.ownerGeneration
        )
    }

    func displayRotationChanged() async {
        rotationCount += 1
        if let rotationGate { await rotationGate.wait() }
    }
    func appDidEnterBackground() async { backgroundCount += 1 }

    func configureStartRecordingGate(_ gate: AsyncTestGate?) {
        startRecordingGate = gate
    }

    func configureStartSessionGate(_ gate: AsyncTestGate?) {
        startSessionGate = gate
    }

    func configureConfirmGate(_ gate: AsyncTestGate?) {
        confirmGate = gate
    }

    func configurePhotoGate(_ gate: AsyncTestGate?) {
        photoGate = gate
    }

    func configureRetakeGate(_ gate: AsyncTestGate?) {
        retakeGate = gate
    }

    func configureSwitchCameraGate(_ gate: AsyncTestGate?) {
        switchCameraGate = gate
    }

    func configureSwitchCameraReturnGate(_ gate: AsyncTestGate?) {
        switchCameraReturnGate = gate
    }

    func configureZoomGate(_ gate: AsyncTestGate?) {
        zoomGate = gate
    }

    func configureLiveAttachGate(_ gate: AsyncTestGate?) {
        liveAttachGate = gate
    }

    func configureLiveDetachGate(_ gate: AsyncTestGate?) {
        liveDetachGate = gate
    }

    func configureCancelGate(_ gate: AsyncTestGate?) {
        cancelGate = gate
    }

    func configureReleaseGate(_ gate: AsyncTestGate?) {
        releaseGate = gate
    }

    func configureRotationGate(_ gate: AsyncTestGate?) {
        rotationGate = gate
    }

    func configureCleanupFailures(cancel: Int, release: Int, liveDetach: Int) {
        cancelFailuresRemaining = cancel
        releaseFailuresRemaining = release
        liveDetachFailuresRemaining = liveDetach
    }

    func configureReleaseFailures(_ failureIds: [MediaCaptureFailure.ID]) {
        releaseFailures = failureIds.map(ReleaseFailure.media)
    }

    func configureReleaseFailureSequence(_ failures: [ReleaseFailure]) {
        releaseFailures = failures
    }

    func snapshot() -> Snapshot {
        Snapshot(
            startCount: startCount,
            photoCount: photoCount,
            startRecordingCount: startRecordingCount,
            stopRecordingCount: stopRecordingCount,
            cancelCount: cancelCount,
            releaseHandles: releaseHandles,
            liveAttachGenerations: liveAttachGenerations,
            previewAttachGenerations: previewAttachGenerations,
            liveDetachCount: liveDetachCount,
            previewDetachCount: previewDetachCount,
            backgroundCount: backgroundCount,
            rotationCount: rotationCount,
            zoomFactors: zoomFactors,
            focusCount: focusCount,
            focusPoints: focusPoints,
            switchCameraCount: switchCameraCount,
            retakeCount: retakeCount,
            flashModes: flashModes,
            cancelAttemptCount: cancelAttemptCount,
            releaseAttemptCount: releaseAttemptCount,
            confirmAttemptCount: confirmAttemptCount,
            eventTerminationCount: eventTerminationState.value
        )
    }
}

final class EventTerminationState: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

final class AsyncTestGate: @unchecked Sendable {
    private let lock = NSLock()
    private var open = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if open {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func release() {
        lock.lock()
        open = true
        let waiters = waiters
        self.waiters.removeAll()
        lock.unlock()
        waiters.forEach { $0.resume() }
    }
}
