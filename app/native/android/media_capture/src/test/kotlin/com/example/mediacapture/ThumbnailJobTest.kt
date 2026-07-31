@file:OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)

package com.example.mediacapture

import com.example.mediacapture.api.FailureCode
import com.example.mediacapture.api.MediaCaptureException
import com.example.mediacapture.api.MediaState
import com.example.mediacapture.api.MediaType
import com.example.mediacapture.framework.ThumbnailArtifact
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest

class ThumbnailJobTest {
    @Test
    fun `failure after caller copy creation wipes copy cleans work and unregisters slot`() = runTest {
        val module = TestModule(this)
        val lostMedia = captureConfirmedPhoto(module)
        val blockerMedia = captureConfirmedPhoto(module)
        val replacementMedia = captureConfirmedPhoto(module)
        val copyReached = CompletableDeferred<Unit>()
        val holdBeforeClaim = CompletableDeferred<Unit>()
        lateinit var uncommittedCopy: ByteArray
        module.core.thumbnailCopyBeforeClaimForTest = { copy ->
            uncommittedCopy = copy
            copyReached.complete(Unit)
            holdBeforeClaim.await()
        }
        val lostWork = FakeThumbnailWork(photoMetadata().defaultArtifact())
        module.thumbnails.queuedWorks += lostWork
        val lostRead = module.core.readMediaThumbnail(lostMedia, 128)
        runCurrent()
        assertTrue(copyReached.isCompleted)

        val blockerGate = CompletableDeferred<Unit>()
        module.thumbnails.queuedWorks +=
            FakeThumbnailWork(photoMetadata().defaultArtifact(), blockerGate)
        val blocker = module.core.readMediaThumbnail(blockerMedia, 128)
        runCurrent()

        module.core.releaseMedia(lostMedia)

        assertTrue(uncommittedCopy.all { it == 0.toByte() })
        assertEquals(FailureCode.INVALID_STATE, thumbnailFailure(lostRead).failure.code)
        assertEquals(
            listOf(
                "generate",
                "revoke_source_access",
                "cancel_and_await_decoder",
                "close_source_handles",
                "wipe_decoded_pixels",
                "wipe_generation_buffer",
                "discard_partial_copy",
            ),
            lostWork.steps,
        )

        module.core.thumbnailCopyBeforeClaimForTest = null
        module.thumbnails.queuedWorks += FakeThumbnailWork(photoMetadata().defaultArtifact())
        val replacement = module.core.readMediaThumbnail(replacementMedia, 128)
        runCurrent()
        assertEquals("image/jpeg", replacement.await().contentType)

        blocker.cancel()
        module.core.releaseMedia(blockerMedia)
        module.core.releaseMedia(replacementMedia)
        module.core.close()
    }

    @Test
    fun `cleanup failures cannot strand failure or success outcome`() = runTest {
        val module = TestModule(this)
        val failedMedia = captureConfirmedPhoto(module)
        val failureGate = CompletableDeferred<Unit>()
        val failureWork =
            FakeThumbnailWork(
                photoMetadata().defaultArtifact(),
                failureGate,
                throwAt =
                    setOf(
                        "revoke_source_access",
                        "cancel_and_await_decoder",
                        "close_source_handles",
                        "wipe_decoded_pixels",
                        "wipe_generation_buffer",
                        "discard_partial_copy",
                    ),
            )
        module.thumbnails.queuedWorks += failureWork
        val failed = module.core.readMediaThumbnail(failedMedia, 128)
        runCurrent()
        module.core.releaseMedia(failedMedia)
        assertEquals(FailureCode.INVALID_STATE, thumbnailFailure(failed).failure.code)
        assertTrue(failureWork.steps.contains("discard_partial_copy"))

        val successMedia = captureConfirmedPhoto(module)
        val successWork =
            FakeThumbnailWork(
                photoMetadata().defaultArtifact(),
                throwAt =
                    setOf(
                        "close_source_access",
                        "finish_and_close_decoder",
                        "close_source_handles",
                        "wipe_decoded_pixels",
                        "wipe_generation_buffer",
                    ),
            )
        module.thumbnails.queuedWorks += successWork
        val success = module.core.readMediaThumbnail(successMedia, 128)
        runCurrent()
        assertEquals("image/jpeg", success.await().contentType)
        assertTrue(successWork.steps.contains("wipe_generation_buffer"))
        module.core.releaseMedia(successMedia)
        module.core.close()
    }

    @Test
    fun `synchronous lease expiry atomically defeats in flight success`() = runTest {
        val module = TestModule(this)
        val media = captureConfirmedPhoto(module)
        val gate = CompletableDeferred<Unit>()
        module.thumbnails.queuedWorks += FakeThumbnailWork(photoMetadata().defaultArtifact(), gate)
        val read = module.core.readMediaThumbnail(media, 128)
        runCurrent()

        module.clock.now += 86_400_000
        assertEquals(FailureCode.INVALID_STATE, failureCode { module.core.withMediaRead(media) { } })
        assertEquals(FailureCode.INVALID_STATE, thumbnailFailure(read).failure.code)
        gate.complete(Unit)
        runCurrent()
        assertEquals(MediaState.EXPIRY_GRACE, module.core.mediaState(media))
        module.core.close()
    }

    @Test
    fun `successful job commits independent sanitized bounded copy then finalizes once`() = runTest {
        val module = TestModule(this)
        val media = captureConfirmedPhoto(module)
        val sourceBytes = photoMetadata().defaultArtifact().encodedJpeg
        val work = FakeThumbnailWork(photoMetadata().defaultArtifact().copy(encodedJpeg = sourceBytes))
        module.thumbnails.queuedWorks += work

        val read = module.core.readMediaThumbnail(media, 256)
        runCurrent()
        val result = read.await()

        assertContentEquals(
            byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 0xD9.toByte()),
            result.copy,
        )
        assertTrue(sourceBytes.all { it == 0.toByte() })
        assertEquals("image/jpeg", result.contentType)
        assertEquals(0, result.orientationDegrees)
        assertNull(result.posterFrameMillis)
        assertEquals(
            listOf(
                "generate",
                "close_source_access",
                "finish_and_close_decoder",
                "close_source_handles",
                "wipe_decoded_pixels",
                "wipe_generation_buffer",
            ),
            work.steps,
        )
        assertEquals(256, module.thumbnails.opened.single().second.maxPixelEdge)
        assertEquals(1_048_576, module.thumbnails.opened.single().second.maxDecodedPixels)
        assertEquals(8_388_608, module.thumbnails.opened.single().second.maxWorkingBytes)

        module.core.releaseMedia(media)
        assertContentEquals(
            byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 0xD9.toByte()),
            result.copy,
        )
        module.core.close()
    }

    @Test
    fun `invalid edge and unconfirmed media reject before source access`() = runTest {
        val module = TestModule(this)
        val session = startReady(module, options(setOf(MediaType.PHOTO)))
        val preview = module.core.takePhoto(session)

        assertEquals(
            FailureCode.INVALID_ARGUMENT,
            failureCode { module.core.readMediaThumbnail(preview.mediaHandle, 63) },
        )
        assertEquals(
            FailureCode.INVALID_STATE,
            failureCode { module.core.readMediaThumbnail(preview.mediaHandle, 128) },
        )
        assertTrue(module.thumbnails.opened.isEmpty())
        module.core.cancel(session)
        module.core.close()
    }

    @Test
    fun `one per media and two per module overload before opening source`() = runTest {
        val module = TestModule(this)
        val firstMedia = captureConfirmedPhoto(module)
        val secondMedia = captureConfirmedPhoto(module)
        val thirdMedia = captureConfirmedPhoto(module)
        val firstGate = CompletableDeferred<Unit>()
        val secondGate = CompletableDeferred<Unit>()
        module.thumbnails.queuedWorks += FakeThumbnailWork(photoMetadata().defaultArtifact(), firstGate)
        module.thumbnails.queuedWorks += FakeThumbnailWork(photoMetadata().defaultArtifact(), secondGate)

        val first = module.core.readMediaThumbnail(firstMedia, 128)
        runCurrent()
        assertEquals(
            FailureCode.THUMBNAIL_OVERLOADED,
            failureCode { module.core.readMediaThumbnail(firstMedia, 128) },
        )
        val second = module.core.readMediaThumbnail(secondMedia, 128)
        runCurrent()
        assertEquals(
            FailureCode.THUMBNAIL_OVERLOADED,
            failureCode { module.core.readMediaThumbnail(thirdMedia, 128) },
        )
        assertEquals(2, module.thumbnails.opened.size)

        first.cancel()
        second.cancel()
        assertFalse(firstGate.isCompleted)
        assertFalse(secondGate.isCompleted)
        module.core.close()
    }

    @Test
    fun `release wins race and runs exact failure cleanup before result delivery`() = runTest {
        val module = TestModule(this)
        val media = captureConfirmedPhoto(module)
        val gate = CompletableDeferred<Unit>()
        val work = FakeThumbnailWork(photoMetadata().defaultArtifact(), gate)
        module.thumbnails.queuedWorks += work
        val read = module.core.readMediaThumbnail(media, 128)
        runCurrent()

        module.core.releaseMedia(media)
        val exception = thumbnailFailure(read)

        assertEquals(FailureCode.INVALID_STATE, exception.failure.code)
        assertEquals(
            listOf(
                "generate",
                "revoke_source_access",
                "cancel_and_await_decoder",
                "close_source_handles",
                "wipe_decoded_pixels",
                "wipe_generation_buffer",
                "discard_partial_copy",
            ),
            work.steps,
        )
        assertFalse(gate.isCompleted)
        module.core.close()
    }

    @Test
    fun `caller cancel and decoder failure expose only stable failures`() = runTest {
        val module = TestModule(this)
        val cancelledMedia = captureConfirmedPhoto(module)
        val gate = CompletableDeferred<Unit>()
        module.thumbnails.queuedWorks += FakeThumbnailWork(photoMetadata().defaultArtifact(), gate)
        val cancelled = module.core.readMediaThumbnail(cancelledMedia, 128)
        runCurrent()
        cancelled.cancel()
        assertEquals(FailureCode.THUMBNAIL_GENERATION_CANCELLED, thumbnailFailure(cancelled).failure.code)

        val failedMedia = captureConfirmedPhoto(module)
        val failedWork = FakeThumbnailWork(photoMetadata().defaultArtifact(), failGeneration = true)
        module.thumbnails.queuedWorks += failedWork
        val failed = module.core.readMediaThumbnail(failedMedia, 128)
        runCurrent()
        val exception = thumbnailFailure(failed)
        assertEquals(FailureCode.THUMBNAIL_GENERATION_FAILED, exception.failure.code)
        assertEquals("thumbnail_generation_failed", exception.message)
        assertEquals(null, exception.cause)
        module.core.close()
    }

    @Test
    fun `restart wins in flight job and invalidates media`() = runTest {
        val module = TestModule(this)
        val media = captureConfirmedPhoto(module)
        val work = FakeThumbnailWork(photoMetadata().defaultArtifact(), CompletableDeferred())
        module.thumbnails.queuedWorks += work
        val read = module.core.readMediaThumbnail(media, 128)
        runCurrent()

        module.core.onAppRestarted()

        assertEquals(FailureCode.MEDIA_INVALID, thumbnailFailure(read).failure.code)
        assertEquals(FailureCode.MEDIA_INVALID, failureCode { module.core.mediaState(media) })
        assertEquals("discard_partial_copy", work.steps.last())
        module.core.close()
    }

    @Test
    fun `video request uses deterministic target and reports actual selected frame`() = runTest {
        val module = TestModule(this)
        val session = startReady(module, options(setOf(MediaType.VIDEO)))
        module.core.startRecording(session)
        val preview = module.core.stopRecording(session)
        module.core.confirm(preview.mediaHandle)
        val artifact = videoMetadata().defaultArtifact().copy(actualPosterFrameMillis = 1_120)
        module.thumbnails.queuedWorks += FakeThumbnailWork(artifact)

        val read = module.core.readMediaThumbnail(preview.mediaHandle, 512)
        runCurrent()
        val result = read.await()

        assertEquals(1_000, module.thumbnails.opened.single().second.videoTargetFrameMillis)
        assertEquals(1_120, result.posterFrameMillis)
        module.core.releaseMedia(preview.mediaHandle)
        module.core.close()
    }

    @Test
    fun `core rejects jpeg carrying EXIF metadata`() = runTest {
        val module = TestModule(this)
        val media = captureConfirmedPhoto(module)
        val exifJpeg =
            byteArrayOf(
                0xFF.toByte(), 0xD8.toByte(),
                0xFF.toByte(), 0xE1.toByte(), 0x00, 0x04, 0x01, 0x02,
                0xFF.toByte(), 0xD9.toByte(),
            )
        module.thumbnails.queuedWorks +=
            FakeThumbnailWork(photoMetadata().defaultArtifact().copy(encodedJpeg = exifJpeg))

        val read = module.core.readMediaThumbnail(media, 128)
        runCurrent()

        assertEquals(FailureCode.THUMBNAIL_GENERATION_FAILED, thumbnailFailure(read).failure.code)
        module.core.close()
    }

    private suspend fun thumbnailFailure(read: com.example.mediacapture.api.ThumbnailRead): MediaCaptureException =
        try {
            read.await()
            error("Expected thumbnail failure")
        } catch (exception: MediaCaptureException) {
            exception
        }
}
