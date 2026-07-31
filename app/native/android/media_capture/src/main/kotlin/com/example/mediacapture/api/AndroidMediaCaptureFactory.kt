package com.example.mediacapture.api

import android.content.Context
import androidx.lifecycle.LifecycleOwner
import com.example.mediacapture.core.MediaCaptureCore
import com.example.mediacapture.framework.AndroidPermissionDelegate
import com.example.mediacapture.framework.AndroidPermissionGateway
import com.example.mediacapture.framework.AndroidPrivateMediaStore
import com.example.mediacapture.framework.AndroidSanitizedThumbnailGenerator
import com.example.mediacapture.framework.CameraXCaptureFramework
import com.example.mediacapture.framework.SecureOpaqueHandleGenerator
import com.example.mediacapture.framework.SystemMediaCaptureClock
import com.example.mediacapture.rendering.DefaultAndroidRenderSurfaceFactory
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope

object AndroidMediaCaptureFactory {
    fun create(
        context: Context,
        lifecycleOwner: LifecycleOwner,
        permissionDelegate: AndroidPermissionDelegate,
        parentScope: CoroutineScope,
        mainDispatcher: CoroutineDispatcher,
        ioDispatcher: CoroutineDispatcher,
        workerDispatcher: CoroutineDispatcher,
    ): MediaCapture {
        val fileStore = AndroidPrivateMediaStore(context, ioDispatcher)
        return MediaCaptureCore(
            captureFramework =
                CameraXCaptureFramework(
                    context = context,
                    lifecycleOwner = lifecycleOwner,
                    fileStore = fileStore,
                    mainDispatcher = mainDispatcher,
                    ioDispatcher = ioDispatcher,
                    cleanupScope = parentScope,
                ),
            permissionGateway = AndroidPermissionGateway(permissionDelegate),
            fileStore = fileStore,
            thumbnailGenerator = AndroidSanitizedThumbnailGenerator(ioDispatcher),
            clock = SystemMediaCaptureClock(),
            handleGenerator = SecureOpaqueHandleGenerator(),
            parentScope = parentScope,
            workerDispatcher = workerDispatcher,
            ioDispatcher = ioDispatcher,
            renderSurfaceFactory =
                DefaultAndroidRenderSurfaceFactory(
                    mainDispatcher = mainDispatcher,
                    ioDispatcher = ioDispatcher,
                ),
        )
    }
}
