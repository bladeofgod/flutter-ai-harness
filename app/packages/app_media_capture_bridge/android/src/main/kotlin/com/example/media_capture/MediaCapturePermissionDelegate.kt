package com.example.media_capture

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.example.mediacapture.api.FailureCode
import com.example.mediacapture.api.MediaType
import com.example.mediacapture.api.PermissionResource
import com.example.mediacapture.api.PermissionState
import com.example.mediacapture.api.SessionOptions
import com.example.mediacapture.framework.AndroidPermissionDelegate
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.withContext

internal class MediaCapturePermissionDelegate(
    private val activity: Activity,
    private val binding: ActivityPluginBinding,
    private val mainDispatcher: CoroutineDispatcher,
    private val requestCodeProvider: () -> Int = ::nextPermissionRequestCode,
) : AndroidPermissionDelegate, PluginRegistry.RequestPermissionsResultListener {
    private val lock = Any()
    private val pending = mutableMapOf<Int, PendingPermission>()
    private val requested = mutableSetOf<PermissionResource>()
    private var closed = false
    private var listenerRemovalRunning = false
    private var listenerRemoved = false

    init {
        binding.addRequestPermissionsResultListener(this)
    }

    override suspend fun currentState(resource: PermissionResource): PermissionState =
        withContext(mainDispatcher) { currentStateOnMain(resource) }

    override suspend fun request(resource: PermissionResource): PermissionState =
        withContext(mainDispatcher) {
            currentStateOnMain(resource).takeIf { it == PermissionState.GRANTED || it == PermissionState.UNSUPPORTED }
                ?: requestOnMain(resource)
        }

    suspend fun prepareForCapture(options: SessionOptions): FailureCode? {
        val resources =
            buildList {
                add(PermissionResource.CAMERA)
                if (MediaType.VIDEO in options.enabledMediaTypes && options.audioEnabled) {
                    add(PermissionResource.MICROPHONE)
                }
            }
        for (resource in resources) {
            val state = request(resource)
            if (state != PermissionState.GRANTED) return state.toFailureCode()
        }
        return null
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        val request = synchronized(lock) { pending[requestCode] } ?: return false
        if (permissions.isEmpty() && grantResults.isEmpty()) {
            val claimed = claimPending(requestCode, request) ?: return false
            claimed.completion.complete(PermissionState.DENIED)
            return true
        }
        if (
            permissions.size != 1 || grantResults.size != 1 ||
            permissions[0] != request.permission
        ) {
            return false
        }
        val claimed = claimPending(requestCode, request) ?: return false
        val granted = grantResults[0] == PackageManager.PERMISSION_GRANTED
        val result =
            if (granted) {
                PermissionState.GRANTED
            } else if (ActivityCompat.shouldShowRequestPermissionRationale(activity, claimed.permission)) {
                PermissionState.DENIED
            } else {
                PermissionState.PERMANENTLY_DENIED
            }
        claimed.completion.complete(result)
        return true
    }

    fun invalidate() {
        val abandoned =
            synchronized(lock) {
                if (closed) return
                closed = true
                pending.values.toList().also { pending.clear() }
            }
        abandoned.forEach { request -> request.completion.complete(PermissionState.DENIED) }
    }

    fun close() {
        invalidate()
        val shouldRemove =
            synchronized(lock) {
                if (listenerRemoved || listenerRemovalRunning) {
                    false
                } else {
                    listenerRemovalRunning = true
                    true
                }
            }
        if (!shouldRemove) return
        try {
            binding.removeRequestPermissionsResultListener(this)
        } catch (exception: Exception) {
            synchronized(lock) { listenerRemovalRunning = false }
            throw exception
        }
        synchronized(lock) {
            listenerRemovalRunning = false
            listenerRemoved = true
        }
    }

    private suspend fun requestOnMain(resource: PermissionResource): PermissionState {
        val permission = resource.permission
        val completion = CompletableDeferred<PermissionState>()
        if (synchronized(lock) { closed }) return PermissionState.DENIED
        val requestCode = requestCodeProvider()
        try {
            synchronized(lock) {
                if (closed) return PermissionState.DENIED
                requested += resource
                pending[requestCode] = PendingPermission(permission, completion)
                ActivityCompat.requestPermissions(activity, arrayOf(permission), requestCode)
            }
            return completion.await()
        } catch (exception: CancellationException) {
            synchronized(lock) {
                pending[requestCode]?.takeIf { it.completion === completion }?.let {
                    pending.remove(requestCode)
                }
            }
            throw exception
        } catch (_: Exception) {
            synchronized(lock) {
                pending[requestCode]?.takeIf { it.completion === completion }?.let {
                    pending.remove(requestCode)
                }
            }
            return PermissionState.DENIED
        }
    }

    private fun claimPending(requestCode: Int, request: PendingPermission): PendingPermission? =
        synchronized(lock) {
            if (pending[requestCode] === request) pending.remove(requestCode) else null
        }

    private fun currentStateOnMain(resource: PermissionResource): PermissionState {
        if (!resource.isSupported(activity.packageManager)) return PermissionState.UNSUPPORTED
        val permission = resource.permission
        if (ContextCompat.checkSelfPermission(activity, permission) == PackageManager.PERMISSION_GRANTED) {
            return PermissionState.GRANTED
        }
        val wasRequested = synchronized(lock) { resource in requested }
        if (!wasRequested) return PermissionState.NOT_DETERMINED
        return if (ActivityCompat.shouldShowRequestPermissionRationale(activity, permission)) {
            PermissionState.DENIED
        } else {
            PermissionState.PERMANENTLY_DENIED
        }
    }

    private data class PendingPermission(
        val permission: String,
        val completion: CompletableDeferred<PermissionState>,
    )

    private companion object {
        const val REQUEST_CODE_MIN = 51_200
        const val REQUEST_CODE_RANGE = 65_536 - REQUEST_CODE_MIN
        val requestSequence = AtomicInteger(0)

        fun nextPermissionRequestCode(): Int =
            REQUEST_CODE_MIN + Math.floorMod(requestSequence.getAndIncrement(), REQUEST_CODE_RANGE)
    }
}

private val PermissionResource.permission: String
    get() =
        when (this) {
            PermissionResource.CAMERA -> Manifest.permission.CAMERA
            PermissionResource.MICROPHONE -> Manifest.permission.RECORD_AUDIO
        }

private fun PermissionResource.isSupported(packageManager: PackageManager): Boolean =
    when (this) {
        PermissionResource.CAMERA -> packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)
        PermissionResource.MICROPHONE -> packageManager.hasSystemFeature(PackageManager.FEATURE_MICROPHONE)
    }

private fun PermissionState.toFailureCode(): FailureCode =
    when (this) {
        PermissionState.GRANTED -> error("Granted permission has no failure.")
        PermissionState.DENIED, PermissionState.NOT_DETERMINED -> FailureCode.PERMISSION_DENIED
        PermissionState.RESTRICTED -> FailureCode.PERMISSION_RESTRICTED
        PermissionState.PERMANENTLY_DENIED -> FailureCode.PERMISSION_PERMANENTLY_DENIED
        PermissionState.UNSUPPORTED -> FailureCode.UNSUPPORTED_CAPABILITY
    }
