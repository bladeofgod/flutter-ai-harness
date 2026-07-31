package com.example.mediacapture.ui

import com.example.mediacapture.api.FailureCode
import com.example.mediacapture.api.MediaCapture
import com.example.mediacapture.api.MediaCaptureException
import com.example.mediacapture.api.MediaHandle
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

internal fun interface MediaCaptureLeaseCleanupOwner {
    fun retain(
        mediaCapture: MediaCapture,
        mediaHandle: MediaHandle,
        onSettled: () -> Unit,
    )
}

internal object ProcessMediaCaptureLeaseCleanupOwner : MediaCaptureLeaseCleanupOwner {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun retain(
        mediaCapture: MediaCapture,
        mediaHandle: MediaHandle,
        onSettled: () -> Unit,
    ) {
        scope.launch {
            var retryDelayMillis = INITIAL_RETRY_DELAY_MILLIS
            while (true) {
                if (releaseIsSettled(mediaCapture, mediaHandle)) {
                    onSettled()
                    return@launch
                }
                delay(retryDelayMillis)
                retryDelayMillis = (retryDelayMillis * 2L).coerceAtMost(MAX_RETRY_DELAY_MILLIS)
            }
        }
    }

    private suspend fun releaseIsSettled(
        mediaCapture: MediaCapture,
        mediaHandle: MediaHandle,
    ): Boolean =
        try {
            mediaCapture.releaseMedia(mediaHandle)
            true
        } catch (throwable: Throwable) {
            if (throwable is CancellationException) throw throwable
            val failureCode = (throwable as? MediaCaptureException)?.failure?.code
            failureCode == FailureCode.MEDIA_INVALID
        }

    private const val INITIAL_RETRY_DELAY_MILLIS = 100L
    private const val MAX_RETRY_DELAY_MILLIS = 5_000L
}
