package com.example.mediacapture.ui

import android.app.Activity
import android.app.Application
import android.app.Dialog
import android.os.Bundle
import android.os.Looper
import android.view.ViewGroup
import android.view.Window
import android.view.WindowManager
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import com.example.mediacapture.api.MediaCapture
import java.lang.ref.WeakReference
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers

class MediaCaptureUiPresenter internal constructor(
    private val activity: Activity,
    private val lifecycleOwner: LifecycleOwner,
    private val mediaCapture: MediaCapture,
    private val uiDispatcher: CoroutineDispatcher,
) {
    constructor(
        activity: Activity,
        lifecycleOwner: LifecycleOwner,
        mediaCapture: MediaCapture,
    ) : this(
        activity = activity,
        lifecycleOwner = lifecycleOwner,
        mediaCapture = mediaCapture,
        uiDispatcher = Dispatchers.Main.immediate,
    )

    fun present(config: MediaCaptureUiConfig = MediaCaptureUiConfig()): MediaCaptureFlowSession {
        check(Looper.myLooper() === Looper.getMainLooper()) {
            "Media capture UI must be presented on the main thread."
        }
        check(!activity.isFinishing && !activity.isDestroyed) {
            "Media capture UI requires a live Activity."
        }
        check(lifecycleOwner.lifecycle.currentState.isAtLeast(Lifecycle.State.CREATED)) {
            "Media capture UI requires a LifecycleOwner in at least CREATED state."
        }

        val presentationToken = Any()
        check(MediaCapturePresentationRegistry.acquire(activity, presentationToken)) {
            "Media capture UI is already presented for this owner."
        }

        val dialog: Dialog
        val coordinator: MediaCaptureFlowCoordinator
        try {
            dialog =
                Dialog(activity, android.R.style.Theme_Black_NoTitleBar_Fullscreen).apply {
                    requestWindowFeature(Window.FEATURE_NO_TITLE)
                }
            val chrome = MediaCaptureChromeView(activity)
            dialog.setContentView(
                chrome,
                ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                ),
            )
            coordinator =
                MediaCaptureFlowCoordinator(
                    context = activity,
                    lifecycleOwner = lifecycleOwner,
                    mediaCapture = mediaCapture,
                    chrome = chrome,
                    uiDispatcher = uiDispatcher,
                )
        } catch (throwable: Throwable) {
            MediaCapturePresentationRegistry.release(activity, presentationToken)
            throw throwable
        }

        lateinit var lifecycleObserver: DefaultLifecycleObserver
        lifecycleObserver =
            object : DefaultLifecycleObserver {
                override fun onStart(owner: LifecycleOwner) {
                    coordinator.foregroundOwner()
                }

                override fun onStop(owner: LifecycleOwner) {
                    coordinator.backgroundOwner()
                }

                override fun onDestroy(owner: LifecycleOwner) {
                    owner.lifecycle.removeObserver(this)
                    coordinator.destroyOwner()
                    if (dialog.isShowing) dialog.dismiss()
                }
            }

        val activityLifecycleCallbacks =
            object : Application.ActivityLifecycleCallbacks {
                override fun onActivityCreated(createdActivity: Activity, savedInstanceState: Bundle?) = Unit

                override fun onActivityStarted(startedActivity: Activity) = Unit

                override fun onActivityResumed(resumedActivity: Activity) = Unit

                override fun onActivityPaused(pausedActivity: Activity) = Unit

                override fun onActivityStopped(stoppedActivity: Activity) = Unit

                override fun onActivitySaveInstanceState(
                    savedActivity: Activity,
                    outState: Bundle,
                ) = Unit

                override fun onActivityDestroyed(destroyedActivity: Activity) {
                    if (destroyedActivity !== activity) return
                    coordinator.destroyOwner()
                    if (dialog.isShowing) dialog.dismiss()
                }
            }

        coordinator.setTerminalListener { cleanupSucceeded ->
            var presentationCleanupSucceeded = cleanupSucceeded
            try {
                lifecycleOwner.lifecycle.removeObserver(lifecycleObserver)
            } catch (throwable: Throwable) {
                presentationCleanupSucceeded = false
            }
            try {
                activity.application.unregisterActivityLifecycleCallbacks(activityLifecycleCallbacks)
            } catch (throwable: Throwable) {
                presentationCleanupSucceeded = false
            }
            try {
                if (dialog.isShowing) dialog.dismiss()
            } catch (throwable: Throwable) {
                presentationCleanupSucceeded = false
            }
            if (presentationCleanupSucceeded) {
                MediaCapturePresentationRegistry.release(activity, presentationToken)
            }
        }
        val activityReference = WeakReference(activity)
        coordinator.setCleanupRecoveredListener {
            activityReference.get()?.let { owner ->
                MediaCapturePresentationRegistry.release(owner, presentationToken)
            }
        }
        dialog.setOnDismissListener { coordinator.cancelFromPresenter() }

        try {
            activity.application.registerActivityLifecycleCallbacks(activityLifecycleCallbacks)
            lifecycleOwner.lifecycle.addObserver(lifecycleObserver)
            dialog.show()
            dialog.window?.setLayout(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
            )
            coordinator.launch { coordinator.start(config) }
        } catch (throwable: Throwable) {
            coordinator.presentationFailed(throwable)
        }

        return MediaCaptureFlowSession(
            awaitAction = coordinator::awaitResult,
            dismissAction = coordinator::cancelFromPresenter,
            rotationAction = coordinator::rotateOwner,
        )
    }
}

class MediaCaptureFlowSession internal constructor(
    private val awaitAction: suspend () -> MediaCaptureFlowResult,
    private val dismissAction: () -> Unit,
    private val rotationAction: () -> Unit,
) {
    suspend fun awaitResult(): MediaCaptureFlowResult = awaitAction()

    fun dismiss() {
        dismissAction()
    }

    fun onDisplayRotationChanged() {
        rotationAction()
    }
}

private object MediaCapturePresentationRegistry {
    private data class Entry(val owner: WeakReference<Activity>, val token: Any)

    private val entries = mutableListOf<Entry>()

    @Synchronized
    fun acquire(owner: Activity, token: Any): Boolean {
        entries.removeAll { it.owner.get() == null }
        if (entries.any { it.owner.get() === owner }) return false
        entries += Entry(WeakReference(owner), token)
        return true
    }

    @Synchronized
    fun release(owner: Activity, token: Any) {
        entries.removeAll { entry ->
            val currentOwner = entry.owner.get()
            currentOwner == null || (currentOwner === owner && entry.token === token)
        }
    }
}
