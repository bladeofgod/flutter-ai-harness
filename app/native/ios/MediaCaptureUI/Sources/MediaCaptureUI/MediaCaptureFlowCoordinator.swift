import Foundation
import MediaCapture
import MediaCaptureAppleRendering
import UIKit

internal typealias MediaCaptureDismissalAction = @MainActor (
    _ viewController: UIViewController,
    _ completion: @escaping @MainActor @Sendable () -> Void
) -> Void

private final class MediaCaptureDismissalSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false

    var isCompleted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return completed
    }

    func complete() {
        lock.lock()
        completed = true
        lock.unlock()
    }
}

@MainActor
internal final class MediaCaptureFlowCompletion {
    private var result: MediaCaptureFlowResult?
    private var waiters: [CheckedContinuation<MediaCaptureFlowResult, Never>] = []
    private var cancellableWaiters: [
        UUID: CheckedContinuation<MediaCaptureFlowResult, Error>
    ] = [:]

    func value() async -> MediaCaptureFlowResult {
        if let result { return result }
        return await withCheckedContinuation { waiters.append($0) }
    }

    func cancellableValue(
        onCancel: @escaping @MainActor @Sendable () -> Void
    ) async throws -> MediaCaptureFlowResult {
        if let result { return result }
        let identifier = UUID()
        return try await withTaskCancellationHandler {
            return try await withCheckedThrowingContinuation { continuation in
                if let result {
                    continuation.resume(returning: result)
                } else if Task.isCancelled {
                    onCancel()
                    continuation.resume(throwing: CancellationError())
                } else {
                    cancellableWaiters[identifier] = continuation
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self,
                      let continuation = self.cancellableWaiters.removeValue(
                          forKey: identifier
                      )
                else { return }
                onCancel()
                continuation.resume(throwing: CancellationError())
            }
        }
    }

    @discardableResult
    func complete(_ result: MediaCaptureFlowResult) -> Bool {
        guard self.result == nil else { return false }
        self.result = result
        let waiters = waiters
        let cancellableWaiters = Array(cancellableWaiters.values)
        self.waiters.removeAll()
        self.cancellableWaiters.removeAll()
        waiters.forEach { $0.resume(returning: result) }
        cancellableWaiters.forEach { $0.resume(returning: result) }
        return true
    }

    var cancellableWaiterCount: Int { cancellableWaiters.count }
}

@MainActor
internal final class MediaCaptureFlowCoordinator {
    private enum LifecycleRequest {
        case rotation
        case background
        case foreground
    }

    private struct SurfaceContext {
        let kind: MediaCaptureSurfaceKind
        let owner: MediaCaptureRenderSurfaceOwner
        let view: MediaCaptureRenderView
    }

    private let core: any MediaCaptureServicing
    private let configuration: MediaCaptureUiConfiguration
    private let completion: MediaCaptureFlowCompletion
    private let releasePresentationSlotAction: @MainActor () -> Void
    private let dismissalAction: MediaCaptureDismissalAction
    private let leaseCleanupOwner: MediaCaptureLeaseCleanupOwner
    private let settleTimeoutNanoseconds: UInt64

    private weak var viewController: MediaCaptureViewController?
    private var phase: MediaCaptureUiPhase = .starting
    private var readySnapshot: SessionReadySnapshot?
    private var sessionHandle: SessionHandle?
    private var currentSurface: SurfaceContext?
    private var currentFlashMode: FlashMode = .off
    private var currentZoomFactor: Double = 1
    private var surfaceGeneration: Int64
    private var actionTask: Task<Void, Never>?
    private var lifecycleTask: Task<Void, Never>?
    private var lifecycleGeneration: UInt64 = 0
    private var eventTask: Task<Void, Never>?
    private var eventOperationTask: Task<Void, Never>?
    private var pendingEvent: MediaCaptureEvent?
    private var terminalTask: Task<Void, Never>?
    private var started = false
    private var terminalStarted = false
    private var transactionAdmissionOpen = true
    private var pendingRecordingStop = false
    private var appIsBackgrounded = false
    private var lateConfirmedMedia: ConfirmedMedia?
    private var currentPreviewMetadata: MediaMetadata?
    private var deferredCleanupHolds = 0
    private var terminalCleanupFinished = false
    private var presentationSlotReleased = false

    init(
        core: any MediaCaptureServicing,
        configuration: MediaCaptureUiConfiguration,
        initialSurfaceGeneration: Int64,
        completion: MediaCaptureFlowCompletion,
        leaseCleanupOwner: MediaCaptureLeaseCleanupOwner = .shared,
        settleTimeoutNanoseconds: UInt64 = 5_000_000_000,
        dismissalAction: @escaping MediaCaptureDismissalAction = { viewController, completion in
            viewController.dismiss(animated: false, completion: completion)
        },
        releasePresentationSlot: @escaping @MainActor () -> Void
    ) {
        self.core = core
        self.configuration = configuration
        surfaceGeneration = initialSurfaceGeneration
        self.completion = completion
        self.leaseCleanupOwner = leaseCleanupOwner
        self.settleTimeoutNanoseconds = settleTimeoutNanoseconds
        self.dismissalAction = dismissalAction
        releasePresentationSlotAction = releasePresentationSlot
    }

    func install(viewController: MediaCaptureViewController) {
        self.viewController = viewController
        renderSnapshot()
    }

    func beginIfNeeded() {
        guard !started, !terminalStarted else { return }
        started = true
        actionTask = Task { [weak self] in
            await self?.startFlow()
        }
    }

    func awaitResult() async -> MediaCaptureFlowResult {
        await completion.value()
    }

    func awaitCancellableResult() async throws -> MediaCaptureFlowResult {
        try await completion.cancellableValue { [weak self] in
            self?.finishExternal(.failure(MediaCaptureFailure(.systemInterrupted)))
        }
    }

    var cancellableResultWaiterCount: Int {
        completion.cancellableWaiterCount
    }

    var videoCaptureEnabled: Bool {
        phase == .live && configuration.sessionOptions.enabledMediaTypes.contains(.video)
    }

    var actionTransactionAvailable: Bool {
        canStartAction
    }

    var eventTransactionInFlight: Bool {
        eventOperationTask != nil
    }

    @discardableResult
    func takePhoto() -> Bool {
        guard phase == .live,
              configuration.sessionOptions.enabledMediaTypes.contains(.photo),
              let sessionHandle,
              canStartAction
        else { return false }
        phase = .capturing
        renderSnapshot()
        let operationGeneration = lifecycleGeneration
        actionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let metadata = try await core.takePhoto(sessionHandle: sessionHandle)
                guard !terminalStarted else { return }
                try await showPreview(metadata)
            } catch {
                await handleActionFailure(error, operationGeneration: operationGeneration)
            }
            if lifecycleGeneration == operationGeneration { actionTask = nil }
        }
        return true
    }

    @discardableResult
    func startRecording() -> Bool {
        guard phase == .live,
              configuration.sessionOptions.enabledMediaTypes.contains(.video),
              let sessionHandle,
              canStartAction
        else { return false }
        pendingRecordingStop = false
        phase = .startingRecording
        renderSnapshot()
        let operationGeneration = lifecycleGeneration
        actionTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await core.startRecording(sessionHandle: sessionHandle)
                guard !terminalStarted else { return }
                phase = .recording
                beginRecordingProgress()
                renderSnapshot()
                if pendingRecordingStop {
                    pendingRecordingStop = false
                    phase = .stoppingRecording
                    renderSnapshot()
                    try await stopRecordingWithinCurrentAction(sessionHandle: sessionHandle)
                }
            } catch {
                await handleActionFailure(error, operationGeneration: operationGeneration)
            }
            if lifecycleGeneration == operationGeneration { actionTask = nil }
        }
        return true
    }

    @discardableResult
    func stopRecording() -> Bool {
        if phase == .startingRecording {
            pendingRecordingStop = true
            return true
        }
        guard phase == .recording else { return false }
        pendingRecordingStop = true
        phase = .stoppingRecording
        renderSnapshot()
        startPendingRecordingStopIfNeeded()
        return true
    }

    private func startPendingRecordingStopIfNeeded() {
        guard pendingRecordingStop,
              phase == .stoppingRecording,
              let sessionHandle,
              canStartAction,
              !terminalStarted
        else { return }
        pendingRecordingStop = false
        let operationGeneration = lifecycleGeneration
        actionTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await stopRecordingWithinCurrentAction(sessionHandle: sessionHandle)
            } catch {
                await handleActionFailure(error, operationGeneration: operationGeneration)
            }
            if lifecycleGeneration == operationGeneration { actionTask = nil }
        }
    }

    func updateZoom(verticalDelta: Double) {
        guard phase == .recording,
              let readySnapshot,
              let sessionHandle,
              canStartAction
        else { return }
        let range = readySnapshot.maximumZoomFactor - readySnapshot.minimumZoomFactor
        let proposed = currentZoomFactor + (verticalDelta / 180) * range
        let clamped = min(max(proposed, readySnapshot.minimumZoomFactor), readySnapshot.maximumZoomFactor)
        guard abs(clamped - currentZoomFactor) >= 0.01 else { return }
        currentZoomFactor = clamped
        let operationGeneration = lifecycleGeneration
        actionTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await core.setZoomFactor(sessionHandle: sessionHandle, factor: clamped)
            } catch {
                await handleActionFailure(error, operationGeneration: operationGeneration)
            }
            if lifecycleGeneration == operationGeneration {
                actionTask = nil
                startPendingRecordingStopIfNeeded()
            }
        }
    }

    @discardableResult
    func focus(normalizedX: Double, normalizedY: Double) -> Bool {
        guard phase == .live || phase == .recording,
              readySnapshot?.focusPointSupported == true,
              let sessionHandle,
              canStartAction,
              normalizedX.isFinite,
              normalizedY.isFinite,
              (0 ... 1).contains(normalizedX),
              (0 ... 1).contains(normalizedY)
        else { return false }
        let operationGeneration = lifecycleGeneration
        actionTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await core.setFocusPoint(
                    sessionHandle: sessionHandle,
                    normalizedX: normalizedX,
                    normalizedY: normalizedY
                )
            } catch {
                await handleActionFailure(error, operationGeneration: operationGeneration)
            }
            if lifecycleGeneration == operationGeneration {
                actionTask = nil
                startPendingRecordingStopIfNeeded()
            }
        }
        return true
    }

    func switchCamera() {
        guard phase == .live,
              readySnapshot?.switchCameraSupported == true,
              let sessionHandle,
              canStartAction
        else { return }
        phase = .switchingCamera
        renderSnapshot()
        let operationGeneration = lifecycleGeneration
        actionTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await core.switchCamera(sessionHandle: sessionHandle)
            } catch {
                await handleActionFailure(error, operationGeneration: operationGeneration)
            }
            if lifecycleGeneration == operationGeneration { actionTask = nil }
        }
    }

    func cycleFlash() {
        guard phase == .live,
              let supported = readySnapshot?.supportedFlashModes,
              supported.contains(where: { $0 != .off }),
              let sessionHandle,
              canStartAction
        else { return }
        let currentIndex = supported.firstIndex(of: currentFlashMode) ?? -1
        let nextMode = supported[(currentIndex + 1) % supported.count]
        let operationGeneration = lifecycleGeneration
        actionTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await core.setFlashMode(sessionHandle: sessionHandle, mode: nextMode)
                guard !terminalStarted else { return }
                currentFlashMode = nextMode
                renderSnapshot()
            } catch {
                await handleActionFailure(error, operationGeneration: operationGeneration)
            }
            if lifecycleGeneration == operationGeneration { actionTask = nil }
        }
    }

    func retake() {
        guard case let .preview(metadata) = phase, canStartAction else { return }
        let operationGeneration = lifecycleGeneration
        actionTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await core.retake(mediaHandle: metadata.mediaHandle)
                guard !terminalStarted else { return }
                currentPreviewMetadata = nil
                phase = .live
                if !appIsBackgrounded {
                    try await replaceSurface(kind: .live(try requireSessionHandle()))
                }
                renderSnapshot()
            } catch {
                await handleActionFailure(error, operationGeneration: operationGeneration)
            }
            if lifecycleGeneration == operationGeneration { actionTask = nil }
        }
    }

    func confirm() {
        guard case let .preview(metadata) = phase, canStartAction else { return }
        phase = .confirming
        renderSnapshot()
        let operationGeneration = lifecycleGeneration
        actionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let confirmed = try await core.confirm(mediaHandle: metadata.mediaHandle)
                if terminalStarted {
                    lateConfirmedMedia = confirmed
                    return
                }
                actionTask = nil
                finishFromAction(.confirmed(confirmed))
            } catch {
                await handleActionFailure(error, operationGeneration: operationGeneration)
                if lifecycleGeneration == operationGeneration { actionTask = nil }
            }
        }
    }

    func dismissByCaller() {
        finishExternal(.cancelled)
    }

    func ownerWasDestroyed() {
        finishExternal(.failure(MediaCaptureFailure(.systemInterrupted)))
    }

    func displayRotationChanged() {
        guard !terminalStarted else { return }
        scheduleLifecycle(.rotation)
    }

    func appDidEnterBackground() {
        guard !terminalStarted, !appIsBackgrounded else { return }
        appIsBackgrounded = true
        scheduleLifecycle(.background)
    }

    func appWillEnterForeground() {
        guard !terminalStarted, appIsBackgrounded else { return }
        appIsBackgrounded = false
        scheduleLifecycle(.foreground)
    }

    private func scheduleLifecycle(_ request: LifecycleRequest) {
        let prior = lifecycleTask
        let action = actionTask
        let eventOperation = eventOperationTask
        prior?.cancel()
        action?.cancel()
        eventOperation?.cancel()
        lifecycleGeneration &+= 1
        transactionAdmissionOpen = false
        renderSnapshot()
        let generation = lifecycleGeneration
        lifecycleTask = Task { [weak self] in
            guard let self else { return }
            addDeferredCleanupHold()
            let tasks = [prior, action, eventOperation].compactMap { $0 }
            let settled = await leaseCleanupOwner.waitForTasks(
                tasks,
                timeoutNanoseconds: settleTimeoutNanoseconds,
                onLateSettled: { [self] in
                    await self.releaseLateConfirmedIfNeeded()
                    self.completeDeferredCleanupHold()
                }
            )
            if settled { completeDeferredCleanupHold() }
            guard settled else {
                actionTask = nil
                eventOperationTask = nil
                lifecycleTask = nil
                finishFromLifecycleFailure()
                return
            }
            actionTask = nil
            eventOperationTask = nil
            guard !Task.isCancelled, !terminalStarted else {
                clearLifecycleTask(generation: generation)
                return
            }
            await executeLifecycle(request, generation: generation)
            clearLifecycleTask(generation: generation)
        }
    }

    private func executeLifecycle(_ request: LifecycleRequest, generation: UInt64) async {
        switch request {
        case .rotation:
            await core.displayRotationChanged()
            guard !Task.isCancelled, !terminalStarted, !appIsBackgrounded else { return }
            await restoreSurfaceAfterLifecycle(operationGeneration: generation)
        case .background:
            await core.appDidEnterBackground()
            currentSurface = nil
            viewController?.removeRenderView()
        case .foreground:
            guard !Task.isCancelled, !terminalStarted, !appIsBackgrounded else { return }
            await restoreSurfaceAfterLifecycle(operationGeneration: generation)
        }
    }

    private func recoverPhaseAfterSupersededActionFailure() {
        switch phase {
        case .capturing, .startingRecording:
            pendingRecordingStop = false
            phase = .live
        case .switchingCamera:
            phase = .live
        case .confirming:
            if let currentPreviewMetadata { phase = .preview(currentPreviewMetadata) }
        case .recording:
            break
        case .stoppingRecording:
            pendingRecordingStop = true
        case .starting, .live, .preview, .terminal:
            break
        }
        renderSnapshot()
    }

    private func restoreSurfaceAfterLifecycle(operationGeneration: UInt64) async {
        do {
            try await restoreSurfaceForCurrentPhase()
        } catch {
            await handleActionFailure(error, operationGeneration: operationGeneration)
        }
    }

    private func clearLifecycleTask(generation: UInt64) {
        guard lifecycleGeneration == generation else { return }
        lifecycleTask = nil
        transactionAdmissionOpen = !terminalStarted && !appIsBackgrounded
        startPendingRecordingStopIfNeeded()
    }

    private func startFlow() async {
        let operationGeneration = lifecycleGeneration
        do {
            let stream = await core.events()
            let created = try await core.startSession(options: configuration.sessionOptions)
            guard !terminalStarted else {
                await settleSessionCancellation(created.sessionHandle)
                return
            }
            sessionHandle = created.sessionHandle
            actionTask = nil
            eventTask = Task { [weak self] in
                for await event in stream {
                    guard let self, !Task.isCancelled else { return }
                    pendingEvent = event
                    while pendingEvent != nil {
                        if let lifecycleTask {
                            _ = await lifecycleTask.result
                        }
                        guard !Task.isCancelled, !terminalStarted else { return }
                        let operation = Task { [weak self] in
                            guard let self, let pendingEvent else { return }
                            guard await prepareForEvent(pendingEvent) else { return }
                            self.pendingEvent = nil
                            let eventGeneration = lifecycleGeneration
                            await self.handle(
                                pendingEvent,
                                operationGeneration: eventGeneration
                            )
                        }
                        eventOperationTask = operation
                        _ = await operation.result
                        eventOperationTask = nil
                    }
                }
                guard let self, !Task.isCancelled, !terminalStarted else { return }
                finishFromEventLoopFailure()
            }
        } catch {
            if lifecycleGeneration == operationGeneration { actionTask = nil }
            await handleActionFailure(error, operationGeneration: operationGeneration)
        }
    }

    private func prepareForEvent(_ event: MediaCaptureEvent) async -> Bool {
        guard !Task.isCancelled, !terminalStarted else { return false }
        guard case .mediaPreviewReady = event else {
            if let actionTask { _ = await actionTask.result }
            return !Task.isCancelled && !terminalStarted
        }
        guard let action = actionTask else { return true }
        action.cancel()
        lifecycleGeneration &+= 1
        addDeferredCleanupHold()
        let settled = await leaseCleanupOwner.waitForTasks(
            [action],
            timeoutNanoseconds: settleTimeoutNanoseconds,
            onLateSettled: { [self] in
                await self.releaseLateConfirmedIfNeeded()
                self.completeDeferredCleanupHold()
            }
        )
        if settled { completeDeferredCleanupHold() }
        actionTask = nil
        guard settled else {
            finishFromEventLoopFailure()
            return false
        }
        return !terminalStarted
    }

    private func handle(_ event: MediaCaptureEvent, operationGeneration: UInt64) async {
        guard !terminalStarted, let sessionHandle else { return }
        switch event {
        case let .sessionReady(snapshot) where snapshot.sessionHandle == sessionHandle:
            readySnapshot = snapshot
            currentFlashMode = snapshot.supportedFlashModes.contains(.off)
                ? .off
                : (snapshot.supportedFlashModes.first ?? .off)
            currentZoomFactor = snapshot.minimumZoomFactor
            phase = .live
            do {
                if !appIsBackgrounded {
                    try Task.checkCancellation()
                    try await replaceSurface(kind: .live(sessionHandle))
                }
                renderSnapshot()
            } catch {
                await handleActionFailure(error, operationGeneration: operationGeneration)
            }
        case let .sessionFailed(handle, failure) where handle == sessionHandle:
            finishExternal(.failure(failure))
        case let .mediaPreviewReady(handle, metadata) where handle == sessionHandle:
            guard case .preview = phase else {
                do {
                    try Task.checkCancellation()
                    try await showPreview(metadata)
                } catch {
                    await handleActionFailure(error, operationGeneration: operationGeneration)
                }
                return
            }
        default:
            break
        }
    }

    private func stopRecordingWithinCurrentAction(sessionHandle: SessionHandle) async throws {
        let metadata = try await core.stopRecording(sessionHandle: sessionHandle)
        guard !terminalStarted else { return }
        try await showPreview(metadata)
    }

    private func showPreview(_ metadata: MediaMetadata) async throws {
        if case let .preview(existing) = phase, existing.mediaHandle == metadata.mediaHandle { return }
        currentPreviewMetadata = metadata
        phase = .preview(metadata)
        if !appIsBackgrounded {
            try await replaceSurface(kind: .preview(metadata.mediaHandle))
        }
        renderSnapshot()
    }

    private func replaceSurface(kind: MediaCaptureSurfaceKind) async throws {
        try Task.checkCancellation()
        try await detachCurrentSurface()
        try Task.checkCancellation()
        guard !terminalStarted else { return }
        surfaceGeneration &+= 1
        let owner = MediaCaptureRenderSurfaceOwner(ownerGeneration: surfaceGeneration)
        let renderView = try MediaCaptureRenderSurfaceFactory.make(owner: owner)
        let context = SurfaceContext(kind: kind, owner: owner, view: renderView)
        currentSurface = context
        viewController?.installRenderView(renderView)
        do {
            switch kind {
            case let .live(handle):
                _ = try await core.attachLivePreview(sessionHandle: handle, surfaceOwner: owner)
            case let .preview(handle):
                _ = try await core.attachUnconfirmedPreviewRender(
                    mediaHandle: handle,
                    surfaceOwner: owner
                )
            }
            try Task.checkCancellation()
            guard currentSurface?.owner === owner, !terminalStarted else {
                try? await detach(context)
                return
            }
        } catch {
            do {
                try await detach(context)
                clearSurfaceIfCurrent(context)
            } catch let detachFailure {
                if MediaCaptureLeaseCleanupOwner.isSettledSurfaceFailure(
                    detachFailure as? MediaCaptureFailure ?? MediaCaptureFailure(.systemInterrupted),
                    kind: context.kind
                ) {
                    clearSurfaceIfCurrent(context)
                }
            }
            throw error
        }
    }

    private func detachCurrentSurface() async throws {
        guard let context = currentSurface else {
            viewController?.removeRenderView()
            return
        }
        do {
            try await detach(context)
            clearSurfaceIfCurrent(context)
        } catch let failure as MediaCaptureFailure
            where MediaCaptureLeaseCleanupOwner.isSettledSurfaceFailure(failure, kind: context.kind) {
            clearSurfaceIfCurrent(context)
        }
    }

    private func detach(_ context: SurfaceContext) async throws {
        switch context.kind {
        case let .live(handle):
            _ = try await core.detachLivePreview(sessionHandle: handle, surfaceOwner: context.owner)
        case let .preview(handle):
            _ = try await core.detachUnconfirmedPreviewRender(
                mediaHandle: handle,
                surfaceOwner: context.owner
            )
        }
    }

    private func clearSurfaceIfCurrent(_ context: SurfaceContext) {
        guard currentSurface?.owner === context.owner else { return }
        currentSurface = nil
        viewController?.removeRenderView()
    }

    private func restoreSurfaceForCurrentPhase() async throws {
        switch phase {
        case .live, .capturing, .startingRecording, .recording, .stoppingRecording:
            try await replaceSurface(kind: .live(try requireSessionHandle()))
        case .preview, .confirming:
            guard let previewHandle = currentPreviewHandle else { return }
            try await replaceSurface(kind: .preview(previewHandle))
        case .starting, .switchingCamera, .terminal:
            break
        }
    }

    private var currentPreviewHandle: MediaHandle? {
        currentPreviewMetadata?.mediaHandle
    }

    private func beginRecordingProgress() {
        let duration = Double(configuration.sessionOptions.maxVideoDurationMilliseconds) / 1_000
        viewController?.beginRecordingProgress(duration: duration)
    }

    private func finishFromAction(_ result: MediaCaptureFlowResult) {
        guard !terminalStarted else { return }
        let lifecycle = lifecycleTask
        let event = eventTask
        let eventOperation = eventOperationTask
        lifecycleTask = nil
        eventTask = nil
        eventOperationTask = nil
        lifecycle?.cancel()
        event?.cancel()
        eventOperation?.cancel()
        actionTask = nil
        enterTerminalState()
        terminalTask = Task {
            await self.settleThenCleanup(
                result,
                tasks: [lifecycle, event, eventOperation].compactMap { $0 }
            )
        }
    }

    private func finishExternal(_ result: MediaCaptureFlowResult) {
        guard !terminalStarted else { return }
        let action = actionTask
        let lifecycle = lifecycleTask
        let event = eventTask
        let eventOperation = eventOperationTask
        actionTask = nil
        lifecycleTask = nil
        eventTask = nil
        eventOperationTask = nil
        action?.cancel()
        lifecycle?.cancel()
        event?.cancel()
        eventOperation?.cancel()
        enterTerminalState()
        terminalTask = Task {
            await self.settleThenCleanup(
                result,
                tasks: [action, lifecycle, event, eventOperation].compactMap { $0 }
            )
        }
    }

    private func finishFromLifecycleFailure() {
        guard !terminalStarted else { return }
        let event = eventTask
        eventTask = nil
        event?.cancel()
        enterTerminalState()
        terminalTask = Task {
            await self.settleThenCleanup(
                .failure(MediaCaptureFailure(.systemInterrupted)),
                tasks: [event].compactMap { $0 }
            )
        }
    }

    private func finishFromEventLoopFailure() {
        guard !terminalStarted else { return }
        let event = eventTask
        eventTask = nil
        event?.cancel()
        enterTerminalState()
        terminalTask = Task {
            await self.cleanupAndComplete(
                .failure(MediaCaptureFailure(.systemInterrupted))
            )
        }
    }

    private func enterTerminalState() {
        terminalStarted = true
        transactionAdmissionOpen = false
        pendingEvent = nil
        phase = .terminal
        renderSnapshot()
    }

    private func settleThenCleanup(
        _ result: MediaCaptureFlowResult,
        tasks: [Task<Void, Never>]
    ) async {
        addDeferredCleanupHold()
        let settled = await leaseCleanupOwner.waitForTasks(
            tasks,
            timeoutNanoseconds: settleTimeoutNanoseconds,
            onLateSettled: { [self] in
                await releaseLateConfirmedIfNeeded()
                completeDeferredCleanupHold()
            }
        )
        if settled { completeDeferredCleanupHold() }
        await cleanupAndComplete(result)
    }

    private func cleanupAndComplete(_ proposedResult: MediaCaptureFlowResult) async {
        if let context = currentSurface {
            clearSurfaceIfCurrent(context)
            await settleSurfaceDetachment(context)
        }
        if case .confirmed = proposedResult {
        } else if let sessionHandle {
            await settleSessionCancellation(sessionHandle)
        }
        await releaseLateConfirmedIfNeeded()
        await dismissViewControllerIfNeeded()
        terminalCleanupFinished = true
        releasePresentationSlotIfReady()
        _ = completion.complete(proposedResult)
        terminalTask = nil
    }

    private func releaseLateConfirmedIfNeeded() async {
        guard let lateConfirmedMedia else { return }
        self.lateConfirmedMedia = nil
        await settleMediaRelease(lateConfirmedMedia.metadata.mediaHandle)
    }

    private func settleSurfaceDetachment(_ context: SurfaceContext) async {
        addDeferredCleanupHold()
        let cleanup = Task { [self] in
            do {
                try await detach(context)
                completeDeferredCleanupHold()
            } catch let failure as MediaCaptureFailure
                where MediaCaptureLeaseCleanupOwner.isSettledSurfaceFailure(
                    failure,
                    kind: context.kind
                ) {
                completeDeferredCleanupHold()
            } catch {
                await leaseCleanupOwner.adoptSurfaceDetachment(
                    kind: context.kind,
                    owner: context.owner,
                    using: core,
                    onRecovered: { [self] in completeDeferredCleanupHold() }
                )
            }
        }
        _ = await leaseCleanupOwner.waitForTasks(
            [cleanup],
            timeoutNanoseconds: settleTimeoutNanoseconds,
            onLateSettled: {}
        )
    }

    private func settleSessionCancellation(_ handle: SessionHandle) async {
        addDeferredCleanupHold()
        let cleanup = Task { [self] in
            do {
                _ = try await core.cancel(sessionHandle: handle)
                completeDeferredCleanupHold()
            } catch let failure as MediaCaptureFailure
                where failure.id == .sessionInvalid || failure.id == .invalidState {
                completeDeferredCleanupHold()
            } catch {
                await leaseCleanupOwner.adoptSessionCancellation(
                    sessionHandle: handle,
                    using: core,
                    onRecovered: { [self] in completeDeferredCleanupHold() }
                )
            }
        }
        _ = await leaseCleanupOwner.waitForTasks(
            [cleanup],
            timeoutNanoseconds: settleTimeoutNanoseconds,
            onLateSettled: {}
        )
    }

    private func settleMediaRelease(_ handle: MediaHandle) async {
        addDeferredCleanupHold()
        let cleanup = Task { [self] in
            do {
                _ = try await core.releaseMedia(mediaHandle: handle)
                completeDeferredCleanupHold()
            } catch let failure as MediaCaptureFailure
                where !MediaCaptureLeaseCleanupOwner.isRetryableMediaReleaseFailure(failure) {
                completeDeferredCleanupHold()
            } catch is MediaCaptureFailure {
                await leaseCleanupOwner.adoptMediaRelease(
                    mediaHandle: handle,
                    using: core,
                    onRecovered: { [self] in completeDeferredCleanupHold() }
                )
            } catch {
                completeDeferredCleanupHold()
            }
        }
        _ = await leaseCleanupOwner.waitForTasks(
            [cleanup],
            timeoutNanoseconds: settleTimeoutNanoseconds,
            onLateSettled: {}
        )
    }

    private func addDeferredCleanupHold() {
        deferredCleanupHolds += 1
    }

    private func completeDeferredCleanupHold() {
        guard deferredCleanupHolds > 0 else { return }
        deferredCleanupHolds -= 1
        releasePresentationSlotIfReady()
    }

    private func releasePresentationSlotIfReady() {
        guard terminalCleanupFinished,
              deferredCleanupHolds == 0,
              !presentationSlotReleased
        else { return }
        presentationSlotReleased = true
        releasePresentationSlotAction()
    }

    private func dismissViewControllerIfNeeded() async {
        guard let viewController else { return }
        viewController.markExpectedDismissal()
        guard viewController.presentingViewController != nil else { return }
        addDeferredCleanupHold()
        let dismissal = Task { [self, weak viewController] in
            guard let viewController else {
                completeDeferredCleanupHold()
                return
            }
            let signal = MediaCaptureDismissalSignal()
            dismissalAction(viewController) {
                signal.complete()
            }
            while !signal.isCompleted && viewController.presentingViewController != nil {
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
            completeDeferredCleanupHold()
        }
        _ = await leaseCleanupOwner.waitForTasks(
            [dismissal],
            timeoutNanoseconds: settleTimeoutNanoseconds,
            onLateSettled: {}
        )
    }

    private var canStartAction: Bool {
        transactionAdmissionOpen && actionTask == nil && eventOperationTask == nil
    }

    private func handleActionFailure(_ error: Error, operationGeneration: UInt64) async {
        guard !terminalStarted else { return }
        guard operationGeneration == lifecycleGeneration else {
            recoverPhaseAfterSupersededActionFailure()
            return
        }
        if error is CancellationError {
            finishExternal(.failure(MediaCaptureFailure(.systemInterrupted)))
        } else if let failure = error as? MediaCaptureFailure {
            finishExternal(.failure(failure))
        } else {
            finishExternal(.failure(MediaCaptureFailure(.systemInterrupted)))
        }
    }

    private func requireSessionHandle() throws -> SessionHandle {
        guard let sessionHandle else { throw MediaCaptureFailure(.sessionInvalid) }
        return sessionHandle
    }

    private func renderSnapshot() {
        viewController?.apply(MediaCaptureUiSnapshot(
            phase: phase,
            ready: readySnapshot,
            flashMode: currentFlashMode,
            recordingProgress: 0,
            photoEnabled: configuration.sessionOptions.enabledMediaTypes.contains(.photo),
            videoEnabled: configuration.sessionOptions.enabledMediaTypes.contains(.video)
        ))
    }
}
