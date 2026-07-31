import Foundation

public struct SessionHandle: Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) throws {
        guard HandleValidator.isValid(rawValue) else {
            throw MediaCaptureFailure(.invalidArgument)
        }
        self.rawValue = rawValue
    }

    internal init(generatedRawValue: String) {
        rawValue = generatedRawValue
    }
}

public struct MediaHandle: Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) throws {
        guard HandleValidator.isValid(rawValue) else {
            throw MediaCaptureFailure(.invalidArgument)
        }
        self.rawValue = rawValue
    }

    internal init(generatedRawValue: String) {
        rawValue = generatedRawValue
    }
}

private enum HandleValidator {
    static func isValid(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 128 else { return false }
        return value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
        }
    }
}

public enum MediaType: String, CaseIterable, Sendable {
    case photo
    case video
}

public enum CameraPosition: String, CaseIterable, Sendable {
    case rear
    case front
}

public enum FlashMode: String, CaseIterable, Sendable {
    case off
    case on
    case auto
    case torch
}

public enum PermissionResource: Sendable {
    case camera
    case microphone
}

public enum PermissionState: String, Sendable {
    case notDetermined = "not_determined"
    case granted
    case denied
    case restricted
    case permanentlyDenied = "permanently_denied"
    case unsupported
}

public struct SessionOptions: Equatable, Sendable {
    public let enabledMediaTypes: Set<MediaType>
    public let preferredCamera: CameraPosition
    public let audioEnabled: Bool
    public let maxVideoDurationMilliseconds: Int

    public init(
        enabledMediaTypes: Set<MediaType>,
        preferredCamera: CameraPosition = .rear,
        audioEnabled: Bool,
        maxVideoDurationMilliseconds: Int
    ) throws {
        guard !enabledMediaTypes.isEmpty,
              (1 ... 60_000).contains(maxVideoDurationMilliseconds)
        else {
            throw MediaCaptureFailure(.invalidArgument)
        }
        self.enabledMediaTypes = enabledMediaTypes
        self.preferredCamera = preferredCamera
        self.audioEnabled = audioEnabled
        self.maxVideoDurationMilliseconds = maxVideoDurationMilliseconds
    }
}

public struct SessionCreated: Equatable, Sendable {
    public let sessionHandle: SessionHandle
}

public struct SessionReadySnapshot: Equatable, Sendable {
    public let sessionHandle: SessionHandle
    public let activeCamera: CameraPosition
    public let availableCameras: [CameraPosition]
    public let switchCameraSupported: Bool
    public let supportedFlashModes: [FlashMode]
    public let focusPointSupported: Bool
    public let minimumZoomFactor: Double
    public let maximumZoomFactor: Double

    public init(
        sessionHandle: SessionHandle,
        activeCamera: CameraPosition,
        availableCameras: [CameraPosition],
        switchCameraSupported: Bool,
        supportedFlashModes: [FlashMode],
        focusPointSupported: Bool,
        minimumZoomFactor: Double,
        maximumZoomFactor: Double
    ) {
        self.sessionHandle = sessionHandle
        self.activeCamera = activeCamera
        self.availableCameras = availableCameras
        self.switchCameraSupported = switchCameraSupported
        self.supportedFlashModes = supportedFlashModes
        self.focusPointSupported = focusPointSupported
        self.minimumZoomFactor = minimumZoomFactor
        self.maximumZoomFactor = maximumZoomFactor
    }
}

public struct MediaMetadata: Equatable, Sendable {
    public let mediaHandle: MediaHandle
    public let mediaType: MediaType
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let durationMilliseconds: Int?
    public let orientationDegrees: Int
    public let byteLength: Int

    public init(
        mediaHandle: MediaHandle,
        mediaType: MediaType,
        pixelWidth: Int,
        pixelHeight: Int,
        durationMilliseconds: Int?,
        orientationDegrees: Int,
        byteLength: Int
    ) throws {
        guard pixelWidth > 0, pixelHeight > 0, byteLength > 0,
              [0, 90, 180, 270].contains(orientationDegrees),
              (mediaType == .photo && durationMilliseconds == nil) ||
              (mediaType == .video && durationMilliseconds.map { $0 > 0 && $0 <= 60_000 } == true)
        else {
            throw MediaCaptureFailure(.encodingFailed)
        }
        self.mediaHandle = mediaHandle
        self.mediaType = mediaType
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.durationMilliseconds = durationMilliseconds
        self.orientationDegrees = orientationDegrees
        self.byteLength = byteLength
    }
}

public struct ConfirmedMedia: Equatable, Sendable {
    public let metadata: MediaMetadata
    public let leaseExpiresAt: Date
}

public struct RecordingStarted: Equatable, Sendable {
    public let sessionHandle: SessionHandle
    public let audioIncluded: Bool
}

public struct RenderAttachmentResult: Equatable, Sendable {
    public let kind: RenderAttachmentKind
    public let ownerGeneration: Int64
}

public enum RenderAttachmentKind: String, Sendable {
    case livePreview = "live_preview"
    case unconfirmedPreview = "unconfirmed_preview"
}

package struct RenderAttachmentContext: Equatable, Sendable {
    package let kind: RenderAttachmentKind
    package let ownerGeneration: Int64

    package init(kind: RenderAttachmentKind, ownerGeneration: Int64) {
        self.kind = kind
        self.ownerGeneration = ownerGeneration
    }
}

/// The native consumer owns this transport-neutral lifecycle value and gives it to
/// `MediaCaptureAppleRendering` when creating a concrete render surface.
public final class MediaCaptureRenderSurfaceOwner: @unchecked Sendable {
    public let ownerGeneration: Int64

    private let lock = NSLock()
    private weak var endpoint: MediaCaptureRenderMountEndpoint?
    private var installedEndpointIdentifier: ObjectIdentifier?
    private var invalidationHandler: (@Sendable () -> Void)?

    public init(ownerGeneration: Int64) {
        self.ownerGeneration = ownerGeneration
    }

    package func install(endpoint: MediaCaptureRenderMountEndpoint) throws {
        lock.lock()
        defer { lock.unlock() }
        guard ownerGeneration > 0, installedEndpointIdentifier == nil else {
            throw MediaCaptureFailure(.invalidArgument)
        }
        installedEndpointIdentifier = endpoint.identity
        self.endpoint = endpoint
    }

    package func endpointSnapshot() -> MediaCaptureRenderMountEndpoint? {
        lock.lock()
        defer { lock.unlock() }
        return endpoint
    }

    package func installedEndpointIdentifierSnapshot() -> ObjectIdentifier? {
        lock.lock()
        defer { lock.unlock() }
        return installedEndpointIdentifier
    }

    package func setInvalidationHandler(
        for endpointIdentifier: ObjectIdentifier,
        _ handler: (@Sendable () -> Void)?
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard installedEndpointIdentifier == endpointIdentifier else { return }
        invalidationHandler = handler
    }

    package func surfaceDestroyed(endpointIdentifier: ObjectIdentifier) {
        lock.lock()
        guard installedEndpointIdentifier == endpointIdentifier else {
            lock.unlock()
            return
        }
        endpoint = nil
        let handler = invalidationHandler
        invalidationHandler = nil
        lock.unlock()
        handler?()
    }
}

public struct MediaThumbnail: Equatable, Sendable {
    public let mediaHandle: MediaHandle
    public let data: Data
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let mediaType: MediaType
    public let posterFrameMilliseconds: Int?
    public let contentType = "image/jpeg"
    public let orientationDegrees = 0

    public var byteLength: Int { data.count }
}

public struct MediaReadAccess: Sendable {
    public let byteLength: Int
    public let contentType: String
    private let readBody: @Sendable () async throws -> Data

    internal init(
        byteLength: Int,
        contentType: String,
        readBody: @escaping @Sendable () async throws -> Data
    ) {
        self.byteLength = byteLength
        self.contentType = contentType
        self.readBody = readBody
    }

    public func readAll() async throws -> Data {
        try await readBody()
    }
}

public enum MediaCaptureEvent: Equatable, Sendable {
    case sessionReady(SessionReadySnapshot)
    case sessionFailed(sessionHandle: SessionHandle, failure: MediaCaptureFailure)
    case mediaPreviewReady(sessionHandle: SessionHandle, metadata: MediaMetadata)
    case mediaLeaseExpired(MediaHandle)
    case mediaReadRevoked(MediaHandle)
    case renderAttachmentRevoked(RenderAttachmentResult)
}

public struct MediaCaptureFailure: Error, Equatable, Sendable {
    public enum ID: String, Hashable, Sendable {
        case permissionDenied = "permission_denied"
        case permissionRestricted = "permission_restricted"
        case permissionPermanentlyDenied = "permission_permanently_denied"
        case resourceInUse = "resource_in_use"
        case storageFull = "storage_full"
        case encodingFailed = "encoding_failed"
        case mediaInvalid = "media_invalid"
        case sessionInvalid = "session_invalid"
        case unsupportedCapability = "unsupported_capability"
        case systemInterrupted = "system_interrupted"
        case sessionConflict = "session_conflict"
        case invalidState = "invalid_state"
        case invalidArgument = "invalid_argument"
        case sessionTimeout = "session_timeout"
        case thumbnailGenerationFailed = "thumbnail_generation_failed"
        case thumbnailGenerationCancelled = "thumbnail_generation_cancelled"
        case thumbnailOverloaded = "thumbnail_overloaded"
        case attachmentGenerationRetired = "attachment_generation_retired"
        case attachmentTargetConflict = "attachment_target_conflict"
    }

    public let id: ID

    public init(_ id: ID) {
        self.id = id
    }

    public var recoverable: Bool {
        switch id {
        case .permissionRestricted, .permissionPermanentlyDenied, .mediaInvalid,
             .sessionInvalid, .attachmentGenerationRetired:
            return false
        default:
            return true
        }
    }

    public var terminal: Bool {
        switch id {
        case .permissionDenied, .permissionRestricted, .permissionPermanentlyDenied,
             .resourceInUse, .storageFull, .encodingFailed, .systemInterrupted,
             .sessionTimeout:
            return true
        default:
            return false
        }
    }
}

internal struct MediaCaptureConfiguration: Sendable {
    let previewTimeToLive: TimeInterval
    let mediaLeaseTimeToLive: TimeInterval
    let readGracePeriod: TimeInterval
    let tombstoneTimeToLive: TimeInterval

    init(
        previewTimeToLive: TimeInterval = 600,
        mediaLeaseTimeToLive: TimeInterval = 86_400,
        readGracePeriod: TimeInterval = 60,
        tombstoneTimeToLive: TimeInterval = 300
    ) {
        self.previewTimeToLive = previewTimeToLive
        self.mediaLeaseTimeToLive = mediaLeaseTimeToLive
        self.readGracePeriod = readGracePeriod
        self.tombstoneTimeToLive = tombstoneTimeToLive
    }
}
