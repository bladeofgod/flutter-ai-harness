import Foundation

internal enum MediaExportCommitOutcome: Equatable {
    case succeeded
    case failed(MediaCaptureFailure.ID)
}

internal final class MediaExportControl: @unchecked Sendable {
    private enum Phase {
        case running
        case committing
        case succeeded
        case failed(MediaCaptureFailure.ID)
    }

    private let lock = NSLock()
    private var phase: Phase = .running
    private var commitCancellationFailure: MediaCaptureFailure.ID?
    private var source: MediaSourceAccess?
    private var sinkBegun = false
    private var sinkCommitted = false
    private var abortClaimed = false

    func installSource(_ source: MediaSourceAccess) -> Bool {
        lock.lock()
        guard case .running = phase else {
            lock.unlock()
            source.close()
            return false
        }
        self.source = source
        lock.unlock()
        return true
    }

    func markSinkBegun() {
        lock.lock()
        sinkBegun = true
        lock.unlock()
    }

    func prepareCommit() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard case .running = phase else { return false }
        phase = .committing
        return true
    }

    @discardableResult
    func claimFailure(_ failure: MediaCaptureFailure.ID) -> Bool {
        lock.lock()
        let shouldCancel: Bool
        switch phase {
        case .running:
            phase = .failed(failure)
            shouldCancel = true
        case .committing:
            if commitCancellationFailure == nil {
                commitCancellationFailure = failure
                shouldCancel = true
            } else {
                shouldCancel = false
            }
        case .succeeded, .failed:
            shouldCancel = false
        }
        let source = self.source
        lock.unlock()
        if shouldCancel {
            source?.close()
        }
        return shouldCancel
    }

    func finishCommitFailure(fallback: MediaCaptureFailure.ID) -> MediaCaptureFailure.ID {
        lock.lock()
        defer { lock.unlock() }
        switch phase {
        case .committing:
            let failure = commitCancellationFailure ?? fallback
            phase = .failed(failure)
            return failure
        case let .failed(failure):
            return failure
        case .running:
            phase = .failed(fallback)
            return fallback
        case .succeeded:
            return fallback
        }
    }

    func completeSuccessfulCommit() -> MediaExportCommitOutcome {
        lock.lock()
        defer { lock.unlock() }
        switch phase {
        case .committing:
            // A normal return from commit is the publication linearization point.
            // Cancellation registered after that return cannot make a published
            // target look failed to the caller.
            sinkCommitted = true
            phase = .succeeded
            return .succeeded
        case let .failed(failure):
            return .failed(failure)
        case .running:
            phase = .failed(.systemInterrupted)
            return .failed(.systemInterrupted)
        case .succeeded:
            return .succeeded
        }
    }

    var hasFailureWinner: Bool {
        lock.lock()
        defer { lock.unlock() }
        switch phase {
        case .failed:
            return true
        case .committing:
            return commitCancellationFailure != nil
        case .running, .succeeded:
            return false
        }
    }

    func failure(or fallback: MediaCaptureFailure.ID) -> MediaCaptureFailure.ID {
        lock.lock()
        defer { lock.unlock() }
        switch phase {
        case let .failed(failure):
            return failure
        case .committing:
            return commitCancellationFailure ?? fallback
        case .running, .succeeded:
            return fallback
        }
    }

    func checkActive() throws {
        lock.lock()
        let active: Bool
        switch phase {
        case .running, .committing:
            active = true
        case .succeeded, .failed:
            active = false
        }
        lock.unlock()
        guard active else { throw CancellationError() }
        try Task.checkCancellation()
    }

    func claimAbortIfNeeded() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard sinkBegun, !sinkCommitted, !abortClaimed else { return false }
        abortClaimed = true
        return true
    }

    func closeSource() {
        lock.lock()
        let source = self.source
        self.source = nil
        lock.unlock()
        source?.close()
    }
}
