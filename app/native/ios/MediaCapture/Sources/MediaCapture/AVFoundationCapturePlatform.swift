@preconcurrency internal import AVFoundation
import Foundation

internal final class AVFoundationCapturePlatform: NSObject, CapturePlatform, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(label: "com.example.media-capture.session")
    private let stateLock = NSLock()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var currentFlashMode: FlashMode = .off
    private var photoDelegates: [UUID: PhotoCaptureDelegate] = [:]
    private var movieOperation: MovieCaptureOperation?
    private var eventContinuations: [UUID: AsyncStream<PlatformEvent>.Continuation] = [:]
    private var observerTokens: [NSObjectProtocol] = []

    override init() {
        super.init()
        let center = NotificationCenter.default
        observerTokens = [
            center.addObserver(
                forName: .AVCaptureSessionWasInterrupted,
                object: session,
                queue: nil
            ) { [weak self] _ in
                self?.yield(.interrupted)
            },
            center.addObserver(
                forName: .AVCaptureSessionRuntimeError,
                object: session,
                queue: nil
            ) { [weak self] _ in
                self?.yield(.interrupted)
            },
        ]
    }

    deinit {
        removeObservers()
    }

    func events() -> AsyncStream<PlatformEvent> {
        let identifier = UUID()
        return AsyncStream { continuation in
            stateLock.lock()
            eventContinuations[identifier] = continuation
            stateLock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.stateLock.lock()
                self?.eventContinuations.removeValue(forKey: identifier)
                self?.stateLock.unlock()
            }
        }
    }

    func permissionState(for resource: PermissionResource) async -> PermissionState {
        let mediaType: AVMediaType = resource == .camera ? .video : .audio
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .granted
        case .restricted:
            return .restricted
        case .denied:
            return .permanentlyDenied
        @unknown default:
            return .unsupported
        }
    }

    func requestPermission(for resource: PermissionResource) async -> PermissionState {
        let mediaType: AVMediaType = resource == .camera ? .video : .audio
        let granted = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: mediaType) { value in
                continuation.resume(returning: value)
            }
        }
        return granted ? .granted : await permissionState(for: resource)
    }

    func prepare(options: SessionOptions) async throws -> PlatformReadySnapshot {
        try await onSessionQueue {
            try configureCaptureSession(
                beginConfiguration: self.session.beginConfiguration,
                applyConfiguration: {
                    self.session.sessionPreset = .high
                    self.session.inputs.forEach(self.session.removeInput)
                    self.session.outputs.forEach(self.session.removeOutput)
                    self.videoInput = nil
                    self.audioInput = nil

                    let position = self.avPosition(for: options.preferredCamera)
                    guard let device = self.camera(position: position)
                        ?? self.camera(position: .unspecified)
                    else {
                        throw PlatformFailure.unsupported
                    }
                    do {
                        let input = try AVCaptureDeviceInput(device: device)
                        guard self.session.canAddInput(input),
                              self.session.canAddOutput(self.photoOutput),
                              self.session.canAddOutput(self.movieOutput)
                        else {
                            throw PlatformFailure.resourceInUse
                        }
                        self.session.addInput(input)
                        self.session.addOutput(self.photoOutput)
                        self.session.addOutput(self.movieOutput)
                        if let connection = self.movieOutput.connection(with: .video),
                           self.movieOutput.availableVideoCodecTypes.contains(.h264) {
                            self.movieOutput.setOutputSettings(
                                [AVVideoCodecKey: AVVideoCodecType.h264],
                                for: connection
                            )
                        }
                        self.videoInput = input
                    } catch let failure as PlatformFailure {
                        throw failure
                    } catch {
                        throw PlatformFailure.resourceInUse
                    }
                },
                commitConfiguration: self.session.commitConfiguration,
                isRunning: { self.session.isRunning },
                startRunning: self.session.startRunning
            )
            return try self.snapshot()
        }
    }

    func capturePhoto(flashMode: FlashMode) async throws -> CapturedPhoto {
        let delegate: PhotoCaptureDelegate = try await onSessionQueue {
            guard self.session.isRunning else { throw PlatformFailure.interrupted }
            let identifier = UUID()
            let delegate = PhotoCaptureDelegate(identifier: identifier)
            self.photoDelegates[identifier] = delegate
            let settings = AVCapturePhotoSettings()
            if self.photoOutput.supportedFlashModes.contains(self.avFlashMode(for: flashMode)) {
                settings.flashMode = self.avFlashMode(for: flashMode)
            }
            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
            return delegate
        }
        defer {
            sessionQueue.async {
                if self.photoDelegates[delegate.identifier] === delegate {
                    self.photoDelegates.removeValue(forKey: delegate.identifier)
                }
            }
        }
        return try await delegate.value { [weak self, weak delegate] in
            guard let self, let delegate else { return }
            delegate.requestCancellation()
            self.sessionQueue.async {
                guard self.photoDelegates[delegate.identifier] === delegate else { return }
                if self.session.isRunning {
                    self.session.stopRunning()
                    self.session.startRunning()
                }
            }
        }
    }

    func configureRecordingAudio(enabled: Bool) async throws {
        try await onSessionQueue {
            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }
            if enabled {
                guard self.audioInput == nil else { return }
                guard let microphone = AVCaptureDevice.default(for: .audio) else {
                    throw PlatformFailure.unsupported
                }
                do {
                    let input = try AVCaptureDeviceInput(device: microphone)
                    guard self.session.canAddInput(input) else { throw PlatformFailure.resourceInUse }
                    self.session.addInput(input)
                    self.audioInput = input
                } catch let failure as PlatformFailure {
                    throw failure
                } catch {
                    throw PlatformFailure.resourceInUse
                }
            } else if let audioInput = self.audioInput {
                self.session.removeInput(audioInput)
                self.audioInput = nil
            }
        }
    }

    func startRecording(to destination: URL) async throws {
        try await onSessionQueue {
            guard self.session.isRunning, !self.movieOutput.isRecording,
                  self.movieOperation == nil
            else {
                throw PlatformFailure.resourceInUse
            }
            let operation = MovieCaptureOperation(destination: destination)
            operation.delegate.didStartHandler = { [weak self, weak operation] in
                guard let self, let operation, operation.stopRequested else { return }
                self.sessionQueue.async {
                    if self.movieOperation === operation, self.movieOutput.isRecording {
                        self.movieOutput.stopRecording()
                    }
                }
            }
            self.movieOperation = operation
            self.movieOutput.startRecording(
                to: destination,
                recordingDelegate: operation.delegate
            )
        }
    }

    func stopRecording() async throws {
        let operation: MovieCaptureOperation = try await onSessionQueue {
            guard let operation = self.movieOperation else {
                throw PlatformFailure.interrupted
            }
            operation.requestStop()
            if self.movieOutput.isRecording { self.movieOutput.stopRecording() }
            return operation
        }
        do {
            try await operation.delegate.value { [weak self, weak operation] in
                guard let self, let operation else { return }
                operation.requestStop()
                self.sessionQueue.async {
                    if self.movieOperation === operation, self.movieOutput.isRecording {
                        self.movieOutput.stopRecording()
                    }
                }
            }
            await clearMovieOperation(operation)
        } catch {
            await clearMovieOperation(operation)
            throw error
        }
    }

    func switchCamera() async throws -> PlatformReadySnapshot {
        try await onSessionQueue {
            guard let currentInput = self.videoInput else { throw PlatformFailure.interrupted }
            let newPosition: AVCaptureDevice.Position = currentInput.device.position == .front ? .back : .front
            guard let device = self.camera(position: newPosition) else {
                throw PlatformFailure.unsupported
            }
            do {
                let replacement = try AVCaptureDeviceInput(device: device)
                self.session.beginConfiguration()
                self.session.removeInput(currentInput)
                if self.session.canAddInput(replacement) {
                    self.session.addInput(replacement)
                    self.videoInput = replacement
                    self.session.commitConfiguration()
                    return try self.snapshot()
                }
                self.session.addInput(currentInput)
                self.session.commitConfiguration()
                throw PlatformFailure.resourceInUse
            } catch let failure as PlatformFailure {
                throw failure
            } catch {
                throw PlatformFailure.resourceInUse
            }
        }
    }

    func setFlashMode(_ mode: FlashMode) async throws {
        try await onSessionQueue {
            guard let device = self.videoInput?.device else { throw PlatformFailure.interrupted }
            if mode == .torch {
                guard device.hasTorch, device.isTorchModeSupported(.on) else {
                    throw PlatformFailure.unsupported
                }
                do {
                    try device.lockForConfiguration()
                    device.torchMode = .on
                    device.unlockForConfiguration()
                } catch {
                    throw PlatformFailure.resourceInUse
                }
            } else if device.hasTorch, device.isTorchActive {
                do {
                    try device.lockForConfiguration()
                    device.torchMode = .off
                    device.unlockForConfiguration()
                } catch {
                    throw PlatformFailure.resourceInUse
                }
            }
            self.currentFlashMode = mode
        }
    }

    func setFocusPoint(x: Double, y: Double) async throws {
        try await onSessionQueue {
            guard let device = self.videoInput?.device,
                  device.isFocusPointOfInterestSupported
            else {
                throw PlatformFailure.unsupported
            }
            do {
                try device.lockForConfiguration()
                device.focusPointOfInterest = CGPoint(x: x, y: y)
                if device.isFocusModeSupported(.autoFocus) {
                    device.focusMode = .autoFocus
                }
                device.unlockForConfiguration()
            } catch {
                throw PlatformFailure.resourceInUse
            }
        }
    }

    func setZoomFactor(_ factor: Double) async throws {
        try await onSessionQueue {
            guard let device = self.videoInput?.device else { throw PlatformFailure.interrupted }
            let minimum = max(1, Double(device.minAvailableVideoZoomFactor))
            let maximum = Double(device.maxAvailableVideoZoomFactor)
            guard factor.isFinite, factor >= minimum, factor <= maximum else {
                throw PlatformFailure.unsupported
            }
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = CGFloat(factor)
                device.unlockForConfiguration()
            } catch {
                throw PlatformFailure.resourceInUse
            }
        }
    }

    func liveRenderSource() async throws -> MediaCaptureRenderSource {
        try await onSessionQueue {
            guard self.session.isRunning else { throw PlatformFailure.interrupted }
            return .live(self.session)
        }
    }

    func stopSession() async {
        let operations = await withCheckedContinuation { continuation in
            sessionQueue.async {
                self.movieOperation?.requestStop()
                if self.movieOutput.isRecording { self.movieOutput.stopRecording() }
                continuation.resume(returning: (
                    Array(self.photoDelegates.values),
                    self.movieOperation
                ))
            }
        }
        for delegate in operations.0 { await delegate.waitForCompletion() }
        await clearPhotoDelegates(operations.0)
        if let operation = operations.1 {
            await operation.delegate.waitForCompletion()
            await clearMovieOperation(operation)
        }
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                if self.session.isRunning { self.session.stopRunning() }
                continuation.resume()
            }
        }
    }

    func close() async {
        await stopSession()
        removeObservers()
        let continuations = withStateLock {
            let values = Array(eventContinuations.values)
            eventContinuations.removeAll()
            return values
        }
        continuations.forEach { $0.finish() }
    }

    internal func registeredObserverCount() -> Int {
        withStateLock { observerTokens.count }
    }

    private func yield(_ event: PlatformEvent) {
        stateLock.lock()
        let continuations = Array(eventContinuations.values)
        stateLock.unlock()
        continuations.forEach { $0.yield(event) }
    }

    private func withStateLock<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }

    private func clearMovieOperation(_ operation: MovieCaptureOperation) async {
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                if self.movieOperation === operation { self.movieOperation = nil }
                continuation.resume()
            }
        }
    }

    private func clearPhotoDelegates(_ delegates: [PhotoCaptureDelegate]) async {
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                for delegate in delegates where
                    self.photoDelegates[delegate.identifier] === delegate {
                    self.photoDelegates.removeValue(forKey: delegate.identifier)
                }
                continuation.resume()
            }
        }
    }

    private func removeObservers() {
        let tokens = withStateLock {
            let values = observerTokens
            observerTokens.removeAll()
            return values
        }
        tokens.forEach(NotificationCenter.default.removeObserver)
    }

    private func onSessionQueue<T: Sendable>(
        _ body: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                do {
                    continuation.resume(returning: try body())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func snapshot() throws -> PlatformReadySnapshot {
        guard let device = videoInput?.device else { throw PlatformFailure.interrupted }
        let available = availablePositions()
        var flashModes: [FlashMode] = [.off]
        if device.hasFlash {
            flashModes.append(contentsOf: [.on, .auto])
        }
        if device.hasTorch {
            flashModes.append(.torch)
        }
        return PlatformReadySnapshot(
            activeCamera: device.position == .front ? .front : .rear,
            availableCameras: available,
            supportedFlashModes: flashModes,
            focusPointSupported: device.isFocusPointOfInterestSupported,
            minimumZoomFactor: max(1, Double(device.minAvailableVideoZoomFactor)),
            maximumZoomFactor: max(1, Double(device.maxAvailableVideoZoomFactor))
        )
    }

    private func availablePositions() -> [CameraPosition] {
        var values: [CameraPosition] = []
        if camera(position: .back) != nil { values.append(.rear) }
        if camera(position: .front) != nil { values.append(.front) }
        return values
    }

    private func camera(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: position
        ).devices.first
    }

    private func avPosition(for position: CameraPosition) -> AVCaptureDevice.Position {
        position == .front ? .front : .back
    }

    private func avFlashMode(for mode: FlashMode) -> AVCaptureDevice.FlashMode {
        switch mode {
        case .off, .torch:
            return .off
        case .on:
            return .on
        case .auto:
            return .auto
        }
    }
}

internal func configureCaptureSession(
    beginConfiguration: () -> Void,
    applyConfiguration: () throws -> Void,
    commitConfiguration: () -> Void,
    isRunning: () -> Bool,
    startRunning: () -> Void
) rethrows {
    beginConfiguration()
    do {
        try applyConfiguration()
    } catch {
        commitConfiguration()
        throw error
    }
    commitConfiguration()
    if !isRunning() {
        startRunning()
    }
}

internal final class OperationCompletion<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?
    private var waiters: [CheckedContinuation<Result<Value, Error>, Never>] = []

    @discardableResult
    func resolve(_ result: Result<Value, Error>) -> Bool {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return false
        }
        self.result = result
        let waiters = self.waiters
        self.waiters.removeAll()
        lock.unlock()
        waiters.forEach { $0.resume(returning: result) }
        return true
    }

    func value() async throws -> Value {
        let result = await resultValue()
        return try result.get()
    }

    func result() async -> Result<Value, Error> {
        await resultValue()
    }

    func waitForCompletion() async {
        _ = await resultValue()
    }

    private func resultValue() async -> Result<Value, Error> {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(returning: result)
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }
}

internal enum CancellableOperationAwaiter {
    static func value<Value: Sendable>(
        _ completion: OperationCompletion<Value>,
        onCancel: @escaping @Sendable () -> Void
    ) async throws -> Value {
        let result = await withTaskCancellationHandler {
            await completion.result()
        } onCancel: {
            onCancel()
        }
        try Task.checkCancellation()
        return try result.get()
    }
}

internal final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let identifier: UUID
    private let completion = OperationCompletion<CapturedPhoto>()
    private let lock = NSLock()
    private var cancellationRequested = false
    private var processedResult: Result<CapturedPhoto, Error>?

    init(identifier: UUID) {
        self.identifier = identifier
    }

    func value(onCancel: @escaping @Sendable () -> Void) async throws -> CapturedPhoto {
        try await CancellableOperationAwaiter.value(completion, onCancel: onCancel)
    }

    func waitForCompletion() async {
        await completion.waitForCompletion()
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let result: Result<CapturedPhoto, Error>
        if error != nil {
            result = .failure(PlatformFailure.encodingFailed)
        } else if let data = photo.fileDataRepresentation(), !data.isEmpty {
            result = .success(CapturedPhoto(encodedData: data))
        } else {
            result = .failure(PlatformFailure.encodingFailed)
        }
        recordProcessedResult(result)
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        finishCapture(error: error)
    }

    func recordProcessedResult(_ result: Result<CapturedPhoto, Error>) {
        lock.lock()
        processedResult = result
        lock.unlock()
    }

    func finishCapture(error: Error?) {
        lock.lock()
        let cancelled = cancellationRequested
        let result = processedResult
        lock.unlock()
        if cancelled {
            completion.resolve(.failure(CancellationError()))
        } else if error != nil {
            completion.resolve(.failure(PlatformFailure.encodingFailed))
        } else {
            completion.resolve(result ?? .failure(PlatformFailure.encodingFailed))
        }
    }

    func requestCancellation() {
        lock.lock()
        cancellationRequested = true
        lock.unlock()
    }
}

internal final class MovieCaptureDelegate: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    private let completion = OperationCompletion<Void>()
    var didStartHandler: (@Sendable () -> Void)?

    func value(onCancel: @escaping @Sendable () -> Void) async throws {
        try await CancellableOperationAwaiter.value(completion, onCancel: onCancel)
    }

    func waitForCompletion() async {
        await completion.waitForCompletion()
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        didStartHandler?()
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        finishRecording(error: error)
    }

    func finishRecording(error: Error?) {
        let frameworkSuccess = (error as NSError?)?
            .userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool
        let recordingIsPlayable = error == nil || frameworkSuccess == true
        MediaCaptureDiagnostics.emit(
            "movie_capture_finished",
            error: error,
            details: "error_present=\(error != nil) framework_success=\(frameworkSuccess.map(String.init) ?? "unset") playable=\(recordingIsPlayable)"
        )
        completion.resolve(recordingIsPlayable
            ? .success(())
            : .failure(PlatformFailure.encodingFailed))
    }
}

private final class MovieCaptureOperation: @unchecked Sendable {
    let identifier = UUID()
    let destination: URL
    let delegate = MovieCaptureDelegate()
    private let lock = NSLock()
    private var requestedStop = false

    init(destination: URL) {
        self.destination = destination
    }

    var stopRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return requestedStop
    }

    func requestStop() {
        lock.lock()
        requestedStop = true
        lock.unlock()
    }
}
