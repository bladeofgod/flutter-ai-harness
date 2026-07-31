@file:OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)

package com.example.mediacapture

import com.example.mediacapture.api.CameraPosition
import com.example.mediacapture.api.FailureCode
import com.example.mediacapture.api.MediaCaptureException
import com.example.mediacapture.api.MediaHandle
import com.example.mediacapture.api.MediaType
import com.example.mediacapture.api.SessionHandle
import com.example.mediacapture.api.SessionOptions
import com.example.mediacapture.core.MediaCaptureCore
import com.example.mediacapture.rendering.AndroidRenderSurfaceFactory
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent

internal class TestModule(
    scope: TestScope,
    renderSurfaceFactory: AndroidRenderSurfaceFactory? = null,
    ioDispatcher: CoroutineDispatcher = StandardTestDispatcher(scope.testScheduler),
) {
    val clock = FakeClock()
    val handles = SequenceHandles()
    val permissions = FakePermissions()
    val framework = FakeCaptureFramework()
    val files = FakeFileStore()
    val thumbnails = FakeThumbnailGenerator()
    val core =
        MediaCaptureCore(
            captureFramework = framework,
            permissionGateway = permissions,
            fileStore = files,
            thumbnailGenerator = thumbnails,
            clock = clock,
            handleGenerator = handles,
            parentScope = scope,
            workerDispatcher = StandardTestDispatcher(scope.testScheduler),
            ioDispatcher = ioDispatcher,
            renderSurfaceFactory = renderSurfaceFactory,
        )
}

internal fun options(
    enabled: Set<MediaType> = setOf(MediaType.PHOTO, MediaType.VIDEO),
    audio: Boolean = false,
    duration: Long = 10_000,
) = SessionOptions(enabled, CameraPosition.REAR, audio, duration)

internal suspend fun TestScope.startReady(
    module: TestModule,
    sessionOptions: SessionOptions = options(),
): SessionHandle {
    val handle = module.core.startSession(sessionOptions).sessionHandle
    runCurrent()
    return handle
}

internal suspend fun TestScope.captureConfirmedPhoto(module: TestModule): MediaHandle {
    val session = startReady(module, options(enabled = setOf(MediaType.PHOTO)))
    val preview = module.core.takePhoto(session)
    module.core.confirm(preview.mediaHandle)
    return preview.mediaHandle
}

internal suspend fun failureCode(block: suspend () -> Unit): FailureCode =
    try {
        block()
        error("Expected MediaCaptureException")
    } catch (exception: MediaCaptureException) {
        exception.failure.code
    }
