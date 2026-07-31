package com.example.mediacapture.ui

import android.app.Activity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import com.example.mediacapture.api.FailureCode
import java.util.concurrent.CompletableFuture
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertTrue
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.android.controller.ActivityController

@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
class MediaCaptureUiPresenterTest {
    @Test
    fun ownerRegistryRejectsOtherPresentersUntilCleanupCompletes() = runTest {
        val fixture = fixture()
        val firstPresenter = fixture.presenter()
        val secondPresenter = fixture.presenter()
        val firstSession = firstPresenter.present()
        runCurrent()

        assertFailsWith<IllegalStateException> { secondPresenter.present() }

        firstSession.dismiss()
        assertFailsWith<IllegalStateException> { secondPresenter.present() }

        advanceUntilIdle()
        assertIs<MediaCaptureFlowResult.Cancelled>(firstSession.awaitResult())

        val secondSession = secondPresenter.present()
        runCurrent()
        secondSession.dismiss()
        advanceUntilIdle()

        assertIs<MediaCaptureFlowResult.Cancelled>(secondSession.awaitResult())
    }

    @Test
    fun ownerRegistryUsesActivityIdentityAcrossLifecycleOwners() = runTest {
        val fixture = fixture()
        val firstOwner = StandaloneLifecycleOwner(Lifecycle.State.CREATED)
        val secondOwner = StandaloneLifecycleOwner(Lifecycle.State.CREATED)
        val firstSession = fixture.presenter(firstOwner).present()
        runCurrent()

        assertFailsWith<IllegalStateException> {
            fixture.presenter(secondOwner).present()
        }

        firstSession.dismiss()
        advanceUntilIdle()

        val secondSession = fixture.presenter(secondOwner).present()
        runCurrent()
        secondSession.dismiss()
        advanceUntilIdle()
    }

    @Test
    fun ownerRegistryDoesNotUseActivityEqualsOrHashCode() = runTest {
        val firstFixture = fixture()
        val secondFixture = fixture()

        val firstSession = firstFixture.presenter().present()
        val secondSession = secondFixture.presenter().present()
        runCurrent()

        firstSession.dismiss()
        secondSession.dismiss()
        advanceUntilIdle()

        assertIs<MediaCaptureFlowResult.Cancelled>(firstSession.awaitResult())
        assertIs<MediaCaptureFlowResult.Cancelled>(secondSession.awaitResult())
    }

    @Test
    fun cleanupFailureKeepsActivitySlotPoisoned() = runTest {
        val fixture = fixture()
        val session = fixture.presenter().present()
        advanceUntilIdle()
        fixture.fake.cancelFailuresRemaining = 1

        session.dismiss()
        advanceUntilIdle()

        assertIs<MediaCaptureFlowResult.Cancelled>(session.awaitResult())
        assertFailsWith<IllegalStateException> { fixture.presenter().present() }
    }

    @Test
    fun cancelledAwaiterCannotCancelFlowOrReleaseOwnerSlot() = runTest {
        val fixture = fixture()
        val session = fixture.presenter().present()
        runCurrent()
        val waiter = launch { session.awaitResult() }
        runCurrent()

        waiter.cancelAndJoin()

        assertFailsWith<IllegalStateException> { fixture.presenter().present() }

        session.dismiss()
        advanceUntilIdle()

        assertEquals(1, fixture.fake.calls.count { it == "cancel" })
        assertIs<MediaCaptureFlowResult.Cancelled>(session.awaitResult())
    }

    @Test
    fun sessionForwardsDisplayRotationThroughProductionEntry() = runTest {
        val fixture = fixture()
        val session = fixture.presenter().present()
        advanceUntilIdle()

        session.onDisplayRotationChanged()
        advanceUntilIdle()

        assertTrue("rotation" in fixture.fake.calls)
        assertEquals(listOf(1L, 2L), fixture.fake.liveAttachGenerations)

        session.dismiss()
        advanceUntilIdle()
    }

    @Test
    fun ownerDestroyCompletesFailureUsingModuleOwnedScope() = runTest {
        val fixture = fixture()
        val session = fixture.presenter().present()
        advanceUntilIdle()

        fixture.activity.moveTo(Lifecycle.State.DESTROYED)
        advanceUntilIdle()

        val result = assertIs<MediaCaptureFlowResult.Failure>(session.awaitResult())
        assertEquals(FailureCode.SYSTEM_INTERRUPTED, result.failure.code)
        assertEquals(1, fixture.fake.calls.count { it == "cancel" })
    }

    @Test
    fun activityDestroyClosesFlowWithIndependentLifecycleOwner() = runTest {
        val fixture = fixture()
        val owner = StandaloneLifecycleOwner(Lifecycle.State.CREATED)
        val session = fixture.presenter(owner).present()
        advanceUntilIdle()

        fixture.controller.destroy()
        advanceUntilIdle()

        val result = assertIs<MediaCaptureFlowResult.Failure>(session.awaitResult())
        assertEquals(FailureCode.SYSTEM_INTERRUPTED, result.failure.code)
    }

    @Test
    fun invalidLifecycleIsRejectedBeforeOwnerSlotAcquisition() = runTest {
        val fixture = fixture(Lifecycle.State.INITIALIZED)
        val presenter = fixture.presenter()

        assertFailsWith<IllegalStateException> { presenter.present() }

        fixture.activity.moveTo(Lifecycle.State.CREATED)
        val session = presenter.present()
        runCurrent()
        session.dismiss()
        advanceUntilIdle()
    }

    @Test
    fun offMainThreadPresentationIsRejected() = runTest {
        val fixture = fixture()
        val failure = CompletableFuture<Throwable?>()

        val thread =
            Thread {
                failure.complete(runCatching { fixture.presenter().present() }.exceptionOrNull())
            }
        thread.start()
        thread.join()

        assertIs<IllegalStateException>(failure.get())
    }

    private fun TestScope.fixture(state: Lifecycle.State = Lifecycle.State.CREATED): Fixture {
        val controller = Robolectric.buildActivity(PresenterTestActivity::class.java).create()
        val activity = controller.get()
        activity.moveTo(state)
        val dispatcher = StandardTestDispatcher(testScheduler)
        val fake = FakeMediaCapture(activity, activity, dispatcher)
        return Fixture(controller, activity, dispatcher, fake)
    }

    private data class Fixture(
        val controller: ActivityController<PresenterTestActivity>,
        val activity: PresenterTestActivity,
        val dispatcher: CoroutineDispatcher,
        val fake: FakeMediaCapture,
    ) {
        fun presenter(owner: LifecycleOwner = activity): MediaCaptureUiPresenter =
            MediaCaptureUiPresenter(
                activity = activity,
                lifecycleOwner = owner,
                mediaCapture = fake,
                uiDispatcher = dispatcher,
            )
    }
}

private class StandaloneLifecycleOwner(state: Lifecycle.State) : LifecycleOwner {
    private val registry = LifecycleRegistry(this).apply { currentState = state }

    override val lifecycle: Lifecycle
        get() = registry
}

class PresenterTestActivity : Activity(), LifecycleOwner {
    private val registry = LifecycleRegistry(this)

    override val lifecycle: Lifecycle
        get() = registry

    fun moveTo(state: Lifecycle.State) {
        registry.currentState = state
    }

    override fun equals(other: Any?): Boolean = other is PresenterTestActivity

    override fun hashCode(): Int = 1
}
