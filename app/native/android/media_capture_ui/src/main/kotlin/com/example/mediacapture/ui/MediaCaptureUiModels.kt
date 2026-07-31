package com.example.mediacapture.ui

import com.example.mediacapture.api.CameraPosition
import com.example.mediacapture.api.ConfirmedMedia
import com.example.mediacapture.api.FailureCode
import com.example.mediacapture.api.FlashMode
import com.example.mediacapture.api.MediaCaptureFailure
import com.example.mediacapture.api.MediaType
import com.example.mediacapture.api.SessionOptions

class MediaCaptureUiConfig(
    enabledMediaTypes: Set<MediaType> = setOf(MediaType.PHOTO, MediaType.VIDEO),
    val preferredCamera: CameraPosition = CameraPosition.REAR,
    val audioEnabled: Boolean = true,
    val maxVideoDurationMillis: Long = 60_000L,
) {
    val enabledMediaTypes: Set<MediaType> = enabledMediaTypes.toSet()

    init {
        require(this.enabledMediaTypes.isNotEmpty()) { "At least one media type is required." }
        require(maxVideoDurationMillis in 1L..60_000L) {
            "Video duration must be between 1 and 60000 milliseconds."
        }
    }

    fun toSessionOptions(): SessionOptions =
        SessionOptions(
            enabledMediaTypes = enabledMediaTypes,
            preferredCamera = preferredCamera,
            audioEnabled = audioEnabled,
            maxVideoDurationMillis = maxVideoDurationMillis,
        )
}

sealed interface MediaCaptureFlowResult {
    data class Confirmed(val media: ConfirmedMedia) : MediaCaptureFlowResult

    data object Cancelled : MediaCaptureFlowResult

    data class Failure(val failure: MediaCaptureFailure) : MediaCaptureFlowResult
}

internal fun Throwable.toCaptureFailure(): MediaCaptureFailure {
    val exception = this as? com.example.mediacapture.api.MediaCaptureException
    return exception?.failure ?: MediaCaptureFailure(FailureCode.SYSTEM_INTERRUPTED)
}
