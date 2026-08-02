package com.example.media_capture

import com.example.mediacapture.api.MediaMetadata
import com.example.mediacapture.api.MediaType
import java.io.File
import java.io.FileDescriptor
import java.nio.file.Files
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlin.io.path.createSymbolicLinkPointingTo
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFails
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.concurrent.thread
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [23])
class MediaCaptureTransferStoreTest {
    @Test
    fun initialDescriptorInspectionFailureClosesRawDescriptorExactlyOnce() {
        var closeCount = 0
        val fileSystem =
            AndroidTransferFileSystem(
                openDescriptor = { FileDescriptor() },
                createHandle = { error("first fstat failed") },
                closeDescriptor = { closeCount += 1 },
            )

        assertNull(fileSystem.openExclusive(File("unused.partial")))
        assertEquals(1, closeCount)
    }

    @Test
    fun commitsBoundedFileUnderCanonicalPrivateRootAndDeletesIt() = runTest {
        withTemporaryDirectory { cache ->
            val store = testTransferStore(cache)
            val reservation = store.createReservation(metadata(byteLength = 4))

            reservation.mediaSink.begin(MediaType.PHOTO, "image/jpeg", 4)
            reservation.mediaSink.write(byteArrayOf(1, 2, 3, 4), 4)
            reservation.mediaSink.commit(4)

            assertTrue(reservation.committed)
            val uri = store.fileUri(reservation)
            assertTrue(uri.startsWith("file://${cache.canonicalPath}/app_media_capture_bridge/exports/"))
            assertFalse(uri.contains(".partial"))
            assertTrue(store.delete(reservation))
            assertTrue(store.delete(reservation))
        }
    }

    @Test
    fun startupSweepsResidualFilesWithoutFollowingSymlinkRoots() = runTest {
        withTemporaryDirectory { cache ->
            val root = File(cache, "app_media_capture_bridge/exports").apply { mkdirs() }
            File(root, "residual.partial").writeBytes(byteArrayOf(1, 2, 3))

            val store = testTransferStore(cache)

            assertTrue(store.isAvailable)
            assertTrue(root.listFiles().orEmpty().isEmpty())
        }
        withTemporaryDirectory { cache ->
            withTemporaryDirectory { outside ->
                val bridge = File(cache, "app_media_capture_bridge").apply { mkdirs() }
                val sentinel = File(outside, "sentinel").apply { writeText("keep") }
                bridge.toPath().resolve("exports").createSymbolicLinkPointingTo(outside.toPath())

                val store = testTransferStore(cache)

                assertFalse(store.isAvailable)
                assertTrue(sentinel.isFile)
            }
        }
    }

    @Test
    fun rejectsLengthDriftAndAbortRemovesStaging() = runTest {
        withTemporaryDirectory { cache ->
            val store = testTransferStore(cache)
            val reservation = store.createReservation(metadata(byteLength = 4))
            reservation.mediaSink.begin(MediaType.PHOTO, "image/jpeg", 4)
            reservation.mediaSink.write(byteArrayOf(1, 2, 3), 3)

            assertFails { reservation.mediaSink.commit(4) }
            reservation.mediaSink.abort()

            assertTrue(File(cache, "app_media_capture_bridge/exports").listFiles().orEmpty().isEmpty())
        }
    }

    @Test
    fun cleanupRejectsRootSymlinkReplacementWithoutTouchingExternalFiles() = runTest {
        withTemporaryDirectory { cache ->
            withTemporaryDirectory { outside ->
                val store = testTransferStore(cache)
                val reservation = store.createReservation(metadata(byteLength = 1))
                val root = File(cache, "app_media_capture_bridge/exports")
                val external = File(outside, reservation.stagingFile.name).apply { writeText("keep") }
                assertTrue(root.deleteRecursively())
                Files.createSymbolicLink(root.toPath(), outside.toPath())

                assertFalse(store.delete(reservation))
                assertFalse(store.isAvailable)
                assertEquals("keep", external.readText())
                Files.delete(root.toPath())
            }
        }
    }

    @Test
    fun stagingSymlinkReplacementCannotRedirectDescriptorWrite() = runTest {
        withTemporaryDirectory { cache ->
            withTemporaryDirectory { outside ->
                val store = testTransferStore(cache)
                val reservation = store.createReservation(metadata(byteLength = 1))
                reservation.mediaSink.begin(MediaType.PHOTO, "image/jpeg", 1)
                val sentinel = File(outside, "sentinel.bin").apply { writeBytes(byteArrayOf(9)) }
                assertTrue(reservation.stagingFile.delete())
                Files.createSymbolicLink(reservation.stagingFile.toPath(), sentinel.toPath())

                assertFails { reservation.mediaSink.write(byteArrayOf(1), 1) }
                reservation.mediaSink.abort()

                assertEquals(byteArrayOf(9).toList(), sentinel.readBytes().toList())
                assertTrue(Files.isSymbolicLink(reservation.stagingFile.toPath()))
                assertTrue(store.delete(reservation))
            }
        }
    }

    @Test
    fun existingFinalTargetIsNotOverwrittenOrDeletedByFailedCommit() = runTest {
        withTemporaryDirectory { cache ->
            val store = testTransferStore(cache)
            val reservation = store.createReservation(metadata(byteLength = 1))
            reservation.mediaSink.begin(MediaType.PHOTO, "image/jpeg", 1)
            reservation.mediaSink.write(byteArrayOf(1), 1)
            reservation.finalFile.writeText("keep")

            assertFails { reservation.mediaSink.commit(1) }
            reservation.mediaSink.abort()

            assertEquals("keep", reservation.finalFile.readText())
            assertFalse(reservation.stagingFile.exists())
            assertTrue(store.delete(reservation))
        }
    }

    @Test
    fun concurrentDeleteWaitsForDescriptorWriteWithoutLockInversion() = runBlocking {
        withTemporaryDirectory { cache ->
            val writeEntered = CountDownLatch(1)
            val allowWrite = CountDownLatch(1)
            val deleteStarted = CountDownLatch(1)
            val writerFailure = AtomicReference<Throwable?>()
            val deleteFailure = AtomicReference<Throwable?>()
            val deleteResult = AtomicReference<Boolean?>()
            val fileSystem =
                TestTransferFileSystem(
                    beforeWrite = {
                        writeEntered.countDown()
                        check(allowWrite.await(5, TimeUnit.SECONDS))
                    },
                )
            val store = testTransferStore(cache, fileSystem = fileSystem)
            val reservation = store.createReservation(metadata(byteLength = 1))
            reservation.mediaSink.begin(MediaType.PHOTO, "image/jpeg", 1)

            val writer =
                thread(name = "media-transfer-writer") {
                    writerFailure.set(
                        runCatching {
                            runBlocking { reservation.mediaSink.write(byteArrayOf(1), 1) }
                        }.exceptionOrNull(),
                    )
                }
            assertTrue(writeEntered.await(5, TimeUnit.SECONDS))
            val deleter =
                thread(name = "media-transfer-deleter") {
                    deleteStarted.countDown()
                    runCatching { store.delete(reservation) }
                        .onSuccess(deleteResult::set)
                        .onFailure(deleteFailure::set)
                }
            assertTrue(deleteStarted.await(5, TimeUnit.SECONDS))
            val blockedDeadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
            while (deleter.state != Thread.State.BLOCKED && System.nanoTime() < blockedDeadline) {
                Thread.yield()
            }
            assertEquals(Thread.State.BLOCKED, deleter.state)
            allowWrite.countDown()
            writer.join(5_000L)
            deleter.join(5_000L)

            assertFalse(writer.isAlive)
            assertFalse(deleter.isAlive)
            assertNull(writerFailure.get())
            assertNull(deleteFailure.get())
            assertEquals(true, deleteResult.get())
        }
    }

    @Test
    fun secondLiveStoreDoesNotSweepFirstStoreTransfer() = runTest {
        withTemporaryDirectory { cache ->
            val first = testTransferStore(cache)
            val reservation = first.createReservation(metadata(byteLength = 1))
            reservation.mediaSink.begin(MediaType.PHOTO, "image/jpeg", 1)
            reservation.mediaSink.write(byteArrayOf(1), 1)
            reservation.mediaSink.commit(1)

            val second = testTransferStore(cache)

            assertTrue(second.isAvailable)
            assertTrue(reservation.finalFile.isFile)
            second.closeGeneration()
            assertTrue(first.delete(reservation))
            first.closeGeneration()
        }
    }

    @Test
    fun closedGenerationRetainsSweepLeaseUntilExistingTransferIsDeleted() = runTest {
        withTemporaryDirectory { cache ->
            val first = testTransferStore(cache)
            val reservation = first.createReservation(metadata(byteLength = 1))
            reservation.mediaSink.begin(MediaType.PHOTO, "image/jpeg", 1)
            reservation.mediaSink.write(byteArrayOf(1), 1)
            reservation.mediaSink.commit(1)
            first.closeGeneration()

            val second = testTransferStore(cache)

            assertTrue(second.isAvailable)
            assertTrue(reservation.finalFile.isFile)
            assertTrue(first.delete(reservation))
            second.closeGeneration()
        }
    }

    @Test
    fun consumesCanonicalFileUriGoldenAndLengthBoundaries() {
        val valid =
            listOf(
                "file:///var/mobile/Containers/Data/Application/app/Library/Caches/media-transfer/a.bin",
                "file:///data/user/0/app/cache/media-transfer/%E7%85%A7%E7%89%87.jpg",
            )
        val invalid =
            listOf(
                "file://localhost/data/a.bin",
                "file:relative/a.bin",
                "file:/data/a.bin",
                "file://:123/data/a.bin",
                "file:///data/../a.bin",
                "file:///data/%2E%2E/a.bin",
                "file:///data/a.bin?x=1",
                "file:///data/a.bin#x",
                "file://user@/data/a.bin",
                "file:///data/%C0%AF.bin",
                "file:///data/%GG.bin",
                "file:///data/a%2Fb.bin",
                "file:///data/a%5Cb.bin",
                "file:///data/a%00.bin",
                "file:///data/a%0A.bin",
                "file:///data/\u7167\u7247.jpg",
            )
        valid.forEach(MediaCaptureWireCodec::requireCanonicalFileUri)
        invalid.forEach { value -> assertFails { MediaCaptureWireCodec.requireCanonicalFileUri(value) } }

        val maximum = "file:///" + "a".repeat(4096 - "file:///".length)
        MediaCaptureWireCodec.requireCanonicalFileUri(maximum)
        assertFails { MediaCaptureWireCodec.requireCanonicalFileUri("${maximum}a") }
    }

    @Test
    fun exportHandlesUseUniqueBase64UrlCSPRNGValues() = runTest {
        withTemporaryDirectory { cache ->
            val store = testTransferStore(cache)
            val reservations = List(32) { store.createReservation(metadata(byteLength = 1)) }

            assertEquals(32, reservations.map { it.exportHandle }.toSet().size)
            assertTrue(reservations.all { it.exportHandle.matches(Regex("^[A-Za-z0-9_-]{22}$")) })
            reservations.forEach { assertTrue(store.delete(it)) }
        }
    }

    private fun metadata(byteLength: Long): MediaMetadata =
        MediaMetadata(
            mediaType = MediaType.PHOTO,
            pixelWidth = 1,
            pixelHeight = 1,
            durationMillis = null,
            orientationDegrees = 0,
            byteLength = byteLength,
            contentType = "image/jpeg",
        )

    private suspend fun withTemporaryDirectory(block: suspend (File) -> Unit) {
        val directory = Files.createTempDirectory("media-capture-transfer-test").toFile()
        try {
            block(directory)
        } finally {
            directory.deleteRecursively()
        }
    }
}
