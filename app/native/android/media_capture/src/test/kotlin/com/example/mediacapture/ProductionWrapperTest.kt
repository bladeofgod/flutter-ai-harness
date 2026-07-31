@file:OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)

package com.example.mediacapture

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.exifinterface.media.ExifInterface
import androidx.test.core.app.ApplicationProvider
import com.example.mediacapture.api.FailureCode
import com.example.mediacapture.api.MediaMetadata
import com.example.mediacapture.api.MediaType
import com.example.mediacapture.framework.AndroidPhotoMetadataSanitizer
import com.example.mediacapture.framework.AndroidPrivateMediaStore
import com.example.mediacapture.framework.AndroidSanitizedThumbnailGenerator
import com.example.mediacapture.framework.AndroidStoredMedia
import com.example.mediacapture.framework.CameraXMediaHandoffGuard
import com.example.mediacapture.framework.CapturedMedia
import com.example.mediacapture.framework.FrameworkException
import com.example.mediacapture.framework.ThumbnailGenerationRequest
import com.example.mediacapture.framework.acquireCancellableResource
import com.example.mediacapture.framework.calculateDecodeSample
import com.example.mediacapture.framework.canonicalizeJpegForWire
import com.example.mediacapture.framework.mapAndroidFrameworkFailure
import com.example.mediacapture.framework.selectPosterFrameMillis
import java.io.ByteArrayOutputStream
import java.io.FileOutputStream
import java.io.File
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class ProductionWrapperTest {
    @Test
    fun `descriptor acquisition cancellation disposes before ownership transfer`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val acquired = CompletableDeferred<Unit>()
        val transferGate = CompletableDeferred<Unit>()
        val resource = Any()
        var disposeCount = 0
        val acquisition =
            launch {
                runCatching {
                    acquireCancellableResource(
                        dispatcher = dispatcher,
                        acquire = { resource },
                        afterAcquire = {
                            acquired.complete(Unit)
                            transferGate.await()
                        },
                        dispose = {
                            assertTrue(it === resource)
                            disposeCount++
                        },
                    )
                }
            }
        runCurrent()
        assertTrue(acquired.isCompleted)

        acquisition.cancel()
        runCurrent()
        acquisition.join()

        assertEquals(1, disposeCount)
    }

    @Test
    fun `CameraX prehandoff cleanup retains failed delete for module retry`() = runTest {
        val files = FakeFileStore().apply { deleteSucceeds = false }
        val stored = AndroidStoredMedia(File("failed-capture.jpg"), "image/jpeg")
        val pending = linkedSetOf<com.example.mediacapture.framework.StoredMediaReference>()
        val guard = CameraXMediaHandoffGuard(stored, files, this, pending)

        guard.cleanupAsync()
        runCurrent()

        assertTrue(stored in pending)
        assertEquals(stored, files.revoked.single())
        assertEquals(stored, files.deleted.single())

        files.deleteSucceeds = true
        guard.cleanupNow()
        assertFalse(stored in pending)

        val handedOff = AndroidStoredMedia(File("handed-off.jpg"), "image/jpeg")
        val transferred = CameraXMediaHandoffGuard(handedOff, files, this, pending)
        transferred.transfer(CapturedMedia(handedOff, photoMetadata()))
        transferred.cleanupNow()
        assertFalse(files.deleted.contains(handedOff))
    }

    @Test
    fun `private store opens scoped read and physically deletes owned file`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val store = AndroidPrivateMediaStore(ApplicationProvider.getApplicationContext(), dispatcher)
        val stored = store.allocate("jpg", "image/jpeg")
        stored.file.writeBytes(byteArrayOf(1, 2, 3, 4))

        val read = store.openRead(stored, 4, "image/jpeg")
        assertEquals(listOf<Byte>(1, 2, 3, 4), read.readBytes().toList())
        read.close()
        assertTrue(store.delete(stored))
        assertFalse(stored.file.exists())
    }

    @Test
    fun `private store streaming read handles sequential EOF revoke and close`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val store = AndroidPrivateMediaStore(ApplicationProvider.getApplicationContext(), dispatcher)
        val bytes = ByteArray(200_123) { index -> (index % 251).toByte() }
        val stored = store.allocate("mp4", "video/mp4")
        stored.file.writeBytes(bytes)
        val read = store.openStreamingRead(stored, bytes.size.toLong(), "video/mp4")
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(65_536)

        while (true) {
            val count = read.read(buffer)
            if (count < 0) break
            output.write(buffer, 0, count)
        }

        assertContentEquals(bytes, output.toByteArray())
        assertEquals(-1, read.read(buffer))
        read.close()
        read.close()
        assertTrue(store.delete(stored))

        val empty = store.allocate("jpg", "image/jpeg")
        val emptyRead = store.openStreamingRead(empty, 1, "image/jpeg")
        assertEquals(-1, emptyRead.read(buffer))
        store.revokeReads(empty)
        val failure =
            try {
                emptyRead.read(buffer)
                null
            } catch (exception: FrameworkException) {
                exception.failureCode
            }
        assertEquals(FailureCode.INVALID_STATE, failure)
        emptyRead.close()
        assertTrue(store.delete(empty))
    }

    @Test
    fun `photo sanitizer removes location device and timestamp EXIF`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val file = java.io.File(context.cacheDir, "sanitizer-test.jpg")
        val bitmap = Bitmap.createBitmap(8, 8, Bitmap.Config.ARGB_8888)
        FileOutputStream(file).use { bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it) }
        ExifInterface(file).apply {
            setAttribute(ExifInterface.TAG_MODEL, "private-device")
            setAttribute(ExifInterface.TAG_DATETIME_ORIGINAL, "2026:07:28 10:00:00")
            setLatLong(31.2, 121.5)
            saveAttributes()
        }

        AndroidPhotoMetadataSanitizer.sanitize(file)

        val sanitized = ExifInterface(file)
        assertNull(sanitized.getAttribute(ExifInterface.TAG_MODEL))
        assertNull(sanitized.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL))
        assertNull(sanitized.latLong)
        file.delete()
    }

    @Test
    fun `android thumbnail wrapper subsamples reencodes and strips EXIF`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val store = AndroidPrivateMediaStore(ApplicationProvider.getApplicationContext(), dispatcher)
        val stored = store.allocate("jpg", "image/jpeg")
        val bitmap = Bitmap.createBitmap(640, 480, Bitmap.Config.ARGB_8888)
        FileOutputStream(stored.file).use { bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it) }
        ExifInterface(stored.file).apply {
            setAttribute(ExifInterface.TAG_MODEL, "private-device")
            saveAttributes()
        }
        val generator = AndroidSanitizedThumbnailGenerator(dispatcher)
        val work =
            generator.open(
                stored,
                MediaMetadata(MediaType.PHOTO, 640, 480, null, 0, stored.file.length(), "image/jpeg"),
                ThumbnailGenerationRequest(maxPixelEdge = 128, videoTargetFrameMillis = null),
            )

        val artifact = work.generate()

        assertTrue(artifact.pixelWidth in 1..128)
        assertTrue(artifact.pixelHeight in 1..128)
        assertEquals(0, artifact.orientationDegrees)
        assertTrue(artifact.encodedJpeg.size in 1..524_288)
        assertFalse(containsExifSegment(artifact.encodedJpeg))
        assertTrue(hasCanonicalJfif(artifact.encodedJpeg))
        work.closeSourceAccess()
        work.finishAndCloseDecoder()
        work.closeSourceHandles()
        work.wipeDecodedPixels()
        work.wipeGenerationBuffer()
        store.delete(stored)
    }

    @Test
    fun `thumbnail canonicalizer replaces missing JFIF and OEM metadata`() {
        val bitmap = Bitmap.createBitmap(32, 24, Bitmap.Config.ARGB_8888)
        val output = ByteArrayOutputStream()
        assertTrue(bitmap.compress(Bitmap.CompressFormat.JPEG, 90, output))
        val platformBytes = output.toByteArray()
        val oemVariant = withOemMetadataWithoutLeadingJfif(platformBytes)

        val canonical = canonicalizeJpegForWire(oemVariant)

        assertTrue(hasCanonicalJfif(canonical))
        val markers = headerMarkers(canonical)
        assertEquals(1, markers.count { it == 0xe0 })
        assertFalse(markers.any { it in 0xe1..0xef || it == 0xfe })
        val decoded = assertNotNull(BitmapFactory.decodeByteArray(canonical, 0, canonical.size))
        assertEquals(32, decoded.width)
        assertEquals(24, decoded.height)
        decoded.recycle()
        bitmap.recycle()
    }

    @Test
    fun `production helpers enforce bounds poster order and permission mapping`() {
        assertTrue(calculateDecodeSample(8_000, 6_000, 512, 1_048_576) > 1)
        assertEquals(1_100, selectPosterFrameMillis(1_000, 1_100, 900))
        assertEquals(900, selectPosterFrameMillis(1_000, null, 900))
        assertEquals(
            FailureCode.PERMISSION_DENIED,
            mapAndroidFrameworkFailure(
                RuntimeException("wrapper", SecurityException("permission revoked")),
                FailureCode.SYSTEM_INTERRUPTED,
            ).failureCode,
        )
        assertEquals(
            FailureCode.SYSTEM_INTERRUPTED,
            mapAndroidFrameworkFailure(IllegalStateException(), FailureCode.SYSTEM_INTERRUPTED).failureCode,
        )
    }

    private fun containsExifSegment(bytes: ByteArray): Boolean {
        var index = 2
        while (index + 3 < bytes.size) {
            if (bytes[index] != 0xFF.toByte()) return false
            val marker = bytes[index + 1].toInt() and 0xFF
            if (marker == 0xDA || marker == 0xD9) return false
            if (marker == 0xE1) return true
            val length =
                ((bytes[index + 2].toInt() and 0xFF) shl 8) or
                    (bytes[index + 3].toInt() and 0xFF)
            if (length < 2) return false
            index += 2 + length
        }
        return false
    }

    private fun hasCanonicalJfif(bytes: ByteArray): Boolean {
        val expected =
            byteArrayOf(
                0xff.toByte(),
                0xd8.toByte(),
                0xff.toByte(),
                0xe0.toByte(),
                0x00,
                0x10,
                0x4a,
                0x46,
                0x49,
                0x46,
                0x00,
                0x01,
                0x01,
                0x00,
                0x00,
                0x01,
                0x00,
                0x01,
                0x00,
                0x00,
            )
        return bytes.size >= expected.size && expected.indices.all { bytes[it] == expected[it] }
    }

    private fun withOemMetadataWithoutLeadingJfif(bytes: ByteArray): ByteArray {
        val firstSegmentEnd =
            if (bytes.size >= 6 && bytes[2] == 0xff.toByte() && bytes[3] == 0xe0.toByte()) {
                val length = ((bytes[4].toInt() and 0xff) shl 8) or (bytes[5].toInt() and 0xff)
                4 + length
            } else {
                2
            }
        return ByteArrayOutputStream(bytes.size + 12).apply {
            write(bytes, 0, 2)
            write(byteArrayOf(0xff.toByte(), 0xe2.toByte(), 0x00, 0x04, 0x12, 0x34))
            write(byteArrayOf(0xff.toByte(), 0xfe.toByte(), 0x00, 0x04, 0x56, 0x78))
            write(bytes, firstSegmentEnd, bytes.size - firstSegmentEnd)
        }.toByteArray()
    }

    private fun headerMarkers(bytes: ByteArray): List<Int> {
        val markers = mutableListOf<Int>()
        var index = 2
        while (index + 3 < bytes.size) {
            if (bytes[index] != 0xff.toByte()) return markers
            val marker = bytes[index + 1].toInt() and 0xff
            markers += marker
            if (marker == 0xda || marker == 0xd9) return markers
            val length =
                ((bytes[index + 2].toInt() and 0xff) shl 8) or
                    (bytes[index + 3].toInt() and 0xff)
            if (length < 2) return markers
            index += 2 + length
        }
        return markers
    }
}
