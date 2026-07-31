package com.example.media_capture

import android.app.Activity
import android.content.pm.PackageManager
import com.example.mediacapture.api.CameraPosition
import com.example.mediacapture.api.FailureCode
import com.example.mediacapture.api.MediaType
import com.example.mediacapture.api.PermissionResource
import com.example.mediacapture.api.PermissionState
import com.example.mediacapture.api.SessionOptions
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf

@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
class MediaCapturePermissionDelegateTest {
    @Test
    fun requestsOnlyExplicitResourceAndMapsGrant() = runTest {
        val activity = Robolectric.buildActivity(Activity::class.java).create().get()
        shadowOf(activity.packageManager).setSystemFeature(PackageManager.FEATURE_CAMERA_ANY, true)
        val binding = FakeActivityPluginBinding(activity)
        val delegate =
            MediaCapturePermissionDelegate(
                activity,
                binding,
                StandardTestDispatcher(testScheduler),
                requestCodeProvider = { 51_200 },
            )

        assertEquals(PermissionState.NOT_DETERMINED, delegate.currentState(PermissionResource.CAMERA))
        val result = async { delegate.request(PermissionResource.CAMERA) }
        runCurrent()
        val listener = binding.permissionListener
        assertSame(delegate, listener)

        listener?.onRequestPermissionsResult(
            51_200,
            arrayOf(android.Manifest.permission.CAMERA),
            intArrayOf(PackageManager.PERMISSION_GRANTED),
        )
        runCurrent()

        assertEquals(PermissionState.GRANTED, result.await())
        delegate.close()
        assertNull(binding.permissionListener)
    }

    @Test
    fun ignoresMismatchedPermissionCallbackWithoutConsumingRequest() = runTest {
        val activity = Robolectric.buildActivity(Activity::class.java).create().get()
        shadowOf(activity.packageManager).setSystemFeature(PackageManager.FEATURE_CAMERA_ANY, true)
        val binding = FakeActivityPluginBinding(activity)
        val delegate =
            MediaCapturePermissionDelegate(
                activity,
                binding,
                StandardTestDispatcher(testScheduler),
                requestCodeProvider = { 60_000 },
            )
        val result = async { delegate.request(PermissionResource.CAMERA) }
        runCurrent()

        assertFalse(
            delegate.onRequestPermissionsResult(
                60_000,
                arrayOf(android.Manifest.permission.RECORD_AUDIO),
                intArrayOf(PackageManager.PERMISSION_GRANTED),
            ),
        )
        assertFalse(result.isCompleted)
        assertTrue(
            delegate.onRequestPermissionsResult(
                60_000,
                arrayOf(android.Manifest.permission.CAMERA),
                intArrayOf(PackageManager.PERMISSION_GRANTED),
            ),
        )
        runCurrent()

        assertEquals(PermissionState.GRANTED, result.await())
        delegate.close()
    }

    @Test
    fun emptyPermissionCallbackCompletesOnceAndAllowsRetryWithNextRequestCode() = runTest {
        val activity = Robolectric.buildActivity(Activity::class.java).create().get()
        shadowOf(activity.packageManager).setSystemFeature(PackageManager.FEATURE_CAMERA_ANY, true)
        val binding = FakeActivityPluginBinding(activity)
        var requestCode = 51_200
        val delegate =
            MediaCapturePermissionDelegate(
                activity,
                binding,
                StandardTestDispatcher(testScheduler),
                requestCodeProvider = { requestCode++ },
            )
        val first = async { delegate.request(PermissionResource.CAMERA) }
        runCurrent()

        assertTrue(delegate.onRequestPermissionsResult(51_200, emptyArray(), intArrayOf()))
        assertFalse(delegate.onRequestPermissionsResult(51_200, emptyArray(), intArrayOf()))
        runCurrent()
        assertEquals(PermissionState.DENIED, first.await())

        val retry = async { delegate.request(PermissionResource.CAMERA) }
        runCurrent()
        assertTrue(
            delegate.onRequestPermissionsResult(
                51_201,
                arrayOf(android.Manifest.permission.CAMERA),
                intArrayOf(PackageManager.PERMISSION_GRANTED),
            ),
        )
        runCurrent()

        assertEquals(PermissionState.GRANTED, retry.await())
        delegate.close()
    }

    @Test
    fun invalidationCompletesPendingAndPreventsNewPermissionRequests() = runTest {
        val activity = Robolectric.buildActivity(Activity::class.java).create().get()
        shadowOf(activity.packageManager).setSystemFeature(PackageManager.FEATURE_CAMERA_ANY, true)
        val binding = FakeActivityPluginBinding(activity)
        var requestCode = 51_200
        val delegate =
            MediaCapturePermissionDelegate(
                activity,
                binding,
                StandardTestDispatcher(testScheduler),
                requestCodeProvider = { requestCode++ },
            )
        val pending = async { delegate.request(PermissionResource.CAMERA) }
        runCurrent()

        delegate.invalidate()
        runCurrent()

        assertEquals(PermissionState.DENIED, pending.await())
        assertFalse(
            delegate.onRequestPermissionsResult(
                51_200,
                arrayOf(android.Manifest.permission.CAMERA),
                intArrayOf(PackageManager.PERMISSION_GRANTED),
            ),
        )
        assertEquals(PermissionState.DENIED, delegate.request(PermissionResource.CAMERA))
        assertEquals(51_201, requestCode)
        assertSame(delegate, binding.permissionListener)

        delegate.close()
        assertNull(binding.permissionListener)
    }

    @Test
    fun unsupportedHardwareDoesNotRequestPermission() = runTest {
        val activity = Robolectric.buildActivity(Activity::class.java).create().get()
        val binding = FakeActivityPluginBinding(activity)
        val delegate = MediaCapturePermissionDelegate(activity, binding, StandardTestDispatcher(testScheduler))

        assertEquals(PermissionState.UNSUPPORTED, delegate.currentState(PermissionResource.MICROPHONE))
        assertEquals(PermissionState.UNSUPPORTED, delegate.request(PermissionResource.MICROPHONE))
        assertSame(delegate, binding.permissionListener)
        delegate.close()
    }

    @Test
    fun capturePreflightRequestsCameraThenAudioVideoMicrophone() = runTest {
        val activity = Robolectric.buildActivity(Activity::class.java).create().get()
        shadowOf(activity.packageManager).setSystemFeature(PackageManager.FEATURE_CAMERA_ANY, true)
        shadowOf(activity.packageManager).setSystemFeature(PackageManager.FEATURE_MICROPHONE, true)
        val binding = FakeActivityPluginBinding(activity)
        var requestCode = 51_200
        val delegate =
            MediaCapturePermissionDelegate(
                activity,
                binding,
                StandardTestDispatcher(testScheduler),
                requestCodeProvider = { requestCode++ },
            )
        val result = async { delegate.prepareForCapture(videoOptions()) }
        runCurrent()

        assertTrue(
            delegate.onRequestPermissionsResult(
                51_200,
                arrayOf(android.Manifest.permission.CAMERA),
                intArrayOf(PackageManager.PERMISSION_GRANTED),
            ),
        )
        runCurrent()
        assertTrue(
            delegate.onRequestPermissionsResult(
                51_201,
                arrayOf(android.Manifest.permission.RECORD_AUDIO),
                intArrayOf(PackageManager.PERMISSION_GRANTED),
            ),
        )
        runCurrent()

        assertNull(result.await())
        delegate.close()
    }

    @Test
    fun capturePreflightSkipsMicrophoneForPhotoAndSilentVideo() = runTest {
        listOf(photoOptions(), silentVideoOptions()).forEachIndexed { index, options ->
            val activity = Robolectric.buildActivity(Activity::class.java).create().get()
            shadowOf(activity.packageManager).setSystemFeature(PackageManager.FEATURE_CAMERA_ANY, true)
            shadowOf(activity.packageManager).setSystemFeature(PackageManager.FEATURE_MICROPHONE, true)
            val binding = FakeActivityPluginBinding(activity)
            val firstRequestCode = 51_200 + index * 2
            var requestCode = firstRequestCode
            val delegate =
                MediaCapturePermissionDelegate(
                    activity,
                    binding,
                    StandardTestDispatcher(testScheduler),
                    requestCodeProvider = { requestCode++ },
                )
            val result = async { delegate.prepareForCapture(options) }
            runCurrent()

            assertTrue(
                delegate.onRequestPermissionsResult(
                    firstRequestCode,
                    arrayOf(android.Manifest.permission.CAMERA),
                    intArrayOf(PackageManager.PERMISSION_GRANTED),
                ),
            )
            runCurrent()

            assertNull(result.await())
            assertEquals(firstRequestCode + 1, requestCode)
            assertFalse(
                delegate.onRequestPermissionsResult(
                    firstRequestCode + 1,
                    arrayOf(android.Manifest.permission.RECORD_AUDIO),
                    intArrayOf(PackageManager.PERMISSION_GRANTED),
                ),
            )
            delegate.close()
        }
    }

    @Test
    fun capturePreflightStopsBeforePresentationWhenCameraIsDenied() = runTest {
        val activity = Robolectric.buildActivity(Activity::class.java).create().get()
        shadowOf(activity.packageManager).setSystemFeature(PackageManager.FEATURE_CAMERA_ANY, true)
        shadowOf(activity.packageManager).setSystemFeature(PackageManager.FEATURE_MICROPHONE, true)
        val binding = FakeActivityPluginBinding(activity)
        val delegate =
            MediaCapturePermissionDelegate(
                activity,
                binding,
                StandardTestDispatcher(testScheduler),
                requestCodeProvider = { 51_200 },
            )
        val result = async { delegate.prepareForCapture(videoOptions()) }
        runCurrent()

        assertTrue(
            delegate.onRequestPermissionsResult(
                51_200,
                arrayOf(android.Manifest.permission.CAMERA),
                intArrayOf(PackageManager.PERMISSION_DENIED),
            ),
        )
        runCurrent()

        assertEquals(FailureCode.PERMISSION_PERMANENTLY_DENIED, result.await())
        delegate.close()
    }
}

private fun videoOptions(): SessionOptions =
    SessionOptions(
        enabledMediaTypes = setOf(MediaType.PHOTO, MediaType.VIDEO),
        preferredCamera = CameraPosition.REAR,
        audioEnabled = true,
        maxVideoDurationMillis = 60_000L,
    )

private fun photoOptions(): SessionOptions =
    SessionOptions(
        enabledMediaTypes = setOf(MediaType.PHOTO),
        preferredCamera = CameraPosition.REAR,
        audioEnabled = true,
        maxVideoDurationMillis = 60_000L,
    )

private fun silentVideoOptions(): SessionOptions =
    SessionOptions(
        enabledMediaTypes = setOf(MediaType.PHOTO, MediaType.VIDEO),
        preferredCamera = CameraPosition.REAR,
        audioEnabled = false,
        maxVideoDurationMillis = 60_000L,
    )

private class FakeActivityPluginBinding(
    private val boundActivity: Activity,
) : ActivityPluginBinding {
    var permissionListener: PluginRegistry.RequestPermissionsResultListener? = null

    override fun getActivity(): Activity = boundActivity

    override fun getLifecycle(): Any = Any()

    override fun addRequestPermissionsResultListener(
        listener: PluginRegistry.RequestPermissionsResultListener,
    ) {
        permissionListener = listener
    }

    override fun removeRequestPermissionsResultListener(
        listener: PluginRegistry.RequestPermissionsResultListener,
    ) {
        if (permissionListener === listener) permissionListener = null
    }

    override fun addActivityResultListener(listener: PluginRegistry.ActivityResultListener) = Unit

    override fun removeActivityResultListener(listener: PluginRegistry.ActivityResultListener) = Unit

    override fun addOnNewIntentListener(listener: PluginRegistry.NewIntentListener) = Unit

    override fun removeOnNewIntentListener(listener: PluginRegistry.NewIntentListener) = Unit

    override fun addOnUserLeaveHintListener(listener: PluginRegistry.UserLeaveHintListener) = Unit

    override fun removeOnUserLeaveHintListener(listener: PluginRegistry.UserLeaveHintListener) = Unit

    override fun addOnWindowFocusChangedListener(
        listener: PluginRegistry.WindowFocusChangedListener,
    ) = Unit

    override fun removeOnWindowFocusChangedListener(
        listener: PluginRegistry.WindowFocusChangedListener,
    ) = Unit

    override fun addOnSaveStateListener(
        listener: ActivityPluginBinding.OnSaveInstanceStateListener,
    ) = Unit

    override fun removeOnSaveStateListener(
        listener: ActivityPluginBinding.OnSaveInstanceStateListener,
    ) = Unit
}
