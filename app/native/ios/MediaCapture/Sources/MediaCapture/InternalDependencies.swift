import Foundation
import Security
import Darwin

internal enum SessionState: Sendable {
    case requestingPermission
    case preparing
    case ready
    case recording
    case previewing
    case completed
    case cancelled
    case failed
}

internal enum MediaState: Sendable {
    case preview
    case leased
    case releaseGrace
    case expiryGrace
    case discarded
    case released
    case expired
}

internal enum PlatformFailure: Error, Sendable {
    case resourceInUse
    case storageFull
    case encodingFailed
    case unsupported
    case interrupted
}

internal enum PlatformEvent: Sendable {
    case interrupted
}

internal struct PlatformReadySnapshot: Sendable {
    let activeCamera: CameraPosition
    let availableCameras: [CameraPosition]
    let supportedFlashModes: [FlashMode]
    let focusPointSupported: Bool
    let minimumZoomFactor: Double
    let maximumZoomFactor: Double
}

internal struct CapturedPhoto: Sendable {
    let encodedData: Data
}

internal protocol CapturePlatform: AnyObject {
    func events() -> AsyncStream<PlatformEvent>
    func permissionState(for resource: PermissionResource) async -> PermissionState
    func requestPermission(for resource: PermissionResource) async -> PermissionState
    func prepare(options: SessionOptions) async throws -> PlatformReadySnapshot
    func capturePhoto(flashMode: FlashMode) async throws -> CapturedPhoto
    func configureRecordingAudio(enabled: Bool) async throws
    func startRecording(to destination: URL) async throws
    func stopRecording() async throws
    func switchCamera() async throws -> PlatformReadySnapshot
    func setFlashMode(_ mode: FlashMode) async throws
    func setFocusPoint(x: Double, y: Double) async throws
    func setZoomFactor(_ factor: Double) async throws
    func liveRenderSource() async throws -> MediaCaptureRenderSource
    func stopSession() async
    func close() async
}

internal protocol MediaCaptureClock: Sendable {
    var now: Date { get }
    func sleep(until deadline: Date) async throws
}

internal struct SystemMediaCaptureClock: MediaCaptureClock {
    var now: Date { Date() }

    func sleep(until deadline: Date) async throws {
        let interval = max(0, deadline.timeIntervalSinceNow)
        let nanoseconds = UInt64(min(interval, 9_223_372_036) * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}

internal protocol HandleGenerating: Sendable {
    func nextHandle() throws -> String
}

internal struct SecureHandleGenerator: HandleGenerating {
    func nextHandle() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw MediaCaptureFailure(.resourceInUse)
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

internal struct StoredMediaReference: Hashable, Sendable {
    let value: String

    init(value: String = UUID().uuidString) {
        self.value = value
    }
}

internal struct StoredMedia: Sendable {
    let reference: StoredMediaReference
    let mediaType: MediaType
    let pixelWidth: Int
    let pixelHeight: Int
    let durationMilliseconds: Int?
    let orientationDegrees: Int
    let byteLength: Int
    let contentType: String
}

internal protocol MediaSourceBackend: Sendable {
    func readChunk(maximumLength: Int) throws -> Data?
    func close()
}

internal final class FileHandleSourceBackend: MediaSourceBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var handle: FileHandle?

    init(url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
    }

    func readChunk(maximumLength: Int) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard let handle else { throw MediaCaptureFailure(.invalidState) }
        var bytes = [UInt8](repeating: 0, count: maximumLength)
        let count = Darwin.read(handle.fileDescriptor, &bytes, maximumLength)
        guard count >= 0 else { throw MediaCaptureFailure(.invalidState) }
        guard count > 0 else { return nil }
        return Data(bytes.prefix(count))
    }

    func close() {
        lock.lock()
        guard let handle else {
            lock.unlock()
            return
        }
        self.handle = nil
        try? handle.close()
        lock.unlock()
    }
}

internal final class MediaSourceAccess: @unchecked Sendable {
    let fileURL: URL?
    private let backend: any MediaSourceBackend
    private let lock = NSLock()
    private var closed = false

    init(fileURL: URL) throws {
        self.fileURL = fileURL
        backend = try FileHandleSourceBackend(url: fileURL)
    }

    init(fileURL: URL? = nil, backend: any MediaSourceBackend) {
        self.fileURL = fileURL
        self.backend = backend
    }

    func readAll() async throws -> Data {
        var result = Data()
        while true {
            try Task.checkCancellation()
            try ensureOpen()
            let chunk = try backend.readChunk(maximumLength: 64 * 1_024)
            try ensureOpen()
            guard let chunk, !chunk.isEmpty else { return result }
            result.append(chunk)
            await Task.yield()
        }
    }

    func close() {
        lock.lock()
        closed = true
        lock.unlock()
        backend.close()
    }

    private func ensureOpen() throws {
        lock.lock()
        let isOpen = !closed
        lock.unlock()
        guard isOpen else { throw MediaCaptureFailure(.invalidState) }
    }
}

internal protocol MediaFileStoring: Sendable {
    func removeTemporaryResidue() async
    func recordingDestination() async throws -> URL
    func storePhoto(_ photo: CapturedPhoto) async throws -> StoredMedia
    func finalizeRecording(at destination: URL) async throws -> StoredMedia
    func discardRecording(at destination: URL) async
    func openSource(_ reference: StoredMediaReference) async throws -> MediaSourceAccess
    func previewRenderSource(_ media: StoredMedia) async throws -> MediaCaptureRenderSource
    func delete(_ reference: StoredMediaReference) async
}

internal struct GeneratedThumbnail: Sendable {
    let buffer: SensitiveDataBuffer
    let pixelWidth: Int
    let pixelHeight: Int
    let actualPosterFrameMilliseconds: Int?
}

internal final class CancellationSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    func checkCancellation() throws {
        if isCancelled { throw CancellationError() }
    }
}

internal protocol ThumbnailGenerating: Sendable {
    func generate(
        from source: MediaSourceAccess,
        media: StoredMedia,
        maximumPixelEdge: Int,
        cancellation: CancellationSignal
    ) async throws -> GeneratedThumbnail
}

internal final class ManagedThumbnailWorker: @unchecked Sendable {
    private let task: Task<GeneratedThumbnail, Error>

    init(
        generator: any ThumbnailGenerating,
        source: MediaSourceAccess,
        media: StoredMedia,
        maximumPixelEdge: Int,
        cancellation: CancellationSignal,
        onDecoderFailure: @escaping @Sendable () -> Void
    ) {
        task = Task {
            do {
                try Task.checkCancellation()
                return try await generator.generate(
                    from: source,
                    media: media,
                    maximumPixelEdge: maximumPixelEdge,
                    cancellation: cancellation
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                onDecoderFailure()
                throw error
            }
        }
    }

    func value() async throws -> GeneratedThumbnail {
        try await task.value
    }

    func cancel() {
        task.cancel()
    }
}

internal final class SensitiveDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let storage: NSMutableData

    init(_ data: Data) {
        storage = NSMutableData(data: data)
    }

    init() {
        storage = NSMutableData()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.length
    }

    var isEmpty: Bool { count == 0 }

    func copy() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return Data(bytes: storage.bytes, count: storage.length)
    }

    func starts(with bytes: [UInt8]) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return Data(bytes: storage.bytes, count: storage.length).starts(with: bytes)
    }

    func suffix(_ length: Int) -> Data {
        lock.lock()
        defer { lock.unlock() }
        return Data(bytes: storage.bytes, count: storage.length).suffix(length)
    }

    func withMutableData<T>(_ body: (NSMutableData) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(storage)
    }

    func wipe() {
        lock.lock()
        if storage.length > 0 {
            memset(storage.mutableBytes, 0, storage.length)
            storage.length = 0
        }
        lock.unlock()
    }
}

internal final class WeakRenderSurfaceOwner: @unchecked Sendable {
    weak var value: MediaCaptureRenderSurfaceOwner?

    init(_ value: MediaCaptureRenderSurfaceOwner) {
        self.value = value
    }
}

internal struct AttachmentBinding: Sendable {
    let generation: Int64
    let targetIdentifier: ObjectIdentifier
    let surfaceOwner: WeakRenderSurfaceOwner
    let mountEndpoint: MediaCaptureRenderMountEndpoint
    let renderSource: MediaCaptureRenderSource
    let renderBinding: MediaCaptureRenderBinding
}

internal struct AttachmentReservation: Sendable {
    let identifier: UUID
    let generation: Int64
    let targetIdentifier: ObjectIdentifier
    let surfaceOwner: WeakRenderSurfaceOwner
    let mountEndpoint: MediaCaptureRenderMountEndpoint
    let callbackGate: MediaCaptureRenderCallbackGate
    let lifecycleEpoch: UInt64
}

internal struct AttachmentSlot: Sendable {
    var highWatermark: Int64 = 0
    var reservation: AttachmentReservation?
    var binding: AttachmentBinding?
    var cleanupInProgress = false
}
