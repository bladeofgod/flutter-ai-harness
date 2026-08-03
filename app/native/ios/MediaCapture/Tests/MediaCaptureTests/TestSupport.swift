import AVFoundation
import Foundation
@testable import MediaCapture

actor FakeCapturePlatform: CapturePlatform {
    nonisolated let eventStream: AsyncStream<PlatformEvent>
    nonisolated let eventContinuation: AsyncStream<PlatformEvent>.Continuation

    var cameraPermission: PermissionState = .granted
    var microphonePermission: PermissionState = .granted
    var requestedPermissions: [PermissionResource] = []
    var preparedOptions: [SessionOptions] = []
    var availableCameras: [CameraPosition] = [.rear, .front]
    var configuredRecordingAudio: [Bool] = []
    var recording = false
    var stopRecordingStarted = false
    var stoppedSessionCount = 0
    var switchCameraCallCount = 0
    var switchCameraFailure: PlatformFailure?
    var switchCameraGate: TestAsyncGate?
    var switchCameraStarted = false
    var capturedPhotoData = Data([1, 2, 3])
    var capturedPhotoFlashModes: [FlashMode] = []
    var flashFailure: PlatformFailure?
    var flashGate: TestAsyncGate?
    var flashCallStarted = false
    var invalidReadySnapshot = false
    var prepareFailure: PlatformFailure?
    var stopSessionGate: TestAsyncGate?
    var stopSessionStarted = false

    init() {
        let pair = AsyncStream<PlatformEvent>.makeStream()
        eventStream = pair.stream
        eventContinuation = pair.continuation
    }

    nonisolated func events() -> AsyncStream<PlatformEvent> { eventStream }

    func permissionState(for resource: PermissionResource) async -> PermissionState {
        resource == .camera ? cameraPermission : microphonePermission
    }

    func requestPermission(for resource: PermissionResource) async -> PermissionState {
        requestedPermissions.append(resource)
        if resource == .camera, cameraPermission == .notDetermined {
            cameraPermission = .granted
        }
        if resource == .microphone, microphonePermission == .notDetermined {
            microphonePermission = .granted
        }
        return resource == .camera ? cameraPermission : microphonePermission
    }

    func prepare(options: SessionOptions) async throws -> PlatformReadySnapshot {
        preparedOptions.append(options)
        if let prepareFailure { throw prepareFailure }
        if invalidReadySnapshot {
            return PlatformReadySnapshot(
                activeCamera: .rear,
                availableCameras: [],
                supportedFlashModes: [],
                focusPointSupported: false,
                minimumZoomFactor: .nan,
                maximumZoomFactor: 0
            )
        }
        return PlatformReadySnapshot(
            activeCamera: options.preferredCamera,
            availableCameras: availableCameras,
            supportedFlashModes: [.off, .on, .auto, .torch],
            focusPointSupported: true,
            minimumZoomFactor: 1,
            maximumZoomFactor: 4
        )
    }

    func capturePhoto(flashMode: FlashMode) async throws -> CapturedPhoto {
        capturedPhotoFlashModes.append(flashMode)
        return CapturedPhoto(encodedData: capturedPhotoData)
    }

    func configureRecordingAudio(enabled: Bool) async throws {
        configuredRecordingAudio.append(enabled)
    }

    func startRecording(to destination: URL) async throws {
        try Data([4, 5, 6]).write(to: destination)
        recording = true
    }

    func stopRecording() async throws {
        stopRecordingStarted = true
        guard recording else { throw PlatformFailure.interrupted }
        recording = false
    }

    func switchCamera() async throws -> PlatformReadySnapshot {
        switchCameraCallCount += 1
        switchCameraStarted = true
        if let switchCameraGate { await switchCameraGate.wait() }
        if let switchCameraFailure { throw switchCameraFailure }
        return PlatformReadySnapshot(
            activeCamera: .front,
            availableCameras: [.rear, .front],
            supportedFlashModes: [.off, .on, .auto],
            focusPointSupported: true,
            minimumZoomFactor: 1,
            maximumZoomFactor: 3
        )
    }

    func setFlashMode(_ mode: FlashMode) async throws {
        flashCallStarted = true
        if let flashGate { await flashGate.wait() }
        if let flashFailure { throw flashFailure }
    }
    func setFocusPoint(x: Double, y: Double) async throws {}
    func setZoomFactor(_ factor: Double) async throws {}

    func liveRenderSource() async throws -> MediaCaptureRenderSource {
        .live(AVCaptureSession())
    }

    func stopSession() async {
        stopSessionStarted = true
        if let stopSessionGate { await stopSessionGate.wait() }
        recording = false
        stoppedSessionCount += 1
    }

    func close() async {
        recording = false
        eventContinuation.finish()
    }

    nonisolated func interrupt() {
        eventContinuation.yield(.interrupted)
    }

    func configureSwitchCameraGate(_ gate: TestAsyncGate?) {
        switchCameraGate = gate
        switchCameraStarted = false
    }

    func configureStopSession(_ gate: TestAsyncGate?) {
        stopSessionGate = gate
        stopSessionStarted = false
    }
}

final class ManualClock: MediaCaptureClock, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(now: Date = Date(timeIntervalSince1970: 1_000)) {
        value = now
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        value = value.addingTimeInterval(interval)
        lock.unlock()
    }

    func sleep(until deadline: Date) async throws {
        while now < deadline {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}

final class SequentialHandleGenerator: HandleGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var next = 0

    func nextHandle() throws -> String {
        lock.lock()
        defer { lock.unlock() }
        next += 1
        return String(format: "test_handle_%032d", next)
    }
}

actor FakeMediaFileStore: MediaFileStoring {
    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("MediaCaptureTests-\(UUID().uuidString)", isDirectory: true)
    private var locations: [StoredMediaReference: URL] = [:]
    private(set) var deletedReferences: [StoredMediaReference] = []
    private(set) var discardedRecordings: [URL] = []
    var readBackend: (any MediaSourceBackend)?
    var openSourceGate: TestAsyncGate?
    private var deleteGate: TestAsyncGate?
    private(set) var openSourceStarted = false
    private(set) var deleteStarted = false

    init() {
        try? FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
    }

    func removeTemporaryResidue() async {
        for url in locations.values { try? FileManager.default.removeItem(at: url) }
        locations.removeAll()
    }

    func recordingDestination() async throws -> URL {
        root.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
    }

    func storePhoto(_ photo: CapturedPhoto) async throws -> StoredMedia {
        let reference = StoredMediaReference()
        let url = root.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        let bytes = Data([0xff, 0xd8, 1, 2, 3, 0xff, 0xd9])
        try bytes.write(to: url)
        locations[reference] = url
        return StoredMedia(
            reference: reference,
            mediaType: .photo,
            pixelWidth: 120,
            pixelHeight: 80,
            durationMilliseconds: nil,
            orientationDegrees: 0,
            byteLength: bytes.count,
            contentType: "image/jpeg"
        )
    }

    func finalizeRecording(at destination: URL) async throws -> StoredMedia {
        let reference = StoredMediaReference()
        locations[reference] = destination
        let count = (try? Data(contentsOf: destination).count) ?? 3
        return StoredMedia(
            reference: reference,
            mediaType: .video,
            pixelWidth: 1920,
            pixelHeight: 1080,
            durationMilliseconds: 1_500,
            orientationDegrees: 0,
            byteLength: count,
            contentType: "video/mp4"
        )
    }

    func discardRecording(at destination: URL) async {
        discardedRecordings.append(destination)
        try? FileManager.default.removeItem(at: destination)
    }

    func openSource(_ reference: StoredMediaReference) async throws -> MediaSourceAccess {
        if let gate = openSourceGate {
            openSourceStarted = true
            openSourceGate = nil
            await gate.wait()
        }
        if let readBackend {
            return MediaSourceAccess(backend: readBackend)
        }
        guard let url = locations[reference] else {
            throw MediaCaptureFailure(.mediaInvalid)
        }
        return try MediaSourceAccess(fileURL: url)
    }

    func previewRenderSource(_ media: StoredMedia) async throws -> MediaCaptureRenderSource {
        guard let url = locations[media.reference] else {
            throw MediaCaptureFailure(.mediaInvalid)
        }
        return .video(url)
    }

    func configureDeleteGate(_ gate: TestAsyncGate) {
        deleteGate = gate
    }

    func delete(_ reference: StoredMediaReference) async {
        deletedReferences.append(reference)
        if let deleteGate {
            deleteStarted = true
            self.deleteGate = nil
            await deleteGate.wait()
        }
        if let url = locations.removeValue(forKey: reference) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

final class TestAsyncGate: @unchecked Sendable {
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

final class BlockingSourceBackend: MediaSourceBackend, @unchecked Sendable {
    private let condition = NSCondition()
    private var closed = false
    private var reading = false

    var didStartReading: Bool {
        condition.lock()
        defer { condition.unlock() }
        return reading
    }

    var isClosed: Bool {
        condition.lock()
        defer { condition.unlock() }
        return closed
    }

    func readChunk(maximumLength: Int) throws -> Data? {
        condition.lock()
        reading = true
        condition.broadcast()
        while !closed { condition.wait() }
        condition.unlock()
        throw MediaCaptureFailure(.invalidState)
    }

    func close() {
        condition.lock()
        closed = true
        condition.broadcast()
        condition.unlock()
    }
}

struct ImmediateThumbnailGenerator: ThumbnailGenerating {
    let posterFrameMilliseconds: Int?

    init(posterFrameMilliseconds: Int? = nil) {
        self.posterFrameMilliseconds = posterFrameMilliseconds
    }

    func generate(
        from source: MediaSourceAccess,
        media: StoredMedia,
        maximumPixelEdge: Int,
        cancellation: CancellationSignal
    ) async throws -> GeneratedThumbnail {
        try cancellation.checkCancellation()
        let edge = min(128, maximumPixelEdge)
        return GeneratedThumbnail(
            buffer: SensitiveDataBuffer(Data([0xff, 0xd8, 7, 8, 9, 0xff, 0xd9])),
            pixelWidth: edge,
            pixelHeight: edge,
            actualPosterFrameMilliseconds: media.mediaType == .video
                ? (posterFrameMilliseconds ?? min(1_000, (media.durationMilliseconds ?? 0) / 2))
                : nil
        )
    }
}

final class BlockingThumbnailGenerator: ThumbnailGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var starts = 0
    private var cancellations = 0

    var started: Bool {
        startCount > 0
    }

    var startCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return starts
    }

    var cancellationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return cancellations
    }

    func generate(
        from source: MediaSourceAccess,
        media: StoredMedia,
        maximumPixelEdge: Int,
        cancellation: CancellationSignal
    ) async throws -> GeneratedThumbnail {
        markStarted()
        do {
            while true {
                try Task.checkCancellation()
                try cancellation.checkCancellation()
                try await Task.sleep(nanoseconds: 1_000_000)
            }
        } catch is CancellationError {
            markCancelled()
            throw CancellationError()
        }
    }

    private func markStarted() {
        lock.lock()
        starts += 1
        lock.unlock()
    }

    private func markCancelled() {
        lock.lock()
        cancellations += 1
        lock.unlock()
    }
}

final class InvalidThumbnailGenerator: ThumbnailGenerating, @unchecked Sendable {
    private(set) var buffer: SensitiveDataBuffer?

    func generate(
        from source: MediaSourceAccess,
        media: StoredMedia,
        maximumPixelEdge: Int,
        cancellation: CancellationSignal
    ) async throws -> GeneratedThumbnail {
        let buffer = SensitiveDataBuffer(Data(repeating: 7, count: 64))
        self.buffer = buffer
        return GeneratedThumbnail(
            buffer: buffer,
            pixelWidth: maximumPixelEdge + 1,
            pixelHeight: maximumPixelEdge + 1,
            actualPosterFrameMilliseconds: nil
        )
    }
}

final class RecordingThumbnailGenerator: ThumbnailGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedEdge: Int?
    private var recordedType: MediaType?

    var request: (Int, MediaType)? {
        lock.lock()
        defer { lock.unlock() }
        guard let recordedEdge, let recordedType else { return nil }
        return (recordedEdge, recordedType)
    }

    func generate(
        from source: MediaSourceAccess,
        media: StoredMedia,
        maximumPixelEdge: Int,
        cancellation: CancellationSignal
    ) async throws -> GeneratedThumbnail {
        record(edge: maximumPixelEdge, type: media.mediaType)
        return GeneratedThumbnail(
            buffer: SensitiveDataBuffer(Data([0xff, 0xd8, 1, 0xff, 0xd9])),
            pixelWidth: maximumPixelEdge,
            pixelHeight: max(1, maximumPixelEdge / 2),
            actualPosterFrameMilliseconds: media.mediaType == .video
                ? min(1_000, (media.durationMilliseconds ?? 0) / 2)
                : nil
        )
    }

    private func record(edge: Int, type: MediaType) {
        lock.lock()
        recordedEdge = edge
        recordedType = type
        lock.unlock()
    }
}

@MainActor
final class FakeRenderTarget: @unchecked Sendable {
    private let owner: MediaCaptureRenderSurfaceOwner
    private(set) var callbacks: [String] = []
    private(set) var bindings: [FakeRenderBinding] = []
    private(set) var mountStarted = false
    private(set) var pendingCallbackGate: MediaCaptureRenderCallbackGate?
    var mountGate: TestAsyncGate?
    private var endpointStorage: MediaCaptureRenderMountEndpoint?
    private var installed = false

    init(ownerGeneration: Int64 = 1) {
        owner = MediaCaptureRenderSurfaceOwner(ownerGeneration: ownerGeneration)
    }

    var surfaceOwner: MediaCaptureRenderSurfaceOwner {
        if !installed {
            try? owner.install(endpoint: endpoint)
            installed = true
        }
        return owner
    }

    func invalidateOwner() {
        owner.surfaceDestroyed(endpointIdentifier: endpoint.identity)
    }

    private var endpoint: MediaCaptureRenderMountEndpoint {
        if let endpointStorage { return endpointStorage }
        let endpoint = MediaCaptureRenderMountEndpoint(
            identity: ObjectIdentifier(self),
            backingAvailable: { [weak self] in self != nil },
            mount: { [weak self] _, _, callbackGate in
                guard let self else { throw MediaCaptureFailure(.invalidArgument) }
                self.mountStarted = true
                self.pendingCallbackGate = callbackGate
                if let mountGate = self.mountGate { await mountGate.wait() }
                guard let binding = await callbackGate.performMountIfActive({
                    let state = FakeRenderBinding(callbackGate: callbackGate)
                    self.bindings.append(state)
                    return state.binding
                }) else {
                    throw MediaCaptureFailure(.attachmentGenerationRetired)
                }
                return binding
            },
            attached: { [weak self] context in
                self?.callbacks.append("attach:\(context.ownerGeneration)")
            },
            revoked: { [weak self] context in
                self?.callbacks.append("revoke:\(context.ownerGeneration)")
            },
            detached: { [weak self] context in
                self?.callbacks.append("detach:\(context.ownerGeneration)")
            }
        )
        endpointStorage = endpoint
        return endpoint
    }
}

@MainActor
final class FakeRenderBinding: @unchecked Sendable {
    private let callbackGate: MediaCaptureRenderCallbackGate
    private(set) var revokeCount = 0
    private(set) var detachCount = 0
    private(set) var renderedFrameCount = 0
    var revokeGate: TestAsyncGate?
    private(set) var revokeStarted = false
    private var bindingStorage: MediaCaptureRenderBinding?

    init(callbackGate: MediaCaptureRenderCallbackGate) {
        self.callbackGate = callbackGate
    }

    var binding: MediaCaptureRenderBinding {
        if let bindingStorage { return bindingStorage }
        let binding = MediaCaptureRenderBinding(
            callbackGate: callbackGate,
            revoke: { [weak self] in
                guard let self else { return }
                self.revokeStarted = true
                if let revokeGate = self.revokeGate { await revokeGate.wait() }
                self.revokeCount += 1
            },
            detach: { [weak self] in
                self?.detachCount += 1
            }
        )
        bindingStorage = binding
        return binding
    }

    func emitFrame() async {
        await callbackGate.performIfActive { [weak self] in
            self?.renderedFrameCount += 1
        }
    }
}

struct CoreFixture {
    let core: MediaCaptureCore
    let platform: FakeCapturePlatform
    let files: FakeMediaFileStore
    let clock: ManualClock

    init(
        configuration: MediaCaptureConfiguration = MediaCaptureConfiguration(),
        thumbnailGenerator: any ThumbnailGenerating = ImmediateThumbnailGenerator()
    ) {
        platform = FakeCapturePlatform()
        files = FakeMediaFileStore()
        clock = ManualClock()
        core = MediaCaptureCore(
            configuration: configuration,
            platform: platform,
            fileStore: files,
            clock: clock,
            handleGenerator: SequentialHandleGenerator(),
            thumbnailGenerator: thumbnailGenerator
        )
    }

    func startReadySession(
        mediaTypes: Set<MediaType> = [.photo, .video],
        audioEnabled: Bool = false,
        maxVideoDurationMilliseconds: Int = 5_000
    ) async throws -> SessionHandle {
        let stream = await core.events()
        let created = try await core.startSession(options: SessionOptions(
            enabledMediaTypes: mediaTypes,
            audioEnabled: audioEnabled,
            maxVideoDurationMilliseconds: maxVideoDurationMilliseconds
        ))
        for await event in stream {
            if case let .sessionReady(snapshot) = event,
               snapshot.sessionHandle == created.sessionHandle {
                return created.sessionHandle
            }
        }
        throw MediaCaptureFailure(.systemInterrupted)
    }

    func confirmedPhoto() async throws -> ConfirmedMedia {
        let session = try await startReadySession(mediaTypes: [.photo])
        let preview = try await core.takePhoto(sessionHandle: session)
        return try await core.confirm(mediaHandle: preview.mediaHandle)
    }
}

func captureFailure(
    _ operation: @Sendable () async throws -> Void
) async -> MediaCaptureFailure? {
    do {
        try await operation()
        return nil
    } catch let failure as MediaCaptureFailure {
        return failure
    } catch {
        return nil
    }
}

func waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    _ predicate: @escaping @Sendable () async -> Bool
) async -> Bool {
    let start = DispatchTime.now().uptimeNanoseconds
    while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
        if await predicate() { return true }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return false
}
