import Foundation
import MediaCapture
import UIKit

package let mediaCaptureWireVersion = generatedMediaCaptureWireVersion
package let mediaCaptureCommandsChannel = generatedCommandsChannel
package let mediaCaptureEventsChannel = generatedEventsChannel

package enum MediaCaptureWirePayload: Sendable {
    case startSession(SessionOptions)
    case sessionAction(SessionHandle)
    case flash(sessionHandle: SessionHandle, mode: FlashMode)
    case focus(sessionHandle: SessionHandle, normalizedX: Double, normalizedY: Double)
    case zoom(sessionHandle: SessionHandle, factor: Double)
    case mediaAction(MediaHandle)
    case thumbnail(mediaHandle: MediaHandle, maxPixelEdge: Int)
    case materialize(MediaHandle)
    case releaseMaterialized(exportHandle: String)
    case dismissPresentation(presentationRequestId: String)
}

package struct MediaCaptureWireRequest: Sendable {
    package let requestId: String
    package let operation: String
    package let payload: MediaCaptureWirePayload
}

package struct MediaCaptureWireFailure: Error, Equatable, Sendable {
    package let code: String
    package let details: [String: String]

    package init(code: String, details: [String: String]) {
        guard let descriptor = generatedErrorDescriptors.first(where: { $0.code == code }) else {
            preconditionFailure("Media Capture Wire error code is not declared by the generated contract")
        }
        precondition(descriptor.messagePolicy == "static_redacted")
        precondition(details.keys.allSatisfy(descriptor.detailsAllowedKeys.contains))
        self.code = code
        self.details = details
    }
}

package final class MediaCaptureWireBytes: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Data

    package init(_ data: Data) {
        storage = uniqueDataCopy(data)
    }

    deinit {
        clear()
    }

    package func copyData() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return uniqueDataCopy(storage)
    }

    package func takeData() -> Data {
        lock.lock()
        defer { lock.unlock() }
        let result = uniqueDataCopy(storage)
        wipe(&storage)
        return result
    }

    package func clear() {
        lock.lock()
        defer { lock.unlock() }
        wipe(&storage)
    }
}

package struct MediaCaptureRecordingValue: Equatable, Sendable {
    package let sessionHandle: SessionHandle
    package let audioIncluded: Bool
}

package struct MediaCaptureConfirmedValue: Equatable, Sendable {
    package let metadata: MediaMetadata
    package let leaseExpiresAt: Date
}

package final class MediaCaptureThumbnailValue: @unchecked Sendable {
    package let mediaHandle: MediaHandle
    package let pixelWidth: Int
    package let pixelHeight: Int
    package let mediaType: MediaType
    package let posterFrameMilliseconds: Int?
    package let contentType: String
    package let orientationDegrees: Int
    private let lock = NSLock()
    private var storage: Data

    package init(
        mediaHandle: MediaHandle,
        data: Data,
        pixelWidth: Int,
        pixelHeight: Int,
        mediaType: MediaType,
        posterFrameMilliseconds: Int?,
        contentType: String,
        orientationDegrees: Int
    ) {
        self.mediaHandle = mediaHandle
        storage = data
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.mediaType = mediaType
        self.posterFrameMilliseconds = posterFrameMilliseconds
        self.contentType = contentType
        self.orientationDegrees = orientationDegrees
    }

    deinit {
        clear()
    }

    package func copyData() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return uniqueDataCopy(storage)
    }

    package func clear() {
        lock.lock()
        defer { lock.unlock() }
        wipe(&storage)
    }
}

private func uniqueDataCopy(_ data: Data) -> Data {
    var result = Data(count: data.count)
    result.withUnsafeMutableBytes { destination in
        data.withUnsafeBytes { source in
            destination.copyMemory(from: source)
        }
    }
    return result
}

private func wipe(_ data: inout Data) {
    guard !data.isEmpty else { return }
    data.resetBytes(in: 0 ..< data.count)
    data.removeAll(keepingCapacity: false)
}

@MainActor
package protocol MediaCaptureBridgeCompletion: AnyObject {
    func success(_ value: [String: Any])
    func failure(_ failure: MediaCaptureWireFailure)
}

@MainActor
package protocol MediaCaptureBridgeEventSink: AnyObject {
    func success(_ value: [String: Any])
    func failure(_ failure: MediaCaptureWireFailure)
    func endOfStream()
}

package enum MediaCapturePresentationResult: Equatable, Sendable {
    case confirmed(MediaCaptureConfirmedValue)
    case cancelled
    case failure(MediaCaptureFailure)
}

package enum MediaCapturePreflightResource: Hashable, Sendable {
    case camera
    case microphone
}

package enum MediaCapturePreflightAuthorization: Equatable, Sendable {
    case notDetermined
    case authorized
    case restricted
    case denied
    case unsupported
}

package protocol MediaCapturePermissionServicing: Sendable {
    func isHardwareAvailable(_ resource: MediaCapturePreflightResource) -> Bool
    func authorizationState(
        for resource: MediaCapturePreflightResource
    ) -> MediaCapturePreflightAuthorization
    func requestAuthorization(
        for resource: MediaCapturePreflightResource
    ) async -> MediaCapturePreflightAuthorization
}

package struct MediaCapturePermissionPreflight: Sendable {
    private let service: any MediaCapturePermissionServicing

    package init(service: any MediaCapturePermissionServicing) {
        self.service = service
    }

    package func authorize(options: SessionOptions) async throws {
        var resources: [MediaCapturePreflightResource] = [.camera]
        if options.enabledMediaTypes.contains(.video), options.audioEnabled {
            resources.append(.microphone)
        }
        for resource in resources {
            guard service.isHardwareAvailable(resource) else {
                throw MediaCaptureFailure(.unsupportedCapability)
            }
            var state = service.authorizationState(for: resource)
            if case .notDetermined = state {
                state = await service.requestAuthorization(for: resource)
            }
            switch state {
            case .authorized:
                continue
            case .restricted:
                throw MediaCaptureFailure(.permissionRestricted)
            case .denied:
                throw MediaCaptureFailure(.permissionPermanentlyDenied)
            case .notDetermined, .unsupported:
                throw MediaCaptureFailure(.unsupportedCapability)
            }
        }
    }
}

@MainActor
package protocol MediaCapturePresentationSession: AnyObject, Sendable {
    func awaitResult() async throws -> MediaCapturePresentationResult
    func dismiss()
}

@MainActor
package protocol MediaCapturePresenting: AnyObject, Sendable {
    func preflight(options: SessionOptions) async throws
    func present(options: SessionOptions) throws -> any MediaCapturePresentationSession
}

package protocol MediaCaptureThumbnailEncoding: Sendable {
    func encode(
        value: MediaCaptureThumbnailValue,
        maxPixelEdge: Int
    ) async throws -> MediaCaptureEncodedThumbnail
}

package struct MediaCaptureEncodedThumbnail: Sendable {
    package let mediaHandle: MediaHandle
    package let bytes: MediaCaptureWireBytes
    package let byteLength: Int
    package let pixelWidth: Int
    package let pixelHeight: Int
    package let mediaType: MediaType
    package let posterFrameMilliseconds: Int?
    package let contentType: String
    package let orientationDegrees: Int
}

@MainActor
package struct MediaCapturePresentationOwner {
    package let identity: ObjectIdentifier
    package let presenter: any MediaCapturePresenting

    package init(identity: ObjectIdentifier, presenter: any MediaCapturePresenting) {
        self.identity = identity
        self.presenter = presenter
    }
}

package struct MediaCaptureOwnerCandidate: Sendable {
    package let identity: ObjectIdentifier
    package let isForeground: Bool
    package let isVisible: Bool
    package let belongsToCurrentEngine: Bool

    package init(
        identity: ObjectIdentifier,
        isForeground: Bool,
        isVisible: Bool,
        belongsToCurrentEngine: Bool
    ) {
        self.identity = identity
        self.isForeground = isForeground
        self.isVisible = isVisible
        self.belongsToCurrentEngine = belongsToCurrentEngine
    }
}

package enum MediaCaptureOwnerResolver {
    package static func uniqueForegroundOwner(
        _ candidates: [MediaCaptureOwnerCandidate]
    ) -> ObjectIdentifier? {
        let matches = candidates.filter {
            $0.isForeground && $0.isVisible && $0.belongsToCurrentEngine
        }
        guard matches.count == 1 else { return nil }
        return matches[0].identity
    }

    package static func isTrackedOwnerAlive(
        _ identity: ObjectIdentifier,
        candidates: [MediaCaptureOwnerCandidate]
    ) -> Bool {
        candidates.contains {
            $0.identity == identity && $0.isVisible && $0.belongsToCurrentEngine
        }
    }
}

@MainActor
package enum MediaCaptureViewControllerHierarchy {
    package static func contains(
        _ root: UIViewController,
        matching predicate: (UIViewController) -> Bool
    ) -> Bool {
        if predicate(root) { return true }
        if let presented = root.presentedViewController,
           contains(presented, matching: predicate) {
            return true
        }
        return root.children.contains { contains($0, matching: predicate) }
    }
}

package protocol MediaCaptureCoreServicing: AnyObject, Sendable {
    func events() async -> AsyncStream<MediaCaptureEvent>
    func startSession(options: SessionOptions) async throws -> SessionHandle
    func takePhoto(sessionHandle: SessionHandle) async throws -> MediaMetadata
    func startRecording(sessionHandle: SessionHandle) async throws -> MediaCaptureRecordingValue
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
    func confirm(mediaHandle: MediaHandle) async throws -> MediaCaptureConfirmedValue
    func cancel(sessionHandle: SessionHandle) async throws -> SessionHandle
    func releaseMedia(mediaHandle: MediaHandle) async throws -> MediaHandle
    func readMediaThumbnail(
        mediaHandle: MediaHandle,
        maxPixelEdge: Int
    ) async throws -> MediaCaptureThumbnailValue
    func copyConfirmedMediaToSink(
        mediaHandle: MediaHandle,
        sink: any MediaCopySink,
        maximumLength: Int
    ) async throws -> MediaExportResult
    func close() async
}
