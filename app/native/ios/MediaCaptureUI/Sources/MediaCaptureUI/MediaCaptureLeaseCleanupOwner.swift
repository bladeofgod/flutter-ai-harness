import Foundation
import MediaCapture

private final class MediaCaptureSettleRace: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Bool?
    private var continuation: CheckedContinuation<Bool, Never>?

    var resolvedResult: Bool? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }

    func resolve(_ result: Bool) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: result)
    }

    func value() async -> Bool {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(returning: result)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }
}

internal actor MediaCaptureLeaseCleanupOwner {
    static let shared = MediaCaptureLeaseCleanupOwner()

    private let retryDelayNanoseconds: UInt64
    private var trackedTasks: [UUID: [Task<Void, Never>]] = [:]

    init(retryDelayNanoseconds: UInt64 = 50_000_000) {
        self.retryDelayNanoseconds = retryDelayNanoseconds
    }

    func waitForTasks(
        _ tasks: [Task<Void, Never>],
        timeoutNanoseconds: UInt64,
        onLateSettled: @escaping @MainActor @Sendable () async -> Void
    ) async -> Bool {
        guard !tasks.isEmpty else { return true }
        let identifier = UUID()
        let race = MediaCaptureSettleRace()
        let waiter = Task {
            for task in tasks { _ = await task.result }
            race.resolve(true)
        }
        let timeout = Task {
            do {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                try Task.checkCancellation()
                race.resolve(false)
            } catch {
            }
        }
        let cleanup = Task { [weak self] in
            await Task.yield()
            _ = await waiter.result
            timeout.cancel()
            if race.resolvedResult == false {
                await onLateSettled()
            }
            await self?.removeTrackedTask(identifier)
        }
        trackedTasks[identifier] = [waiter, timeout, cleanup]
        return await race.value()
    }

    func adoptMediaRelease(
        mediaHandle: MediaHandle,
        using core: any MediaCaptureServicing,
        onRecovered: @escaping @MainActor @Sendable () -> Void
    ) {
        let identifier = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            var delay = retryDelayNanoseconds
            while true {
                try? await Task.sleep(nanoseconds: delay)
                do {
                    _ = try await core.releaseMedia(mediaHandle: mediaHandle)
                    await onRecovered()
                    await removeTrackedTask(identifier)
                    return
                } catch let failure as MediaCaptureFailure
                    where !Self.isRetryableMediaReleaseFailure(failure) {
                    await onRecovered()
                    await removeTrackedTask(identifier)
                    return
                } catch is MediaCaptureFailure {
                    delay = min(delay * 2, 5_000_000_000)
                } catch {
                    await onRecovered()
                    await removeTrackedTask(identifier)
                    return
                }
            }
        }
        trackedTasks[identifier] = [task]
    }

    func adoptSessionCancellation(
        sessionHandle: SessionHandle,
        using core: any MediaCaptureServicing,
        onRecovered: @escaping @MainActor @Sendable () -> Void
    ) {
        let identifier = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            var delay = retryDelayNanoseconds
            while true {
                try? await Task.sleep(nanoseconds: delay)
                do {
                    _ = try await core.cancel(sessionHandle: sessionHandle)
                    await onRecovered()
                    await removeTrackedTask(identifier)
                    return
                } catch let failure as MediaCaptureFailure
                    where failure.id == .sessionInvalid || failure.id == .invalidState {
                    await onRecovered()
                    await removeTrackedTask(identifier)
                    return
                } catch {
                    delay = min(delay * 2, 5_000_000_000)
                }
            }
        }
        trackedTasks[identifier] = [task]
    }

    func adoptSurfaceDetachment(
        kind: MediaCaptureSurfaceKind,
        owner: MediaCaptureRenderSurfaceOwner,
        using core: any MediaCaptureServicing,
        onRecovered: @escaping @MainActor @Sendable () -> Void
    ) {
        let identifier = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            var delay = retryDelayNanoseconds
            while true {
                try? await Task.sleep(nanoseconds: delay)
                do {
                    switch kind {
                    case let .live(sessionHandle):
                        _ = try await core.detachLivePreview(
                            sessionHandle: sessionHandle,
                            surfaceOwner: owner
                        )
                    case let .preview(mediaHandle):
                        _ = try await core.detachUnconfirmedPreviewRender(
                            mediaHandle: mediaHandle,
                            surfaceOwner: owner
                        )
                    }
                    await onRecovered()
                    await removeTrackedTask(identifier)
                    return
                } catch let failure as MediaCaptureFailure
                    where Self.isSettledSurfaceFailure(failure, kind: kind) {
                    await onRecovered()
                    await removeTrackedTask(identifier)
                    return
                } catch {
                    delay = min(delay * 2, 5_000_000_000)
                }
            }
        }
        trackedTasks[identifier] = [task]
    }

    nonisolated static func isSettledSurfaceFailure(
        _ failure: MediaCaptureFailure,
        kind: MediaCaptureSurfaceKind
    ) -> Bool {
        if failure.id == .attachmentGenerationRetired || failure.id == .invalidState {
            return true
        }
        switch kind {
        case .live:
            return failure.id == .sessionInvalid
        case .preview:
            return failure.id == .mediaInvalid
        }
    }

    nonisolated static func isRetryableMediaReleaseFailure(
        _ failure: MediaCaptureFailure
    ) -> Bool {
        failure.id == .invalidState
    }

    private func removeTrackedTask(_ identifier: UUID) {
        trackedTasks.removeValue(forKey: identifier)
    }
}
