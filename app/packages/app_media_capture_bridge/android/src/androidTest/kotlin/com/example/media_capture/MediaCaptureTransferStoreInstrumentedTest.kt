package com.example.media_capture

import android.content.Context
import android.system.Os
import android.system.OsConstants
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.example.mediacapture.api.MediaMetadata
import com.example.mediacapture.api.MediaType
import java.io.File
import java.util.UUID
import kotlin.test.assertEquals
import kotlin.test.assertFails
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlinx.coroutines.runBlocking
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MediaCaptureTransferStoreInstrumentedTest {
    @Test
    fun productionDescriptorRejectsSymlinkAndHardLinkDrift() = withProductionStore { root, store ->
        val sentinel = File(root, "sentinel.bin").apply { writeBytes(byteArrayOf(9)) }
        val symlinkReservation = store.createReservation(metadata())
        runBlocking { symlinkReservation.mediaSink.begin(MediaType.PHOTO, "image/jpeg", 1) }
        assertTrue(symlinkReservation.transferFile.delete())
        Os.symlink(sentinel.absolutePath, symlinkReservation.transferFile.absolutePath)

        assertFails { runBlocking { symlinkReservation.mediaSink.write(byteArrayOf(1), 1) } }
        runBlocking { symlinkReservation.mediaSink.abort() }

        assertEquals(byteArrayOf(9).toList(), sentinel.readBytes().toList())
        assertTrue(OsConstants.S_ISLNK(Os.lstat(symlinkReservation.transferFile.absolutePath).st_mode))
        assertFalse(symlinkReservation.descriptor.valid)
        Os.remove(symlinkReservation.transferFile.absolutePath)

        val hardLinkReservation = store.createReservation(metadata())
        runBlocking { hardLinkReservation.mediaSink.begin(MediaType.PHOTO, "image/jpeg", 1) }
        val alias = File(hardLinkReservation.transferFile.parentFile, "external-hard-link")
        val hardLinksSupported =
            runCatching {
                Os.link(hardLinkReservation.transferFile.absolutePath, alias.absolutePath)
            }.isSuccess
        if (!hardLinksSupported) {
            assertTrue(store.delete(hardLinkReservation))
            return@withProductionStore
        }

        assertFails { runBlocking { hardLinkReservation.mediaSink.write(byteArrayOf(1), 1) } }
        runBlocking { hardLinkReservation.mediaSink.abort() }

        assertTrue(alias.isFile)
        assertFalse(hardLinkReservation.descriptor.valid)
        assertTrue(alias.delete())
    }

    @Test
    fun productionDescriptorRejectsExternalLengthDriftAndClosesOnAbort() =
        withProductionStore { _, store ->
            val reservation = store.createReservation(metadata())
            runBlocking { reservation.mediaSink.begin(MediaType.PHOTO, "image/jpeg", 1) }
            val externalDescriptor =
                Os.open(
                    reservation.transferFile.absolutePath,
                    OsConstants.O_WRONLY or OsConstants.O_APPEND,
                    0,
                )
            try {
                assertEquals(1, Os.write(externalDescriptor, byteArrayOf(7), 0, 1))
            } finally {
                Os.close(externalDescriptor)
            }

            assertFails { runBlocking { reservation.mediaSink.write(byteArrayOf(1), 1) } }
            runBlocking { reservation.mediaSink.abort() }

            assertFalse(reservation.descriptor.valid)
            assertFalse(reservation.transferFile.exists())
        }

    @Test
    fun productionCommitDoesNotReplaceTargetAndClosesDescriptor() = withProductionStore { root, store ->
        val reservation = store.createReservation(metadata())
        runBlocking {
            reservation.mediaSink.begin(MediaType.PHOTO, "image/jpeg", 1)
            reservation.mediaSink.write(byteArrayOf(1), 1)
        }
        val sentinel = File(root, "final-sentinel.bin").apply { writeBytes(byteArrayOf(8)) }
        assertTrue(reservation.transferFile.delete())
        Os.symlink(sentinel.absolutePath, reservation.transferFile.absolutePath)

        assertFails { runBlocking { reservation.mediaSink.commit(1) } }
        runBlocking { reservation.mediaSink.abort() }

        assertEquals(byteArrayOf(8).toList(), sentinel.readBytes().toList())
        assertTrue(OsConstants.S_ISLNK(Os.lstat(reservation.transferFile.absolutePath).st_mode))
        assertFalse(reservation.descriptor.valid)
        assertTrue(store.delete(reservation))
        Os.remove(reservation.transferFile.absolutePath)
    }

    @Test
    fun productionCommitKeepsReservedPathAndClosesDescriptor() = withProductionStore { _, store ->
        val reservation = store.createReservation(metadata())
        val reservedPath = reservation.transferFile.canonicalPath

        runBlocking {
            reservation.mediaSink.begin(MediaType.PHOTO, "image/jpeg", 1)
            reservation.mediaSink.write(byteArrayOf(1), 1)
            reservation.mediaSink.commit(1)
        }

        assertTrue(reservation.committed)
        assertEquals(reservedPath, reservation.transferFile.canonicalPath)
        assertTrue(store.fileUri(reservation).endsWith(".jpg"))
        assertFalse(reservation.descriptor.valid)
        assertTrue(store.delete(reservation))
    }

    private fun withProductionStore(block: (File, MediaCaptureTransferStore) -> Unit) {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val root = File(context.cacheDir, "media-transfer-instrumented-${UUID.randomUUID()}")
        assertTrue(root.mkdirs())
        val store = MediaCaptureTransferStore(root)
        try {
            assertTrue(store.isAvailable)
            block(root, store)
        } finally {
            store.closeGeneration()
            root.deleteRecursively()
        }
    }

    private fun metadata(): MediaMetadata =
        MediaMetadata(
            mediaType = MediaType.PHOTO,
            pixelWidth = 1,
            pixelHeight = 1,
            durationMillis = null,
            orientationDegrees = 0,
            byteLength = 1,
            contentType = "image/jpeg",
        )
}
