import Foundation
@testable import MediaCapture
import XCTest
@testable import MediaCaptureBridgeCore

enum BridgeTestOutcome {
    case success([String: Any])
    case failure(MediaCaptureWireFailure)
}

@MainActor
final class CompletionProbe: MediaCaptureBridgeCompletion {
    private var outcome: BridgeTestOutcome?
    private var continuation: CheckedContinuation<BridgeTestOutcome, Never>?
    private let onSuccess: (([String: Any]) -> Void)?
    private(set) var completionCount = 0
    private(set) var completedOnMainThread = false

    init(onSuccess: (([String: Any]) -> Void)? = nil) {
        self.onSuccess = onSuccess
    }

    func success(_ value: [String: Any]) {
        finish(.success(value))
        onSuccess?(value)
    }

    func failure(_ failure: MediaCaptureWireFailure) {
        finish(.failure(failure))
    }

    func value() async -> BridgeTestOutcome {
        if let outcome { return outcome }
        return await withCheckedContinuation { continuation = $0 }
    }

    private func finish(_ value: BridgeTestOutcome) {
        completionCount += 1
        completedOnMainThread = Thread.isMainThread
        guard outcome == nil else { return }
        outcome = value
        continuation?.resume(returning: value)
        continuation = nil
    }
}

@MainActor
final class EventSinkProbe: MediaCaptureBridgeEventSink {
    private(set) var values: [[String: Any]] = []
    private(set) var failures: [MediaCaptureWireFailure] = []
    private(set) var endCount = 0

    func success(_ value: [String: Any]) { values.append(value) }
    func failure(_ failure: MediaCaptureWireFailure) { failures.append(failure) }
    func endOfStream() { endCount += 1 }
}

actor FakeMediaCaptureCore: MediaCaptureCoreServicing {
    nonisolated let stream: AsyncStream<MediaCaptureEvent>
    private nonisolated let eventContinuation: AsyncStream<MediaCaptureEvent>.Continuation

    private var sessionCounter = 0
    private var photoCounter = 0
    private var videoCounter = 0
    private var mediaByHandle: [String: MediaMetadata] = [:]
    private var sessionByMedia: [String: SessionHandle] = [:]
    private var cancelledHandles: [String] = []
    private var releasedHandles: [String] = []
    private var operations: [String] = []
    private var closed = false
    private var startDelayNanoseconds: UInt64 = 0
    private var ignoreStartCancellation = false
    private var confirmDelayNanoseconds: UInt64 = 0
    private var ignoreConfirmCancellation = false
    private var thumbnailDelayNanoseconds: UInt64 = 0
    private var ignoreThumbnailCancellation = false
    private var releaseDelayNanoseconds: UInt64 = 0
    private var ignoreReleaseCancellation = false
    private var neverCompleteCancel = false
    private var neverCompleteRelease = false
    private var neverCompleteClose = false
    private var cancelWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var closeWaiters: [CheckedContinuation<Void, Never>] = []
    private var nextStartupFailure: MediaCaptureFailure?
    private var eventRegistrationBlocked = false
    private var eventRegistrationCompleted = false
    private var eventRegistrationWaiters: [CheckedContinuation<Void, Never>] = []
    private var nextStartError: MediaCaptureFailure?
    private var neverCompleteStart = false
    private var neverStartContinuations: [CheckedContinuation<Void, Never>] = []
    private var thumbnailOverride: MediaCaptureThumbnailValue?
    private var lastReturnedThumbnail: MediaCaptureThumbnailValue?
    private var exportDelayNanoseconds: UInt64 = 0
    private var ignoreExportCancellation = false
    private var exportResultLengthMismatch = false
    private var exportFailureAfterBegin: MediaCaptureFailure?
    private var capturedMediaByteLength = 4_096

    init() {
        let pair = AsyncStream<MediaCaptureEvent>.makeStream()
        stream = pair.stream
        eventContinuation = pair.continuation
    }

    func events() async -> AsyncStream<MediaCaptureEvent> {
        if eventRegistrationBlocked {
            await withCheckedContinuation { eventRegistrationWaiters.append($0) }
        }
        eventRegistrationCompleted = true
        return stream
    }

    func configureEventRegistrationBlocked(_ blocked: Bool) {
        eventRegistrationBlocked = blocked
    }

    func unblockEventRegistration() {
        eventRegistrationBlocked = false
        let waiters = eventRegistrationWaiters
        eventRegistrationWaiters.removeAll(keepingCapacity: false)
        waiters.forEach { $0.resume() }
    }

    func isEventRegistrationCompleted() -> Bool { eventRegistrationCompleted }

    func configureStartDelay(nanoseconds: UInt64, ignoreCancellation: Bool) {
        startDelayNanoseconds = nanoseconds
        ignoreStartCancellation = ignoreCancellation
    }

    func configureNextStartError(_ failure: MediaCaptureFailure?) {
        nextStartError = failure
    }

    func configureConfirmDelay(nanoseconds: UInt64, ignoreCancellation: Bool) {
        confirmDelayNanoseconds = nanoseconds
        ignoreConfirmCancellation = ignoreCancellation
    }

    func setThumbnail(_ value: MediaCaptureThumbnailValue) {
        thumbnailOverride = value
    }

    func configureThumbnailDelay(nanoseconds: UInt64, ignoreCancellation: Bool) {
        thumbnailDelayNanoseconds = nanoseconds
        ignoreThumbnailCancellation = ignoreCancellation
    }

    func configureReleaseDelay(nanoseconds: UInt64, ignoreCancellation: Bool) {
        releaseDelayNanoseconds = nanoseconds
        ignoreReleaseCancellation = ignoreCancellation
    }

    func configureExportDelay(nanoseconds: UInt64, ignoreCancellation: Bool) {
        exportDelayNanoseconds = nanoseconds
        ignoreExportCancellation = ignoreCancellation
    }

    func configureExportResultLengthMismatch(_ enabled: Bool) {
        exportResultLengthMismatch = enabled
    }

    func configureExportFailureAfterBegin(_ failure: MediaCaptureFailure?) {
        exportFailureAfterBegin = failure
    }

    func configureCapturedMediaByteLength(_ byteLength: Int) {
        capturedMediaByteLength = byteLength
    }

    func configureNeverCompleteCleanup(
        cancel: Bool = false,
        release: Bool = false,
        close: Bool = false
    ) {
        neverCompleteCancel = cancel
        neverCompleteRelease = release
        neverCompleteClose = close
    }

    func unblockCleanup() {
        neverCompleteCancel = false
        neverCompleteRelease = false
        neverCompleteClose = false
        let waiters = cancelWaiters + releaseWaiters + closeWaiters
        cancelWaiters.removeAll(keepingCapacity: false)
        releaseWaiters.removeAll(keepingCapacity: false)
        closeWaiters.removeAll(keepingCapacity: false)
        waiters.forEach { $0.resume() }
    }

    func configureNextStartupFailure(_ failure: MediaCaptureFailure?) {
        nextStartupFailure = failure
    }

    func configureNeverCompleteStart(_ enabled: Bool) {
        neverCompleteStart = enabled
    }

    func unblockNeverCompleteStart() {
        neverCompleteStart = false
        let waiters = neverStartContinuations
        neverStartContinuations.removeAll(keepingCapacity: false)
        waiters.forEach { $0.resume() }
    }

    func lastThumbnailIsCleared() -> Bool {
        lastReturnedThumbnail?.copyData().isEmpty == true
    }

    func emit(_ event: MediaCaptureEvent) {
        if case let .mediaPreviewReady(sessionHandle, metadata) = event {
            mediaByHandle[metadata.mediaHandle.rawValue] = metadata
            sessionByMedia[metadata.mediaHandle.rawValue] = sessionHandle
        }
        eventContinuation.yield(event)
    }

    func snapshot() -> (operations: [String], cancelled: [String], released: [String], closed: Bool) {
        (operations, cancelledHandles, releasedHandles, closed)
    }

    func startSession(options _: SessionOptions) async throws -> SessionHandle {
        operations.append("start_session")
        if neverCompleteStart {
            await withCheckedContinuation { neverStartContinuations.append($0) }
        }
        if startDelayNanoseconds > 0 {
            do {
                try await Task.sleep(nanoseconds: startDelayNanoseconds)
            } catch {
                if !ignoreStartCancellation { throw error }
            }
        }
        if let nextStartError {
            self.nextStartError = nil
            throw nextStartError
        }
        sessionCounter += 1
        let handle = try SessionHandle(rawValue: "session_\(sessionCounter)")
        if let failure = nextStartupFailure {
            nextStartupFailure = nil
            eventContinuation.yield(
                .sessionFailed(sessionHandle: handle, failure: failure)
            )
        } else {
            eventContinuation.yield(
                .sessionReady(
                    SessionReadySnapshot(
                        sessionHandle: handle,
                        activeCamera: .rear,
                        availableCameras: [.rear, .front],
                        switchCameraSupported: true,
                        supportedFlashModes: [.off, .auto],
                        focusPointSupported: true,
                        minimumZoomFactor: 1,
                        maximumZoomFactor: 4
                    )
                )
            )
        }
        return handle
    }

    func takePhoto(sessionHandle: SessionHandle) async throws -> MediaMetadata {
        operations.append("take_photo")
        photoCounter += 1
        let value = try MediaMetadata(
            mediaHandle: MediaHandle(rawValue: "photo_\(photoCounter)"),
            mediaType: .photo,
            pixelWidth: 1_080,
            pixelHeight: 1_920,
            durationMilliseconds: nil,
            orientationDegrees: 0,
            byteLength: capturedMediaByteLength
        )
        mediaByHandle[value.mediaHandle.rawValue] = value
        sessionByMedia[value.mediaHandle.rawValue] = sessionHandle
        return value
    }

    func startRecording(sessionHandle: SessionHandle) async throws -> MediaCaptureRecordingValue {
        operations.append("start_recording")
        return MediaCaptureRecordingValue(sessionHandle: sessionHandle, audioIncluded: true)
    }

    func stopRecording(sessionHandle: SessionHandle) async throws -> MediaMetadata {
        operations.append("stop_recording")
        videoCounter += 1
        let value = try MediaMetadata(
            mediaHandle: MediaHandle(rawValue: "video_\(videoCounter)"),
            mediaType: .video,
            pixelWidth: 1_080,
            pixelHeight: 1_920,
            durationMilliseconds: 1_200,
            orientationDegrees: 0,
            byteLength: capturedMediaByteLength
        )
        mediaByHandle[value.mediaHandle.rawValue] = value
        sessionByMedia[value.mediaHandle.rawValue] = sessionHandle
        return value
    }

    func switchCamera(sessionHandle: SessionHandle) async throws -> SessionHandle {
        operations.append("switch_camera")
        return sessionHandle
    }

    func setFlashMode(sessionHandle: SessionHandle, mode _: FlashMode) async throws -> SessionHandle {
        operations.append("set_flash_mode")
        return sessionHandle
    }

    func setFocusPoint(
        sessionHandle: SessionHandle,
        normalizedX _: Double,
        normalizedY _: Double
    ) async throws -> SessionHandle {
        operations.append("set_focus_point")
        return sessionHandle
    }

    func setZoomFactor(sessionHandle: SessionHandle, factor _: Double) async throws -> SessionHandle {
        operations.append("set_zoom")
        return sessionHandle
    }

    func retake(mediaHandle: MediaHandle) async throws -> SessionHandle {
        operations.append("retake")
        guard let session = sessionByMedia[mediaHandle.rawValue] else {
            throw MediaCaptureFailure(.mediaInvalid)
        }
        return session
    }

    func confirm(mediaHandle: MediaHandle) async throws -> MediaCaptureConfirmedValue {
        operations.append("confirm")
        if confirmDelayNanoseconds > 0 {
            do {
                try await Task.sleep(nanoseconds: confirmDelayNanoseconds)
            } catch {
                if !ignoreConfirmCancellation { throw error }
            }
        }
        guard let metadata = mediaByHandle[mediaHandle.rawValue] else {
            throw MediaCaptureFailure(.mediaInvalid)
        }
        return MediaCaptureConfirmedValue(
            metadata: metadata,
            leaseExpiresAt: Date(timeIntervalSince1970: 2_000_000_000)
        )
    }

    func cancel(sessionHandle: SessionHandle) async throws -> SessionHandle {
        operations.append("cancel")
        if neverCompleteCancel {
            await withCheckedContinuation { cancelWaiters.append($0) }
        }
        cancelledHandles.append(sessionHandle.rawValue)
        return sessionHandle
    }

    func releaseMedia(mediaHandle: MediaHandle) async throws -> MediaHandle {
        operations.append("release_media")
        if neverCompleteRelease {
            await withCheckedContinuation { releaseWaiters.append($0) }
        }
        if releaseDelayNanoseconds > 0 {
            do {
                try await Task.sleep(nanoseconds: releaseDelayNanoseconds)
            } catch {
                if !ignoreReleaseCancellation { throw error }
            }
        }
        releasedHandles.append(mediaHandle.rawValue)
        return mediaHandle
    }

    func readMediaThumbnail(
        mediaHandle: MediaHandle,
        maxPixelEdge _: Int
    ) async throws -> MediaCaptureThumbnailValue {
        operations.append("read_media_thumbnail")
        if thumbnailDelayNanoseconds > 0 {
            do {
                try await Task.sleep(nanoseconds: thumbnailDelayNanoseconds)
            } catch {
                if !ignoreThumbnailCancellation { throw error }
            }
        }
        let value: MediaCaptureThumbnailValue
        if let thumbnailOverride {
            value = MediaCaptureThumbnailValue(
                mediaHandle: mediaHandle,
                data: thumbnailOverride.copyData(),
                pixelWidth: thumbnailOverride.pixelWidth,
                pixelHeight: thumbnailOverride.pixelHeight,
                mediaType: thumbnailOverride.mediaType,
                posterFrameMilliseconds: thumbnailOverride.posterFrameMilliseconds,
                contentType: thumbnailOverride.contentType,
                orientationDegrees: thumbnailOverride.orientationDegrees
            )
        } else {
            value = MediaCaptureThumbnailValue(
                mediaHandle: mediaHandle,
                data: sanitizedJpeg(),
                pixelWidth: 2,
                pixelHeight: 2,
                mediaType: .photo,
                posterFrameMilliseconds: nil,
                contentType: "image/jpeg",
                orientationDegrees: 0
            )
        }
        lastReturnedThumbnail = value
        return value
    }

    func copyConfirmedMediaToSink(
        mediaHandle: MediaHandle,
        sink: any MediaCopySink,
        maximumLength: Int
    ) async throws -> MediaExportResult {
        operations.append("materialize_media_resource")
        guard let metadata = mediaByHandle[mediaHandle.rawValue] else {
            throw MediaCaptureFailure(.mediaInvalid)
        }
        guard metadata.byteLength <= maximumLength else {
            throw MediaCaptureFailure(.mediaExportTooLarge)
        }
        let contentType = metadata.mediaType == .photo ? "image/jpeg" : "video/mp4"
        if exportDelayNanoseconds > 0 {
            do {
                try await Task.sleep(nanoseconds: exportDelayNanoseconds)
            } catch {
                if !ignoreExportCancellation { throw error }
            }
        }
        if let exportFailureAfterBegin {
            try await sink.begin(
                mediaType: metadata.mediaType,
                contentType: contentType,
                byteLength: metadata.byteLength
            )
            try await sink.abort()
            throw exportFailureAfterBegin
        }
        let bytes = Data(repeating: metadata.mediaType == .photo ? 0x4a : 0x56, count: metadata.byteLength)
        try await sink.begin(
            mediaType: metadata.mediaType,
            contentType: contentType,
            byteLength: metadata.byteLength
        )
        do {
            try await sink.write(MediaCopyChunk(bytes))
        } catch {
            try? await sink.abort()
            throw MediaCaptureFailure(.mediaExportWriteFailed)
        }
        try await sink.commit(byteLength: metadata.byteLength)
        return MediaExportResult(
            mediaHandle: mediaHandle,
            mediaType: metadata.mediaType,
            contentType: contentType,
            byteLength: exportResultLengthMismatch ? metadata.byteLength + 1 : metadata.byteLength
        )
    }

    func close() async {
        operations.append("close")
        if neverCompleteClose {
            await withCheckedContinuation { closeWaiters.append($0) }
        }
        closed = true
        eventContinuation.finish()
    }
}

@MainActor
final class PresentationSessionProbe: MediaCapturePresentationSession {
    private var result: MediaCapturePresentationResult?
    private var continuations: [
        CheckedContinuation<MediaCapturePresentationResult, Error>
    ] = []
    private(set) var dismissCount = 0
    var autoResolveDismiss = true

    func awaitResult() async throws -> MediaCapturePresentationResult {
        if let result { return result }
        return try await withCheckedThrowingContinuation { continuations.append($0) }
    }

    func resolve(_ value: MediaCapturePresentationResult) {
        guard result == nil else { return }
        result = value
        let waiters = continuations
        continuations.removeAll(keepingCapacity: false)
        waiters.forEach { $0.resume(returning: value) }
    }

    func dismiss() {
        dismissCount += 1
        if autoResolveDismiss { resolve(.cancelled) }
    }
}

@MainActor
final class PresenterProbe: MediaCapturePresenting {
    private(set) var sessions: [PresentationSessionProbe] = []
    private(set) var preflightCount = 0
    var preflightFailure: MediaCaptureFailure?
    var permissionPreflight: MediaCapturePermissionPreflight?

    func preflight(options: SessionOptions) async throws {
        preflightCount += 1
        if let preflightFailure { throw preflightFailure }
        if let permissionPreflight {
            try await permissionPreflight.authorize(options: options)
        }
    }

    func present(options _: SessionOptions) throws -> any MediaCapturePresentationSession {
        let session = PresentationSessionProbe()
        sessions.append(session)
        return session
    }
}

@MainActor
final class PresentationOwnerBox {
    private let token = NSObject()
    let presenter = PresenterProbe()
    var presentationAvailable = true
    var alive = true

    var identity: ObjectIdentifier { ObjectIdentifier(token) }

    func owner() -> MediaCapturePresentationOwner? {
        guard presentationAvailable else { return nil }
        return MediaCapturePresentationOwner(identity: identity, presenter: presenter)
    }
}

@MainActor
func makeController(
    core: FakeMediaCaptureCore,
    owner: PresentationOwnerBox,
    transferStore: MediaCaptureTransferStore? = nil,
    drainTimeoutNanoseconds: UInt64 = 50_000_000,
    ownerPollNanoseconds: UInt64 = 1_000_000,
    transferTTLNanoseconds: UInt64 = 300_000_000_000,
    maximumActiveTransferBytes: Int = 104_857_600,
    monotonicMilliseconds: @escaping @Sendable () -> UInt64 = {
        DispatchTime.now().uptimeNanoseconds / 1_000_000
    },
    epochMilliseconds: @escaping @Sendable () -> Int64 = {
        Int64(Date().timeIntervalSince1970 * 1_000)
    }
) -> MediaCaptureBridgeController {
    MediaCaptureBridgeController(
        core: core,
        transferStore: transferStore,
        presentationOwner: { [weak owner] in owner?.owner() },
        ownerIsAlive: { [weak owner] identity in
            owner?.alive == true && owner?.identity == identity
        },
        drainTimeoutNanoseconds: drainTimeoutNanoseconds,
        ownerPollNanoseconds: ownerPollNanoseconds,
        transferTTLNanoseconds: transferTTLNanoseconds,
        maximumActiveTransferBytes: maximumActiveTransferBytes,
        monotonicMilliseconds: monotonicMilliseconds,
        epochMilliseconds: epochMilliseconds
    )
}

final class MonotonicClockProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64

    init(_ value: UInt64) {
        self.value = value
    }

    func now() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(by milliseconds: UInt64) {
        lock.lock()
        value += milliseconds
        lock.unlock()
    }
}

final class WeakReference<Value: AnyObject> {
    weak var value: Value?

    init(_ value: Value?) {
        self.value = value
    }
}

final class PermissionServiceProbe: MediaCapturePermissionServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var unavailable: Set<MediaCapturePreflightResource> = []
    private var states: [
        MediaCapturePreflightResource: MediaCapturePreflightAuthorization
    ] = [
        .camera: .authorized,
        .microphone: .authorized,
    ]
    private var requested: [MediaCapturePreflightResource] = []

    func setAvailable(_ available: Bool, for resource: MediaCapturePreflightResource) {
        lock.lock()
        if available {
            unavailable.remove(resource)
        } else {
            unavailable.insert(resource)
        }
        lock.unlock()
    }

    func setState(
        _ state: MediaCapturePreflightAuthorization,
        for resource: MediaCapturePreflightResource
    ) {
        lock.lock()
        states[resource] = state
        lock.unlock()
    }

    func isHardwareAvailable(_ resource: MediaCapturePreflightResource) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !unavailable.contains(resource)
    }

    func authorizationState(
        for resource: MediaCapturePreflightResource
    ) -> MediaCapturePreflightAuthorization {
        lock.lock()
        defer { lock.unlock() }
        return states[resource] ?? .unsupported
    }

    func requestAuthorization(
        for resource: MediaCapturePreflightResource
    ) async -> MediaCapturePreflightAuthorization {
        recordRequest(resource)
    }

    private func recordRequest(
        _ resource: MediaCapturePreflightResource
    ) -> MediaCapturePreflightAuthorization {
        lock.lock()
        requested.append(resource)
        let state = states[resource] ?? .unsupported
        lock.unlock()
        return state
    }

    func requestedResources() -> [MediaCapturePreflightResource] {
        lock.lock()
        defer { lock.unlock() }
        return requested
    }
}

@MainActor
func invoke(
    _ controller: MediaCaptureBridgeController,
    operation: String,
    requestId: String,
    payload: [String: Any]
) async -> BridgeTestOutcome {
    let probe = CompletionProbe()
    controller.handle(
        operation: operation,
        arguments: requestEnvelope(requestId: requestId, payload: payload),
        completion: probe
    )
    return await probe.value()
}

@MainActor
func assertResultType(
    _ controller: MediaCaptureBridgeController,
    operation: String,
    requestId: String,
    payload: [String: Any],
    expected: String,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    let outcome = await invoke(
        controller,
        operation: operation,
        requestId: requestId,
        payload: payload
    )
    XCTAssertEqual(resultType(outcome), expected, file: file, line: line)
}

func requestEnvelope(requestId: String, payload: [String: Any]) -> [String: Any] {
    ["wireVersion": 3, "requestId": requestId, "payload": payload]
}

func startPayload() -> [String: Any] {
    [
        "enabledMediaTypes": ["photo", "video"],
        "preferredCamera": "rear",
        "audioEnabled": true,
        "maxVideoDurationMillis": 15_000,
    ]
}

func sessionPayload(_ handle: String) -> [String: Any] { ["sessionHandle": handle] }
func mediaPayload(_ handle: String) -> [String: Any] { ["mediaHandle": handle] }

func resultType(_ outcome: BridgeTestOutcome) -> String? {
    guard case let .success(value) = outcome else { return nil }
    return value["resultType"] as? String
}

func failure(_ outcome: BridgeTestOutcome) -> MediaCaptureWireFailure? {
    guard case let .failure(value) = outcome else { return nil }
    return value
}

func media(handle: String, type: MediaType, durationMilliseconds: Int?) throws -> MediaMetadata {
    try MediaMetadata(
        mediaHandle: MediaHandle(rawValue: handle),
        mediaType: type,
        pixelWidth: 1_080,
        pixelHeight: 1_920,
        durationMilliseconds: durationMilliseconds,
        orientationDegrees: 0,
        byteLength: 4_096
    )
}

func sanitizedJpeg() -> Data {
    Data([
        0xff, 0xd8,
        0xff, 0xe0, 0x00, 0x10,
        0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00,
        0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
        0xff, 0xc0, 0x00, 0x0b,
        0x08, 0x00, 0x02, 0x00, 0x02, 0x01, 0x01, 0x11, 0x00,
        0xff, 0xda, 0x00, 0x08,
        0x01, 0x01, 0x00, 0x00, 0x3f, 0x00,
        0x01, 0xff, 0xd9,
    ])
}

@MainActor
func waitUntil(
    iterations: Int = 200,
    condition: @MainActor () async -> Bool
) async -> Bool {
    for _ in 0 ..< iterations {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return false
}
