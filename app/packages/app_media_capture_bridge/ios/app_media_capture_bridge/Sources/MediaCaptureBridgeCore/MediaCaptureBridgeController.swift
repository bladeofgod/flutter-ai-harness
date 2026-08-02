import Foundation
import MediaCapture
import MediaCaptureUI

private final class MediaCaptureNativeCallGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?
    private var cancelled = false
    private var normalResolved = false
    private var cancellationFinished = false

    func wait() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(with: result)
            } else if cancellationFinished {
                lock.unlock()
                continuation.resume(throwing: CancellationError())
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    func resolve(_ result: Result<Value, Error>) -> Bool {
        lock.lock()
        guard !cancelled, !normalResolved else {
            lock.unlock()
            return false
        }
        normalResolved = true
        if let continuation {
            self.continuation = nil
            lock.unlock()
            continuation.resume(with: result)
        } else {
            self.result = result
            lock.unlock()
        }
        return true
    }

    func cancel(afterNanoseconds timeout: UInt64) {
        lock.lock()
        guard !normalResolved, !cancelled else {
            lock.unlock()
            return
        }
        cancelled = true
        lock.unlock()
        Task.detached { [weak self] in
            try? await Task.sleep(nanoseconds: timeout)
            self?.finishCancellation()
        }
    }

    func timeOut() {
        lock.lock()
        guard !normalResolved, !cancelled else {
            lock.unlock()
            return
        }
        cancelled = true
        cancellationFinished = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(throwing: CancellationError())
    }

    func finishCancellation() {
        lock.lock()
        guard cancelled, !cancellationFinished else {
            lock.unlock()
            return
        }
        cancellationFinished = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(throwing: CancellationError())
    }
}

private enum MediaCaptureNativeCall {
    static func run<Value: Sendable>(
        cancellationDrainNanoseconds: UInt64,
        operation: @escaping @Sendable () async throws -> Value,
        lateSuccess: @escaping @Sendable (Value) async -> Void = { _ in },
        onSettled: @escaping @Sendable () async -> Void = {}
    ) async throws -> Value {
        let gate = MediaCaptureNativeCallGate<Value>()
        Task.detached {
            do {
                let value = try await operation()
                if !gate.resolve(.success(value)) {
                    await lateSuccess(value)
                    await onSettled()
                    gate.finishCancellation()
                } else {
                    await onSettled()
                }
            } catch {
                if !gate.resolve(.failure(error)) {
                    await onSettled()
                    gate.finishCancellation()
                } else {
                    await onSettled()
                }
            }
        }
        return try await withTaskCancellationHandler {
            try await gate.wait()
        } onCancel: {
            gate.cancel(afterNanoseconds: cancellationDrainNanoseconds)
        }
    }

    static func runBounded<Value: Sendable>(
        timeoutNanoseconds: UInt64,
        operation: @escaping @Sendable () async throws -> Value,
        lateSuccess: @escaping @Sendable (Value) async -> Void = { _ in },
        onSettled: @escaping @Sendable () async -> Void = {}
    ) async throws -> Value {
        let gate = MediaCaptureNativeCallGate<Value>()
        Task.detached {
            do {
                let value = try await operation()
                if !gate.resolve(.success(value)) {
                    await lateSuccess(value)
                }
                await onSettled()
                gate.finishCancellation()
            } catch {
                _ = gate.resolve(.failure(error))
                await onSettled()
                gate.finishCancellation()
            }
        }
        Task.detached {
            if timeoutNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            }
            gate.timeOut()
        }
        return try await gate.wait()
    }
}

private final class MediaCaptureDrainWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Bool?
    private var continuation: CheckedContinuation<Bool, Never>?

    func wait() async -> Bool {
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

    func finish(_ result: Bool) {
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
}

private final class MediaCaptureTransferReleaseWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Bool?
    private var continuations: [CheckedContinuation<Bool, Never>] = []

    func wait() async -> Bool {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(returning: result)
            } else {
                continuations.append(continuation)
                lock.unlock()
            }
        }
    }

    func finish(_ result: Bool) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        let continuations = continuations
        self.continuations.removeAll(keepingCapacity: false)
        lock.unlock()
        continuations.forEach { $0.resume(returning: result) }
    }
}

private enum MediaCaptureTaskDrain {
    static func wait(
        for tasks: [Task<Void, Never>],
        timeoutNanoseconds: UInt64
    ) async -> Bool {
        guard !tasks.isEmpty else { return true }
        let waiter = MediaCaptureDrainWaiter()
        Task.detached {
            for task in tasks {
                await task.value
            }
            waiter.finish(true)
        }
        Task.detached {
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            waiter.finish(false)
        }
        return await waiter.wait()
    }
}

private final class MediaCaptureBoundaryCleanupCoordinator: @unchecked Sendable {
    private let core: any MediaCaptureCoreServicing
    private let sessionHandles: [SessionHandle]
    private let mediaHandles: [MediaHandle]
    private let prerequisiteTasks: [Task<Void, Never>]
    private let closeCore: Bool
    private let timeoutNanoseconds: UInt64
    private let onAllSettled: @Sendable () async -> Void
    private let lock = NSLock()
    private var unsettledCount: Int
    private var notified = false

    init(
        core: any MediaCaptureCoreServicing,
        sessionHandles: [SessionHandle],
        mediaHandles: [MediaHandle],
        prerequisiteTasks: [Task<Void, Never>] = [],
        closeCore: Bool,
        timeoutNanoseconds: UInt64,
        onAllSettled: @escaping @Sendable () async -> Void
    ) {
        self.core = core
        self.sessionHandles = sessionHandles
        self.mediaHandles = mediaHandles
        self.prerequisiteTasks = prerequisiteTasks
        self.closeCore = closeCore
        self.timeoutNanoseconds = timeoutNanoseconds
        self.onAllSettled = onAllSettled
        unsettledCount = sessionHandles.count + mediaHandles.count + (closeCore ? 1 : 0)
    }

    func start() -> Task<Void, Never> {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let cleanupTasks = sessionHandles.map { handle in
            Task.detached { [self, core = self.core] in
                _ = try? await MediaCaptureNativeCall.runBounded(
                    timeoutNanoseconds: timeoutNanoseconds,
                    operation: {
                        let result = try await core.cancel(sessionHandle: handle)
                        guard result == handle else { throw MediaCaptureFailure(.invalidState) }
                    },
                    onSettled: { [self] in await markSettled() }
                )
            }
        } + mediaHandles.map { handle in
            Task.detached { [self, core = self.core] in
                _ = try? await MediaCaptureNativeCall.runBounded(
                    timeoutNanoseconds: timeoutNanoseconds,
                    operation: {
                        let result = try await core.releaseMedia(mediaHandle: handle)
                        guard result == handle else { throw MediaCaptureFailure(.invalidState) }
                    },
                    onSettled: { [self] in await markSettled() }
                )
            }
        }

        if sessionHandles.isEmpty, mediaHandles.isEmpty, !closeCore {
            Task.detached { [self] in await markAllSettledIfEmpty() }
        }

        return Task.detached { [self, core = self.core] in
            for task in cleanupTasks {
                await task.value
            }
            guard closeCore else { return }
            var elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
            var remaining = elapsed < timeoutNanoseconds
                ? timeoutNanoseconds - elapsed
                : 0
            _ = await MediaCaptureTaskDrain.wait(
                for: prerequisiteTasks,
                timeoutNanoseconds: remaining
            )
            elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
            remaining = elapsed < timeoutNanoseconds
                ? timeoutNanoseconds - elapsed
                : 0
            _ = try? await MediaCaptureNativeCall.runBounded(
                timeoutNanoseconds: remaining,
                operation: {
                    await core.close()
                },
                onSettled: { [self] in await markSettled() }
            )
        }
    }

    private func markSettled() async {
        let shouldNotify = claimSettlement(decrement: true)
        if shouldNotify { await onAllSettled() }
    }

    private func markAllSettledIfEmpty() async {
        let shouldNotify = claimSettlement(decrement: false)
        if shouldNotify { await onAllSettled() }
    }

    private func claimSettlement(decrement: Bool) -> Bool {
        lock.lock()
        if decrement, unsettledCount > 0 { unsettledCount -= 1 }
        let shouldNotify = unsettledCount == 0 && !notified
        if shouldNotify { notified = true }
        lock.unlock()
        return shouldNotify
    }
}

@MainActor
package final class MediaCaptureBridgeController {
    package typealias PresentationOwnerProvider = @MainActor () -> MediaCapturePresentationOwner?
    package typealias OwnerLivenessProvider = @MainActor (ObjectIdentifier) -> Bool

    private final class PendingRequest {
        let requestId: String
        let operation: String
        let ownerIdentity: ObjectIdentifier?
        private var completion: (any MediaCaptureBridgeCompletion)?
        var task: Task<Void, Never>?

        init(
            requestId: String,
            operation: String,
            ownerIdentity: ObjectIdentifier?,
            completion: any MediaCaptureBridgeCompletion
        ) {
            self.requestId = requestId
            self.operation = operation
            self.ownerIdentity = ownerIdentity
            self.completion = completion
        }

        func takeCompletion() -> (any MediaCaptureBridgeCompletion)? {
            defer { completion = nil }
            return completion
        }
    }

    @MainActor
    private final class ActivePresentation {
        let ownerIdentity: ObjectIdentifier
        let requestId: String
        var session: (any MediaCapturePresentationSession)?
        var dismissRequested = false
        private var settled = false
        private var settlementWaiters: [CheckedContinuation<Void, Never>] = []

        init(ownerIdentity: ObjectIdentifier, requestId: String) {
            self.ownerIdentity = ownerIdentity
            self.requestId = requestId
        }

        func waitUntilSettled() async {
            if settled { return }
            await withCheckedContinuation { settlementWaiters.append($0) }
        }

        func settle() {
            guard !settled else { return }
            settled = true
            let waiters = settlementWaiters
            settlementWaiters.removeAll(keepingCapacity: false)
            waiters.forEach { $0.resume() }
        }
    }

    private final class TransferRecord: @unchecked Sendable {
        let reservation: MediaCaptureTransferStore.Reservation
        var active = false
        var cleanupPending = false
        var expired = false
        var releaseTombstoneReserved = false
        var expiresAtEpochMilliseconds: Int64?
        var ttlTask: Task<Void, Never>?
        var cleanupTask: Task<Void, Never>?

        init(reservation: MediaCaptureTransferStore.Reservation) {
            self.reservation = reservation
        }
    }

    private enum TransferReleaseDecision {
        case alreadyReleased
        case claim(TransferRecord, MediaCaptureTransferReleaseWaiter)
        case join(MediaCaptureTransferReleaseWaiter)
        case rejected(MediaCaptureWireFailure)
    }

    private struct Listener {
        let generation: UInt64
        let sink: any MediaCaptureBridgeEventSink
    }

    private enum SessionStartupOutcome: Sendable {
        case ready(SessionReadySnapshot)
        case failed(sessionHandle: SessionHandle, failure: MediaCaptureFailure)

        var sessionHandle: SessionHandle {
            switch self {
            case let .ready(snapshot):
                return snapshot.sessionHandle
            case let .failed(sessionHandle, _):
                return sessionHandle
            }
        }

        var event: MediaCaptureEvent {
            switch self {
            case let .ready(snapshot):
                return .sessionReady(snapshot)
            case let .failed(sessionHandle, failure):
                return .sessionFailed(sessionHandle: sessionHandle, failure: failure)
            }
        }
    }

    private let core: any MediaCaptureCoreServicing
    private let thumbnailEncoder: any MediaCaptureThumbnailEncoding
    private let transferStore: MediaCaptureTransferStore?
    private let presentationOwner: PresentationOwnerProvider
    private let ownerIsAlive: OwnerLivenessProvider
    private let monotonicMilliseconds: @Sendable () -> UInt64
    private let epochMilliseconds: @Sendable () -> Int64
    private let drainTimeoutNanoseconds: UInt64
    private let ownerPollNanoseconds: UInt64
    private let transferTTLNanoseconds: UInt64
    private let maximumActiveTransferBytes: Int

    private var engineOpen = true
    private var pending: [String: PendingRequest] = [:]
    private var completed: [String: UInt64] = [:]
    private var sessions: Set<String> = []
    private var sessionOwners: [String: ObjectIdentifier] = [:]
    private var previews: [String: String] = [:]
    private var leases: Set<String> = []
    private var settlingLeases: Set<String> = []
    private var leaseMetadata: [String: MediaMetadata] = [:]
    private var transfers: [String: TransferRecord] = [:]
    private var releaseTombstones: [String: UInt64] = [:]
    private var releaseClaims: [String: MediaCaptureTransferReleaseWaiter] = [:]
    private var transferGenerationOpen: Bool
    private var activeTransferBytes = 0
    private var pendingTransferReservations: [UUID: Int] = [:]
    private var activePresentation: ActivePresentation?
    private var presentationCleanupInProgress = false
    private var listener: Listener?
    private var listenerGeneration: UInt64 = 0
    private var eventTask: Task<Void, Never>?
    private var ownerMonitorTask: Task<Void, Never>?
    private var eventCollectionReady = false
    private var eventCollectionClosed = false
    private var eventCollectionWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var boundaryTasks: [UUID: Task<Void, Never>] = [:]
    private var nativeCallRequests: [UUID: String] = [:]
    private var ownerCleanupWaitingRequestIds: Set<String> = []
    private var ownerRequestDrainWaitingIds: Set<String> = []
    private var ownerBoundaryCleanupTokens: Set<UUID> = []
    private var ownerBoundaryPublicTokens: Set<UUID> = []
    private var startupWaiters: [
        String: CheckedContinuation<SessionStartupOutcome, Error>
    ] = [:]
    private var earlyStartupOutcomes: [String: SessionStartupOutcome] = [:]

    package init(
        core: any MediaCaptureCoreServicing,
        thumbnailEncoder: any MediaCaptureThumbnailEncoding = LiveMediaCaptureThumbnailEncoder(),
        transferStore: MediaCaptureTransferStore? = nil,
        presentationOwner: @escaping PresentationOwnerProvider,
        ownerIsAlive: @escaping OwnerLivenessProvider,
        drainTimeoutNanoseconds: UInt64 = 5_000_000_000,
        ownerPollNanoseconds: UInt64 = 250_000_000,
        transferTTLNanoseconds: UInt64 = 300_000_000_000,
        maximumActiveTransferBytes: Int = 104_857_600,
        monotonicMilliseconds: @escaping @Sendable () -> UInt64 = {
            DispatchTime.now().uptimeNanoseconds / 1_000_000
        },
        epochMilliseconds: @escaping @Sendable () -> Int64 = {
            let value = Date().timeIntervalSince1970 * 1_000
            guard value.isFinite, value >= 0, value <= Double(Int64.max) else { return -1 }
            return Int64(value.rounded(.towardZero))
        }
    ) {
        self.core = core
        self.thumbnailEncoder = thumbnailEncoder
        self.transferStore = transferStore
        self.presentationOwner = presentationOwner
        self.ownerIsAlive = ownerIsAlive
        self.drainTimeoutNanoseconds = drainTimeoutNanoseconds
        self.ownerPollNanoseconds = ownerPollNanoseconds
        self.transferTTLNanoseconds = transferTTLNanoseconds
        self.maximumActiveTransferBytes = maximumActiveTransferBytes
        self.monotonicMilliseconds = monotonicMilliseconds
        self.epochMilliseconds = epochMilliseconds
        transferGenerationOpen = transferStore != nil
        startEventCollection()
    }

    deinit {
        eventTask?.cancel()
        ownerMonitorTask?.cancel()
        boundaryTasks.values.forEach { $0.cancel() }
    }

    package func handle(
        operation: String,
        arguments: Any?,
        completion: any MediaCaptureBridgeCompletion
    ) {
        let request: MediaCaptureWireRequest
        do {
            request = try MediaCaptureWireCodec.decodeRequest(
                operation: operation,
                arguments: arguments
            )
        } catch let failure as MediaCaptureWireFailure {
            completion.failure(failure)
            return
        } catch {
            completion.failure(
                MediaCaptureWireCodec.invalidPayload(
                    operation: operation,
                    field: "payload",
                    reason: "type_mismatch"
                )
            )
            return
        }

        let pendingRequest: PendingRequest
        do {
            pendingRequest = try reserve(request: request, completion: completion)
        } catch let failure as MediaCaptureWireFailure {
            completion.failure(failure)
            return
        } catch {
            completion.failure(MediaCaptureWireCodec.wireEncodingFailure(operation: operation))
            return
        }

        let task = Task { [weak self, weak pendingRequest] in
            guard let self, let pendingRequest else { return }
            await self.execute(pendingRequest: pendingRequest, request: request)
        }
        pendingRequest.task = task
    }

    package func onListen(
        arguments: Any?,
        sink: any MediaCaptureBridgeEventSink
    ) {
        do {
            try MediaCaptureWireCodec.decodeListenArguments(arguments)
        } catch let failure as MediaCaptureWireFailure {
            sink.failure(failure)
            return
        } catch {
            sink.failure(
                MediaCaptureWireCodec.invalidPayload(
                    operation: "unknown_operation",
                    field: "payload",
                    reason: "type_mismatch"
                )
            )
            return
        }
        guard engineOpen else {
            sink.failure(
                MediaCaptureWireCodec.bridgeUnavailable(
                    operation: "unknown_operation",
                    reason: "engine_detached"
                )
            )
            return
        }
        guard listener == nil else {
            sink.failure(MediaCaptureWireCodec.listenerAlreadyActive())
            return
        }
        listenerGeneration &+= 1
        listener = Listener(generation: listenerGeneration, sink: sink)
    }

    package func onCancel() {
        listener = nil
    }

    package func ownerDestroyed(_ identity: ObjectIdentifier) {
        guard engineOpen else { return }
        let affectedSessions = sessionOwners.compactMap { entry in
            entry.value == identity ? entry.key : nil
        }
        let affectedRequests = pending.values.filter { $0.ownerIdentity == identity }
        let presentation = activePresentation?.ownerIdentity == identity ? activePresentation : nil
        if presentation != nil {
            activePresentation = nil
        }
        affectedRequests.forEach { request in
            pending.removeValue(forKey: request.requestId)
            addTombstone(request.requestId)
            request.task?.cancel()
        }
        affectedSessions.forEach(removeSessionOwnership)
        updateOwnerMonitor()

        guard !affectedRequests.isEmpty || !affectedSessions.isEmpty || presentation != nil else {
            return
        }
        presentationCleanupInProgress = true
        presentation?.session?.dismiss()
        let requestTasks = affectedRequests.compactMap(\.task)
        affectedRequests.forEach { $0.task = nil }
        let cleanupToken = UUID()
        ownerBoundaryCleanupTokens.insert(cleanupToken)
        ownerBoundaryPublicTokens.insert(cleanupToken)
        let cleanup = MediaCaptureBoundaryCleanupCoordinator(
            core: core,
            sessionHandles: affectedSessions.compactMap {
                try? SessionHandle(rawValue: $0)
            },
            mediaHandles: [],
            closeCore: false,
            timeoutNanoseconds: drainTimeoutNanoseconds,
            onAllSettled: { @MainActor [weak self] in
                self?.ownerBoundaryCleanupTokens.remove(cleanupToken)
                self?.updatePresentationCleanupState()
            }
        )
        let cleanupTask = cleanup.start()
        let timeout = drainTimeoutNanoseconds
        let requestDrainTask = Task.detached {
            await MediaCaptureTaskDrain.wait(
                for: requestTasks,
                timeoutNanoseconds: timeout
            )
        }
        let identifier = UUID()
        let task = Task { [weak self] in
            await cleanupTask.value
            let drained = await requestDrainTask.value
            presentation?.settle()
            for request in affectedRequests {
                request.takeCompletion()?.failure(
                    MediaCaptureWireCodec.bridgeUnavailable(
                        operation: request.operation,
                        reason: "view_controller_destroyed"
                    )
                )
            }
            let requestIds = Set(affectedRequests.map(\.requestId))
            self?.finishOwnerCleanup(requestIds: requestIds)
            if !drained {
                self?.ownerRequestDrainWaitingIds.formUnion(requestIds)
                self?.retainOwnerCleanupUntilDrained(
                    requestTasks,
                    requestIds: requestIds
                )
            }
            self?.ownerBoundaryPublicTokens.remove(cleanupToken)
            self?.updatePresentationCleanupState()
            self?.boundaryTasks.removeValue(forKey: identifier)
        }
        boundaryTasks[identifier] = task
    }

    package func detachEngine() {
        guard engineOpen else { return }
        engineOpen = false
        transferGenerationOpen = false
        transferStore?.closeGeneration()
        closeEventCollectionBarrier()
        eventTask?.cancel()
        eventTask = nil
        ownerMonitorTask?.cancel()
        ownerMonitorTask = nil

        let claimedRequests = Array(pending.values)
        pending.removeAll(keepingCapacity: false)
        claimedRequests.forEach { request in
            addTombstone(request.requestId)
            request.task?.cancel()
        }
        let claimedRequestTasks = claimedRequests.compactMap(\.task)
        claimedRequests.forEach { $0.task = nil }
        let claimedPresentation = activePresentation
        activePresentation = nil
        presentationCleanupInProgress = claimedPresentation != nil
        let claimedSessions = Array(sessions)
        let claimedLeases = Array(leases.union(settlingLeases))
        sessions.removeAll(keepingCapacity: false)
        sessionOwners.removeAll(keepingCapacity: false)
        previews.removeAll(keepingCapacity: false)
        leases.removeAll(keepingCapacity: false)
        settlingLeases.removeAll(keepingCapacity: false)
        leaseMetadata.removeAll(keepingCapacity: false)
        let claimedTransfers = Array(transfers.values)
        transfers.removeAll(keepingCapacity: false)
        activeTransferBytes = 0
        claimedTransfers.forEach { record in
            record.cleanupPending = true
            record.ttlTask?.cancel()
            record.cleanupTask?.cancel()
            record.ttlTask = nil
            record.cleanupTask = nil
        }
        releaseClaims.values.forEach { $0.finish(false) }
        releaseClaims.removeAll(keepingCapacity: false)
        releaseTombstones.removeAll(keepingCapacity: false)
        let claimedListener = listener
        listener = nil
        claimedPresentation?.session?.dismiss()
        let cleanup = MediaCaptureBoundaryCleanupCoordinator(
            core: core,
            sessionHandles: claimedSessions.compactMap {
                try? SessionHandle(rawValue: $0)
            },
            mediaHandles: claimedLeases.compactMap {
                try? MediaHandle(rawValue: $0)
            },
            prerequisiteTasks: claimedRequestTasks,
            closeCore: true,
            timeoutNanoseconds: drainTimeoutNanoseconds,
            onAllSettled: {}
        )
        let cleanupTask = cleanup.start()
        let timeout = drainTimeoutNanoseconds
        let requestDrainTask = Task.detached {
            await MediaCaptureTaskDrain.wait(
                for: claimedRequestTasks,
                timeoutNanoseconds: timeout
            )
        }
        let store = transferStore
        let transferCleanupTask = Task.detached(priority: .utility) {
            guard let store else { return }
            for record in claimedTransfers {
                for attempt in 0 ..< 3 {
                    if store.delete(record.reservation) { break }
                    if attempt < 2 {
                        try? await Task.sleep(nanoseconds: 50_000_000)
                    }
                }
            }
        }

        let identifier = UUID()
        let task = Task { [weak self] in
            await cleanupTask.value
            _ = await requestDrainTask.value
            await transferCleanupTask.value
            claimedPresentation?.settle()
            for request in claimedRequests {
                request.takeCompletion()?.failure(
                    MediaCaptureWireCodec.bridgeUnavailable(
                        operation: request.operation,
                        reason: "engine_detached"
                    )
                )
            }
            claimedListener?.sink.endOfStream()
            self?.presentationCleanupInProgress = false
            self?.boundaryTasks.removeValue(forKey: identifier)
        }
        boundaryTasks[identifier] = task
    }

    private func startEventCollection() {
        eventTask = Task { [weak self, core] in
            let events = await core.events()
            self?.markEventCollectionReady()
            for await event in events {
                guard !Task.isCancelled else { return }
                self?.handleNativeEvent(event)
            }
        }
    }

    private func updateOwnerMonitor() {
        let hasTrackedOwner = activePresentation != nil ||
            !sessionOwners.isEmpty ||
            pending.values.contains { $0.ownerIdentity != nil }
        guard engineOpen, hasTrackedOwner else {
            ownerMonitorTask?.cancel()
            ownerMonitorTask = nil
            return
        }
        guard ownerMonitorTask == nil else { return }
        let interval = ownerPollNanoseconds
        ownerMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: interval)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self?.pollTrackedOwners()
            }
        }
    }

    private func pollTrackedOwners() {
        var identities = Set(sessionOwners.values)
        identities.formUnion(pending.values.compactMap(\.ownerIdentity))
        if let activePresentation {
            identities.insert(activePresentation.ownerIdentity)
        }
        for identity in identities where !ownerIsAlive(identity) {
            ownerDestroyed(identity)
        }
        updateOwnerMonitor()
    }

    private func waitForEventCollection() async {
        guard !eventCollectionReady, !eventCollectionClosed else { return }
        let identifier = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if eventCollectionReady || eventCollectionClosed || Task.isCancelled {
                    continuation.resume()
                } else {
                    eventCollectionWaiters[identifier] = continuation
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.eventCollectionWaiters.removeValue(forKey: identifier)?.resume()
            }
        }
    }

    private func markEventCollectionReady() {
        guard !eventCollectionClosed else { return }
        eventCollectionReady = true
        let waiters = Array(eventCollectionWaiters.values)
        eventCollectionWaiters.removeAll(keepingCapacity: false)
        waiters.forEach { $0.resume() }
    }

    private func closeEventCollectionBarrier() {
        eventCollectionClosed = true
        let waiters = Array(eventCollectionWaiters.values)
        eventCollectionWaiters.removeAll(keepingCapacity: false)
        waiters.forEach { $0.resume() }
    }

    private func reserve(
        request: MediaCaptureWireRequest,
        completion: any MediaCaptureBridgeCompletion
    ) throws -> PendingRequest {
        pruneTombstones()
        guard engineOpen else {
            throw MediaCaptureWireCodec.bridgeUnavailable(
                operation: request.operation,
                reason: "engine_detached"
            )
        }
        guard pending[request.requestId] == nil, completed[request.requestId] == nil else {
            throw MediaCaptureWireCodec.duplicateRequest(operation: request.operation)
        }
        guard pending.count < 32 else {
            throw MediaCaptureWireCodec.bridgeOverloaded(
                operation: request.operation,
                capacity: "pending_requests"
            )
        }
        guard pending.count + completed.count < 4_096 else {
            throw MediaCaptureWireCodec.bridgeOverloaded(
                operation: request.operation,
                capacity: "completed_request_tombstones"
            )
        }
        let ownerIdentity = try ownerIdentity(for: request)
        if request.operation == "present_capture_flow" {
            guard !presentationCleanupInProgress, activePresentation == nil,
                  let ownerIdentity
            else {
                throw MediaCaptureWireCodec.presentationConflict()
            }
            activePresentation = ActivePresentation(
                ownerIdentity: ownerIdentity,
                requestId: request.requestId
            )
        } else if case let .dismissPresentation(presentationRequestId) = request.payload,
                  activePresentation?.requestId == presentationRequestId {
            activePresentation?.dismissRequested = true
        }
        let value = PendingRequest(
            requestId: request.requestId,
            operation: request.operation,
            ownerIdentity: ownerIdentity,
            completion: completion
        )
        pending[request.requestId] = value
        updateOwnerMonitor()
        return value
    }

    private func ownerIdentity(for request: MediaCaptureWireRequest) throws -> ObjectIdentifier? {
        switch request.payload {
        case .startSession:
            guard let identity = presentationOwner()?.identity else {
                throw MediaCaptureWireCodec.bridgeUnavailable(
                    operation: request.operation,
                    reason: "view_controller_destroyed"
                )
            }
            return identity
        case let .sessionAction(handle),
             let .flash(handle, _),
             let .focus(handle, _, _),
             let .zoom(handle, _):
            return sessionOwners[handle.rawValue]
        case let .mediaAction(handle):
            if request.operation == "release_media",
               leases.contains(handle.rawValue) || settlingLeases.contains(handle.rawValue) {
                return nil
            }
            guard let session = previews[handle.rawValue] else { return nil }
            return sessionOwners[session]
        case let .thumbnail(handle, _):
            guard let session = previews[handle.rawValue] else { return nil }
            return sessionOwners[session]
        case .materialize, .releaseMaterialized:
            return nil
        case let .dismissPresentation(presentationRequestId):
            return activePresentation?.requestId == presentationRequestId
                ? activePresentation?.ownerIdentity
                : nil
        }
    }

    private func runNativeCall<Value: Sendable>(
        request: PendingRequest,
        operation: @escaping @Sendable () async throws -> Value,
        lateSuccess: @escaping @Sendable (Value) async -> Void = { _ in }
    ) async throws -> Value {
        let identifier = UUID()
        nativeCallRequests[identifier] = request.requestId
        return try await MediaCaptureNativeCall.run(
            cancellationDrainNanoseconds: drainTimeoutNanoseconds,
            operation: operation,
            lateSuccess: lateSuccess,
            onSettled: { @MainActor [weak self] in
                self?.nativeCallSettled(identifier)
            }
        )
    }

    private func nativeCallSettled(_ identifier: UUID) {
        guard let requestId = nativeCallRequests.removeValue(forKey: identifier) else { return }
        guard !nativeCallRequests.values.contains(requestId) else { return }
        ownerCleanupWaitingRequestIds.remove(requestId)
        updatePresentationCleanupState()
    }

    private func execute(
        pendingRequest: PendingRequest,
        request: MediaCaptureWireRequest
    ) async {
        await waitForEventCollection()
        guard engineOpen, pending[request.requestId] === pendingRequest else { return }
        do {
            switch request.payload {
            case let .startSession(options):
                if request.operation == "present_capture_flow" {
                    try await executePresentation(request: pendingRequest, options: options)
                } else {
                    try await executeStartSession(request: pendingRequest, options: options)
                }
            case let .sessionAction(handle):
                try await executeSessionAction(request: pendingRequest, handle: handle)
            case let .flash(handle, mode):
                try requireSession(handle)
                let applied = try await runNativeCall(request: pendingRequest) { [core = self.core] in
                    try await core.setFlashMode(sessionHandle: handle, mode: mode)
                }
                guard applied == handle else { throw MediaCaptureWireCodec.wireEncodingFailure(operation: request.operation) }
                try await completeSuccess(
                    pendingRequest,
                    value: MediaCaptureWireCodec.controlApplied(
                        requestId: request.requestId,
                        handle: handle
                    ),
                    lateCleanup: { [weak self] in await self?.cancelSessionIfPossible(handle.rawValue) }
                )
            case let .focus(handle, x, y):
                try requireSession(handle)
                let applied = try await runNativeCall(request: pendingRequest) { [core = self.core] in
                    try await core.setFocusPoint(
                        sessionHandle: handle,
                        normalizedX: x,
                        normalizedY: y
                    )
                }
                guard applied == handle else { throw MediaCaptureWireCodec.wireEncodingFailure(operation: request.operation) }
                try await completeSuccess(
                    pendingRequest,
                    value: MediaCaptureWireCodec.controlApplied(
                        requestId: request.requestId,
                        handle: handle
                    ),
                    lateCleanup: { [weak self] in await self?.cancelSessionIfPossible(handle.rawValue) }
                )
            case let .zoom(handle, factor):
                try requireSession(handle)
                let applied = try await runNativeCall(request: pendingRequest) { [core = self.core] in
                    try await core.setZoomFactor(sessionHandle: handle, factor: factor)
                }
                guard applied == handle else { throw MediaCaptureWireCodec.wireEncodingFailure(operation: request.operation) }
                try await completeSuccess(
                    pendingRequest,
                    value: MediaCaptureWireCodec.controlApplied(
                        requestId: request.requestId,
                        handle: handle
                    ),
                    lateCleanup: { [weak self] in await self?.cancelSessionIfPossible(handle.rawValue) }
                )
            case let .mediaAction(handle):
                try await executeMediaAction(request: pendingRequest, handle: handle)
            case let .thumbnail(handle, maxPixelEdge):
                try requireMedia(handle)
                let thumbnail = try await runNativeCall(
                    request: pendingRequest,
                    operation: { [core = self.core] in
                        try await core.readMediaThumbnail(
                            mediaHandle: handle,
                            maxPixelEdge: maxPixelEdge
                        )
                    },
                    lateSuccess: { $0.clear() }
                )
                guard thumbnail.mediaHandle == handle else {
                    thumbnail.clear()
                    throw MediaCaptureWireCodec.wireEncodingFailure(operation: request.operation)
                }
                let encoded: [String: Any]
                do {
                    let validated = try await thumbnailEncoder.encode(
                        value: thumbnail,
                        maxPixelEdge: maxPixelEdge
                    )
                    encoded = try MediaCaptureWireCodec.thumbnail(
                        requestId: request.requestId,
                        encoded: validated
                    )
                } catch {
                    thumbnail.clear()
                    throw error
                }
                thumbnail.clear()
                let wireBytes = (encoded["payload"] as? [String: Any])?["thumbnailCopy"]
                    as? MediaCaptureWireBytes
                try await completeSuccess(
                    pendingRequest,
                    value: encoded,
                    lateCleanup: { wireBytes?.clear() }
                )
            case let .materialize(handle):
                try await executeMaterialize(request: pendingRequest, handle: handle)
            case let .releaseMaterialized(exportHandle):
                try await executeReleaseMaterialized(
                    request: pendingRequest,
                    exportHandle: exportHandle
                )
            case let .dismissPresentation(presentationRequestId):
                try await executeDismissPresentation(
                    request: pendingRequest,
                    presentationRequestId: presentationRequestId
                )
            }
        } catch let failure as MediaCaptureWireFailure {
            completeFailure(pendingRequest, failure: failure)
        } catch let failure as MediaCaptureFailure {
            completeFailure(
                pendingRequest,
                failure: MediaCaptureWireCodec.capabilityFailure(
                    operation: pendingRequest.operation,
                    failure: failure
                )
            )
        } catch is CancellationError {
            let failure = engineOpen
                ? MediaCaptureWireCodec.capabilityFailure(
                    operation: pendingRequest.operation,
                    failure: MediaCaptureFailure(.systemInterrupted)
                )
                : MediaCaptureWireCodec.bridgeUnavailable(
                    operation: pendingRequest.operation,
                    reason: "engine_detached"
                )
            completeFailure(pendingRequest, failure: failure)
        } catch let error as MediaCaptureUiPresentationError {
            let failure: MediaCaptureWireFailure = switch error {
            case .ownerUnavailable:
                MediaCaptureWireCodec.bridgeUnavailable(
                    operation: pendingRequest.operation,
                    reason: "view_controller_destroyed"
                )
            case .presentationConflict, .presentationFailed:
                MediaCaptureWireCodec.presentationConflict()
            }
            completeFailure(pendingRequest, failure: failure)
        } catch {
            completeFailure(
                pendingRequest,
                failure: MediaCaptureWireCodec.wireEncodingFailure(
                    operation: pendingRequest.operation
                )
            )
        }
    }

    private func executeStartSession(
        request: PendingRequest,
        options: SessionOptions
    ) async throws {
        let handle = try await runNativeCall(
            request: request,
            operation: { [core = self.core] in
                try await core.startSession(options: options)
            },
            lateSuccess: { [core = self.core] handle in
                _ = try? await core.cancel(sessionHandle: handle)
            }
        )
        let startup: SessionStartupOutcome
        do {
            startup = try await awaitSessionStartup(handle)
        } catch {
            await cancelSessionIfPossible(handle.rawValue)
            throw error
        }
        if case let .failed(_, failure) = startup,
           failure.id == .unsupportedCapability {
            await cancelSessionIfPossible(handle.rawValue)
            throw failure
        }
        let encoded: [String: Any]
        do {
            encoded = try MediaCaptureWireCodec.sessionCreated(
                requestId: request.requestId,
                handle: handle
            )
        } catch {
            await cancelSessionIfPossible(handle.rawValue)
            throw error
        }
        try await completeSuccess(
            request,
            value: encoded,
            adopt: {
                guard self.sessions.insert(handle.rawValue).inserted else {
                    throw MediaCaptureWireCodec.wireEncodingFailure(operation: request.operation)
                }
                if let owner = request.ownerIdentity {
                    self.sessionOwners[handle.rawValue] = owner
                }
            },
            lateCleanup: { [weak self] in await self?.cancelSessionIfPossible(handle.rawValue) }
        )
        handleNativeEvent(startup.event)
    }

    private func executeSessionAction(
        request: PendingRequest,
        handle: SessionHandle
    ) async throws {
        try requireSession(handle)
        switch request.operation {
        case "take_photo":
            let metadata = try await runNativeCall(
                request: request,
                operation: { [core = self.core] in
                    try await core.takePhoto(sessionHandle: handle)
                },
                lateSuccess: { [core = self.core] _ in
                    _ = try? await core.cancel(sessionHandle: handle)
                }
            )
            try await completePreview(request: request, session: handle, metadata: metadata)
        case "start_recording":
            let started = try await runNativeCall(
                request: request,
                operation: { [core = self.core] in
                    try await core.startRecording(sessionHandle: handle)
                },
                lateSuccess: { [core = self.core] _ in
                    _ = try? await core.cancel(sessionHandle: handle)
                }
            )
            guard started.sessionHandle == handle else {
                await cancelSessionIfPossible(handle.rawValue)
                await cancelSessionIfPossible(started.sessionHandle.rawValue)
                throw MediaCaptureWireCodec.wireEncodingFailure(operation: request.operation)
            }
            try await completeSuccess(
                request,
                value: MediaCaptureWireCodec.recordingStarted(
                    requestId: request.requestId,
                    value: started
                ),
                lateCleanup: { [weak self] in await self?.cancelSessionIfPossible(handle.rawValue) }
            )
        case "stop_recording":
            let metadata = try await runNativeCall(
                request: request,
                operation: { [core = self.core] in
                    try await core.stopRecording(sessionHandle: handle)
                },
                lateSuccess: { [core = self.core] _ in
                    _ = try? await core.cancel(sessionHandle: handle)
                }
            )
            try await completePreview(request: request, session: handle, metadata: metadata)
        case "switch_camera":
            let applied = try await runNativeCall(
                request: request,
                operation: { [core = self.core] in
                    try await core.switchCamera(sessionHandle: handle)
                },
                lateSuccess: { [core = self.core] applied in
                    _ = try? await core.cancel(sessionHandle: handle)
                    if applied != handle {
                        _ = try? await core.cancel(sessionHandle: applied)
                    }
                }
            )
            guard applied == handle else {
                await cancelSessionIfPossible(handle.rawValue)
                await cancelSessionIfPossible(applied.rawValue)
                throw MediaCaptureWireCodec.wireEncodingFailure(operation: request.operation)
            }
            try await completeSuccess(
                request,
                value: MediaCaptureWireCodec.controlApplied(
                    requestId: request.requestId,
                    handle: handle
                ),
                lateCleanup: { [weak self] in await self?.cancelSessionIfPossible(handle.rawValue) }
            )
        case "cancel":
            let cancelled = try await runNativeCall(request: request) { [core = self.core] in
                try await core.cancel(sessionHandle: handle)
            }
            guard cancelled == handle else {
                throw MediaCaptureWireCodec.wireEncodingFailure(operation: request.operation)
            }
            try await completeSuccess(
                request,
                value: MediaCaptureWireCodec.sessionCancelled(
                    requestId: request.requestId,
                    handle: handle
                ),
                adopt: { self.removeSessionOwnership(handle.rawValue) }
            )
        default:
            throw MediaCaptureWireCodec.invalidPayload(
                operation: request.operation,
                field: "payload",
                reason: "invalid_enum"
            )
        }
    }

    private func executeMediaAction(
        request: PendingRequest,
        handle: MediaHandle
    ) async throws {
        switch request.operation {
        case "retake":
            guard previews[handle.rawValue] != nil else { throw MediaCaptureFailure(.mediaInvalid) }
            let session = try await runNativeCall(
                request: request,
                operation: { [core = self.core] in
                    try await core.retake(mediaHandle: handle)
                },
                lateSuccess: { [core = self.core] session in
                    _ = try? await core.cancel(sessionHandle: session)
                }
            )
            guard previews[handle.rawValue] == session.rawValue else {
                await cancelSessionIfPossible(session.rawValue)
                throw MediaCaptureWireCodec.wireEncodingFailure(operation: request.operation)
            }
            try await completeSuccess(
                request,
                value: MediaCaptureWireCodec.retakeReady(
                    requestId: request.requestId,
                    handle: session
                ),
                adopt: { self.previews.removeValue(forKey: handle.rawValue) },
                lateCleanup: { [weak self] in await self?.cancelSessionIfPossible(session.rawValue) }
            )
        case "confirm":
            guard let session = previews[handle.rawValue] else { throw MediaCaptureFailure(.mediaInvalid) }
            let confirmed = try await runNativeCall(
                request: request,
                operation: { [core = self.core] in
                    try await core.confirm(mediaHandle: handle)
                },
                lateSuccess: { [core = self.core] confirmed in
                    _ = try? await core.releaseMedia(
                        mediaHandle: confirmed.metadata.mediaHandle
                    )
                }
            )
            guard confirmed.metadata.mediaHandle == handle,
                  !leases.contains(handle.rawValue),
                  !settlingLeases.contains(handle.rawValue)
            else {
                await releaseMediaIfPossible(confirmed.metadata.mediaHandle.rawValue)
                throw MediaCaptureWireCodec.wireEncodingFailure(operation: request.operation)
            }
            let encoded: [String: Any]
            do {
                encoded = try MediaCaptureWireCodec.confirmedMedia(
                    requestId: request.requestId,
                    value: confirmed
                )
            } catch {
                await releaseMediaIfPossible(handle.rawValue)
                throw error
            }
            try await completeSuccess(
                request,
                value: encoded,
                adopt: {
                    self.previews.removeValue(forKey: handle.rawValue)
                    self.removeSessionOwnership(session)
                    guard self.leases.insert(handle.rawValue).inserted else {
                        throw MediaCaptureWireCodec.wireEncodingFailure(operation: request.operation)
                    }
                    self.leaseMetadata[handle.rawValue] = confirmed.metadata
                },
                lateCleanup: { [weak self] in await self?.releaseMediaIfPossible(handle.rawValue) }
            )
        case "release_media":
            try requireMedia(handle, allowSettlingLease: true)
            let wasDeliveredLease = leases.contains(handle.rawValue) ||
                settlingLeases.contains(handle.rawValue)
            let released = try await runNativeCall(request: request) { [core = self.core] in
                try await core.releaseMedia(mediaHandle: handle)
            }
            guard released == handle else {
                throw MediaCaptureWireCodec.wireEncodingFailure(operation: request.operation)
            }
            try await completeSuccess(
                request,
                value: MediaCaptureWireCodec.mediaReleased(
                    requestId: request.requestId,
                    handle: handle
                ),
                adopt: {
                    if wasDeliveredLease {
                        let stillTracked = self.leases.remove(handle.rawValue) != nil ||
                            self.settlingLeases.contains(handle.rawValue)
                        if stillTracked {
                            self.settlingLeases.insert(handle.rawValue)
                        }
                    }
                    self.previews.removeValue(forKey: handle.rawValue)
                    self.leaseMetadata.removeValue(forKey: handle.rawValue)
                }
            )
        default:
            throw MediaCaptureWireCodec.invalidPayload(
                operation: request.operation,
                field: "payload",
                reason: "invalid_enum"
            )
        }
    }

    private func completePreview(
        request: PendingRequest,
        session: SessionHandle,
        metadata: MediaMetadata
    ) async throws {
        guard sessions.contains(session.rawValue),
              previews[metadata.mediaHandle.rawValue] == nil,
              !leases.contains(metadata.mediaHandle.rawValue),
              !settlingLeases.contains(metadata.mediaHandle.rawValue)
        else {
            await cancelSessionIfPossible(session.rawValue)
            throw MediaCaptureWireCodec.wireEncodingFailure(operation: request.operation)
        }
        let encoded: [String: Any]
        do {
            encoded = try MediaCaptureWireCodec.mediaPreview(
                requestId: request.requestId,
                metadata: metadata
            )
        } catch {
            await cancelSessionIfPossible(session.rawValue)
            throw error
        }
        try await completeSuccess(
            request,
            value: encoded,
            adopt: { self.previews[metadata.mediaHandle.rawValue] = session.rawValue },
            lateCleanup: { [weak self] in await self?.cancelSessionIfPossible(session.rawValue) }
        )
    }

    private func executeMaterialize(
        request: PendingRequest,
        handle: MediaHandle
    ) async throws {
        guard leases.contains(handle.rawValue),
              let metadata = leaseMetadata[handle.rawValue]
        else {
            throw MediaCaptureFailure(.mediaInvalid)
        }
        retryRetainedTransferCleanup()
        let record = try await reserveTransfer(operation: request.operation, metadata: metadata)
        do {
            let exported = try await runNativeCall(
                request: request,
                operation: { [core = self.core] in
                    try await core.copyConfirmedMediaToSink(
                        mediaHandle: handle,
                        sink: record.reservation.mediaSink,
                        maximumLength: MediaCaptureTransferStore.maximumFileBytes
                    )
                },
                lateSuccess: { [weak self] _ in
                    await self?.cleanupTransferRecord(record)
                }
            )
            guard exported.mediaHandle == handle,
                  exported.mediaType == metadata.mediaType,
                  exported.contentType == expectedContentType(metadata.mediaType),
                  exported.byteLength == metadata.byteLength,
                  record.reservation.committed
            else {
                throw MediaCaptureWireCodec.wireEncodingFailure(operation: request.operation)
            }
            guard let store = transferStore else {
                throw MediaCaptureWireCodec.transferStoreUnavailable(operation: request.operation)
            }
            let fileURI = try await Task.detached(priority: .utility) {
                try store.fileURI(record.reservation)
            }.value
            let monotonicNow = DispatchTime.now().uptimeNanoseconds
            let epochNow = epochMilliseconds()
            guard epochNow >= 0, epochNow <= Int64.max - 300_000 else {
                throw MediaCaptureWireCodec.wireEncodingFailure(operation: request.operation)
            }
            let expiresAt = epochNow + 300_000
            let (deadlineCandidate, deadlineOverflow) = monotonicNow.addingReportingOverflow(
                transferTTLNanoseconds
            )
            let monotonicDeadline = deadlineOverflow ? UInt64.max : deadlineCandidate
            let encoded = try MediaCaptureWireCodec.materializedMedia(
                requestId: request.requestId,
                exportHandle: record.reservation.exportHandle,
                fileURI: fileURI,
                metadata: metadata,
                expiresAtEpochMilliseconds: expiresAt
            )
            guard completeTransferSuccess(
                request: request,
                record: record,
                expiresAtEpochMilliseconds: expiresAt,
                expiresAtMonotonicNanoseconds: monotonicDeadline,
                value: encoded
            ) else {
                await cleanupTransferRecord(record)
                return
            }
        } catch {
            await cleanupTransferRecord(record)
            throw error
        }
    }

    private func executeReleaseMaterialized(
        request: PendingRequest,
        exportHandle: String
    ) async throws {
        retryRetainedTransferCleanup()
        let released: Bool
        switch claimTransferRelease(exportHandle) {
        case .alreadyReleased:
            released = true
        case let .rejected(failure):
            throw failure
        case let .join(waiter):
            released = await waiter.wait()
        case let .claim(record, waiter):
            let deleted = await deleteTransferFiles(record)
            finishTransferRelease(record: record, waiter: waiter, deleted: deleted)
            released = deleted
        }
        guard released else {
            throw MediaCaptureWireCodec.transferStoreUnavailable(operation: request.operation)
        }
        try await completeSuccess(
            request,
            value: MediaCaptureWireCodec.materializedMediaReleased(requestId: request.requestId)
        )
    }

    private func reserveTransfer(
        operation: String,
        metadata: MediaMetadata
    ) async throws -> TransferRecord {
        guard transferGenerationOpen, let transferStore else {
            throw MediaCaptureWireCodec.transferStoreUnavailable(operation: operation)
        }
        guard transfers.count + pendingTransferReservations.count < 4 else {
            throw MediaCaptureWireCodec.transferStoreOverloaded(
                operation: operation,
                capacity: "active_exports"
            )
        }
        let pendingBytes = pendingTransferReservations.values.reduce(0, +)
        guard metadata.byteLength > 0,
              activeTransferBytes <= maximumActiveTransferBytes - pendingBytes,
              metadata.byteLength <= maximumActiveTransferBytes - activeTransferBytes - pendingBytes
        else {
            throw MediaCaptureWireCodec.transferStoreOverloaded(
                operation: operation,
                capacity: "active_export_bytes"
            )
        }
        let claim = UUID()
        pendingTransferReservations[claim] = metadata.byteLength
        defer { pendingTransferReservations.removeValue(forKey: claim) }
        for _ in 0 ..< 32 {
            let reservation: MediaCaptureTransferStore.Reservation
            do {
                reservation = try await Task.detached(priority: .utility) {
                    try transferStore.createReservation(metadata: metadata)
                }.value
            } catch {
                throw MediaCaptureWireCodec.transferStoreUnavailable(operation: operation)
            }
            guard !Task.isCancelled, engineOpen, transferGenerationOpen else {
                _ = await Task.detached(priority: .utility) {
                    transferStore.delete(reservation)
                }.value
                throw CancellationError()
            }
            let handle = reservation.exportHandle
            guard transfers[handle] == nil, releaseTombstones[handle] == nil else {
                _ = await Task.detached(priority: .utility) {
                    transferStore.delete(reservation)
                }.value
                continue
            }
            let record = TransferRecord(reservation: reservation)
            transfers[handle] = record
            activeTransferBytes += metadata.byteLength
            return record
        }
        throw MediaCaptureWireCodec.transferStoreUnavailable(operation: operation)
    }

    private func completeTransferSuccess(
        request: PendingRequest,
        record: TransferRecord,
        expiresAtEpochMilliseconds: Int64,
        expiresAtMonotonicNanoseconds: UInt64,
        value: [String: Any]
    ) -> Bool {
        let handle = record.reservation.exportHandle
        guard isOpen(request), transfers[handle] === record,
              !record.cleanupPending, record.reservation.committed
        else {
            return false
        }
        record.active = true
        record.expiresAtEpochMilliseconds = expiresAtEpochMilliseconds
        let ttlTask = Task.detached(priority: .utility) { [weak self, weak record] in
            let current = DispatchTime.now().uptimeNanoseconds
            if current < expiresAtMonotonicNanoseconds {
                do {
                    try await Task.sleep(nanoseconds: expiresAtMonotonicNanoseconds - current)
                } catch {
                    return
                }
            }
            guard let self, let record else { return }
            await self.expireTransfer(record)
        }
        record.ttlTask = ttlTask
        pending.removeValue(forKey: request.requestId)
        addTombstone(request.requestId)
        updateOwnerMonitor()
        request.takeCompletion()?.success(value)
        if transfers[handle] !== record || !record.active || record.cleanupPending {
            ttlTask.cancel()
        }
        return true
    }

    private func claimTransferRelease(_ exportHandle: String) -> TransferReleaseDecision {
        pruneReleaseTombstones()
        guard engineOpen else {
            return .rejected(
                MediaCaptureWireCodec.bridgeUnavailable(
                    operation: "release_materialized_media",
                    reason: "engine_detached"
                )
            )
        }
        if releaseTombstones[exportHandle] != nil { return .alreadyReleased }
        guard let record = transfers[exportHandle] else {
            return .rejected(MediaCaptureWireCodec.materializedMediaInvalid())
        }
        if record.expired {
            return .rejected(MediaCaptureWireCodec.materializedMediaInvalid())
        }
        if let waiter = releaseClaims[exportHandle] { return .join(waiter) }
        if record.cleanupTask != nil {
            return .rejected(
                MediaCaptureWireCodec.transferStoreUnavailable(
                    operation: "release_materialized_media"
                )
            )
        }
        let reservedCount = transfers.values.filter(\.releaseTombstoneReserved).count
        guard record.releaseTombstoneReserved || releaseTombstones.count + reservedCount < 4_096 else {
            return .rejected(
                MediaCaptureWireCodec.transferStoreOverloaded(
                    operation: "release_materialized_media",
                    capacity: "release_tombstones"
                )
            )
        }
        record.cleanupPending = true
        record.releaseTombstoneReserved = true
        record.ttlTask?.cancel()
        record.ttlTask = nil
        let waiter = MediaCaptureTransferReleaseWaiter()
        releaseClaims[exportHandle] = waiter
        return .claim(record, waiter)
    }

    private func finishTransferRelease(
        record: TransferRecord,
        waiter: MediaCaptureTransferReleaseWaiter,
        deleted: Bool
    ) {
        let handle = record.reservation.exportHandle
        if releaseClaims[handle] === waiter { releaseClaims.removeValue(forKey: handle) }
        if deleted, transfers[handle] === record {
            removeTransfer(record)
            releaseTombstones[handle] = monotonicMilliseconds()
        }
        waiter.finish(deleted)
        if !deleted { scheduleTransferCleanup(record) }
    }

    private func expireTransfer(_ record: TransferRecord) async {
        let handle = record.reservation.exportHandle
        guard transfers[handle] === record else { return }
        record.expired = true
        record.cleanupPending = true
        record.ttlTask = nil
        await cleanupTransferRecord(record)
    }

    private func cleanupTransferRecord(_ record: TransferRecord) async {
        let handle = record.reservation.exportHandle
        guard transfers[handle] === record else { return }
        record.cleanupPending = true
        record.ttlTask?.cancel()
        record.ttlTask = nil
        if await deleteTransferFiles(record) {
            settleTransferCleanup(record)
        } else {
            scheduleTransferCleanup(record)
        }
    }

    private func deleteTransferFiles(_ record: TransferRecord) async -> Bool {
        guard let transferStore else { return false }
        for attempt in 0 ..< 3 {
            let deleted = await Task.detached(priority: .utility) {
                transferStore.delete(record.reservation)
            }.value
            if deleted {
                return true
            }
            if attempt < 2 {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        return false
    }

    private func scheduleTransferCleanup(_ record: TransferRecord) {
        let handle = record.reservation.exportHandle
        guard transfers[handle] === record, record.cleanupTask == nil else { return }
        let cleanup = Task { [weak self, weak record] in
            guard let self, let record else { return }
            var delay: UInt64 = 50_000_000
            for _ in 0 ..< 8 {
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    return
                }
                guard self.transfers[handle] === record else { return }
                if await self.deleteTransferFiles(record) {
                    self.settleTransferCleanup(record)
                    return
                }
                delay = min(delay * 2, 5_000_000_000)
            }
            if self.transfers[handle] === record { record.cleanupTask = nil }
        }
        record.cleanupTask = cleanup
    }

    private func retryRetainedTransferCleanup() {
        for record in transfers.values where record.cleanupPending && record.cleanupTask == nil {
            scheduleTransferCleanup(record)
        }
    }

    private func removeTransfer(_ record: TransferRecord) {
        let handle = record.reservation.exportHandle
        guard transfers[handle] === record else { return }
        transfers.removeValue(forKey: handle)
        activeTransferBytes = max(0, activeTransferBytes - record.reservation.metadata.byteLength)
        record.ttlTask?.cancel()
        record.cleanupTask?.cancel()
        record.ttlTask = nil
        record.cleanupTask = nil
    }

    private func settleTransferCleanup(_ record: TransferRecord) {
        let handle = record.reservation.exportHandle
        guard transfers[handle] === record else { return }
        let addTombstone = record.releaseTombstoneReserved
        removeTransfer(record)
        if addTombstone { releaseTombstones[handle] = monotonicMilliseconds() }
    }

    private func pruneReleaseTombstones() {
        let now = monotonicMilliseconds()
        releaseTombstones = releaseTombstones.filter {
            now < $0.value || now - $0.value < 300_000
        }
    }

    private func expectedContentType(_ mediaType: MediaType) -> String {
        mediaType == .photo ? "image/jpeg" : "video/mp4"
    }

    private func executePresentation(
        request: PendingRequest,
        options: SessionOptions
    ) async throws {
        guard let presentation = activePresentation,
              presentation.requestId == request.requestId,
              presentation.session == nil
        else { throw MediaCaptureWireCodec.presentationConflict() }
        if presentation.dismissRequested {
            try await completeSuccess(
                request,
                value: MediaCaptureWireCodec.captureFlowCancelled(requestId: request.requestId),
                adopt: { self.clearPresentation(request.requestId) }
            )
            return
        }
        guard let owner = presentationOwner(), owner.identity == request.ownerIdentity else {
            throw MediaCaptureWireCodec.bridgeUnavailable(
                operation: request.operation,
                reason: "view_controller_destroyed"
            )
        }
        try await runNativeCall(request: request) {
            try await owner.presenter.preflight(options: options)
        }
        guard isOpen(request), activePresentation === presentation,
              ownerIsAlive(owner.identity)
        else {
            throw MediaCaptureWireCodec.bridgeUnavailable(
                operation: request.operation,
                reason: "view_controller_destroyed"
            )
        }
        let session: any MediaCapturePresentationSession
        do {
            session = try owner.presenter.present(options: options)
        } catch {
            if activePresentation === presentation { activePresentation = nil }
            throw error
        }
        guard isOpen(request), activePresentation === presentation else {
            session.dismiss()
            throw MediaCaptureWireCodec.bridgeUnavailable(
                operation: request.operation,
                reason: "view_controller_destroyed"
            )
        }
        presentation.session = session
        let outcome = try await runNativeCall(
            request: request,
            operation: {
                try await session.awaitResult()
            },
            lateSuccess: { [core = self.core] outcome in
                if case let .confirmed(media) = outcome {
                    _ = try? await core.releaseMedia(
                        mediaHandle: media.metadata.mediaHandle
                    )
                }
            }
        )
        if presentation.dismissRequested,
           case let .confirmed(media) = outcome {
            await releaseMediaIfPossible(media.metadata.mediaHandle.rawValue)
            try await completeSuccess(
                request,
                value: MediaCaptureWireCodec.captureFlowCancelled(requestId: request.requestId),
                adopt: { self.clearPresentation(request.requestId) }
            )
            return
        }
        switch outcome {
        case let .confirmed(media):
            let handle = media.metadata.mediaHandle
            guard !leases.contains(handle.rawValue),
                  !settlingLeases.contains(handle.rawValue)
            else {
                await releaseMediaIfPossible(handle.rawValue)
                clearPresentation(request.requestId)
                throw MediaCaptureWireCodec.wireEncodingFailure(operation: request.operation)
            }
            let encoded: [String: Any]
            do {
                encoded = try MediaCaptureWireCodec.confirmedMedia(
                    requestId: request.requestId,
                    value: media,
                    resultType: "capture_flow_confirmed"
                )
            } catch {
                await releaseMediaIfPossible(handle.rawValue)
                clearPresentation(request.requestId)
                throw error
            }
            try await completeSuccess(
                request,
                value: encoded,
                adopt: {
                    guard self.leases.insert(handle.rawValue).inserted else {
                        throw MediaCaptureWireCodec.wireEncodingFailure(operation: request.operation)
                    }
                    self.leaseMetadata[handle.rawValue] = media.metadata
                    self.clearPresentation(request.requestId)
                },
                lateCleanup: { [weak self] in
                    await self?.releaseMediaIfPossible(handle.rawValue)
                    self?.clearPresentation(request.requestId)
                }
            )
        case .cancelled:
            try await completeSuccess(
                request,
                value: MediaCaptureWireCodec.captureFlowCancelled(requestId: request.requestId),
                adopt: { self.clearPresentation(request.requestId) },
                lateCleanup: { [weak self] in
                    self?.clearPresentation(request.requestId)
                }
            )
        case let .failure(failure):
            clearPresentation(request.requestId)
            throw failure
        }
    }

    private func executeDismissPresentation(
        request: PendingRequest,
        presentationRequestId: String
    ) async throws {
        if let presentation = activePresentation,
           presentation.requestId == presentationRequestId,
           let target = pending[presentationRequestId],
           target.operation == "present_capture_flow" {
            presentationCleanupInProgress = true
            if let session = presentation.session {
                session.dismiss()
                await presentation.waitUntilSettled()
            } else {
                activePresentation = nil
                pending.removeValue(forKey: target.requestId)
                addTombstone(target.requestId)
                target.task?.cancel()
                target.takeCompletion()?.success(
                    try MediaCaptureWireCodec.captureFlowCancelled(requestId: target.requestId)
                )
                presentation.settle()
                presentationCleanupInProgress = false
            }
        }
        try await completeSuccess(
            request,
            value: MediaCaptureWireCodec.captureFlowDismissed(requestId: request.requestId)
        )
    }

    private func completeSuccess(
        _ request: PendingRequest,
        value: [String: Any],
        adopt: () throws -> Void = {},
        lateCleanup: @escaping () async -> Void = {}
    ) async throws {
        guard engineOpen, pending[request.requestId] === request else {
            await lateCleanup()
            return
        }
        if let owner = unavailableOwner(for: request) {
            ownerDestroyed(owner)
            await lateCleanup()
            return
        }
        do {
            try adopt()
        } catch {
            await lateCleanup()
            throw error
        }
        pending.removeValue(forKey: request.requestId)
        addTombstone(request.requestId)
        updateOwnerMonitor()
        request.takeCompletion()?.success(value)
    }

    private func completeFailure(
        _ request: PendingRequest,
        failure: MediaCaptureWireFailure
    ) {
        guard pending[request.requestId] === request else { return }
        if let owner = unavailableOwner(for: request) {
            ownerDestroyed(owner)
            return
        }
        pending.removeValue(forKey: request.requestId)
        clearPresentation(request.requestId)
        addTombstone(request.requestId)
        updateOwnerMonitor()
        request.takeCompletion()?.failure(failure)
    }

    private func isOpen(_ request: PendingRequest) -> Bool {
        guard engineOpen, pending[request.requestId] === request else { return false }
        return unavailableOwner(for: request) == nil
    }

    private func unavailableOwner(for request: PendingRequest) -> ObjectIdentifier? {
        guard let owner = request.ownerIdentity,
              !ownerIsAlive(owner)
        else {
            return nil
        }
        return owner
    }

    private func requireSession(_ handle: SessionHandle) throws {
        guard sessions.contains(handle.rawValue) else { throw MediaCaptureFailure(.sessionInvalid) }
    }

    private func requireMedia(
        _ handle: MediaHandle,
        allowSettlingLease: Bool = false
    ) throws {
        guard previews[handle.rawValue] != nil || leases.contains(handle.rawValue) ||
                (allowSettlingLease && settlingLeases.contains(handle.rawValue))
        else {
            throw MediaCaptureFailure(.mediaInvalid)
        }
    }

    private func removeSessionOwnership(_ rawHandle: String) {
        sessions.remove(rawHandle)
        sessionOwners.removeValue(forKey: rawHandle)
        previews = previews.filter { $0.value != rawHandle }
        updateOwnerMonitor()
    }

    private func clearPresentation(_ requestId: String) {
        if let presentation = activePresentation,
           presentation.requestId == requestId {
            activePresentation = nil
            presentation.settle()
            updatePresentationCleanupState()
            updateOwnerMonitor()
        }
    }

    private func cancelSessionIfPossible(_ rawHandle: String) async {
        guard let handle = try? SessionHandle(rawValue: rawHandle) else { return }
        let timeout = drainTimeoutNanoseconds
        _ = try? await MediaCaptureNativeCall.runBounded(
            timeoutNanoseconds: timeout,
            operation: { [core = self.core] in
                _ = try await core.cancel(sessionHandle: handle)
            }
        )
        removeSessionOwnership(rawHandle)
    }

    private func releaseMediaIfPossible(_ rawHandle: String) async {
        guard let handle = try? MediaHandle(rawValue: rawHandle) else { return }
        let timeout = drainTimeoutNanoseconds
        _ = try? await MediaCaptureNativeCall.runBounded(
            timeoutNanoseconds: timeout,
            operation: { [core = self.core] in
                _ = try await core.releaseMedia(mediaHandle: handle)
            }
        )
        leases.remove(rawHandle)
        settlingLeases.remove(rawHandle)
        leaseMetadata.removeValue(forKey: rawHandle)
        previews.removeValue(forKey: rawHandle)
    }

    private func handleNativeEvent(_ event: MediaCaptureEvent) {
        guard engineOpen else { return }
        if let startup = startupOutcome(event) {
            let rawHandle = startup.sessionHandle.rawValue
            if let waiter = startupWaiters.removeValue(forKey: rawHandle) {
                waiter.resume(returning: startup)
                return
            }
            let hasPendingDirectStart = pending.values.contains {
                $0.operation == "start_session"
            }
            if hasPendingDirectStart,
               !sessions.contains(rawHandle),
               earlyStartupOutcomes.count < 32 {
                earlyStartupOutcomes[rawHandle] = startup
                return
            }
        }
        let shouldDeliver: Bool
        switch event {
        case let .sessionReady(snapshot):
            shouldDeliver = sessions.contains(snapshot.sessionHandle.rawValue)
        case let .sessionFailed(handle, _):
            shouldDeliver = sessions.contains(handle.rawValue)
            removeSessionOwnership(handle.rawValue)
        case let .mediaPreviewReady(sessionHandle, metadata):
            shouldDeliver = sessions.contains(sessionHandle.rawValue)
            if shouldDeliver,
               previews[metadata.mediaHandle.rawValue] == nil,
               !leases.contains(metadata.mediaHandle.rawValue),
               !settlingLeases.contains(metadata.mediaHandle.rawValue) {
                previews[metadata.mediaHandle.rawValue] = sessionHandle.rawValue
            } else if shouldDeliver {
                terminateListenerWithEncodingFailure()
                Task { [weak self] in await self?.cancelSessionIfPossible(sessionHandle.rawValue) }
                return
            }
        case let .mediaLeaseExpired(handle):
            if leases.remove(handle.rawValue) != nil {
                settlingLeases.insert(handle.rawValue)
                leaseMetadata.removeValue(forKey: handle.rawValue)
                shouldDeliver = true
            } else {
                shouldDeliver = false
            }
        case let .mediaReadRevoked(handle):
            let wasLeased = leases.remove(handle.rawValue) != nil
            let wasSettling = settlingLeases.remove(handle.rawValue) != nil
            leaseMetadata.removeValue(forKey: handle.rawValue)
            shouldDeliver = wasLeased || wasSettling
        case .renderAttachmentRevoked:
            shouldDeliver = false
        }
        guard shouldDeliver, let listener else { return }
        do {
            guard let envelope = try MediaCaptureWireCodec.event(event) else { return }
            guard self.listener?.generation == listener.generation else { return }
            listener.sink.success(envelope)
        } catch {
            terminateListenerWithEncodingFailure()
        }
    }

    private func terminateListenerWithEncodingFailure() {
        guard let listener else { return }
        self.listener = nil
        listener.sink.failure(MediaCaptureWireCodec.wireEncodingFailure(operation: "unknown_operation"))
    }

    private func awaitSessionStartup(
        _ handle: SessionHandle
    ) async throws -> SessionStartupOutcome {
        if let early = earlyStartupOutcomes.removeValue(forKey: handle.rawValue) {
            return early
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    startupWaiters[handle.rawValue] = continuation
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelStartupWaiter(handle.rawValue)
            }
        }
    }

    private func cancelStartupWaiter(_ rawHandle: String) {
        earlyStartupOutcomes.removeValue(forKey: rawHandle)
        startupWaiters.removeValue(forKey: rawHandle)?.resume(
            throwing: CancellationError()
        )
    }

    private func startupOutcome(_ event: MediaCaptureEvent) -> SessionStartupOutcome? {
        switch event {
        case let .sessionReady(snapshot):
            return .ready(snapshot)
        case let .sessionFailed(sessionHandle, failure):
            return .failed(sessionHandle: sessionHandle, failure: failure)
        default:
            return nil
        }
    }

    private func finishOwnerCleanup(requestIds: Set<String>) {
        let unresolved = requestIds.filter { requestId in
            nativeCallRequests.values.contains(requestId)
        }
        ownerCleanupWaitingRequestIds.formUnion(unresolved)
        updatePresentationCleanupState()
    }

    private func updatePresentationCleanupState() {
        guard activePresentation == nil else { return }
        presentationCleanupInProgress = !ownerCleanupWaitingRequestIds.isEmpty ||
            !ownerRequestDrainWaitingIds.isEmpty ||
            !ownerBoundaryCleanupTokens.isEmpty ||
            !ownerBoundaryPublicTokens.isEmpty
    }

    private func retainOwnerCleanupUntilDrained(
        _ tasks: [Task<Void, Never>],
        requestIds: Set<String>
    ) {
        let identifier = UUID()
        let task = Task { [weak self] in
            for task in tasks {
                await task.value
            }
            self?.ownerRequestDrainWaitingIds.subtract(requestIds)
            self?.finishOwnerCleanup(requestIds: requestIds)
            self?.boundaryTasks.removeValue(forKey: identifier)
        }
        boundaryTasks[identifier] = task
    }

    private func pruneTombstones() {
        let now = monotonicMilliseconds()
        completed = completed.filter { now >= $0.value && now - $0.value < 300_000 }
    }

    private func addTombstone(_ requestId: String) {
        completed[requestId] = monotonicMilliseconds()
    }
}
