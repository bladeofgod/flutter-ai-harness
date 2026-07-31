import AVFoundation
import MediaCaptureAppleRendering
import XCTest
@testable import MediaCapture

@MainActor
final class RenderAttachmentTests: XCTestCase {
    func testMissingConcreteSurfaceIsRejectedBeforeGenerationMutation() async throws {
        let fixture = CoreFixture()
        let session = try await fixture.startReadySession()
        let missingSurface = MediaCaptureRenderSurfaceOwner(ownerGeneration: 5)

        let failure = await captureFailure {
            _ = try await fixture.core.attachLivePreview(
                sessionHandle: session,
                surfaceOwner: missingSurface
            )
        }
        XCTAssertEqual(failure?.id, .invalidArgument)

        let validOwner = MediaCaptureRenderSurfaceOwner(ownerGeneration: 5)
        let view = try MediaCaptureRenderSurfaceFactory.make(owner: validOwner)
        _ = try await fixture.core.attachLivePreview(
            sessionHandle: session,
            surfaceOwner: validOwner
        )
        XCTAssertTrue(view.layer.sublayers?.first is AVCaptureVideoPreviewLayer)
        await fixture.core.close()
    }

    func testConcreteSurfacePipelineReplacesAndRejectsStaleGeneration() async throws {
        let fixture = CoreFixture()
        let session = try await fixture.startReadySession()
        let firstOwner = MediaCaptureRenderSurfaceOwner(ownerGeneration: 1)
        let firstView = try MediaCaptureRenderSurfaceFactory.make(owner: firstOwner)
        let secondOwner = MediaCaptureRenderSurfaceOwner(ownerGeneration: 2)
        let secondView = try MediaCaptureRenderSurfaceFactory.make(owner: secondOwner)

        _ = try await fixture.core.attachLivePreview(
            sessionHandle: session,
            surfaceOwner: firstOwner
        )
        XCTAssertTrue(firstView.layer.sublayers?.first is AVCaptureVideoPreviewLayer)

        _ = try await fixture.core.attachLivePreview(
            sessionHandle: session,
            surfaceOwner: secondOwner
        )
        XCTAssertTrue(firstView.layer.sublayers?.isEmpty ?? true)
        XCTAssertTrue(secondView.layer.sublayers?.first is AVCaptureVideoPreviewLayer)

        let stale = await captureFailure {
            _ = try await fixture.core.attachLivePreview(
                sessionHandle: session,
                surfaceOwner: firstOwner
            )
        }
        XCTAssertEqual(stale?.id, .attachmentGenerationRetired)
        XCTAssertTrue(secondView.layer.sublayers?.first is AVCaptureVideoPreviewLayer)

        _ = try await fixture.core.detachLivePreview(
            sessionHandle: session,
            surfaceOwner: secondOwner
        )
        XCTAssertTrue(secondView.layer.sublayers?.isEmpty ?? true)
        await fixture.core.close()
    }

    func testGenerationHighWatermarkIdentityAndReplacementOrder() async throws {
        let fixture = CoreFixture()
        let session = try await fixture.startReadySession()
        let first = FakeRenderTarget(ownerGeneration: 1)
        let conflictTarget = FakeRenderTarget(ownerGeneration: 1)
        let replacement = FakeRenderTarget(ownerGeneration: 2)

        _ = try await fixture.core.attachLivePreview(
            sessionHandle: session,
            surfaceOwner: first.surfaceOwner
        )
        let firstBinding = try XCTUnwrap(first.bindings.first)
        await firstBinding.emitFrame()
        XCTAssertEqual(firstBinding.renderedFrameCount, 1)
        _ = try await fixture.core.attachLivePreview(
            sessionHandle: session,
            surfaceOwner: first.surfaceOwner
        )
        XCTAssertEqual(first.callbacks, ["attach:1"])

        let conflict = await captureFailure {
            _ = try await fixture.core.attachLivePreview(
                sessionHandle: session,
                surfaceOwner: conflictTarget.surfaceOwner
            )
        }
        XCTAssertEqual(conflict?.id, .attachmentTargetConflict)

        _ = try await fixture.core.attachLivePreview(
            sessionHandle: session,
            surfaceOwner: replacement.surfaceOwner
        )
        XCTAssertEqual(first.callbacks, ["attach:1", "revoke:1", "detach:1"])
        XCTAssertEqual(replacement.callbacks, ["attach:2"])
        XCTAssertEqual(firstBinding.revokeCount, 1)
        XCTAssertEqual(firstBinding.detachCount, 1)
        await firstBinding.emitFrame()
        XCTAssertEqual(firstBinding.renderedFrameCount, 1)
        let secondBinding = try XCTUnwrap(replacement.bindings.first)
        await secondBinding.emitFrame()
        XCTAssertEqual(secondBinding.renderedFrameCount, 1)

        let stale = await captureFailure {
            _ = try await fixture.core.attachLivePreview(
                sessionHandle: session,
                surfaceOwner: first.surfaceOwner
            )
        }
        XCTAssertEqual(stale?.id, .attachmentGenerationRetired)
        _ = try await fixture.core.detachLivePreview(
            sessionHandle: session,
            surfaceOwner: conflictTarget.surfaceOwner
        )
        XCTAssertEqual(replacement.callbacks, ["attach:2"])
        _ = try await fixture.core.detachLivePreview(
            sessionHandle: session,
            surfaceOwner: replacement.surfaceOwner
        )
        XCTAssertEqual(replacement.callbacks, ["attach:2", "revoke:2", "detach:2"])

        let retired = await captureFailure {
            _ = try await fixture.core.attachLivePreview(
                sessionHandle: session,
                surfaceOwner: replacement.surfaceOwner
            )
        }
        XCTAssertEqual(retired?.id, .attachmentGenerationRetired)
        await fixture.core.close()
    }

    func testUnconfirmedAttachmentRevokesBeforeConfirmAndOwnerDestroy() async throws {
        let fixture = CoreFixture()
        let session = try await fixture.startReadySession(mediaTypes: [.photo])
        let preview = try await fixture.core.takePhoto(sessionHandle: session)
        let target = FakeRenderTarget(ownerGeneration: 4)
        _ = try await fixture.core.attachUnconfirmedPreviewRender(
            mediaHandle: preview.mediaHandle,
            surfaceOwner: target.surfaceOwner
        )
        let previewBinding = try XCTUnwrap(target.bindings.first)
        await previewBinding.emitFrame()
        XCTAssertEqual(previewBinding.renderedFrameCount, 1)
        target.invalidateOwner()
        let ownerWasRevoked = await waitUntil {
            await MainActor.run { target.callbacks.count == 3 }
        }
        XCTAssertTrue(ownerWasRevoked)
        XCTAssertEqual(target.callbacks, ["attach:4", "revoke:4", "detach:4"])
        await previewBinding.emitFrame()
        XCTAssertEqual(previewBinding.renderedFrameCount, 1)

        let second = FakeRenderTarget(ownerGeneration: 5)
        _ = try await fixture.core.attachUnconfirmedPreviewRender(
            mediaHandle: preview.mediaHandle,
            surfaceOwner: second.surfaceOwner
        )
        _ = try await fixture.core.confirm(mediaHandle: preview.mediaHandle)
        XCTAssertEqual(second.callbacks, ["attach:5", "revoke:5", "detach:5"])
        await fixture.core.close()
    }

    func testBackgroundRevokesBothAttachmentKinds() async throws {
        let fixture = CoreFixture()
        let session = try await fixture.startReadySession()
        let live = FakeRenderTarget(ownerGeneration: 1)
        _ = try await fixture.core.attachLivePreview(
            sessionHandle: session,
            surfaceOwner: live.surfaceOwner
        )
        await fixture.core.appDidEnterBackground()
        XCTAssertEqual(live.callbacks, ["attach:1", "revoke:1", "detach:1"])
        _ = try await fixture.core.cancel(sessionHandle: session)

        let nextSession = try await fixture.startReadySession(mediaTypes: [.photo])
        let preview = try await fixture.core.takePhoto(sessionHandle: nextSession)
        let unconfirmed = FakeRenderTarget(ownerGeneration: 1)
        _ = try await fixture.core.attachUnconfirmedPreviewRender(
            mediaHandle: preview.mediaHandle,
            surfaceOwner: unconfirmed.surfaceOwner
        )
        await fixture.core.appDidEnterBackground()
        XCTAssertEqual(unconfirmed.callbacks, ["attach:1", "revoke:1", "detach:1"])
        await fixture.core.close()
    }

    func testRotationAndReleasedTargetStillDetachOwnedBinding() async throws {
        let fixture = CoreFixture()
        let session = try await fixture.startReadySession()
        var target: FakeRenderTarget? = FakeRenderTarget(ownerGeneration: 1)
        weak let weakTarget = target
        _ = try await fixture.core.attachLivePreview(
            sessionHandle: session,
            surfaceOwner: try XCTUnwrap(target).surfaceOwner
        )
        let binding = try XCTUnwrap(target?.bindings.first)
        target = nil
        XCTAssertNil(weakTarget)
        await fixture.core.displayRotationChanged()
        let detached = await waitUntil { await MainActor.run { binding.detachCount == 1 } }
        XCTAssertTrue(detached)
        XCTAssertEqual(binding.revokeCount, 1)
        await fixture.core.close()
    }

    func testRestartRevokesBindingAndInvalidatesOldScope() async throws {
        let fixture = CoreFixture()
        let session = try await fixture.startReadySession()
        let target = FakeRenderTarget(ownerGeneration: 9)
        _ = try await fixture.core.attachLivePreview(
            sessionHandle: session,
            surfaceOwner: target.surfaceOwner
        )
        let binding = try XCTUnwrap(target.bindings.first)
        await fixture.core.appRestarted()
        XCTAssertEqual(binding.revokeCount, 1)
        XCTAssertEqual(binding.detachCount, 1)
        let failure = await captureFailure {
            _ = try await fixture.core.detachLivePreview(
                sessionHandle: session,
                surfaceOwner: target.surfaceOwner
            )
        }
        XCTAssertEqual(failure?.id, .sessionInvalid)
        await fixture.core.close()
    }

    func testLiveOwnerDestroyRevokesAndDetachesBinding() async throws {
        let fixture = CoreFixture()
        let session = try await fixture.startReadySession()
        let target = FakeRenderTarget(ownerGeneration: 3)
        _ = try await fixture.core.attachLivePreview(
            sessionHandle: session,
            surfaceOwner: target.surfaceOwner
        )
        let binding = try XCTUnwrap(target.bindings.first)
        target.invalidateOwner()
        let detached = await waitUntil {
            await MainActor.run { binding.detachCount == 1 }
        }
        XCTAssertTrue(detached)
        XCTAssertEqual(target.callbacks, ["attach:3", "revoke:3", "detach:3"])
        await fixture.core.close()
    }

    func testRotationInvalidatesPendingLiveMountBeforeSurfaceMutation() async throws {
        let fixture = CoreFixture()
        let session = try await fixture.startReadySession()
        let target = FakeRenderTarget(ownerGeneration: 1)
        let mountGate = TestAsyncGate()
        target.mountGate = mountGate

        let attach = Task {
            await captureFailure {
                _ = try await fixture.core.attachLivePreview(
                    sessionHandle: session,
                    surfaceOwner: target.surfaceOwner
                )
            }
        }
        let mountDidStart = await waitUntil { await MainActor.run { target.mountStarted } }
        XCTAssertTrue(mountDidStart)

        let rotation = Task { await fixture.core.displayRotationChanged() }
        let invalidated = await waitUntil {
            await MainActor.run { target.pendingCallbackGate?.acceptsMutations == false }
        }
        XCTAssertTrue(invalidated)
        mountGate.release()

        await rotation.value
        let attachFailure = await attach.value
        XCTAssertEqual(attachFailure?.id, .attachmentGenerationRetired)
        XCTAssertTrue(target.bindings.isEmpty)
        XCTAssertTrue(target.callbacks.isEmpty)
        await fixture.core.close()
    }

    func testOwnerDestroyInvalidatesPendingUnconfirmedMountBeforeSurfaceMutation() async throws {
        let fixture = CoreFixture()
        let session = try await fixture.startReadySession(mediaTypes: [.photo])
        let preview = try await fixture.core.takePhoto(sessionHandle: session)
        let target = FakeRenderTarget(ownerGeneration: 1)
        let mountGate = TestAsyncGate()
        target.mountGate = mountGate

        let attach = Task {
            await captureFailure {
                _ = try await fixture.core.attachUnconfirmedPreviewRender(
                    mediaHandle: preview.mediaHandle,
                    surfaceOwner: target.surfaceOwner
                )
            }
        }
        let mountDidStart = await waitUntil { await MainActor.run { target.mountStarted } }
        XCTAssertTrue(mountDidStart)

        target.invalidateOwner()
        let invalidated = await waitUntil {
            await MainActor.run { target.pendingCallbackGate?.acceptsMutations == false }
        }
        XCTAssertTrue(invalidated)
        mountGate.release()

        let attachFailure = await attach.value
        XCTAssertEqual(attachFailure?.id, .attachmentGenerationRetired)
        XCTAssertTrue(target.bindings.isEmpty)
        XCTAssertTrue(target.callbacks.isEmpty)
        await fixture.core.close()
    }

    func testReplacementWaitsForPriorRendererCleanupBeforeMounting() async throws {
        let fixture = CoreFixture()
        let session = try await fixture.startReadySession()
        let first = FakeRenderTarget(ownerGeneration: 1)
        let replacement = FakeRenderTarget(ownerGeneration: 2)
        let competing = FakeRenderTarget(ownerGeneration: 3)

        _ = try await fixture.core.attachLivePreview(
            sessionHandle: session,
            surfaceOwner: first.surfaceOwner
        )
        let firstBinding = try XCTUnwrap(first.bindings.first)
        let revokeGate = TestAsyncGate()
        firstBinding.revokeGate = revokeGate

        let replacementAttach = Task {
            try await fixture.core.attachLivePreview(
                sessionHandle: session,
                surfaceOwner: replacement.surfaceOwner
            )
        }
        let revokeDidStart = await waitUntil {
            await MainActor.run { firstBinding.revokeStarted }
        }
        XCTAssertTrue(revokeDidStart)

        let competingFailure = await captureFailure {
            _ = try await fixture.core.attachLivePreview(
                sessionHandle: session,
                surfaceOwner: competing.surfaceOwner
            )
        }
        XCTAssertEqual(competingFailure?.id, .attachmentTargetConflict)
        XCTAssertFalse(replacement.mountStarted)
        XCTAssertTrue(replacement.bindings.isEmpty)

        revokeGate.release()
        _ = try await replacementAttach.value
        XCTAssertTrue(replacement.mountStarted)
        XCTAssertEqual(firstBinding.revokeCount, 1)
        XCTAssertEqual(firstBinding.detachCount, 1)
        XCTAssertEqual(replacement.callbacks, ["attach:2"])
        await fixture.core.close()
    }
}
