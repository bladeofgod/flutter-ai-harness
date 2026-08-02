import MediaCapture
import UIKit

@MainActor
public final class MediaCaptureFlowSession {
    private let coordinator: MediaCaptureFlowCoordinator

    internal init(coordinator: MediaCaptureFlowCoordinator) {
        self.coordinator = coordinator
    }

    public func awaitResult() async throws -> MediaCaptureFlowResult {
        try await coordinator.awaitCancellableResult()
    }

    public func dismiss() {
        coordinator.dismissByCaller()
    }

    public func onDisplayRotationChanged() {
        coordinator.displayRotationChanged()
    }

    internal var resultWaiterRegisteredForTesting: Bool {
        coordinator.cancellableResultWaiterCount > 0
    }
}

@MainActor
public final class MediaCaptureUiPresenter {
    private weak var presentingViewController: UIViewController?
    private let core: any MediaCaptureServicing
    private let dismissalAction: MediaCaptureDismissalAction
    private let leaseCleanupOwner: MediaCaptureLeaseCleanupOwner
    private let settleTimeoutNanoseconds: UInt64

    public init(
        presentingViewController: UIViewController,
        core: MediaCaptureCore
    ) {
        self.presentingViewController = presentingViewController
        self.core = MediaCaptureCoreService(core: core)
        self.dismissalAction = { viewController, completion in
            viewController.dismiss(animated: false, completion: completion)
        }
        self.leaseCleanupOwner = .shared
        self.settleTimeoutNanoseconds = 5_000_000_000
    }

    internal init(
        presentingViewController: UIViewController,
        core: any MediaCaptureServicing,
        leaseCleanupOwner: MediaCaptureLeaseCleanupOwner = .shared,
        settleTimeoutNanoseconds: UInt64 = 5_000_000_000,
        dismissalAction: @escaping MediaCaptureDismissalAction = { viewController, completion in
            viewController.dismiss(animated: false, completion: completion)
        }
    ) {
        self.presentingViewController = presentingViewController
        self.core = core
        self.leaseCleanupOwner = leaseCleanupOwner
        self.settleTimeoutNanoseconds = settleTimeoutNanoseconds
        self.dismissalAction = dismissalAction
    }

    public func present(
        configuration: MediaCaptureUiConfiguration
    ) throws -> MediaCaptureFlowSession {
        guard let owner = presentingViewController,
              owner.viewIfLoaded?.window != nil
        else {
            throw MediaCaptureUiPresentationError.ownerUnavailable
        }
        guard owner.presentedViewController == nil else {
            throw MediaCaptureUiPresentationError.presentationConflict
        }
        let reservation = try MediaCapturePresentationRegistry.acquire(owner: owner)
        let completion = MediaCaptureFlowCompletion()
        let coordinator = MediaCaptureFlowCoordinator(
            core: core,
            configuration: configuration,
            initialSurfaceGeneration: reservation.generation,
            completion: completion,
            leaseCleanupOwner: leaseCleanupOwner,
            settleTimeoutNanoseconds: settleTimeoutNanoseconds,
            dismissalAction: dismissalAction,
            releasePresentationSlot: {
                MediaCapturePresentationRegistry.release(
                    ownerIdentifier: reservation.ownerIdentifier,
                    token: reservation.token
                )
            }
        )
        let captureViewController = MediaCaptureViewController(coordinator: coordinator)
        coordinator.install(viewController: captureViewController)
        owner.present(captureViewController, animated: false)
        guard owner.presentedViewController === captureViewController else {
            MediaCapturePresentationRegistry.release(
                ownerIdentifier: reservation.ownerIdentifier,
                token: reservation.token
            )
            throw MediaCaptureUiPresentationError.presentationFailed
        }
        return MediaCaptureFlowSession(coordinator: coordinator)
    }
}

@MainActor
internal enum MediaCapturePresentationRegistry {
    struct Reservation {
        let ownerIdentifier: ObjectIdentifier
        let token: UUID
        let generation: Int64
    }

    private final class Slot {
        weak var owner: UIViewController?
        let token: UUID

        init(owner: UIViewController, token: UUID) {
            self.owner = owner
            self.token = token
        }
    }

    private static var slots: [ObjectIdentifier: Slot] = [:]
    private static var nextGeneration: Int64 = 0

    static func acquire(owner: UIViewController) throws -> Reservation {
        slots = slots.filter { $0.value.owner != nil }
        let identifier = ObjectIdentifier(owner)
        guard slots[identifier] == nil else {
            throw MediaCaptureUiPresentationError.presentationConflict
        }
        nextGeneration = nextGeneration == Int64.max ? 1 : nextGeneration + 1
        let token = UUID()
        slots[identifier] = Slot(owner: owner, token: token)
        return Reservation(
            ownerIdentifier: identifier,
            token: token,
            generation: nextGeneration
        )
    }

    static func release(ownerIdentifier: ObjectIdentifier, token: UUID) {
        guard slots[ownerIdentifier]?.token == token else { return }
        slots.removeValue(forKey: ownerIdentifier)
    }

}
