import AVFoundation
import CoreGraphics
import Foundation

package enum MediaCaptureRenderSource: @unchecked Sendable {
    case live(AVCaptureSession)
    case photo(CGImage)
    case video(URL)
}

package struct MediaCaptureRenderCallbackGate: Sendable {
    private let mountBody: @Sendable () async -> Bool
    private let activeBody: @Sendable () async -> Bool
    private let mutationGate = MediaCaptureRenderMutationGate()

    package init(
        mountBody: @escaping @Sendable () async -> Bool,
        activeBody: @escaping @Sendable () async -> Bool
    ) {
        self.mountBody = mountBody
        self.activeBody = activeBody
    }

    package func validateBeforeMount() async -> Bool {
        guard mutationGate.isActive else { return false }
        guard await mountBody() else { return false }
        return mutationGate.isActive
    }

    package func invalidate() {
        mutationGate.invalidate()
    }

    package var acceptsMutations: Bool {
        mutationGate.isActive
    }

    @MainActor
    package func performMountIfActive(
        _ body: @MainActor @Sendable () throws -> MediaCaptureRenderBinding
    ) async rethrows -> MediaCaptureRenderBinding? {
        guard await mountBody() else { return nil }
        return try mutationGate.perform(body)
    }

    @discardableResult
    @MainActor
    package func performIfActive(
        _ body: @MainActor @Sendable () -> Void
    ) async -> Bool {
        guard await activeBody() else { return false }
        return mutationGate.perform(body) != nil
    }
}

private final class MediaCaptureRenderMutationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return active
    }

    func invalidate() {
        lock.lock()
        active = false
        lock.unlock()
    }

    @MainActor
    func perform<T>(_ body: @MainActor () throws -> T) rethrows -> T? {
        lock.lock()
        defer { lock.unlock() }
        guard active else { return nil }
        return try body()
    }
}

@MainActor
package final class MediaCaptureRenderBinding: @unchecked Sendable {
    private let callbackGate: MediaCaptureRenderCallbackGate
    private let revokeBody: @MainActor @Sendable () async -> Void
    private let detachBody: @MainActor @Sendable () async -> Void
    private var revoked = false
    private var detached = false

    package init(
        callbackGate: MediaCaptureRenderCallbackGate,
        revoke: @escaping @MainActor @Sendable () async -> Void,
        detach: @escaping @MainActor @Sendable () async -> Void
    ) {
        self.callbackGate = callbackGate
        revokeBody = revoke
        detachBody = detach
    }

    nonisolated package func invalidateGate() {
        callbackGate.invalidate()
    }

    package func revoke() async {
        guard !revoked else { return }
        revoked = true
        await revokeBody()
    }

    package func detach() async {
        guard !detached else { return }
        detached = true
        await detachBody()
    }
}

@MainActor
package final class MediaCaptureRenderMountEndpoint: @unchecked Sendable {
    nonisolated package let identity: ObjectIdentifier

    private let backingAvailableBody: @MainActor @Sendable () -> Bool
    private let mountBody: @MainActor @Sendable (
        MediaCaptureRenderSource,
        RenderAttachmentContext,
        MediaCaptureRenderCallbackGate
    ) async throws -> MediaCaptureRenderBinding
    private let attachedBody: @MainActor @Sendable (RenderAttachmentContext) -> Void
    private let revokedBody: @MainActor @Sendable (RenderAttachmentContext) -> Void
    private let detachedBody: @MainActor @Sendable (RenderAttachmentContext) -> Void

    package init(
        identity: ObjectIdentifier,
        backingAvailable: @escaping @MainActor @Sendable () -> Bool,
        mount: @escaping @MainActor @Sendable (
            MediaCaptureRenderSource,
            RenderAttachmentContext,
            MediaCaptureRenderCallbackGate
        ) async throws -> MediaCaptureRenderBinding,
        attached: @escaping @MainActor @Sendable (RenderAttachmentContext) -> Void = { _ in },
        revoked: @escaping @MainActor @Sendable (RenderAttachmentContext) -> Void = { _ in },
        detached: @escaping @MainActor @Sendable (RenderAttachmentContext) -> Void = { _ in }
    ) {
        self.identity = identity
        backingAvailableBody = backingAvailable
        mountBody = mount
        attachedBody = attached
        revokedBody = revoked
        detachedBody = detached
    }

    package func isBackingAvailable() -> Bool {
        backingAvailableBody()
    }

    package func mount(
        source: MediaCaptureRenderSource,
        context: RenderAttachmentContext,
        callbackGate: MediaCaptureRenderCallbackGate
    ) async throws -> MediaCaptureRenderBinding {
        try await mountBody(source, context, callbackGate)
    }

    package func didAttach(_ context: RenderAttachmentContext) {
        attachedBody(context)
    }

    package func didRevoke(_ context: RenderAttachmentContext) {
        revokedBody(context)
    }

    package func didDetach(_ context: RenderAttachmentContext) {
        detachedBody(context)
    }
}
