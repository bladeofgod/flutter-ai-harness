import Foundation

public actor MediaCaptureCore {
    private enum ModuleLifecycleState {
        case idle
        case captureActive
        case tearingDown
        case restarting
        case closed
    }

    private struct SessionRecord {
        let handle: SessionHandle
        let options: SessionOptions
        let creationEpoch: UInt64
        var state: SessionState
        var readySnapshot: SessionReadySnapshot?
        var currentMediaHandle: MediaHandle?
        var cachedPreview: MediaMetadata?
        var recordingDestination: URL?
        var flashMode: FlashMode = .off
        var operationInFlight = false
        var operationGeneration: UInt64 = 0
        var liveAttachment = AttachmentSlot()
        var terminalAt: Date?
    }

    private struct MediaRecord {
        let handle: MediaHandle
        let sessionHandle: SessionHandle
        let storedMedia: StoredMedia
        let metadata: MediaMetadata
        var state: MediaState
        var stateDeadline: Date?
        var terminalAt: Date?
        var previewAttachment = AttachmentSlot()
        var operationInFlight = false
        var operationGeneration: UInt64 = 0
    }

    private enum ThumbnailWinner: Equatable {
        case success
        case release
        case expiry
        case restart
        case callerCancelled
        case decoderFailure
    }

    private final class ThumbnailOutcomeArbiter: @unchecked Sendable {
        private let lock = NSLock()
        private var winner: ThumbnailWinner?

        @discardableResult
        func tryWin(_ proposed: ThumbnailWinner) -> ThumbnailWinner {
            lock.lock()
            defer { lock.unlock() }
            if let winner { return winner }
            winner = proposed
            return proposed
        }

        var current: ThumbnailWinner? {
            lock.lock()
            defer { lock.unlock() }
            return winner
        }
    }

    private struct ThumbnailJob {
        let identifier: UUID
        let mediaHandle: MediaHandle
        let cancellation: CancellationSignal
        let arbiter: ThumbnailOutcomeArbiter
        let reservedWorkingBytes: Int
        var source: MediaSourceAccess?
        var worker: ManagedThumbnailWorker?
        var finalized = false
    }

    private struct ExportJob {
        let identifier: UUID
        let mediaHandle: MediaHandle
        let control: MediaExportControl
        var worker: Task<MediaExportResult, Error>?
        var deadline: Task<Void, Never>?
    }

    private struct DeadlineTaskRecord {
        let identifier: UUID
        let task: Task<Void, Never>
    }

    private struct SessionOperationToken {
        let handle: SessionHandle
        let generation: UInt64
        let epoch: UInt64
    }

    private struct MediaTransitionToken {
        let mediaHandle: MediaHandle
        let sessionHandle: SessionHandle
        let mediaGeneration: UInt64
        let sessionGeneration: UInt64
        let epoch: UInt64
    }

    private enum CapabilityOperation: Equatable {
        case startSession
        case takePhoto
        case startRecording
        case stopRecording
        case switchCamera
        case setFlashMode
        case setFocusPoint
        case setZoom
        case attachLivePreview
        case attachUnconfirmedPreview
    }

    private let configuration: MediaCaptureConfiguration
    private let platform: any CapturePlatform
    private let fileStore: any MediaFileStoring
    private let clock: any MediaCaptureClock
    private let handleGenerator: any HandleGenerating
    private let thumbnailGenerator: any ThumbnailGenerating
    private let exportExecutor: any MediaExportExecuting
    private let exportBufferAccounting: (any MediaExportBufferAccounting)?
    private let exportCommitReturned: (@Sendable () async -> Void)?

    private var sessions: [SessionHandle: SessionRecord] = [:]
    private var media: [MediaHandle: MediaRecord] = [:]
    private var activeSessionHandle: SessionHandle?
    private var issuedHandleValues: Set<String> = []
    private var eventContinuations: [UUID: AsyncStream<MediaCaptureEvent>.Continuation] = [:]
    private var preparationTasks: [SessionHandle: Task<Void, Never>] = [:]
    private var deadlineTasks: [String: DeadlineTaskRecord] = [:]
    private var platformEventTask: Task<Void, Never>?
    private var readScopes: [UUID: (mediaHandle: MediaHandle, source: MediaSourceAccess)] = [:]
    private var thumbnailJobs: [UUID: ThumbnailJob] = [:]
    private var thumbnailDrainWaiters: [CheckedContinuation<Void, Never>] = []
    private var exportJobs: [MediaHandle: ExportJob] = [:]
    private var exportDrainWaiters: [CheckedContinuation<Void, Never>] = []
    private var attachmentOperationCount = 0
    private var attachmentOperationWaiters: [CheckedContinuation<Void, Never>] = []
    private var attachmentCleanupTasks: [UUID: Task<Void, Never>] = [:]
    private var startupResidueRemoved = false
    private var closed = false
    private var moduleLifecycleState: ModuleLifecycleState = .idle
    private var captureTeardownGeneration: UInt64 = 0
    private var lifecycleEpoch: UInt64 = 0
    private let thumbnailJobWorkingBytes = 8_388_608
    private let thumbnailModuleWorkingBytes = 16_777_216
    private let exportReadBufferBytes = 131_072
    private let exportReservedWorkingBytes = 262_144
    private let exportModuleWorkingBytes = 1_048_576
    private let maximumExportBytes = 52_428_800
    private let exportDeadlineSeconds: TimeInterval = 120

    public init() {
        configuration = MediaCaptureConfiguration()
        platform = AVFoundationCapturePlatform()
        fileStore = AppleMediaFileStore()
        clock = SystemMediaCaptureClock()
        handleGenerator = SecureHandleGenerator()
        thumbnailGenerator = AppleThumbnailGenerator()
        exportExecutor = DispatchMediaExportExecutor()
        exportBufferAccounting = nil
        exportCommitReturned = nil
    }

    internal init(
        configuration: MediaCaptureConfiguration = MediaCaptureConfiguration(),
        platform: any CapturePlatform,
        fileStore: any MediaFileStoring,
        clock: any MediaCaptureClock,
        handleGenerator: any HandleGenerating,
        thumbnailGenerator: any ThumbnailGenerating,
        exportExecutor: any MediaExportExecuting = DispatchMediaExportExecutor(),
        exportBufferAccounting: (any MediaExportBufferAccounting)? = nil,
        exportCommitReturned: (@Sendable () async -> Void)? = nil
    ) {
        self.configuration = configuration
        self.platform = platform
        self.fileStore = fileStore
        self.clock = clock
        self.handleGenerator = handleGenerator
        self.thumbnailGenerator = thumbnailGenerator
        self.exportExecutor = exportExecutor
        self.exportBufferAccounting = exportBufferAccounting
        self.exportCommitReturned = exportCommitReturned
    }

    public func events() -> AsyncStream<MediaCaptureEvent> {
        let identifier = UUID()
        return AsyncStream { continuation in
            eventContinuations[identifier] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeEventContinuation(identifier) }
            }
        }
    }

    public func permissionState(for resource: PermissionResource) async -> PermissionState {
        await platform.permissionState(for: resource)
    }

    public func startSession(options: SessionOptions) async throws -> SessionCreated {
        try ensureCanStartSession()
        await processDeadlines()
        if !startupResidueRemoved {
            startupResidueRemoved = true
            await fileStore.removeTemporaryResidue()
        }
        if let activeSessionHandle,
           let active = sessions[activeSessionHandle],
           ![SessionState.completed, .cancelled, .failed].contains(active.state) {
            throw MediaCaptureFailure(.sessionConflict)
        }

        let handle = try makeSessionHandle()
        sessions[handle] = SessionRecord(
            handle: handle,
            options: options,
            creationEpoch: lifecycleEpoch,
            state: .requestingPermission
        )
        moduleLifecycleState = .captureActive
        activeSessionHandle = handle
        observePlatformEventsIfNeeded()
        preparationTasks[handle] = Task { [weak self] in
            await self?.prepareSession(handle)
        }
        return SessionCreated(sessionHandle: handle)
    }

    public func takePhoto(sessionHandle: SessionHandle) async throws -> MediaMetadata {
        try ensureOpen()
        await processDeadlines()
        guard var session = sessions[sessionHandle] else {
            throw MediaCaptureFailure(.sessionInvalid)
        }
        guard session.state == .ready, !session.operationInFlight
        else {
            throw MediaCaptureFailure(.invalidState)
        }
        guard session.options.enabledMediaTypes.contains(.photo) else {
            throw MediaCaptureFailure(.unsupportedCapability)
        }
        session.operationInFlight = true
        session.operationGeneration &+= 1
        let operationGeneration = session.operationGeneration
        let operationEpoch = lifecycleEpoch
        sessions[sessionHandle] = session
        await revokeLiveAttachment(sessionHandle: sessionHandle)
        var pendingStoredMedia: StoredMedia?
        do {
            try validateSessionOperation(
                sessionHandle,
                generation: operationGeneration,
                epoch: operationEpoch,
                allowedStates: [.ready]
            )
            let photo = try await platform.capturePhoto(flashMode: session.flashMode)
            try Task.checkCancellation()
            let stored = try await fileStore.storePhoto(photo)
            pendingStoredMedia = stored
            try Task.checkCancellation()
            guard var current = sessions[sessionHandle],
                  current.state == .ready,
                  current.operationInFlight,
                  current.operationGeneration == operationGeneration,
                  lifecycleEpoch == operationEpoch
            else {
                await fileStore.delete(stored.reference)
                pendingStoredMedia = nil
                throw MediaCaptureFailure(.invalidState)
            }
            let record = try makeMediaRecord(
                storedMedia: stored,
                sessionHandle: sessionHandle,
                state: .preview,
                deadline: clock.now.addingTimeInterval(configuration.previewTimeToLive)
            )
            media[record.handle] = record
            current.currentMediaHandle = record.handle
            current.cachedPreview = record.metadata
            current.state = .previewing
            current.operationInFlight = false
            sessions[sessionHandle] = current
            pendingStoredMedia = nil
            scheduleDeadline(
                key: mediaDeadlineKey(record.handle),
                at: record.stateDeadline ?? clock.now
            )
            return record.metadata
        } catch is CancellationError {
            if let pendingStoredMedia {
                await fileStore.delete(pendingStoredMedia.reference)
            }
            clearOperation(sessionHandle, generation: operationGeneration)
            throw CancellationError()
        } catch {
            clearOperation(sessionHandle, generation: operationGeneration)
            let failure = mapFailure(error, for: .takePhoto)
            if failure.terminal { await failSession(sessionHandle, failure: failure) }
            throw failure
        }
    }

    public func startRecording(sessionHandle: SessionHandle) async throws -> RecordingStarted {
        try ensureOpen()
        await processDeadlines()
        guard var session = sessions[sessionHandle] else {
            throw MediaCaptureFailure(.sessionInvalid)
        }
        guard session.state == .ready, !session.operationInFlight
        else {
            throw MediaCaptureFailure(.invalidState)
        }
        guard session.options.enabledMediaTypes.contains(.video) else {
            throw MediaCaptureFailure(.unsupportedCapability)
        }
        session.operationInFlight = true
        session.operationGeneration &+= 1
        let operationGeneration = session.operationGeneration
        let operationEpoch = lifecycleEpoch
        sessions[sessionHandle] = session
        var pendingDestination: URL?
        do {
            if session.options.audioEnabled {
                let microphoneState = try await resolvePermission(.microphone)
                try validateSessionOperation(
                    sessionHandle,
                    generation: operationGeneration,
                    epoch: operationEpoch,
                    allowedStates: [.ready]
                )
                guard microphoneState == .granted else {
                    throw permissionFailure(for: microphoneState)
                }
            }
            try await platform.configureRecordingAudio(enabled: session.options.audioEnabled)
            try validateSessionOperation(
                sessionHandle,
                generation: operationGeneration,
                epoch: operationEpoch,
                allowedStates: [.ready]
            )
            let destination = try await fileStore.recordingDestination()
            pendingDestination = destination
            try validateSessionOperation(
                sessionHandle,
                generation: operationGeneration,
                epoch: operationEpoch,
                allowedStates: [.ready]
            )
            try await platform.startRecording(to: destination)
            try Task.checkCancellation()
            guard var current = sessions[sessionHandle],
                  current.state == .ready,
                  current.operationInFlight,
                  current.operationGeneration == operationGeneration,
                  lifecycleEpoch == operationEpoch
            else {
                try? await platform.stopRecording()
                await fileStore.discardRecording(at: destination)
                throw MediaCaptureFailure(.invalidState)
            }
            current.state = .recording
            current.recordingDestination = destination
            pendingDestination = nil
            current.operationInFlight = false
            sessions[sessionHandle] = current
            let deadline = clock.now.addingTimeInterval(
                Double(session.options.maxVideoDurationMilliseconds) / 1_000
            )
            scheduleRecordingDeadline(sessionHandle, at: deadline)
            return RecordingStarted(
                sessionHandle: sessionHandle,
                audioIncluded: session.options.audioEnabled
            )
        } catch is CancellationError {
            try? await platform.stopRecording()
            if let pendingDestination { await fileStore.discardRecording(at: pendingDestination) }
            clearOperation(sessionHandle, generation: operationGeneration)
            throw CancellationError()
        } catch {
            if let pendingDestination { await fileStore.discardRecording(at: pendingDestination) }
            clearOperation(sessionHandle, generation: operationGeneration)
            let failure = mapFailure(error, for: .startRecording)
            if failure.terminal { await failSession(sessionHandle, failure: failure) }
            throw failure
        }
    }

    public func stopRecording(sessionHandle: SessionHandle) async throws -> MediaMetadata {
        try ensureOpen()
        await processDeadlines()
        guard let session = sessions[sessionHandle] else {
            throw MediaCaptureFailure(.sessionInvalid)
        }
        if session.state == .previewing, let preview = session.cachedPreview {
            return preview
        }
        guard session.state == .recording, !session.operationInFlight else {
            throw MediaCaptureFailure(.invalidState)
        }
        return try await finishRecording(sessionHandle: sessionHandle, automatic: false)
    }

    @discardableResult
    public func switchCamera(sessionHandle: SessionHandle) async throws -> SessionHandle {
        try ensureOpen()
        await processDeadlines()
        let token = try beginSessionOperation(sessionHandle, allowedStates: [.ready])
        guard let session = sessions[sessionHandle] else {
            throw MediaCaptureFailure(.sessionInvalid)
        }
        guard session.readySnapshot?.switchCameraSupported == true else {
            clearOperation(sessionHandle, generation: token.generation)
            throw MediaCaptureFailure(.unsupportedCapability)
        }
        do {
            let updated = try await platform.switchCamera()
            let snapshot = try publicSnapshot(updated, handle: sessionHandle)
            var current = try validatedSessionOperationAfterPlatformCommit(
                token,
                allowedStates: [.ready]
            )
            current.readySnapshot = snapshot
            current.flashMode = snapshot.supportedFlashModes.contains(.off)
                ? .off
                : snapshot.supportedFlashModes[0]
            current.operationInFlight = false
            sessions[sessionHandle] = current
            yield(.sessionReady(snapshot))
            return sessionHandle
        } catch is CancellationError {
            clearOperation(sessionHandle, generation: token.generation)
            throw CancellationError()
        } catch {
            clearOperation(sessionHandle, generation: token.generation)
            let failure = mapFailure(error, for: .switchCamera)
            if failure.terminal { await failSession(sessionHandle, failure: failure) }
            throw failure
        }
    }

    @discardableResult
    public func setFlashMode(
        sessionHandle: SessionHandle,
        mode: FlashMode
    ) async throws -> SessionHandle {
        try ensureOpen()
        await processDeadlines()
        let token = try beginSessionOperation(sessionHandle, allowedStates: [.ready, .recording])
        guard let session = sessions[sessionHandle] else {
            throw MediaCaptureFailure(.sessionInvalid)
        }
        guard session.readySnapshot?.supportedFlashModes.contains(mode) == true else {
            clearOperation(sessionHandle, generation: token.generation)
            throw MediaCaptureFailure(.unsupportedCapability)
        }
        do {
            try await platform.setFlashMode(mode)
            try Task.checkCancellation()
            var current = try validatedSessionOperation(token, allowedStates: [.ready, .recording])
            current.flashMode = mode
            current.operationInFlight = false
            sessions[sessionHandle] = current
            return sessionHandle
        } catch is CancellationError {
            clearOperation(sessionHandle, generation: token.generation)
            throw CancellationError()
        } catch {
            clearOperation(sessionHandle, generation: token.generation)
            let failure = mapFailure(error, for: .setFlashMode)
            if failure.terminal { await failSession(sessionHandle, failure: failure) }
            throw failure
        }
    }

    @discardableResult
    public func setFocusPoint(
        sessionHandle: SessionHandle,
        normalizedX: Double,
        normalizedY: Double
    ) async throws -> SessionHandle {
        try ensureOpen()
        await processDeadlines()
        guard normalizedX.isFinite, normalizedY.isFinite,
              (0 ... 1).contains(normalizedX), (0 ... 1).contains(normalizedY)
        else {
            throw MediaCaptureFailure(.invalidArgument)
        }
        let token = try beginSessionOperation(sessionHandle, allowedStates: [.ready, .recording])
        guard let session = sessions[sessionHandle] else {
            throw MediaCaptureFailure(.sessionInvalid)
        }
        guard session.readySnapshot?.focusPointSupported == true else {
            clearOperation(sessionHandle, generation: token.generation)
            throw MediaCaptureFailure(.unsupportedCapability)
        }
        do {
            try await platform.setFocusPoint(x: normalizedX, y: normalizedY)
            try Task.checkCancellation()
            var current = try validatedSessionOperation(token, allowedStates: [.ready, .recording])
            current.operationInFlight = false
            sessions[sessionHandle] = current
            return sessionHandle
        } catch is CancellationError {
            clearOperation(sessionHandle, generation: token.generation)
            throw CancellationError()
        } catch {
            clearOperation(sessionHandle, generation: token.generation)
            let failure = mapFailure(error, for: .setFocusPoint)
            if failure.terminal { await failSession(sessionHandle, failure: failure) }
            throw failure
        }
    }

    @discardableResult
    public func setZoomFactor(
        sessionHandle: SessionHandle,
        factor: Double
    ) async throws -> SessionHandle {
        try ensureOpen()
        await processDeadlines()
        let token = try beginSessionOperation(sessionHandle, allowedStates: [.ready, .recording])
        guard let session = sessions[sessionHandle] else {
            throw MediaCaptureFailure(.sessionInvalid)
        }
        guard factor.isFinite,
              let snapshot = session.readySnapshot,
              factor >= snapshot.minimumZoomFactor,
              factor <= snapshot.maximumZoomFactor
        else {
            clearOperation(sessionHandle, generation: token.generation)
            throw MediaCaptureFailure(.invalidArgument)
        }
        do {
            try await platform.setZoomFactor(factor)
            try Task.checkCancellation()
            var current = try validatedSessionOperation(token, allowedStates: [.ready, .recording])
            current.operationInFlight = false
            sessions[sessionHandle] = current
            return sessionHandle
        } catch is CancellationError {
            clearOperation(sessionHandle, generation: token.generation)
            throw CancellationError()
        } catch {
            clearOperation(sessionHandle, generation: token.generation)
            let failure = mapFailure(error, for: .setZoom)
            if failure.terminal { await failSession(sessionHandle, failure: failure) }
            throw failure
        }
    }

    @discardableResult
    public func retake(mediaHandle: MediaHandle) async throws -> SessionHandle {
        try ensureOpen()
        await processDeadlines()
        let token = try beginMediaTransition(mediaHandle)
        do {
            await revokePreviewAttachment(mediaHandle: mediaHandle)
            try Task.checkCancellation()
            var (mediaRecord, session) = try validatedMediaTransition(token)
            await fileStore.delete(mediaRecord.storedMedia.reference)
            (mediaRecord, session) = try validatedMediaTransition(token)
            cancelDeadline(mediaDeadlineKey(mediaHandle))
            mediaRecord.state = .discarded
            mediaRecord.stateDeadline = nil
            mediaRecord.terminalAt = clock.now
            mediaRecord.operationInFlight = false
            media[mediaHandle] = mediaRecord
            session.currentMediaHandle = nil
            session.cachedPreview = nil
            session.state = .ready
            session.operationInFlight = false
            sessions[session.handle] = session
            return session.handle
        } catch {
            clearMediaTransition(token)
            throw error
        }
    }

    public func confirm(mediaHandle: MediaHandle) async throws -> ConfirmedMedia {
        try ensureOpen()
        await processDeadlines()
        let token = try beginMediaTransition(mediaHandle)
        let teardownEpoch = beginCaptureTeardown()
        do {
            await revokePreviewAttachment(mediaHandle: mediaHandle)
            try Task.checkCancellation()
            var (mediaRecord, session) = try validatedMediaTransition(token)
            let leaseExpiry = clock.now.addingTimeInterval(configuration.mediaLeaseTimeToLive)
            mediaRecord.state = .leased
            mediaRecord.stateDeadline = leaseExpiry
            mediaRecord.operationInFlight = false
            media[mediaHandle] = mediaRecord
            session.state = .completed
            session.terminalAt = clock.now
            session.operationInFlight = false
            sessions[session.handle] = session
            preparationTasks.removeValue(forKey: session.handle)?.cancel()
            cancelDeadline(recordingDeadlineKey(session.handle))
            scheduleDeadline(key: mediaDeadlineKey(mediaHandle), at: leaseExpiry)
            await platform.stopSession()
            finishCaptureTeardown(epoch: teardownEpoch, sessionHandle: session.handle)
            return ConfirmedMedia(metadata: mediaRecord.metadata, leaseExpiresAt: leaseExpiry)
        } catch {
            clearMediaTransition(token)
            abandonCaptureTeardown(epoch: teardownEpoch)
            throw error
        }
    }

    @discardableResult
    public func cancel(sessionHandle: SessionHandle) async throws -> SessionHandle {
        try ensureTerminalOperationAllowed()
        await processDeadlines()
        guard var session = sessions[sessionHandle] else {
            throw MediaCaptureFailure(.sessionInvalid)
        }
        if session.state == .cancelled { return sessionHandle }
        guard [.requestingPermission, .preparing, .ready, .recording, .previewing].contains(session.state) else {
            throw MediaCaptureFailure(.invalidState)
        }
        session.operationGeneration &+= 1
        session.operationInFlight = false
        session.state = .cancelled
        session.terminalAt = clock.now
        let teardownEpoch = beginCaptureTeardown()
        let previewHandle = session.currentMediaHandle
        let recordingDestination = session.recordingDestination
        sessions[sessionHandle] = session
        preparationTasks.removeValue(forKey: sessionHandle)?.cancel()
        cancelDeadline(recordingDeadlineKey(sessionHandle))
        if let previewHandle, var preview = media[previewHandle], preview.state == .preview {
            preview.operationGeneration &+= 1
            preview.operationInFlight = false
            preview.state = .discarded
            preview.stateDeadline = nil
            preview.terminalAt = clock.now
            media[previewHandle] = preview
            cancelDeadline(mediaDeadlineKey(previewHandle))
        }
        await revokeLiveAttachment(sessionHandle: sessionHandle)
        if let previewHandle, let preview = media[previewHandle] {
            await revokePreviewAttachment(mediaHandle: previewHandle)
            await fileStore.delete(preview.storedMedia.reference)
        }
        await waitForAttachmentOperationsToDrain()
        await waitForAttachmentCleanupsToDrain()
        await platform.stopSession()
        if let recordingDestination {
            await fileStore.discardRecording(at: recordingDestination)
        }
        finishCaptureTeardown(epoch: teardownEpoch, sessionHandle: sessionHandle)
        return sessionHandle
    }

    public func withMediaRead<T: Sendable>(
        mediaHandle: MediaHandle,
        operation: @Sendable (MediaReadAccess) async throws -> T
    ) async throws -> T {
        try ensureOpen()
        await processDeadlines()
        guard let record = media[mediaHandle] else {
            throw MediaCaptureFailure(.mediaInvalid)
        }
        guard record.state == .leased else {
            throw MediaCaptureFailure(.invalidState)
        }
        let source = try await fileStore.openSource(record.storedMedia.reference)
        await processDeadlines()
        guard let current = media[mediaHandle] else {
            source.close()
            throw MediaCaptureFailure(.mediaInvalid)
        }
        guard current.state == .leased,
              current.storedMedia.reference == record.storedMedia.reference,
              let leaseDeadline = current.stateDeadline,
              leaseDeadline > clock.now
        else {
            source.close()
            throw MediaCaptureFailure(.invalidState)
        }
        let scopeIdentifier = UUID()
        readScopes[scopeIdentifier] = (mediaHandle, source)
        let access = MediaReadAccess(
            byteLength: current.storedMedia.byteLength,
            contentType: current.storedMedia.contentType
        ) { try await source.readAll() }
        do {
            let result = try await operation(access)
            source.close()
            readScopes.removeValue(forKey: scopeIdentifier)
            return result
        } catch is CancellationError {
            source.close()
            readScopes.removeValue(forKey: scopeIdentifier)
            throw CancellationError()
        } catch {
            source.close()
            readScopes.removeValue(forKey: scopeIdentifier)
            throw error
        }
    }

    @discardableResult
    public func releaseMedia(mediaHandle: MediaHandle) async throws -> MediaHandle {
        try ensureMediaReleaseAllowed()
        await processDeadlines()
        guard var record = media[mediaHandle] else {
            throw MediaCaptureFailure(.mediaInvalid)
        }
        if record.state == .released { return mediaHandle }
        if record.state == .releaseGrace { return mediaHandle }
        if [.discarded, .expiryGrace, .expired].contains(record.state) {
            throw MediaCaptureFailure(.mediaInvalid)
        }
        guard record.state == .leased else {
            throw MediaCaptureFailure(.invalidState)
        }
        markThumbnailJobs(for: mediaHandle, winner: .release)
        let exportWorker = claimExportFailure(
            mediaHandle: mediaHandle,
            failure: .invalidState
        )
        record.state = .releaseGrace
        record.stateDeadline = clock.now.addingTimeInterval(configuration.readGracePeriod)
        media[mediaHandle] = record
        scheduleDeadline(key: mediaDeadlineKey(mediaHandle), at: record.stateDeadline ?? clock.now)
        if let exportWorker {
            _ = await exportWorker.result
        }
        return mediaHandle
    }

    public func readMediaThumbnail(
        mediaHandle: MediaHandle,
        maximumPixelEdge: Int
    ) async throws -> MediaThumbnail {
        try ensureOpen()
        await processDeadlines()
        guard (64 ... 512).contains(maximumPixelEdge) else {
            throw MediaCaptureFailure(.invalidArgument)
        }
        guard let record = media[mediaHandle] else {
            throw MediaCaptureFailure(.mediaInvalid)
        }
        guard record.state == .leased else {
            throw MediaCaptureFailure(.invalidState)
        }
        let reservedWorkingBytes = thumbnailJobs.values.reduce(0) {
            $0 + $1.reservedWorkingBytes
        }
        guard !thumbnailJobs.values.contains(where: { $0.mediaHandle == mediaHandle }),
              thumbnailJobs.count < 2,
              reservedWorkingBytes + thumbnailJobWorkingBytes <= thumbnailModuleWorkingBytes
        else {
            throw MediaCaptureFailure(.thumbnailOverloaded)
        }

        let identifier = UUID()
        let cancellation = CancellationSignal()
        let arbiter = ThumbnailOutcomeArbiter()
        thumbnailJobs[identifier] = ThumbnailJob(
            identifier: identifier,
            mediaHandle: mediaHandle,
            cancellation: cancellation,
            arbiter: arbiter,
            reservedWorkingBytes: thumbnailJobWorkingBytes
        )
        do {
            let source = try await fileStore.openSource(record.storedMedia.reference)
            guard var job = thumbnailJobs[identifier] else {
                source.close()
                throw MediaCaptureFailure(.thumbnailGenerationFailed)
            }
            job.source = source
            thumbnailJobs[identifier] = job
            let worker = ManagedThumbnailWorker(
                generator: thumbnailGenerator,
                source: source,
                media: record.storedMedia,
                maximumPixelEdge: maximumPixelEdge,
                cancellation: cancellation,
                onDecoderFailure: {
                    arbiter.tryWin(.decoderFailure)
                }
            )
            job.worker = worker
            thumbnailJobs[identifier] = job
            if job.arbiter.current != nil {
                cancellation.cancel()
                worker.cancel()
            }

            var generated = try await withTaskCancellationHandler {
                try await worker.value()
            } onCancel: {
                arbiter.tryWin(.callerCancelled)
                cancellation.cancel()
                worker.cancel()
            }
            return try completeThumbnailSuccess(
                identifier: identifier,
                generated: &generated,
                record: record,
                maximumPixelEdge: maximumPixelEdge
            )
        } catch is CancellationError {
            let winner = completeThumbnailFailure(identifier: identifier, proposedWinner: .callerCancelled)
            if winner == .callerCancelled { throw CancellationError() }
            throw thumbnailFailure(for: winner)
        } catch let failure as MediaCaptureFailure {
            let proposed: ThumbnailWinner = failure.id == .thumbnailGenerationCancelled
                ? .callerCancelled
                : .decoderFailure
            let winner = completeThumbnailFailure(identifier: identifier, proposedWinner: proposed)
            throw thumbnailFailure(for: winner)
        } catch {
            let winner = completeThumbnailFailure(identifier: identifier, proposedWinner: .decoderFailure)
            throw thumbnailFailure(for: winner)
        }
    }

    public func copyConfirmedMediaToSink(
        mediaHandle: MediaHandle,
        sink: any MediaCopySink,
        maximumLength: Int
    ) async throws -> MediaExportResult {
        try ensureOpen()
        await processDeadlines()
        guard (1 ... maximumExportBytes).contains(maximumLength) else {
            throw MediaCaptureFailure(.invalidArgument)
        }
        guard let record = media[mediaHandle] else {
            throw MediaCaptureFailure(.mediaInvalid)
        }
        guard record.state == .leased,
              let leaseDeadline = record.stateDeadline,
              leaseDeadline > clock.now
        else {
            throw MediaCaptureFailure(.invalidState)
        }
        try validateExportSource(record.storedMedia, maximumLength: maximumLength)
        if exportJobs[mediaHandle] != nil {
            throw MediaCaptureFailure(.mediaExportConflict)
        }
        let reservedWorkingBytes = exportJobs.count * exportReservedWorkingBytes
        guard exportJobs.count < 4,
              reservedWorkingBytes + exportReservedWorkingBytes <= exportModuleWorkingBytes
        else {
            throw MediaCaptureFailure(.mediaExportOverloaded)
        }

        let identifier = UUID()
        let control = MediaExportControl()
        exportJobs[mediaHandle] = ExportJob(
            identifier: identifier,
            mediaHandle: mediaHandle,
            control: control
        )
        let worker = Task { [weak self] in
            guard let self else { throw MediaCaptureFailure(.systemInterrupted) }
            return try await self.executeExport(
                identifier: identifier,
                mediaHandle: mediaHandle,
                storedMedia: record.storedMedia,
                sink: sink,
                control: control
            )
        }
        let deadlineAt = clock.now.addingTimeInterval(exportDeadlineSeconds)
        let clock = self.clock
        let deadline = Task { [weak self] in
            do {
                try await clock.sleep(until: deadlineAt)
                if !Task.isCancelled {
                    await self?.exportDeadlineElapsed(
                        mediaHandle: mediaHandle,
                        identifier: identifier
                    )
                }
            } catch is CancellationError {
            } catch {
                await self?.exportDeadlineElapsed(
                    mediaHandle: mediaHandle,
                    identifier: identifier
                )
            }
        }
        guard var registered = exportJobs[mediaHandle],
              registered.identifier == identifier
        else {
            worker.cancel()
            deadline.cancel()
            throw MediaCaptureFailure(.systemInterrupted)
        }
        registered.worker = worker
        registered.deadline = deadline
        exportJobs[mediaHandle] = registered

        do {
            return try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: {
                if control.claimFailure(.mediaExportCancelled) {
                    worker.cancel()
                }
            }
        } catch let failure as MediaCaptureFailure {
            throw failure
        } catch is CancellationError {
            throw MediaCaptureFailure(control.failure(or: .mediaExportCancelled))
        } catch {
            throw MediaCaptureFailure(control.failure(or: .mediaExportReadFailed))
        }
    }

    public func attachLivePreview(
        sessionHandle: SessionHandle,
        surfaceOwner: MediaCaptureRenderSurfaceOwner
    ) async throws -> RenderAttachmentResult {
        try ensureOpen()
        await processDeadlines()
        let ownerGeneration = surfaceOwner.ownerGeneration
        guard ownerGeneration > 0 else { throw MediaCaptureFailure(.invalidArgument) }
        guard let endpoint = surfaceOwner.endpointSnapshot(),
              await endpoint.isBackingAvailable()
        else {
            throw MediaCaptureFailure(.invalidArgument)
        }
        guard var session = sessions[sessionHandle] else {
            throw MediaCaptureFailure(.sessionInvalid)
        }
        guard [.ready, .recording].contains(session.state) else {
            throw MediaCaptureFailure(.invalidState)
        }
        attachmentOperationCount += 1
        var attachmentOperationRegistered = true
        defer {
            if attachmentOperationRegistered { finishAttachmentOperation() }
        }
        let identifier = endpoint.identity
        guard session.liveAttachment.reservation == nil,
              !session.liveAttachment.cleanupInProgress
        else {
            throw MediaCaptureFailure(.attachmentTargetConflict)
        }
        if let binding = session.liveAttachment.binding,
           binding.generation == ownerGeneration {
            if binding.targetIdentifier == identifier,
               binding.surfaceOwner.value != nil,
               await endpoint.isBackingAvailable() {
                guard let current = sessions[sessionHandle]?.liveAttachment.binding,
                      current.generation == ownerGeneration,
                      current.targetIdentifier == identifier,
                      sessions[sessionHandle]?.liveAttachment.cleanupInProgress == false
                else { throw MediaCaptureFailure(.attachmentTargetConflict) }
                return RenderAttachmentResult(
                    kind: .livePreview,
                    ownerGeneration: ownerGeneration
                )
            }
            throw MediaCaptureFailure(.attachmentTargetConflict)
        }
        guard ownerGeneration > session.liveAttachment.highWatermark else {
            throw MediaCaptureFailure(.attachmentGenerationRetired)
        }

        let reservationIdentifier = UUID()
        let attachmentEpoch = lifecycleEpoch
        let context = RenderAttachmentContext(kind: .livePreview, ownerGeneration: ownerGeneration)
        let gate = MediaCaptureRenderCallbackGate(
            mountBody: { [weak self, weak surfaceOwner] in
                guard let self, let surfaceOwner,
                      surfaceOwner.endpointSnapshot()?.identity == identifier,
                      await endpoint.isBackingAvailable()
                else { return false }
                return await self.isLiveRenderMountReservationActive(
                    sessionHandle: sessionHandle,
                    reservationIdentifier: reservationIdentifier
                )
            },
            activeBody: { [weak self] in
                await self?.isRenderCallbackActive(
                    kind: .livePreview,
                    sessionHandle: sessionHandle,
                    mediaHandle: nil,
                    ownerGeneration: ownerGeneration,
                    targetIdentifier: identifier,
                    epoch: attachmentEpoch
                ) ?? false
            }
        )
        let oldBinding = session.liveAttachment.binding
        oldBinding?.renderBinding.invalidateGate()
        session.liveAttachment.highWatermark = ownerGeneration
        session.liveAttachment.reservation = AttachmentReservation(
            identifier: reservationIdentifier,
            generation: ownerGeneration,
            targetIdentifier: identifier,
            surfaceOwner: WeakRenderSurfaceOwner(surfaceOwner),
            mountEndpoint: endpoint,
            callbackGate: gate,
            lifecycleEpoch: attachmentEpoch
        )
        session.liveAttachment.cleanupInProgress = oldBinding != nil
        sessions[sessionHandle] = session
        surfaceOwner.setInvalidationHandler(for: identifier) { [weak self] in
            Task {
                await self?.renderOwnerDestroyed(
                    kind: .livePreview,
                    sessionHandle: sessionHandle,
                    mediaHandle: nil,
                    ownerGeneration: ownerGeneration,
                    targetIdentifier: identifier
                )
            }
        }
        if let oldBinding {
            await detachBinding(oldBinding, kind: .livePreview, emitEvent: true)
            finishLiveBindingCleanup(sessionHandle: sessionHandle, binding: oldBinding)
        }
        var uncommittedBinding: MediaCaptureRenderBinding?
        do {
            try validateLiveAttachmentReservation(
                sessionHandle: sessionHandle,
                reservationIdentifier: reservationIdentifier
            )
            let source = try await platform.liveRenderSource()
            try validateLiveAttachmentReservation(
                sessionHandle: sessionHandle,
                reservationIdentifier: reservationIdentifier
            )
            let renderBinding = try await endpoint.mount(
                source: source,
                context: context,
                callbackGate: gate
            )
            uncommittedBinding = renderBinding
            guard surfaceOwner.endpointSnapshot()?.identity == identifier,
                  await endpoint.isBackingAvailable()
            else {
                throw MediaCaptureFailure(.attachmentGenerationRetired)
            }
            guard var current = sessions[sessionHandle],
                  [.ready, .recording].contains(current.state),
                  current.liveAttachment.reservation?.identifier == reservationIdentifier,
                  current.liveAttachment.binding == nil,
                  !current.liveAttachment.cleanupInProgress,
                  lifecycleEpoch == attachmentEpoch
            else {
                throw MediaCaptureFailure(.attachmentGenerationRetired)
            }
            current.liveAttachment.binding = AttachmentBinding(
                generation: ownerGeneration,
                targetIdentifier: identifier,
                surfaceOwner: WeakRenderSurfaceOwner(surfaceOwner),
                mountEndpoint: endpoint,
                renderSource: source,
                renderBinding: renderBinding
            )
            current.liveAttachment.reservation = nil
            sessions[sessionHandle] = current
            uncommittedBinding = nil
            _ = await gate.performIfActive { endpoint.didAttach(context) }
            return RenderAttachmentResult(kind: .livePreview, ownerGeneration: ownerGeneration)
        } catch is CancellationError {
            cancelLiveAttachmentReservation(
                sessionHandle: sessionHandle,
                reservationIdentifier: reservationIdentifier
            )
            if let uncommittedBinding {
                await revokeUncommittedTarget(
                    surfaceOwner,
                    endpoint: endpoint,
                    context: context,
                    renderBinding: uncommittedBinding
                )
            } else {
                surfaceOwner.setInvalidationHandler(for: identifier, nil)
            }
            throw CancellationError()
        } catch let failure as MediaCaptureFailure {
            cancelLiveAttachmentReservation(
                sessionHandle: sessionHandle,
                reservationIdentifier: reservationIdentifier
            )
            if let uncommittedBinding {
                await revokeUncommittedTarget(
                    surfaceOwner,
                    endpoint: endpoint,
                    context: context,
                    renderBinding: uncommittedBinding
                )
            } else {
                surfaceOwner.setInvalidationHandler(for: identifier, nil)
            }
            let mapped = mapFailure(failure, for: .attachLivePreview)
            if mapped.terminal {
                attachmentOperationRegistered = false
                finishAttachmentOperation()
                await failSession(sessionHandle, failure: mapped)
            }
            throw mapped
        } catch {
            cancelLiveAttachmentReservation(
                sessionHandle: sessionHandle,
                reservationIdentifier: reservationIdentifier
            )
            if let uncommittedBinding {
                await revokeUncommittedTarget(
                    surfaceOwner,
                    endpoint: endpoint,
                    context: context,
                    renderBinding: uncommittedBinding
                )
            } else {
                surfaceOwner.setInvalidationHandler(for: identifier, nil)
            }
            let mapped = mapFailure(error, for: .attachLivePreview)
            if mapped.terminal {
                attachmentOperationRegistered = false
                finishAttachmentOperation()
                await failSession(sessionHandle, failure: mapped)
            }
            throw mapped
        }
    }

    public func detachLivePreview(
        sessionHandle: SessionHandle,
        surfaceOwner: MediaCaptureRenderSurfaceOwner
    ) async throws -> RenderAttachmentResult {
        try ensureOpen()
        let ownerGeneration = surfaceOwner.ownerGeneration
        guard ownerGeneration > 0 else { throw MediaCaptureFailure(.invalidArgument) }
        guard var session = sessions[sessionHandle] else {
            throw MediaCaptureFailure(.sessionInvalid)
        }
        guard let identifier = surfaceOwner.installedEndpointIdentifierSnapshot() else {
            return RenderAttachmentResult(kind: .livePreview, ownerGeneration: ownerGeneration)
        }
        if let reservation = session.liveAttachment.reservation,
           reservation.generation == ownerGeneration,
           reservation.targetIdentifier == identifier {
            reservation.callbackGate.invalidate()
            session.liveAttachment.reservation = nil
            surfaceOwner.setInvalidationHandler(for: identifier, nil)
        }
        if let binding = session.liveAttachment.binding,
           binding.generation == ownerGeneration,
           binding.targetIdentifier == identifier {
            binding.renderBinding.invalidateGate()
            if session.liveAttachment.cleanupInProgress {
                sessions[sessionHandle] = session
                return RenderAttachmentResult(kind: .livePreview, ownerGeneration: ownerGeneration)
            }
            session.liveAttachment.cleanupInProgress = true
            sessions[sessionHandle] = session
            await detachBinding(binding, kind: .livePreview, emitEvent: false)
            finishLiveBindingCleanup(sessionHandle: sessionHandle, binding: binding)
        } else {
            sessions[sessionHandle] = session
        }
        return RenderAttachmentResult(kind: .livePreview, ownerGeneration: ownerGeneration)
    }

    public func attachUnconfirmedPreviewRender(
        mediaHandle: MediaHandle,
        surfaceOwner: MediaCaptureRenderSurfaceOwner
    ) async throws -> RenderAttachmentResult {
        try ensureOpen()
        await processDeadlines()
        let ownerGeneration = surfaceOwner.ownerGeneration
        guard ownerGeneration > 0 else { throw MediaCaptureFailure(.invalidArgument) }
        guard let endpoint = surfaceOwner.endpointSnapshot(),
              await endpoint.isBackingAvailable()
        else {
            throw MediaCaptureFailure(.invalidArgument)
        }
        guard var record = media[mediaHandle] else {
            throw MediaCaptureFailure(.mediaInvalid)
        }
        guard record.state == .preview else { throw MediaCaptureFailure(.invalidState) }
        attachmentOperationCount += 1
        var attachmentOperationRegistered = true
        defer {
            if attachmentOperationRegistered { finishAttachmentOperation() }
        }
        let identifier = endpoint.identity
        guard record.previewAttachment.reservation == nil,
              !record.previewAttachment.cleanupInProgress
        else {
            throw MediaCaptureFailure(.attachmentTargetConflict)
        }
        if let binding = record.previewAttachment.binding,
           binding.generation == ownerGeneration {
            if binding.targetIdentifier == identifier,
               binding.surfaceOwner.value != nil,
               await endpoint.isBackingAvailable() {
                guard let current = media[mediaHandle]?.previewAttachment.binding,
                      current.generation == ownerGeneration,
                      current.targetIdentifier == identifier,
                      media[mediaHandle]?.previewAttachment.cleanupInProgress == false
                else { throw MediaCaptureFailure(.attachmentTargetConflict) }
                return RenderAttachmentResult(
                    kind: .unconfirmedPreview,
                    ownerGeneration: ownerGeneration
                )
            }
            throw MediaCaptureFailure(.attachmentTargetConflict)
        }
        guard ownerGeneration > record.previewAttachment.highWatermark else {
            throw MediaCaptureFailure(.attachmentGenerationRetired)
        }
        let reservationIdentifier = UUID()
        let attachmentEpoch = lifecycleEpoch
        let context = RenderAttachmentContext(
            kind: .unconfirmedPreview,
            ownerGeneration: ownerGeneration
        )
        let gate = MediaCaptureRenderCallbackGate(
            mountBody: { [weak self, weak surfaceOwner] in
                guard let self, let surfaceOwner,
                      surfaceOwner.endpointSnapshot()?.identity == identifier,
                      await endpoint.isBackingAvailable()
                else { return false }
                return await self.isPreviewRenderMountReservationActive(
                    mediaHandle: mediaHandle,
                    reservationIdentifier: reservationIdentifier
                )
            },
            activeBody: { [weak self] in
                await self?.isRenderCallbackActive(
                    kind: .unconfirmedPreview,
                    sessionHandle: nil,
                    mediaHandle: mediaHandle,
                    ownerGeneration: ownerGeneration,
                    targetIdentifier: identifier,
                    epoch: attachmentEpoch
                ) ?? false
            }
        )
        let oldBinding = record.previewAttachment.binding
        oldBinding?.renderBinding.invalidateGate()
        record.previewAttachment.highWatermark = ownerGeneration
        record.previewAttachment.reservation = AttachmentReservation(
            identifier: reservationIdentifier,
            generation: ownerGeneration,
            targetIdentifier: identifier,
            surfaceOwner: WeakRenderSurfaceOwner(surfaceOwner),
            mountEndpoint: endpoint,
            callbackGate: gate,
            lifecycleEpoch: attachmentEpoch
        )
        record.previewAttachment.cleanupInProgress = oldBinding != nil
        media[mediaHandle] = record
        surfaceOwner.setInvalidationHandler(for: identifier) { [weak self] in
            Task {
                await self?.renderOwnerDestroyed(
                    kind: .unconfirmedPreview,
                    sessionHandle: nil,
                    mediaHandle: mediaHandle,
                    ownerGeneration: ownerGeneration,
                    targetIdentifier: identifier
                )
            }
        }
        if let oldBinding {
            await detachBinding(oldBinding, kind: .unconfirmedPreview, emitEvent: true)
            finishPreviewBindingCleanup(mediaHandle: mediaHandle, binding: oldBinding)
        }
        var uncommittedBinding: MediaCaptureRenderBinding?
        do {
            try validatePreviewAttachmentReservation(
                mediaHandle: mediaHandle,
                reservationIdentifier: reservationIdentifier
            )
            let source = try await fileStore.previewRenderSource(record.storedMedia)
            try validatePreviewAttachmentReservation(
                mediaHandle: mediaHandle,
                reservationIdentifier: reservationIdentifier
            )
            let renderBinding = try await endpoint.mount(
                source: source,
                context: context,
                callbackGate: gate
            )
            uncommittedBinding = renderBinding
            guard surfaceOwner.endpointSnapshot()?.identity == identifier,
                  await endpoint.isBackingAvailable()
            else {
                throw MediaCaptureFailure(.attachmentGenerationRetired)
            }
            guard var current = media[mediaHandle],
                  current.state == .preview,
                  current.previewAttachment.reservation?.identifier == reservationIdentifier,
                  current.previewAttachment.binding == nil,
                  !current.previewAttachment.cleanupInProgress,
                  lifecycleEpoch == attachmentEpoch
            else {
                throw MediaCaptureFailure(.attachmentGenerationRetired)
            }
            current.previewAttachment.binding = AttachmentBinding(
                generation: ownerGeneration,
                targetIdentifier: identifier,
                surfaceOwner: WeakRenderSurfaceOwner(surfaceOwner),
                mountEndpoint: endpoint,
                renderSource: source,
                renderBinding: renderBinding
            )
            current.previewAttachment.reservation = nil
            media[mediaHandle] = current
            uncommittedBinding = nil
            _ = await gate.performIfActive { endpoint.didAttach(context) }
            return RenderAttachmentResult(kind: .unconfirmedPreview, ownerGeneration: ownerGeneration)
        } catch is CancellationError {
            cancelPreviewAttachmentReservation(
                mediaHandle: mediaHandle,
                reservationIdentifier: reservationIdentifier
            )
            if let uncommittedBinding {
                await revokeUncommittedTarget(
                    surfaceOwner,
                    endpoint: endpoint,
                    context: context,
                    renderBinding: uncommittedBinding
                )
            } else {
                surfaceOwner.setInvalidationHandler(for: identifier, nil)
            }
            throw CancellationError()
        } catch let failure as MediaCaptureFailure {
            cancelPreviewAttachmentReservation(
                mediaHandle: mediaHandle,
                reservationIdentifier: reservationIdentifier
            )
            if let uncommittedBinding {
                await revokeUncommittedTarget(
                    surfaceOwner,
                    endpoint: endpoint,
                    context: context,
                    renderBinding: uncommittedBinding
                )
            } else {
                surfaceOwner.setInvalidationHandler(for: identifier, nil)
            }
            let mapped = mapFailure(failure, for: .attachUnconfirmedPreview)
            if mapped.terminal, let sessionHandle = media[mediaHandle]?.sessionHandle {
                attachmentOperationRegistered = false
                finishAttachmentOperation()
                await failSession(sessionHandle, failure: mapped)
            }
            throw mapped
        } catch {
            cancelPreviewAttachmentReservation(
                mediaHandle: mediaHandle,
                reservationIdentifier: reservationIdentifier
            )
            if let uncommittedBinding {
                await revokeUncommittedTarget(
                    surfaceOwner,
                    endpoint: endpoint,
                    context: context,
                    renderBinding: uncommittedBinding
                )
            } else {
                surfaceOwner.setInvalidationHandler(for: identifier, nil)
            }
            let mapped = mapFailure(error, for: .attachUnconfirmedPreview)
            if mapped.terminal, let sessionHandle = media[mediaHandle]?.sessionHandle {
                attachmentOperationRegistered = false
                finishAttachmentOperation()
                await failSession(sessionHandle, failure: mapped)
            }
            throw mapped
        }
    }

    public func detachUnconfirmedPreviewRender(
        mediaHandle: MediaHandle,
        surfaceOwner: MediaCaptureRenderSurfaceOwner
    ) async throws -> RenderAttachmentResult {
        try ensureOpen()
        let ownerGeneration = surfaceOwner.ownerGeneration
        guard ownerGeneration > 0 else { throw MediaCaptureFailure(.invalidArgument) }
        guard var record = media[mediaHandle] else {
            throw MediaCaptureFailure(.mediaInvalid)
        }
        guard let identifier = surfaceOwner.installedEndpointIdentifierSnapshot() else {
            return RenderAttachmentResult(kind: .unconfirmedPreview, ownerGeneration: ownerGeneration)
        }
        if let reservation = record.previewAttachment.reservation,
           reservation.generation == ownerGeneration,
           reservation.targetIdentifier == identifier {
            reservation.callbackGate.invalidate()
            record.previewAttachment.reservation = nil
            surfaceOwner.setInvalidationHandler(for: identifier, nil)
        }
        if let binding = record.previewAttachment.binding,
           binding.generation == ownerGeneration,
           binding.targetIdentifier == identifier {
            binding.renderBinding.invalidateGate()
            if record.previewAttachment.cleanupInProgress {
                media[mediaHandle] = record
                return RenderAttachmentResult(
                    kind: .unconfirmedPreview,
                    ownerGeneration: ownerGeneration
                )
            }
            record.previewAttachment.cleanupInProgress = true
            media[mediaHandle] = record
            await detachBinding(
                binding,
                kind: .unconfirmedPreview,
                emitEvent: false
            )
            finishPreviewBindingCleanup(mediaHandle: mediaHandle, binding: binding)
        } else {
            media[mediaHandle] = record
        }
        return RenderAttachmentResult(kind: .unconfirmedPreview, ownerGeneration: ownerGeneration)
    }

    public func displayRotationChanged() async {
        lifecycleEpoch &+= 1
        await revokeAllRenderAttachments()
        await waitForAttachmentOperationsToDrain()
        await waitForAttachmentCleanupsToDrain()
    }

    public func appDidEnterBackground() async {
        lifecycleEpoch &+= 1
        await revokeAllRenderAttachments()
        await waitForAttachmentOperationsToDrain()
        await waitForAttachmentCleanupsToDrain()
    }

    public func appRestarted() async {
        guard !closed, moduleLifecycleState != .restarting else { return }
        moduleLifecycleState = .restarting
        lifecycleEpoch &+= 1
        let partialRecordings = invalidateRegistriesForShutdown()
        let exportWorkers = claimAllExportFailures(.systemInterrupted)
        preparationTasks.values.forEach { $0.cancel() }
        deadlineTasks.values.forEach { $0.task.cancel() }
        preparationTasks.removeAll()
        deadlineTasks.removeAll()
        markAllThumbnailJobs(winner: .restart)
        await revokeAllRenderAttachments()
        await waitForAttachmentOperationsToDrain()
        await waitForAttachmentCleanupsToDrain()
        await platform.stopSession()
        for destination in partialRecordings {
            await fileStore.discardRecording(at: destination)
        }
        await waitForThumbnailJobsToDrain()
        for worker in exportWorkers {
            _ = await worker.result
        }
        await waitForExportJobsToDrain()
        readScopes.values.forEach { $0.source.close() }
        readScopes.removeAll()
        for record in media.values {
            await fileStore.delete(record.storedMedia.reference)
        }
        sessions.removeAll()
        media.removeAll()
        activeSessionHandle = nil
        await fileStore.removeTemporaryResidue()
        if !closed, moduleLifecycleState == .restarting {
            moduleLifecycleState = .idle
        }
    }

    public func close() async {
        guard !closed else { return }
        closed = true
        moduleLifecycleState = .closed
        lifecycleEpoch &+= 1
        let partialRecordings = invalidateRegistriesForShutdown()
        let exportWorkers = claimAllExportFailures(.systemInterrupted)
        preparationTasks.values.forEach { $0.cancel() }
        deadlineTasks.values.forEach { $0.task.cancel() }
        preparationTasks.removeAll()
        deadlineTasks.removeAll()
        markAllThumbnailJobs(winner: .restart)
        await revokeAllRenderAttachments()
        await waitForAttachmentOperationsToDrain()
        await waitForAttachmentCleanupsToDrain()
        await platform.close()
        for destination in partialRecordings {
            await fileStore.discardRecording(at: destination)
        }
        await waitForThumbnailJobsToDrain()
        for worker in exportWorkers {
            _ = await worker.result
        }
        await waitForExportJobsToDrain()
        platformEventTask?.cancel()
        platformEventTask = nil
        readScopes.values.forEach { $0.source.close() }
        readScopes.removeAll()
        for record in media.values {
            await fileStore.delete(record.storedMedia.reference)
        }
        sessions.removeAll()
        media.removeAll()
        activeSessionHandle = nil
        eventContinuations.values.forEach { $0.finish() }
        eventContinuations.removeAll()
    }

    private func invalidateRegistriesForShutdown() -> [URL] {
        var partialRecordings: [URL] = []
        for handle in Array(sessions.keys) {
            guard var session = sessions[handle] else { continue }
            session.operationGeneration &+= 1
            session.operationInFlight = false
            if ![SessionState.completed, .cancelled, .failed].contains(session.state) {
                session.state = .failed
                session.terminalAt = clock.now
            }
            if let destination = session.recordingDestination {
                partialRecordings.append(destination)
            }
            sessions[handle] = session
        }
        for handle in Array(media.keys) {
            guard var record = media[handle] else { continue }
            record.operationGeneration &+= 1
            record.operationInFlight = false
            record.state = record.state == .preview ? .discarded : .expired
            record.stateDeadline = nil
            record.terminalAt = clock.now
            media[handle] = record
        }
        activeSessionHandle = nil
        return partialRecordings
    }

    internal func processDeadlines() async {
        let now = clock.now
        let previewHandles = media.values
            .filter { $0.state == .preview && ($0.stateDeadline ?? .distantFuture) <= now }
            .map(\.handle)
        for handle in previewHandles {
            guard let record = media[handle] else { continue }
            await failSession(record.sessionHandle, failure: MediaCaptureFailure(.sessionTimeout))
        }

        let leaseHandles = media.values
            .filter { $0.state == .leased && ($0.stateDeadline ?? .distantFuture) <= now }
            .map(\.handle)
        for handle in leaseHandles {
            guard var record = media[handle], record.state == .leased else { continue }
            markThumbnailJobs(for: handle, winner: .expiry)
            let exportWorker = claimExportFailure(
                mediaHandle: handle,
                failure: .invalidState
            )
            record.state = .expiryGrace
            record.stateDeadline = now.addingTimeInterval(configuration.readGracePeriod)
            media[handle] = record
            yield(.mediaLeaseExpired(handle))
            scheduleDeadline(key: mediaDeadlineKey(handle), at: record.stateDeadline ?? now)
            if let exportWorker {
                _ = await exportWorker.result
            }
        }

        let graceHandles = media.values
            .filter {
                [.releaseGrace, .expiryGrace].contains($0.state) &&
                    ($0.stateDeadline ?? .distantFuture) <= now
            }
            .map(\.handle)
        for handle in graceHandles {
            guard var record = media[handle],
                  [.releaseGrace, .expiryGrace].contains(record.state),
                  (record.stateDeadline ?? .distantFuture) <= now
            else { continue }
            let finalState: MediaState = record.state == .releaseGrace ? .released : .expired
            record.state = finalState
            record.stateDeadline = nil
            record.terminalAt = now
            media[handle] = record
            cancelDeadline(mediaDeadlineKey(handle))
            revokeReadScopes(for: handle)
            await fileStore.delete(record.storedMedia.reference)
            yield(.mediaReadRevoked(handle))
        }

        let expiredSessionHandles = sessions.values.compactMap { record -> SessionHandle? in
            guard let terminalAt = record.terminalAt,
                  now.timeIntervalSince(terminalAt) > configuration.tombstoneTimeToLive
            else { return nil }
            return record.handle
        }
        let expiredMediaHandles = media.values.compactMap { record -> MediaHandle? in
            guard let terminalAt = record.terminalAt,
                  now.timeIntervalSince(terminalAt) > configuration.tombstoneTimeToLive
            else { return nil }
            return record.handle
        }
        for handle in expiredSessionHandles {
            cancelDeadline(recordingDeadlineKey(handle))
            sessions.removeValue(forKey: handle)
        }
        for handle in expiredMediaHandles {
            cancelDeadline(mediaDeadlineKey(handle))
            media.removeValue(forKey: handle)
        }
    }

    private func executeExport(
        identifier: UUID,
        mediaHandle: MediaHandle,
        storedMedia: StoredMedia,
        sink: any MediaCopySink,
        control: MediaExportControl
    ) async throws -> MediaExportResult {
        var activeChunk: MediaCopyChunk?
        do {
            let source: MediaSourceAccess
            do {
                source = try await fileStore.openSource(storedMedia.reference)
            } catch is CancellationError {
                if control.hasFailureWinner { throw CancellationError() }
                throw MediaCaptureFailure(.mediaExportReadFailed)
            } catch {
                throw MediaCaptureFailure(.mediaExportReadFailed)
            }
            guard control.installSource(source) else {
                throw CancellationError()
            }
            try control.checkActive()

            do {
                try await sink.begin(
                    mediaType: storedMedia.mediaType,
                    contentType: storedMedia.contentType,
                    byteLength: storedMedia.byteLength
                )
                control.markSinkBegun()
                try control.checkActive()
            } catch is CancellationError {
                if control.hasFailureWinner { throw CancellationError() }
                throw MediaCaptureFailure(.mediaExportSinkRejected)
            } catch {
                throw MediaCaptureFailure(.mediaExportSinkRejected)
            }

            var copied = 0
            while true {
                try control.checkActive()
                var bytes: Data?
                do {
                    bytes = try await exportExecutor.execute {
                        try source.readChunk(maximumLength: self.exportReadBufferBytes)
                    }
                } catch is CancellationError {
                    if control.hasFailureWinner { throw CancellationError() }
                    throw MediaCaptureFailure(.mediaExportReadFailed)
                } catch {
                    throw MediaCaptureFailure(.mediaExportReadFailed)
                }
                guard var bytes else { break }
                exportBufferAccounting?.allocationChanged(
                    jobIdentifier: identifier,
                    delta: bytes.count
                )
                do {
                    try control.checkActive()
                } catch {
                    wipeExportReadBuffer(&bytes, identifier: identifier)
                    throw error
                }
                guard !bytes.isEmpty, bytes.count <= exportReadBufferBytes else {
                    wipeExportReadBuffer(&bytes, identifier: identifier)
                    throw MediaCaptureFailure(.mediaExportTooLarge)
                }
                let (nextLength, overflow) = copied.addingReportingOverflow(bytes.count)
                guard !overflow,
                      nextLength <= storedMedia.byteLength,
                      nextLength <= maximumExportBytes
                else {
                    wipeExportReadBuffer(&bytes, identifier: identifier)
                    throw MediaCaptureFailure(.mediaExportTooLarge)
                }
                let chunk = MediaCopyChunk(bytes)
                exportBufferAccounting?.allocationChanged(
                    jobIdentifier: identifier,
                    delta: chunk.byteCount
                )
                wipeExportReadBuffer(&bytes, identifier: identifier)
                activeChunk = chunk
                do {
                    try await sink.write(chunk)
                } catch is CancellationError {
                    if control.hasFailureWinner { throw CancellationError() }
                    throw MediaCaptureFailure(.mediaExportWriteFailed)
                } catch {
                    throw MediaCaptureFailure(.mediaExportWriteFailed)
                }
                invalidateExportChunk(chunk, identifier: identifier)
                activeChunk = nil
                copied = nextLength
                try control.checkActive()
            }
            guard copied == storedMedia.byteLength else {
                throw MediaCaptureFailure(.mediaExportTooLarge)
            }
            guard prepareExportCommit(
                mediaHandle: mediaHandle,
                identifier: identifier,
                storedMedia: storedMedia,
                control: control
            ) else {
                throw CancellationError()
            }

            do {
                try control.checkActive()
                try await sink.commit(byteLength: copied)
            } catch is CancellationError {
                if control.hasFailureWinner { throw CancellationError() }
                throw MediaCaptureFailure(.mediaExportSinkRejected)
            } catch {
                throw MediaCaptureFailure(.mediaExportSinkRejected)
            }
            if let exportCommitReturned {
                await exportCommitReturned()
            }
            switch control.completeSuccessfulCommit() {
            case .succeeded:
                break
            case let .failed(failure):
                throw MediaCaptureFailure(failure)
            }

            if let activeChunk {
                invalidateExportChunk(activeChunk, identifier: identifier)
            }
            control.closeSource()
            finishExportRegistration(mediaHandle: mediaHandle, identifier: identifier)
            return MediaExportResult(
                mediaHandle: mediaHandle,
                mediaType: storedMedia.mediaType,
                contentType: storedMedia.contentType,
                byteLength: copied
            )
        } catch {
            if let activeChunk {
                invalidateExportChunk(activeChunk, identifier: identifier)
            }
            let fallback = exportFailureID(for: error)
            let failure = control.finishCommitFailure(fallback: fallback)
            if control.claimAbortIfNeeded() {
                let abortTask = Task {
                    try? await sink.abort()
                }
                await abortTask.value
            }
            control.closeSource()
            finishExportRegistration(mediaHandle: mediaHandle, identifier: identifier)
            throw MediaCaptureFailure(failure)
        }
    }

    private func prepareExportCommit(
        mediaHandle: MediaHandle,
        identifier: UUID,
        storedMedia: StoredMedia,
        control: MediaExportControl
    ) -> Bool {
        guard exportJobs[mediaHandle]?.identifier == identifier,
              var record = media[mediaHandle],
              record.storedMedia.reference == storedMedia.reference
        else {
            control.claimFailure(.invalidState)
            return false
        }
        guard record.state == .leased else {
            control.claimFailure(.invalidState)
            return false
        }
        guard let leaseDeadline = record.stateDeadline,
              leaseDeadline > clock.now
        else {
            markThumbnailJobs(for: mediaHandle, winner: .expiry)
            record.state = .expiryGrace
            record.stateDeadline = clock.now.addingTimeInterval(configuration.readGracePeriod)
            media[mediaHandle] = record
            control.claimFailure(.invalidState)
            yield(.mediaLeaseExpired(mediaHandle))
            scheduleDeadline(
                key: mediaDeadlineKey(mediaHandle),
                at: record.stateDeadline ?? clock.now
            )
            return false
        }
        return control.prepareCommit()
    }

    private func validateExportSource(
        _ storedMedia: StoredMedia,
        maximumLength: Int
    ) throws {
        let expectedContentType: String
        switch storedMedia.mediaType {
        case .photo:
            expectedContentType = "image/jpeg"
        case .video:
            expectedContentType = "video/mp4"
        }
        guard storedMedia.contentType == expectedContentType else {
            throw MediaCaptureFailure(.invalidState)
        }
        guard storedMedia.byteLength > 0,
              storedMedia.byteLength <= maximumLength,
              storedMedia.byteLength <= maximumExportBytes
        else {
            throw MediaCaptureFailure(.mediaExportTooLarge)
        }
    }

    private func exportFailureID(for error: Error) -> MediaCaptureFailure.ID {
        if error is CancellationError {
            return .systemInterrupted
        }
        if let failure = error as? MediaCaptureFailure {
            switch failure.id {
            case .mediaExportTooLarge, .mediaExportSinkRejected,
                 .mediaExportReadFailed, .mediaExportWriteFailed:
                return failure.id
            default:
                return .mediaExportReadFailed
            }
        }
        return .mediaExportReadFailed
    }

    private func exportDeadlineElapsed(mediaHandle: MediaHandle, identifier: UUID) {
        guard let job = exportJobs[mediaHandle], job.identifier == identifier else { return }
        if job.control.claimFailure(.mediaExportTimedOut) {
            job.worker?.cancel()
        }
    }

    private func claimExportFailure(
        mediaHandle: MediaHandle,
        failure: MediaCaptureFailure.ID
    ) -> Task<MediaExportResult, Error>? {
        guard let job = exportJobs[mediaHandle] else { return nil }
        if job.control.claimFailure(failure) {
            job.worker?.cancel()
        }
        return job.worker
    }

    private func claimAllExportFailures(
        _ failure: MediaCaptureFailure.ID
    ) -> [Task<MediaExportResult, Error>] {
        exportJobs.values.compactMap { job in
            if job.control.claimFailure(failure) {
                job.worker?.cancel()
            }
            return job.worker
        }
    }

    private func finishExportRegistration(mediaHandle: MediaHandle, identifier: UUID) {
        guard let job = exportJobs[mediaHandle], job.identifier == identifier else { return }
        job.deadline?.cancel()
        exportJobs.removeValue(forKey: mediaHandle)
        if exportJobs.isEmpty {
            let waiters = exportDrainWaiters
            exportDrainWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }

    private func waitForExportJobsToDrain() async {
        if exportJobs.isEmpty { return }
        await withCheckedContinuation { continuation in
            exportDrainWaiters.append(continuation)
        }
    }

    private func wipe(_ data: inout Data) {
        if !data.isEmpty {
            data.withUnsafeMutableBytes { buffer in
                if let baseAddress = buffer.baseAddress {
                    memset(baseAddress, 0, buffer.count)
                }
            }
            data.removeAll(keepingCapacity: false)
        }
    }

    private func wipeExportReadBuffer(_ data: inout Data, identifier: UUID) {
        let byteCount = data.count
        wipe(&data)
        if byteCount > 0 {
            exportBufferAccounting?.allocationChanged(
                jobIdentifier: identifier,
                delta: -byteCount
            )
        }
    }

    private func invalidateExportChunk(_ chunk: MediaCopyChunk, identifier: UUID) {
        let releasedBytes = chunk.invalidate()
        if releasedBytes > 0 {
            exportBufferAccounting?.allocationChanged(
                jobIdentifier: identifier,
                delta: -releasedBytes
            )
        }
    }

    internal func pendingDeadlineTaskCount() -> Int {
        deadlineTasks.count
    }

    internal func exportReservationSnapshot() -> (jobCount: Int, reservedWorkingBytes: Int) {
        (exportJobs.count, exportJobs.count * exportReservedWorkingBytes)
    }

    private func prepareSession(_ handle: SessionHandle) async {
        do {
            guard let initial = sessions[handle] else { return }
            let setupEpoch = initial.creationEpoch
            let cameraState = try await resolvePermission(.camera)
            guard lifecycleEpoch == setupEpoch else {
                throw PlatformFailure.interrupted
            }
            guard cameraState == .granted else {
                throw permissionFailure(for: cameraState)
            }
            guard var record = sessions[handle], record.state == .requestingPermission else { return }
            record.state = .preparing
            sessions[handle] = record
            let platformSnapshot = try await platform.prepare(options: record.options)
            let snapshot = try publicSnapshot(platformSnapshot, handle: handle)
            guard var current = sessions[handle], current.state == .preparing else {
                await platform.stopSession()
                return
            }
            guard lifecycleEpoch == setupEpoch else {
                await platform.stopSession()
                throw PlatformFailure.interrupted
            }
            current.state = .ready
            current.readySnapshot = snapshot
            sessions[handle] = current
            preparationTasks.removeValue(forKey: handle)
            yield(.sessionReady(snapshot))
        } catch is CancellationError {
            return
        } catch {
            let failure = mapFailure(error, for: .startSession)
            await failSession(handle, failure: failure)
        }
    }

    private func resolvePermission(_ resource: PermissionResource) async throws -> PermissionState {
        let current = await platform.permissionState(for: resource)
        if current == .notDetermined {
            return await platform.requestPermission(for: resource)
        }
        return current
    }

    private func permissionFailure(for state: PermissionState) -> MediaCaptureFailure {
        switch state {
        case .denied:
            return MediaCaptureFailure(.permissionDenied)
        case .restricted:
            return MediaCaptureFailure(.permissionRestricted)
        case .permanentlyDenied:
            return MediaCaptureFailure(.permissionPermanentlyDenied)
        case .unsupported, .notDetermined:
            return MediaCaptureFailure(.unsupportedCapability)
        case .granted:
            return MediaCaptureFailure(.invalidState)
        }
    }

    private func finishRecording(
        sessionHandle: SessionHandle,
        automatic: Bool
    ) async throws -> MediaMetadata {
        guard var session = sessions[sessionHandle],
              session.state == .recording,
              !session.operationInFlight,
              let destination = session.recordingDestination
        else {
            throw MediaCaptureFailure(.invalidState)
        }
        session.operationInFlight = true
        session.operationGeneration &+= 1
        let operationGeneration = session.operationGeneration
        let operationEpoch = lifecycleEpoch
        sessions[sessionHandle] = session
        cancelDeadline(recordingDeadlineKey(sessionHandle))
        await revokeLiveAttachment(sessionHandle: sessionHandle)
        var pendingStoredMedia: StoredMedia?
        do {
            try validateSessionOperation(
                sessionHandle,
                generation: operationGeneration,
                epoch: operationEpoch,
                allowedStates: [.recording]
            )
            try await platform.stopRecording()
            try Task.checkCancellation()
            try validateSessionOperation(
                sessionHandle,
                generation: operationGeneration,
                epoch: operationEpoch,
                allowedStates: [.recording]
            )
            let stored = try await fileStore.finalizeRecording(at: destination)
            pendingStoredMedia = stored
            try Task.checkCancellation()
            guard var current = sessions[sessionHandle],
                  current.state == .recording,
                  current.operationInFlight,
                  current.operationGeneration == operationGeneration,
                  lifecycleEpoch == operationEpoch
            else {
                await fileStore.delete(stored.reference)
                pendingStoredMedia = nil
                throw MediaCaptureFailure(.invalidState)
            }
            let record = try makeMediaRecord(
                storedMedia: stored,
                sessionHandle: sessionHandle,
                state: .preview,
                deadline: clock.now.addingTimeInterval(configuration.previewTimeToLive)
            )
            media[record.handle] = record
            current.currentMediaHandle = record.handle
            current.cachedPreview = record.metadata
            current.recordingDestination = nil
            current.operationInFlight = false
            current.state = .previewing
            sessions[sessionHandle] = current
            pendingStoredMedia = nil
            scheduleDeadline(key: mediaDeadlineKey(record.handle), at: record.stateDeadline ?? clock.now)
            if automatic {
                yield(.mediaPreviewReady(sessionHandle: sessionHandle, metadata: record.metadata))
            }
            return record.metadata
        } catch is CancellationError {
            if let pendingStoredMedia {
                await fileStore.delete(pendingStoredMedia.reference)
            }
            await fileStore.discardRecording(at: destination)
            clearOperation(sessionHandle, generation: operationGeneration)
            throw CancellationError()
        } catch {
            await fileStore.discardRecording(at: destination)
            clearOperation(sessionHandle, generation: operationGeneration)
            let failure = mapFailure(error, for: .stopRecording)
            if failure.terminal { await failSession(sessionHandle, failure: failure) }
            throw failure
        }
    }

    private func failSession(_ handle: SessionHandle, failure: MediaCaptureFailure) async {
        guard var session = sessions[handle],
              ![SessionState.completed, .cancelled, .failed].contains(session.state)
        else { return }
        session.operationGeneration &+= 1
        session.operationInFlight = false
        session.state = .failed
        session.terminalAt = clock.now
        let teardownEpoch = beginCaptureTeardown()
        let previewHandle = session.currentMediaHandle
        let recordingDestination = session.recordingDestination
        sessions[handle] = session
        preparationTasks.removeValue(forKey: handle)?.cancel()
        cancelDeadline(recordingDeadlineKey(handle))
        if let previewHandle, var preview = media[previewHandle], preview.state == .preview {
            preview.operationGeneration &+= 1
            preview.operationInFlight = false
            preview.state = .discarded
            preview.stateDeadline = nil
            preview.terminalAt = clock.now
            media[previewHandle] = preview
            cancelDeadline(mediaDeadlineKey(previewHandle))
        }
        await revokeLiveAttachment(sessionHandle: handle)
        if let previewHandle, let preview = media[previewHandle] {
            await revokePreviewAttachment(mediaHandle: previewHandle)
            await fileStore.delete(preview.storedMedia.reference)
        }
        await waitForAttachmentOperationsToDrain()
        await waitForAttachmentCleanupsToDrain()
        await platform.stopSession()
        if let recordingDestination {
            await fileStore.discardRecording(at: recordingDestination)
        }
        yield(.sessionFailed(sessionHandle: handle, failure: failure))
        finishCaptureTeardown(epoch: teardownEpoch, sessionHandle: handle)
    }

    private func publicSnapshot(
        _ snapshot: PlatformReadySnapshot,
        handle: SessionHandle
    ) throws -> SessionReadySnapshot {
        guard !snapshot.availableCameras.isEmpty,
              snapshot.availableCameras.contains(snapshot.activeCamera),
              !snapshot.supportedFlashModes.isEmpty,
              snapshot.minimumZoomFactor.isFinite,
              snapshot.maximumZoomFactor.isFinite,
              snapshot.minimumZoomFactor > 0,
              snapshot.maximumZoomFactor >= snapshot.minimumZoomFactor
        else {
            throw PlatformFailure.interrupted
        }
        return SessionReadySnapshot(
            sessionHandle: handle,
            activeCamera: snapshot.activeCamera,
            availableCameras: snapshot.availableCameras,
            switchCameraSupported: snapshot.availableCameras.count > 1,
            supportedFlashModes: snapshot.supportedFlashModes,
            focusPointSupported: snapshot.focusPointSupported,
            minimumZoomFactor: snapshot.minimumZoomFactor,
            maximumZoomFactor: snapshot.maximumZoomFactor
        )
    }

    private func makeMediaRecord(
        storedMedia: StoredMedia,
        sessionHandle: SessionHandle,
        state: MediaState,
        deadline: Date
    ) throws -> MediaRecord {
        let handle = try makeMediaHandle()
        let metadata = try MediaMetadata(
            mediaHandle: handle,
            mediaType: storedMedia.mediaType,
            pixelWidth: storedMedia.pixelWidth,
            pixelHeight: storedMedia.pixelHeight,
            durationMilliseconds: storedMedia.durationMilliseconds,
            orientationDegrees: storedMedia.orientationDegrees,
            byteLength: storedMedia.byteLength
        )
        return MediaRecord(
            handle: handle,
            sessionHandle: sessionHandle,
            storedMedia: storedMedia,
            metadata: metadata,
            state: state,
            stateDeadline: deadline
        )
    }

    private func makeSessionHandle() throws -> SessionHandle {
        SessionHandle(generatedRawValue: try uniqueHandleValue())
    }

    private func makeMediaHandle() throws -> MediaHandle {
        MediaHandle(generatedRawValue: try uniqueHandleValue())
    }

    private func uniqueHandleValue() throws -> String {
        for _ in 0 ..< 16 {
            let value = try handleGenerator.nextHandle()
            guard value.utf8.count <= 128, !value.isEmpty else { continue }
            if issuedHandleValues.insert(value).inserted { return value }
        }
        throw MediaCaptureFailure(.resourceInUse)
    }

    private func beginSessionOperation(
        _ handle: SessionHandle,
        allowedStates: [SessionState]
    ) throws -> SessionOperationToken {
        guard var session = sessions[handle] else {
            throw MediaCaptureFailure(.sessionInvalid)
        }
        guard allowedStates.contains(session.state), !session.operationInFlight else {
            throw MediaCaptureFailure(.invalidState)
        }
        session.operationGeneration &+= 1
        session.operationInFlight = true
        sessions[handle] = session
        return SessionOperationToken(
            handle: handle,
            generation: session.operationGeneration,
            epoch: lifecycleEpoch
        )
    }

    private func validatedSessionOperation(
        _ token: SessionOperationToken,
        allowedStates: [SessionState]
    ) throws -> SessionRecord {
        try validateSessionOperation(
            token.handle,
            generation: token.generation,
            epoch: token.epoch,
            allowedStates: allowedStates
        )
        guard let session = sessions[token.handle] else {
            throw MediaCaptureFailure(.sessionInvalid)
        }
        return session
    }

    private func validatedSessionOperationAfterPlatformCommit(
        _ token: SessionOperationToken,
        allowedStates: [SessionState]
    ) throws -> SessionRecord {
        guard let session = sessions[token.handle],
              session.operationInFlight,
              session.operationGeneration == token.generation,
              allowedStates.contains(session.state)
        else {
            throw MediaCaptureFailure(.invalidState)
        }
        return session
    }

    private func validateSessionOperation(
        _ handle: SessionHandle,
        generation: UInt64,
        epoch: UInt64,
        allowedStates: [SessionState]
    ) throws {
        guard lifecycleEpoch == epoch,
              let session = sessions[handle],
              session.operationInFlight,
              session.operationGeneration == generation,
              allowedStates.contains(session.state)
        else {
            throw MediaCaptureFailure(.invalidState)
        }
    }

    private func clearOperation(_ handle: SessionHandle, generation: UInt64) {
        guard var session = sessions[handle],
              session.operationGeneration == generation
        else { return }
        session.operationInFlight = false
        sessions[handle] = session
    }

    private func beginMediaTransition(_ handle: MediaHandle) throws -> MediaTransitionToken {
        guard var mediaRecord = media[handle] else {
            throw MediaCaptureFailure(.mediaInvalid)
        }
        guard mediaRecord.state == .preview,
              !mediaRecord.operationInFlight,
              var session = sessions[mediaRecord.sessionHandle],
              session.state == .previewing,
              !session.operationInFlight,
              session.currentMediaHandle == handle
        else {
            throw MediaCaptureFailure(.invalidState)
        }
        mediaRecord.operationGeneration &+= 1
        mediaRecord.operationInFlight = true
        session.operationGeneration &+= 1
        session.operationInFlight = true
        media[handle] = mediaRecord
        sessions[session.handle] = session
        return MediaTransitionToken(
            mediaHandle: handle,
            sessionHandle: session.handle,
            mediaGeneration: mediaRecord.operationGeneration,
            sessionGeneration: session.operationGeneration,
            epoch: lifecycleEpoch
        )
    }

    private func validatedMediaTransition(
        _ token: MediaTransitionToken
    ) throws -> (MediaRecord, SessionRecord) {
        guard lifecycleEpoch == token.epoch,
              let mediaRecord = media[token.mediaHandle],
              mediaRecord.state == .preview,
              mediaRecord.operationInFlight,
              mediaRecord.operationGeneration == token.mediaGeneration,
              let session = sessions[token.sessionHandle],
              session.state == .previewing,
              session.operationInFlight,
              session.operationGeneration == token.sessionGeneration,
              session.currentMediaHandle == token.mediaHandle
        else {
            throw MediaCaptureFailure(.invalidState)
        }
        return (mediaRecord, session)
    }

    private func clearMediaTransition(_ token: MediaTransitionToken) {
        if var mediaRecord = media[token.mediaHandle],
           mediaRecord.operationGeneration == token.mediaGeneration {
            mediaRecord.operationInFlight = false
            media[token.mediaHandle] = mediaRecord
        }
        clearOperation(token.sessionHandle, generation: token.sessionGeneration)
    }

    private func scheduleRecordingDeadline(_ handle: SessionHandle, at deadline: Date) {
        let key = recordingDeadlineKey(handle)
        cancelDeadline(key)
        let identifier = UUID()
        let clock = self.clock
        let task = Task { [weak self] in
            do {
                try await clock.sleep(until: deadline)
                if !Task.isCancelled,
                   await self?.beginExecutingDeadlineTask(
                       key: key,
                       identifier: identifier
                   ) == true {
                    try Task.checkCancellation()
                    _ = try await self?.finishRecording(sessionHandle: handle, automatic: true)
                }
            } catch is CancellationError {
            } catch {
                let failure = await self?.mapFailure(error, for: .stopRecording)
                    ?? MediaCaptureFailure(.encodingFailed)
                await self?.failSession(handle, failure: failure)
            }
            await self?.deadlineTaskFinished(key: key, identifier: identifier)
        }
        deadlineTasks[key] = DeadlineTaskRecord(identifier: identifier, task: task)
    }

    private func beginExecutingDeadlineTask(key: String, identifier: UUID) -> Bool {
        guard deadlineTasks[key]?.identifier == identifier else { return false }
        deadlineTasks.removeValue(forKey: key)
        return true
    }

    private func scheduleDeadline(key: String, at deadline: Date) {
        cancelDeadline(key)
        let identifier = UUID()
        let clock = self.clock
        let task = Task { [weak self] in
            do {
                try await clock.sleep(until: deadline)
                if !Task.isCancelled { await self?.processDeadlines() }
            } catch {
            }
            await self?.deadlineTaskFinished(key: key, identifier: identifier)
        }
        deadlineTasks[key] = DeadlineTaskRecord(identifier: identifier, task: task)
    }

    private func cancelDeadline(_ key: String) {
        deadlineTasks.removeValue(forKey: key)?.task.cancel()
    }

    private func deadlineTaskFinished(key: String, identifier: UUID) {
        guard deadlineTasks[key]?.identifier == identifier else { return }
        deadlineTasks.removeValue(forKey: key)
    }

    private func mediaDeadlineKey(_ handle: MediaHandle) -> String {
        "media:\(handle.rawValue)"
    }

    private func recordingDeadlineKey(_ handle: SessionHandle) -> String {
        "recording:\(handle.rawValue)"
    }

    private func observePlatformEventsIfNeeded() {
        guard platformEventTask == nil else { return }
        let stream = platform.events()
        platformEventTask = Task { [weak self] in
            for await event in stream {
                guard !Task.isCancelled else { return }
                await self?.receivePlatformEvent(event)
            }
        }
    }

    private func receivePlatformEvent(_ event: PlatformEvent) async {
        switch event {
        case .interrupted:
            if let activeSessionHandle {
                await failSession(
                    activeSessionHandle,
                    failure: MediaCaptureFailure(.systemInterrupted)
                )
            }
        }
    }

    private func validateLiveAttachmentReservation(
        sessionHandle: SessionHandle,
        reservationIdentifier: UUID
    ) throws {
        guard let session = sessions[sessionHandle],
              [.ready, .recording].contains(session.state),
              let reservation = session.liveAttachment.reservation,
              reservation.identifier == reservationIdentifier,
              reservation.lifecycleEpoch == lifecycleEpoch,
              session.liveAttachment.binding == nil,
              !session.liveAttachment.cleanupInProgress
        else {
            throw MediaCaptureFailure(.attachmentGenerationRetired)
        }
    }

    private func validatePreviewAttachmentReservation(
        mediaHandle: MediaHandle,
        reservationIdentifier: UUID
    ) throws {
        guard let record = media[mediaHandle],
              record.state == .preview,
              let reservation = record.previewAttachment.reservation,
              reservation.identifier == reservationIdentifier,
              reservation.lifecycleEpoch == lifecycleEpoch,
              record.previewAttachment.binding == nil,
              !record.previewAttachment.cleanupInProgress
        else {
            throw MediaCaptureFailure(.attachmentGenerationRetired)
        }
    }

    private func isLiveRenderMountReservationActive(
        sessionHandle: SessionHandle,
        reservationIdentifier: UUID
    ) -> Bool {
        (try? validateLiveAttachmentReservation(
            sessionHandle: sessionHandle,
            reservationIdentifier: reservationIdentifier
        )) != nil
    }

    private func isPreviewRenderMountReservationActive(
        mediaHandle: MediaHandle,
        reservationIdentifier: UUID
    ) -> Bool {
        (try? validatePreviewAttachmentReservation(
            mediaHandle: mediaHandle,
            reservationIdentifier: reservationIdentifier
        )) != nil
    }

    private func isRenderCallbackActive(
        kind: RenderAttachmentKind,
        sessionHandle: SessionHandle?,
        mediaHandle: MediaHandle?,
        ownerGeneration: Int64,
        targetIdentifier: ObjectIdentifier,
        epoch: UInt64
    ) -> Bool {
        guard !closed, lifecycleEpoch == epoch else { return false }
        switch kind {
        case .livePreview:
            guard let sessionHandle,
                  let session = sessions[sessionHandle],
                  [.ready, .recording].contains(session.state),
                  let binding = session.liveAttachment.binding
            else { return false }
            return binding.generation == ownerGeneration &&
                binding.targetIdentifier == targetIdentifier &&
                binding.surfaceOwner.value != nil
        case .unconfirmedPreview:
            guard let mediaHandle,
                  let record = media[mediaHandle],
                  record.state == .preview,
                  let binding = record.previewAttachment.binding
            else { return false }
            return binding.generation == ownerGeneration &&
                binding.targetIdentifier == targetIdentifier &&
                binding.surfaceOwner.value != nil
        }
    }

    private func cancelLiveAttachmentReservation(
        sessionHandle: SessionHandle,
        reservationIdentifier: UUID
    ) {
        guard var session = sessions[sessionHandle],
              let reservation = session.liveAttachment.reservation,
              reservation.identifier == reservationIdentifier
        else { return }
        reservation.callbackGate.invalidate()
        reservation.surfaceOwner.value?.setInvalidationHandler(
            for: reservation.targetIdentifier,
            nil
        )
        session.liveAttachment.reservation = nil
        sessions[sessionHandle] = session
    }

    private func cancelPreviewAttachmentReservation(
        mediaHandle: MediaHandle,
        reservationIdentifier: UUID
    ) {
        guard var record = media[mediaHandle],
              let reservation = record.previewAttachment.reservation,
              reservation.identifier == reservationIdentifier
        else { return }
        reservation.callbackGate.invalidate()
        reservation.surfaceOwner.value?.setInvalidationHandler(
            for: reservation.targetIdentifier,
            nil
        )
        record.previewAttachment.reservation = nil
        media[mediaHandle] = record
    }

    private func finishLiveBindingCleanup(
        sessionHandle: SessionHandle,
        binding: AttachmentBinding
    ) {
        guard var session = sessions[sessionHandle],
              let current = session.liveAttachment.binding,
              current.generation == binding.generation,
              current.targetIdentifier == binding.targetIdentifier
        else { return }
        session.liveAttachment.binding = nil
        session.liveAttachment.cleanupInProgress = false
        sessions[sessionHandle] = session
    }

    private func finishPreviewBindingCleanup(
        mediaHandle: MediaHandle,
        binding: AttachmentBinding
    ) {
        guard var record = media[mediaHandle],
              let current = record.previewAttachment.binding,
              current.generation == binding.generation,
              current.targetIdentifier == binding.targetIdentifier
        else { return }
        record.previewAttachment.binding = nil
        record.previewAttachment.cleanupInProgress = false
        media[mediaHandle] = record
    }

    private func revokeLiveAttachment(sessionHandle: SessionHandle) async {
        guard var session = sessions[sessionHandle] else { return }
        if let reservation = session.liveAttachment.reservation {
            reservation.callbackGate.invalidate()
            reservation.surfaceOwner.value?.setInvalidationHandler(
                for: reservation.targetIdentifier,
                nil
            )
            session.liveAttachment.reservation = nil
        }
        guard let binding = session.liveAttachment.binding else {
            sessions[sessionHandle] = session
            return
        }
        binding.renderBinding.invalidateGate()
        if session.liveAttachment.cleanupInProgress {
            sessions[sessionHandle] = session
            return
        }
        session.liveAttachment.cleanupInProgress = true
        sessions[sessionHandle] = session
        await detachBinding(binding, kind: .livePreview, emitEvent: true)
        finishLiveBindingCleanup(sessionHandle: sessionHandle, binding: binding)
    }

    private func revokePreviewAttachment(mediaHandle: MediaHandle) async {
        guard var record = media[mediaHandle] else { return }
        if let reservation = record.previewAttachment.reservation {
            reservation.callbackGate.invalidate()
            reservation.surfaceOwner.value?.setInvalidationHandler(
                for: reservation.targetIdentifier,
                nil
            )
            record.previewAttachment.reservation = nil
        }
        guard let binding = record.previewAttachment.binding else {
            media[mediaHandle] = record
            return
        }
        binding.renderBinding.invalidateGate()
        if record.previewAttachment.cleanupInProgress {
            media[mediaHandle] = record
            return
        }
        record.previewAttachment.cleanupInProgress = true
        media[mediaHandle] = record
        await detachBinding(
            binding,
            kind: .unconfirmedPreview,
            emitEvent: true
        )
        finishPreviewBindingCleanup(mediaHandle: mediaHandle, binding: binding)
    }

    private func revokeAllRenderAttachments() async {
        let sessionHandles = Array(sessions.keys)
        for handle in sessionHandles { await revokeLiveAttachment(sessionHandle: handle) }
        let mediaHandles = Array(media.keys)
        for handle in mediaHandles { await revokePreviewAttachment(mediaHandle: handle) }
    }

    private func finishAttachmentOperation() {
        attachmentOperationCount -= 1
        guard attachmentOperationCount == 0 else { return }
        let waiters = attachmentOperationWaiters
        attachmentOperationWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func waitForAttachmentOperationsToDrain() async {
        guard attachmentOperationCount > 0 else { return }
        await withCheckedContinuation { continuation in
            attachmentOperationWaiters.append(continuation)
        }
    }

    private func trackAttachmentCleanup(
        _ body: @escaping @Sendable () async -> Void
    ) -> DeadlineTaskRecord {
        let identifier = UUID()
        let task = Task { await body() }
        let record = DeadlineTaskRecord(identifier: identifier, task: task)
        attachmentCleanupTasks[identifier] = task
        return record
    }

    private func attachmentCleanupFinished(_ identifier: UUID) {
        attachmentCleanupTasks.removeValue(forKey: identifier)
    }

    private func waitForAttachmentCleanupsToDrain() async {
        while !attachmentCleanupTasks.isEmpty {
            let tasks = Array(attachmentCleanupTasks.values)
            for task in tasks { await task.value }
            let completed = attachmentCleanupTasks.filter { $0.value.isCancelled }.map(\.key)
            for identifier in completed { attachmentCleanupTasks.removeValue(forKey: identifier) }
            if !attachmentCleanupTasks.isEmpty { await Task.yield() }
        }
    }

    private func detachBinding(
        _ binding: AttachmentBinding,
        kind: RenderAttachmentKind,
        emitEvent: Bool
    ) async {
        binding.renderBinding.invalidateGate()
        let context = RenderAttachmentContext(kind: kind, ownerGeneration: binding.generation)
        let cleanup = trackAttachmentCleanup {
            await binding.renderBinding.revoke()
            if let surfaceOwner = binding.surfaceOwner.value {
                surfaceOwner.setInvalidationHandler(for: binding.targetIdentifier, nil)
            }
            await binding.mountEndpoint.didRevoke(context)
            await binding.renderBinding.detach()
            await binding.mountEndpoint.didDetach(context)
        }
        await cleanup.task.value
        attachmentCleanupFinished(cleanup.identifier)
        if emitEvent {
            yield(.renderAttachmentRevoked(
                RenderAttachmentResult(kind: kind, ownerGeneration: binding.generation)
            ))
        }
    }

    private func revokeUncommittedTarget(
        _ surfaceOwner: MediaCaptureRenderSurfaceOwner,
        endpoint: MediaCaptureRenderMountEndpoint,
        context: RenderAttachmentContext,
        renderBinding: MediaCaptureRenderBinding
    ) async {
        renderBinding.invalidateGate()
        let cleanup = trackAttachmentCleanup {
            await renderBinding.revoke()
            surfaceOwner.setInvalidationHandler(for: endpoint.identity, nil)
            await endpoint.didRevoke(context)
            await renderBinding.detach()
            await endpoint.didDetach(context)
        }
        await cleanup.task.value
        attachmentCleanupFinished(cleanup.identifier)
    }

    private func renderOwnerDestroyed(
        kind: RenderAttachmentKind,
        sessionHandle: SessionHandle?,
        mediaHandle: MediaHandle?,
        ownerGeneration: Int64,
        targetIdentifier: ObjectIdentifier
    ) async {
        switch kind {
        case .livePreview:
            guard let sessionHandle, var session = sessions[sessionHandle] else { return }
            if let reservation = session.liveAttachment.reservation,
               reservation.generation == ownerGeneration,
               reservation.targetIdentifier == targetIdentifier {
                reservation.callbackGate.invalidate()
                session.liveAttachment.reservation = nil
            }
            guard let binding = session.liveAttachment.binding,
                  binding.generation == ownerGeneration,
                  binding.targetIdentifier == targetIdentifier
            else {
                sessions[sessionHandle] = session
                return
            }
            binding.renderBinding.invalidateGate()
            if session.liveAttachment.cleanupInProgress {
                sessions[sessionHandle] = session
                return
            }
            session.liveAttachment.cleanupInProgress = true
            sessions[sessionHandle] = session
            await detachBinding(binding, kind: kind, emitEvent: true)
            finishLiveBindingCleanup(sessionHandle: sessionHandle, binding: binding)
        case .unconfirmedPreview:
            guard let mediaHandle, var record = media[mediaHandle] else { return }
            if let reservation = record.previewAttachment.reservation,
               reservation.generation == ownerGeneration,
               reservation.targetIdentifier == targetIdentifier {
                reservation.callbackGate.invalidate()
                record.previewAttachment.reservation = nil
            }
            guard let binding = record.previewAttachment.binding,
                  binding.generation == ownerGeneration,
                  binding.targetIdentifier == targetIdentifier
            else {
                media[mediaHandle] = record
                return
            }
            binding.renderBinding.invalidateGate()
            if record.previewAttachment.cleanupInProgress {
                media[mediaHandle] = record
                return
            }
            record.previewAttachment.cleanupInProgress = true
            media[mediaHandle] = record
            await detachBinding(binding, kind: kind, emitEvent: true)
            finishPreviewBindingCleanup(mediaHandle: mediaHandle, binding: binding)
        }
    }

    private func completeThumbnailSuccess(
        identifier: UUID,
        generated: inout GeneratedThumbnail,
        record: MediaRecord,
        maximumPixelEdge: Int
    ) throws -> MediaThumbnail {
        guard generated.buffer.count > 0,
              generated.buffer.count <= 524_288,
              generated.buffer.starts(with: [0xff, 0xd8]),
              generated.buffer.suffix(2) == Data([0xff, 0xd9]),
              generated.pixelWidth > 0,
              generated.pixelHeight > 0,
              generated.pixelWidth <= maximumPixelEdge,
              generated.pixelHeight <= maximumPixelEdge,
              generated.pixelWidth <= 512,
              generated.pixelHeight <= 512,
              (record.storedMedia.mediaType == .photo && generated.actualPosterFrameMilliseconds == nil) ||
              (record.storedMedia.mediaType == .video &&
                  generated.actualPosterFrameMilliseconds.map {
                      $0 >= 0 && $0 <= (record.storedMedia.durationMilliseconds ?? 0)
                  } == true)
        else {
            generated.buffer.wipe()
            _ = completeThumbnailFailure(identifier: identifier, proposedWinner: .decoderFailure)
            throw MediaCaptureFailure(.thumbnailGenerationFailed)
        }
        guard var job = thumbnailJobs[identifier] else {
            generated.buffer.wipe()
            throw MediaCaptureFailure(.thumbnailGenerationFailed)
        }
        let terminalWinner = job.arbiter.tryWin(.success)
        thumbnailJobs[identifier] = job
        guard terminalWinner == .success else {
            generated.buffer.wipe()
            let winner = completeThumbnailFailure(
                identifier: identifier,
                proposedWinner: terminalWinner
            )
            throw thumbnailFailure(for: winner)
        }
        let callerCopy = generated.buffer.copy()
        job.source?.close()
        generated.buffer.wipe()
        job.finalized = true
        thumbnailJobs[identifier] = job
        unregisterThumbnailJob(identifier)
        return MediaThumbnail(
            mediaHandle: record.handle,
            data: callerCopy,
            pixelWidth: generated.pixelWidth,
            pixelHeight: generated.pixelHeight,
            mediaType: record.storedMedia.mediaType,
            posterFrameMilliseconds: generated.actualPosterFrameMilliseconds
        )
    }

    @discardableResult
    private func completeThumbnailFailure(
        identifier: UUID,
        proposedWinner: ThumbnailWinner
    ) -> ThumbnailWinner {
        guard var job = thumbnailJobs[identifier] else { return proposedWinner }
        let winner = job.arbiter.tryWin(proposedWinner)
        job.cancellation.cancel()
        job.worker?.cancel()
        job.source?.close()
        job.finalized = true
        thumbnailJobs[identifier] = job
        unregisterThumbnailJob(identifier)
        return winner
    }

    private func waitForThumbnailJobsToDrain() async {
        guard !thumbnailJobs.isEmpty else { return }
        await withCheckedContinuation { continuation in
            thumbnailDrainWaiters.append(continuation)
        }
    }

    private func unregisterThumbnailJob(_ identifier: UUID) {
        thumbnailJobs.removeValue(forKey: identifier)
        guard thumbnailJobs.isEmpty else { return }
        let waiters = thumbnailDrainWaiters
        thumbnailDrainWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func markThumbnailJobs(for handle: MediaHandle, winner: ThumbnailWinner) {
        for identifier in Array(thumbnailJobs.keys) {
            guard let job = thumbnailJobs[identifier], job.mediaHandle == handle else { continue }
            let terminalWinner = job.arbiter.tryWin(winner)
            if terminalWinner != .success {
                job.cancellation.cancel()
                job.worker?.cancel()
                thumbnailJobs[identifier] = job
            }
        }
    }

    private func markAllThumbnailJobs(winner: ThumbnailWinner) {
        for identifier in Array(thumbnailJobs.keys) {
            guard let job = thumbnailJobs[identifier] else { continue }
            let terminalWinner = job.arbiter.tryWin(winner)
            if terminalWinner != .success {
                job.cancellation.cancel()
                job.worker?.cancel()
                thumbnailJobs[identifier] = job
            }
        }
    }

    private func thumbnailFailure(for winner: ThumbnailWinner) -> MediaCaptureFailure {
        switch winner {
        case .release, .expiry:
            return MediaCaptureFailure(.invalidState)
        case .restart:
            return MediaCaptureFailure(.mediaInvalid)
        case .callerCancelled:
            return MediaCaptureFailure(.thumbnailGenerationCancelled)
        case .decoderFailure, .success:
            return MediaCaptureFailure(.thumbnailGenerationFailed)
        }
    }

    private func revokeReadScopes(for handle: MediaHandle) {
        let identifiers = readScopes
            .filter { $0.value.mediaHandle == handle }
            .map(\.key)
        for identifier in identifiers {
            readScopes.removeValue(forKey: identifier)?.source.close()
        }
    }

    private func mapFailure(
        _ error: Error,
        for operation: CapabilityOperation
    ) -> MediaCaptureFailure {
        let candidate: MediaCaptureFailure.ID
        if let failure = error as? MediaCaptureFailure {
            candidate = failure.id
        } else if let platformFailure = error as? PlatformFailure {
            switch platformFailure {
            case .resourceInUse:
                candidate = .resourceInUse
            case .storageFull:
                candidate = .storageFull
            case .encodingFailed:
                candidate = .encodingFailed
            case .unsupported:
                candidate = .unsupportedCapability
            case .interrupted:
                candidate = .systemInterrupted
            }
        } else {
            candidate = .systemInterrupted
        }
        let allowed = failureAllowlist(for: operation)
        if allowed.contains(candidate) { return MediaCaptureFailure(candidate) }
        if [.attachLivePreview, .attachUnconfirmedPreview].contains(operation),
           candidate == .unsupportedCapability {
            return MediaCaptureFailure(.invalidArgument)
        }
        return MediaCaptureFailure(.systemInterrupted)
    }

    private func failureAllowlist(
        for operation: CapabilityOperation
    ) -> Set<MediaCaptureFailure.ID> {
        switch operation {
        case .startSession:
            return [.invalidArgument, .permissionDenied, .permissionRestricted,
                    .permissionPermanentlyDenied, .resourceInUse, .storageFull,
                    .unsupportedCapability, .systemInterrupted, .sessionConflict]
        case .takePhoto:
            return [.sessionInvalid, .invalidState, .invalidArgument, .storageFull,
                    .encodingFailed, .unsupportedCapability, .systemInterrupted]
        case .startRecording:
            return [.sessionInvalid, .invalidState, .invalidArgument, .permissionDenied,
                    .permissionRestricted, .permissionPermanentlyDenied, .resourceInUse,
                    .storageFull, .encodingFailed, .unsupportedCapability, .systemInterrupted]
        case .stopRecording:
            return [.sessionInvalid, .invalidState, .invalidArgument, .encodingFailed,
                    .systemInterrupted]
        case .switchCamera:
            return [.sessionInvalid, .invalidState, .invalidArgument, .resourceInUse,
                    .unsupportedCapability, .systemInterrupted]
        case .setFlashMode, .setFocusPoint, .setZoom:
            return [.sessionInvalid, .invalidState, .invalidArgument,
                    .unsupportedCapability, .systemInterrupted]
        case .attachLivePreview:
            return [.sessionInvalid, .invalidState, .invalidArgument,
                    .attachmentGenerationRetired, .attachmentTargetConflict,
                    .systemInterrupted]
        case .attachUnconfirmedPreview:
            return [.mediaInvalid, .invalidState, .invalidArgument,
                    .attachmentGenerationRetired, .attachmentTargetConflict,
                    .systemInterrupted]
        }
    }

    private func ensureOpen() throws {
        guard !closed, moduleLifecycleState != .closed,
              moduleLifecycleState != .tearingDown,
              moduleLifecycleState != .restarting
        else {
            throw MediaCaptureFailure(.invalidState)
        }
    }

    private func ensureMediaReleaseAllowed() throws {
        guard !closed, moduleLifecycleState != .closed else {
            throw MediaCaptureFailure(.mediaInvalid)
        }
        guard moduleLifecycleState != .tearingDown,
              moduleLifecycleState != .restarting
        else {
            throw MediaCaptureFailure(.invalidState)
        }
    }

    private func ensureCanStartSession() throws {
        guard !closed, moduleLifecycleState != .closed else {
            throw MediaCaptureFailure(.invalidState)
        }
        guard moduleLifecycleState != .tearingDown,
              moduleLifecycleState != .restarting
        else {
            throw MediaCaptureFailure(.resourceInUse)
        }
    }

    private func ensureTerminalOperationAllowed() throws {
        guard !closed, moduleLifecycleState != .closed,
              moduleLifecycleState != .restarting
        else {
            throw MediaCaptureFailure(.invalidState)
        }
    }

    private func beginCaptureTeardown() -> UInt64 {
        moduleLifecycleState = .tearingDown
        captureTeardownGeneration &+= 1
        return captureTeardownGeneration
    }

    private func finishCaptureTeardown(epoch: UInt64, sessionHandle: SessionHandle) {
        guard !closed, captureTeardownGeneration == epoch,
              moduleLifecycleState == .tearingDown
        else { return }
        if activeSessionHandle == sessionHandle { activeSessionHandle = nil }
        moduleLifecycleState = .idle
    }

    private func abandonCaptureTeardown(epoch: UInt64) {
        guard !closed, captureTeardownGeneration == epoch,
              moduleLifecycleState == .tearingDown
        else { return }
        moduleLifecycleState = activeSessionHandle == nil ? .idle : .captureActive
    }

    private func yield(_ event: MediaCaptureEvent) {
        eventContinuations.values.forEach { $0.yield(event) }
    }

    private func removeEventContinuation(_ identifier: UUID) {
        eventContinuations.removeValue(forKey: identifier)
    }
}
