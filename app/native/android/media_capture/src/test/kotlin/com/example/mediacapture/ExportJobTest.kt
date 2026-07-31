@file:OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)

package com.example.mediacapture

import com.example.mediacapture.api.FailureCode
import com.example.mediacapture.api.MediaCaptureException
import com.example.mediacapture.api.MediaCopySink
import com.example.mediacapture.api.MediaHandle
import com.example.mediacapture.api.MediaType
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.supervisorScope
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withContext
import kotlin.coroutines.CoroutineContext

class ExportJobTest {
    @Test
    fun `confirmed JPEG streams through bounded chunks without full buffering`() = runTest {
        val module = TestModule(this)
        val source = generatedBytes(600_123)
        val media = captureConfirmedPhoto(module, source)
        val sink = RecordingSink()

        val result = module.core.copyConfirmedMediaToSink(media, sink, 1_000_000)

        assertEquals(media, result.mediaHandle)
        assertEquals(MediaType.PHOTO, result.mediaType)
        assertEquals("image/jpeg", result.contentType)
        assertEquals(source.size.toLong(), result.byteLength)
        assertContentEquals(source, sink.output.toByteArray())
        assertTrue(sink.peakWrite <= 262_144)
        assertEquals("begin", sink.phases.first())
        assertEquals("commit", sink.phases.last())
        assertEquals(5, sink.phases.count { it == "write" })
        assertEquals(0, sink.abortCount)
        assertEquals(1, module.files.streamingClosed.size)
        module.core.releaseMedia(media)
        module.core.close()
    }

    @Test
    fun `export copy and sink callbacks use the injected IO dispatcher`() = runTest {
        val ioDispatcher = RecordingDispatcher(StandardTestDispatcher(testScheduler))
        val module = TestModule(this, ioDispatcher = ioDispatcher)
        val operations = mutableListOf<Pair<String, Boolean>>()
        module.files.streamingOperationObserver = { phase -> operations += phase to ioDispatcher.isActive }
        val media = captureConfirmedPhoto(module, generatedBytes(20_000))
        val successSink = RecordingSink { phase -> operations += phase to ioDispatcher.isActive }

        module.core.copyConfirmedMediaToSink(media, successSink, 52_428_800)

        val failedMedia = captureConfirmedPhoto(module, generatedBytes(20_000))
        val failedSink = RecordingSink(
            failWrite = true,
            phaseObserver = { phase -> operations += phase to ioDispatcher.isActive },
        )
        assertEquals(
            FailureCode.MEDIA_EXPORT_WRITE_FAILED,
            failureCode { module.core.copyConfirmedMediaToSink(failedMedia, failedSink, 52_428_800) },
        )

        assertTrue(ioDispatcher.dispatchCount > 0)
        assertTrue(operations.map { it.first }.containsAll(listOf("open", "read", "close")))
        assertTrue(operations.map { it.first }.containsAll(listOf("begin", "write", "commit", "abort")))
        assertTrue(operations.all { it.second })
        module.core.releaseMedia(media)
        module.core.releaseMedia(failedMedia)
        module.core.close()
    }

    @Test
    fun `confirmed MP4 export preserves content type and byte order`() = runTest {
        val module = TestModule(this)
        val source = generatedBytes(50_000)
        val media = captureConfirmedVideo(module, source)
        val sink = RecordingSink()

        val result = module.core.copyConfirmedMediaToSink(media, sink, 52_428_800)

        assertEquals(MediaType.VIDEO, result.mediaType)
        assertEquals("video/mp4", result.contentType)
        assertContentEquals(source, sink.output.toByteArray())
        assertEquals(1, sink.commitCount)
        module.core.releaseMedia(media)
        module.core.close()
    }

    @Test
    fun `capacity rejects per media conflict and module overload before touching sink`() = runTest {
        val module = TestModule(this)
        var activeBufferBytes = 0
        var peakBufferBytes = 0
        module.core.exportBufferAllocationChangedForTest = { delta ->
            activeBufferBytes += delta
            peakBufferBytes = maxOf(peakBufferBytes, activeBufferBytes)
            assertTrue(activeBufferBytes >= 0)
        }
        val media = (0 until 5).map { captureConfirmedPhoto(module, generatedBytes(200_000)) }
        val writeGate = CompletableDeferred<Unit>()
        val activeSinks = List(4) { RecordingSink(writeGate = writeGate) }

        val active =
            activeSinks.mapIndexed { index, sink ->
                async { module.core.copyConfirmedMediaToSink(media[index], sink, 52_428_800) }
            }
        runCurrent()
        val conflictSink = RecordingSink()
        assertEquals(
            FailureCode.MEDIA_EXPORT_CONFLICT,
            failureCode { module.core.copyConfirmedMediaToSink(media.first(), conflictSink, 52_428_800) },
        )
        assertEquals(0, conflictSink.beginCount)

        val overloadSink = RecordingSink()
        assertEquals(
            FailureCode.MEDIA_EXPORT_OVERLOADED,
            failureCode { module.core.copyConfirmedMediaToSink(media.last(), overloadSink, 52_428_800) },
        )
        assertEquals(0, overloadSink.beginCount)

        writeGate.complete(Unit)
        active.forEach { it.await() }
        assertEquals(1_048_576, peakBufferBytes)
        assertEquals(0, activeBufferBytes)
        media.forEach { module.core.releaseMedia(it) }
        module.core.close()
    }

    @Test
    fun `exact 50 MiB boundary streams without whole file allocation`() = runTest {
        val module = TestModule(this)
        val maximum = 52_428_800L
        val atBoundary = captureConfirmedGeneratedPhoto(module, maximum)
        val countingSink = CountingSink()

        val result = module.core.copyConfirmedMediaToSink(atBoundary, countingSink, maximum)

        assertEquals(maximum, result.byteLength)
        assertEquals(maximum, countingSink.written)
        assertEquals(400, countingSink.writeCount)
        assertEquals(1, countingSink.commitCount)

        val overBoundary = captureConfirmedGeneratedPhoto(module, maximum + 1)
        val untouchedSink = CountingSink()
        assertEquals(
            FailureCode.MEDIA_EXPORT_TOO_LARGE,
            failureCode { module.core.copyConfirmedMediaToSink(overBoundary, untouchedSink, maximum) },
        )
        assertEquals(0, untouchedSink.beginCount)
        module.core.close()
    }

    @Test
    fun `length guards reject declared oversized truncated and growing sources`() = runTest {
        val module = TestModule(this)
        val declaredTooLarge = captureConfirmedPhoto(module, generatedBytes(20_000))
        val noTouch = RecordingSink()
        assertEquals(
            FailureCode.MEDIA_EXPORT_TOO_LARGE,
            failureCode { module.core.copyConfirmedMediaToSink(declaredTooLarge, noTouch, 10_000) },
        )
        assertEquals(0, noTouch.beginCount)

        val truncated = captureConfirmedPhoto(module, generatedBytes(10_000), declaredLength = 12_000)
        val truncatedSink = RecordingSink()
        assertEquals(
            FailureCode.MEDIA_EXPORT_TOO_LARGE,
            failureCode { module.core.copyConfirmedMediaToSink(truncated, truncatedSink, 52_428_800) },
        )
        assertEquals(1, truncatedSink.abortCount)

        val growing = captureConfirmedPhoto(module, generatedBytes(12_001), declaredLength = 12_000)
        val growingSink = RecordingSink()
        assertEquals(
            FailureCode.MEDIA_EXPORT_TOO_LARGE,
            failureCode { module.core.copyConfirmedMediaToSink(growing, growingSink, 52_428_800) },
        )
        assertEquals(1, growingSink.abortCount)

        val empty = captureConfirmedPhoto(module, byteArrayOf(), declaredLength = 1)
        val emptySink = RecordingSink()
        assertEquals(
            FailureCode.MEDIA_EXPORT_TOO_LARGE,
            failureCode { module.core.copyConfirmedMediaToSink(empty, emptySink, 52_428_800) },
        )
        assertEquals(1, emptySink.abortCount)
        module.core.close()
    }

    @Test
    fun `sink and source failures map to stable export taxonomy and cleanup once`() = runTest {
        val module = TestModule(this)

        val beginMedia = captureConfirmedPhoto(module, generatedBytes(1_024))
        val beginSink = RecordingSink(failBegin = true)
        assertEquals(
            FailureCode.MEDIA_EXPORT_SINK_REJECTED,
            failureCode { module.core.copyConfirmedMediaToSink(beginMedia, beginSink, 52_428_800) },
        )
        assertEquals(0, beginSink.abortCount)

        val writeMedia = captureConfirmedPhoto(module, generatedBytes(1_024))
        val writeSink = RecordingSink(failWrite = true)
        assertEquals(
            FailureCode.MEDIA_EXPORT_WRITE_FAILED,
            failureCode { module.core.copyConfirmedMediaToSink(writeMedia, writeSink, 52_428_800) },
        )
        assertEquals(1, writeSink.abortCount)

        val commitMedia = captureConfirmedPhoto(module, generatedBytes(1_024))
        val commitSink = RecordingSink(failCommit = true)
        assertEquals(
            FailureCode.MEDIA_EXPORT_SINK_REJECTED,
            failureCode { module.core.copyConfirmedMediaToSink(commitMedia, commitSink, 52_428_800) },
        )
        assertEquals(1, commitSink.abortCount)

        module.files.streamingReadFailureAfterReads = 0
        val readMedia = captureConfirmedPhoto(module, generatedBytes(1_024))
        val readSink = RecordingSink()
        assertEquals(
            FailureCode.MEDIA_EXPORT_READ_FAILED,
            failureCode { module.core.copyConfirmedMediaToSink(readMedia, readSink, 52_428_800) },
        )
        assertEquals(1, readSink.abortCount)

        module.files.streamingReadFailureAfterReads = null
        val abortMedia = captureConfirmedPhoto(module, generatedBytes(1_024))
        val abortSink = RecordingSink(failWrite = true, failAbort = true)
        assertEquals(
            FailureCode.MEDIA_EXPORT_WRITE_FAILED,
            failureCode { module.core.copyConfirmedMediaToSink(abortMedia, abortSink, 52_428_800) },
        )
        assertEquals(1, abortSink.abortCount)
        module.core.copyConfirmedMediaToSink(abortMedia, RecordingSink(), 52_428_800)
        module.core.close()
    }

    @Test
    fun `caller cancellation aborts never returning cancellable sink and frees reservation`() = runTest {
        val module = TestModule(this)
        val media = captureConfirmedPhoto(module, generatedBytes(20_000))
        val sink = RecordingSink(neverReturnFromWrite = true)

        supervisorScope {
            val export = async { module.core.copyConfirmedMediaToSink(media, sink, 52_428_800) }
            runCurrent()
            export.cancel()
            assertEquals(FailureCode.MEDIA_EXPORT_CANCELLED, exportFailure(export))
        }
        assertEquals(1, sink.abortCount)

        val retrySink = RecordingSink()
        module.core.copyConfirmedMediaToSink(media, retrySink, 52_428_800)
        assertEquals(1, retrySink.commitCount)
        module.core.releaseMedia(media)
        module.core.close()
    }

    @Test
    fun `caller cancellation claims failure while the core mutex is contended`() = runTest {
        val module = TestModule(this)
        val cancelledMedia = captureConfirmedPhoto(module, generatedBytes(20_000))
        val contendingMedia = captureConfirmedPhoto(module, generatedBytes(20_000))
        val cancelledSink = RecordingSink(neverReturnFromWrite = true)
        val lockEntered = CompletableDeferred<Unit>()
        val releaseLock = CompletableDeferred<Unit>()

        supervisorScope {
            val cancelledExport =
                async {
                    module.core.copyConfirmedMediaToSink(cancelledMedia, cancelledSink, 52_428_800)
                }
            runCurrent()
            module.core.exportReservationInsideMutexForTest = { handle ->
                if (handle == contendingMedia) {
                    lockEntered.complete(Unit)
                    releaseLock.await()
                }
            }
            val contendingExport =
                async {
                    module.core.copyConfirmedMediaToSink(contendingMedia, RecordingSink(), 52_428_800)
                }
            lockEntered.await()

            cancelledExport.cancel()
            runCurrent()
            assertFalse(cancelledExport.isCompleted)

            releaseLock.complete(Unit)
            runCurrent()
            assertEquals(FailureCode.MEDIA_EXPORT_CANCELLED, exportFailure(cancelledExport))
            contendingExport.await()
        }
        assertEquals(1, cancelledSink.abortCount)
        module.core.exportReservationInsideMutexForTest = null
        module.core.releaseMedia(cancelledMedia)
        module.core.releaseMedia(contendingMedia)
        module.core.close()
    }

    @Test
    fun `deadline aborts exactly once and late sink return cannot commit`() = runTest {
        val module = TestModule(this)
        val media = captureConfirmedPhoto(module, generatedBytes(20_000))
        val sink = RecordingSink(neverReturnFromWrite = true)

        supervisorScope {
            val export = async { module.core.copyConfirmedMediaToSink(media, sink, 52_428_800) }
            runCurrent()
            advanceTimeBy(120_000)
            runCurrent()
            assertEquals(FailureCode.MEDIA_EXPORT_TIMED_OUT, exportFailure(export))
        }
        assertEquals(1, sink.abortCount)
        assertEquals(0, sink.commitCount)
        module.core.releaseMedia(media)
        module.core.close()
    }

    @Test
    fun `deadline and release can win while sink commit is pending`() = runTest {
        val timeoutModule = TestModule(this)
        val timeoutMedia = captureConfirmedPhoto(timeoutModule, generatedBytes(20_000))
        val timeoutSink = RecordingSink(neverReturnFromCommit = true)
        supervisorScope {
            val export =
                async {
                    timeoutModule.core.copyConfirmedMediaToSink(timeoutMedia, timeoutSink, 52_428_800)
                }
            runCurrent()
            assertEquals(1, timeoutSink.commitAttemptCount)
            assertEquals(0, timeoutSink.commitCount)
            advanceTimeBy(120_000)
            runCurrent()
            assertEquals(FailureCode.MEDIA_EXPORT_TIMED_OUT, exportFailure(export))
        }
        assertEquals(1, timeoutSink.abortCount)
        timeoutModule.core.releaseMedia(timeoutMedia)
        timeoutModule.core.close()

        val releaseModule = TestModule(this)
        val releaseMedia = captureConfirmedPhoto(releaseModule, generatedBytes(20_000))
        val releaseSink = RecordingSink(commitGate = CompletableDeferred())
        supervisorScope {
            val export =
                async {
                    releaseModule.core.copyConfirmedMediaToSink(releaseMedia, releaseSink, 52_428_800)
                }
            runCurrent()
            assertEquals(1, releaseSink.commitAttemptCount)
            assertEquals(0, releaseSink.commitCount)
            releaseModule.core.releaseMedia(releaseMedia)
            assertEquals(FailureCode.INVALID_STATE, exportFailure(export))
        }
        assertEquals(1, releaseSink.abortCount)
        releaseModule.core.close()
    }

    @Test
    fun `successful sink commit linearizes before a late release cancellation`() = runTest {
        val module = TestModule(this)
        val media = captureConfirmedPhoto(module, generatedBytes(20_000))
        val commitReturned = CompletableDeferred<Unit>()
        val allowSuccessClaim = CompletableDeferred<Unit>()
        module.core.exportCommitAfterSinkForTest = {
            commitReturned.complete(Unit)
            allowSuccessClaim.await()
        }
        val sink = RecordingSink()

        val export = async { module.core.copyConfirmedMediaToSink(media, sink, 52_428_800) }
        commitReturned.await()
        module.core.releaseMedia(media)
        allowSuccessClaim.complete(Unit)

        assertEquals(media, export.await().mediaHandle)
        assertEquals(1, sink.commitCount)
        assertEquals(0, sink.abortCount)
        module.core.close()
    }

    @Test
    fun `lease expiry is checked atomically before export reservation`() = runTest {
        val module = TestModule(this)
        val media = captureConfirmedPhoto(module, generatedBytes(20_000))
        module.clock.now += 86_400_000L
        val sink = RecordingSink()

        assertEquals(
            FailureCode.INVALID_STATE,
            failureCode { module.core.copyConfirmedMediaToSink(media, sink, 52_428_800) },
        )
        assertEquals(0, sink.beginCount)
        assertTrue(module.files.streamingOpened.isEmpty())
        module.core.close()
    }

    @Test
    fun `non cooperative write retains reservation until late sequential abort`() = runTest {
        val module = TestModule(this)
        val source = generatedBytes(300_000)
        val media = captureConfirmedPhoto(module, source)
        val writeGate = CompletableDeferred<Unit>()
        val sink = RecordingSink(writeGate = writeGate, ignoreWriteCancellation = true)

        supervisorScope {
            val export = async { module.core.copyConfirmedMediaToSink(media, sink, 52_428_800) }
            runCurrent()
            export.cancel()
            runCurrent()

            advanceTimeBy(5_001)
            runCurrent()
            assertEquals(FailureCode.MEDIA_EXPORT_CANCELLED, exportFailure(export))
            assertEquals(0, sink.abortCount)

            val conflictSink = RecordingSink()
            assertEquals(
                FailureCode.MEDIA_EXPORT_CONFLICT,
                failureCode { module.core.copyConfirmedMediaToSink(media, conflictSink, 52_428_800) },
            )
            assertEquals(0, conflictSink.beginCount)

            writeGate.complete(Unit)
            runCurrent()
            assertEquals(1, sink.phases.count { it == "write" })
            assertFalse("commit" in sink.phases)
            assertEquals(1, sink.abortCount)

            val retrySink = RecordingSink()
            module.core.copyConfirmedMediaToSink(media, retrySink, 52_428_800)
            assertEquals(1, retrySink.commitCount)
        }
        assertEquals(1, sink.abortCount)
        module.core.releaseMedia(media)
        module.core.close()
    }

    @Test
    fun `restart retains late export capacity until callback cleanup completes`() = runTest {
        val module = TestModule(this)
        val oldMedia = captureConfirmedPhoto(module, generatedBytes(300_000))
        val oldGate = CompletableDeferred<Unit>()
        val oldSink = RecordingSink(writeGate = oldGate, ignoreWriteCancellation = true)

        supervisorScope {
            val oldExport =
                async { module.core.copyConfirmedMediaToSink(oldMedia, oldSink, 52_428_800) }
            runCurrent()
            val restart = async { module.core.onAppRestarted() }
            runCurrent()
            advanceTimeBy(5_001)
            runCurrent()

            assertEquals(FailureCode.SYSTEM_INTERRUPTED, exportFailure(oldExport))
            restart.await()

            val media = (0 until 4).map {
                captureConfirmedPhoto(module, generatedBytes(20_000))
            }
            val gates = List(3) { CompletableDeferred<Unit>() }
            val active =
                gates.mapIndexed { index, gate ->
                    async {
                        module.core.copyConfirmedMediaToSink(
                            media[index],
                            RecordingSink(writeGate = gate),
                            52_428_800,
                        )
                    }
                }
            runCurrent()

            val overloadedSink = RecordingSink()
            assertEquals(
                FailureCode.MEDIA_EXPORT_OVERLOADED,
                failureCode {
                    module.core.copyConfirmedMediaToSink(media.last(), overloadedSink, 52_428_800)
                },
            )
            assertEquals(0, overloadedSink.beginCount)

            oldGate.complete(Unit)
            gates.forEach { it.complete(Unit) }
            runCurrent()
            active.forEach { it.await() }
            assertEquals(1, oldSink.abortCount)

            val retrySink = RecordingSink()
            module.core.copyConfirmedMediaToSink(media.last(), retrySink, 52_428_800)
            assertEquals(1, retrySink.commitCount)
            media.forEach { module.core.releaseMedia(it) }
        }
        module.core.close()
    }

    @Test
    fun `core close keeps an independent owner for late callback cleanup`() = runTest {
        val module = TestModule(this)
        var activeBufferBytes = 0
        module.core.exportBufferAllocationChangedForTest = { delta -> activeBufferBytes += delta }
        val media = captureConfirmedPhoto(module, generatedBytes(300_000))
        val writeGate = CompletableDeferred<Unit>()
        val sink = RecordingSink(writeGate = writeGate, ignoreWriteCancellation = true)

        supervisorScope {
            val export = async { module.core.copyConfirmedMediaToSink(media, sink, 52_428_800) }
            runCurrent()
            assertTrue(activeBufferBytes > 0)
            val closing = async { module.core.close() }
            runCurrent()
            advanceTimeBy(10_002)
            runCurrent()

            assertEquals(FailureCode.SYSTEM_INTERRUPTED, exportFailure(export))
            closing.await()
            assertEquals(0, sink.abortCount)

            writeGate.complete(Unit)
            runCurrent()
            assertEquals(1, sink.abortCount)
            assertEquals(0, activeBufferBytes)
        }
    }

    @Test
    fun `write buffers are borrowed and wiped after callback completion`() = runTest {
        val module = TestModule(this)
        val source = generatedBytes(600_123)
        val media = captureConfirmedPhoto(module, source)
        val sink = RecordingSink(retainWriteBuffersForContractTest = true)

        module.core.copyConfirmedMediaToSink(media, sink, 1_000_000)

        assertContentEquals(source, sink.output.toByteArray())
        assertTrue(sink.borrowedBuffers.isNotEmpty())
        assertTrue(sink.borrowedBuffers.all { buffer -> buffer.all { it == 0.toByte() } })
        module.core.releaseMedia(media)
        module.core.close()
    }

    @Test
    fun `never returning abort is bounded and does not retain the reservation`() = runTest {
        val module = TestModule(this)
        val media = captureConfirmedPhoto(module, generatedBytes(20_000))
        val sink = RecordingSink(failWrite = true, neverReturnFromAbort = true)

        assertEquals(
            FailureCode.MEDIA_EXPORT_WRITE_FAILED,
            failureCode { module.core.copyConfirmedMediaToSink(media, sink, 52_428_800) },
        )
        assertEquals(1, sink.abortCount)

        val retrySink = RecordingSink()
        module.core.copyConfirmedMediaToSink(media, retrySink, 52_428_800)
        assertEquals(1, retrySink.commitCount)
        module.core.releaseMedia(media)
        module.core.close()
    }

    @Test
    fun `public guards reject invalid limits handles states and media types`() = runTest {
        val module = TestModule(this)
        val leased = captureConfirmedPhoto(module, generatedBytes(1_024))
        assertEquals(
            FailureCode.INVALID_ARGUMENT,
            failureCode { module.core.copyConfirmedMediaToSink(leased, RecordingSink(), 0) },
        )
        assertEquals(
            FailureCode.INVALID_ARGUMENT,
            failureCode { module.core.copyConfirmedMediaToSink(leased, RecordingSink(), 52_428_801) },
        )
        assertEquals(
            FailureCode.MEDIA_INVALID,
            failureCode {
                module.core.copyConfirmedMediaToSink(
                    MediaHandle("missing-media"),
                    RecordingSink(),
                    52_428_800,
                )
            },
        )

        val previewSession = startReady(module, options(enabled = setOf(MediaType.PHOTO)))
        val preview = module.core.takePhoto(previewSession)
        assertEquals(
            FailureCode.INVALID_STATE,
            failureCode {
                module.core.copyConfirmedMediaToSink(preview.mediaHandle, RecordingSink(), 52_428_800)
            },
        )
        module.core.cancel(previewSession)

        val reference = FakeStoredMedia(module.framework.photoIndex)
        module.files.bytes[reference] = generatedBytes(1_024)
        module.framework.nextPhotoMetadata = photoMetadata().copy(contentType = "image/png")
        val mimeSession = startReady(module, options(enabled = setOf(MediaType.PHOTO)))
        val mimePreview = module.core.takePhoto(mimeSession)
        module.core.confirm(mimePreview.mediaHandle)
        assertEquals(
            FailureCode.INVALID_STATE,
            failureCode {
                module.core.copyConfirmedMediaToSink(
                    mimePreview.mediaHandle,
                    RecordingSink(),
                    52_428_800,
                )
            },
        )
        module.core.close()
    }

    @Test
    fun `release expiry and core close race active export into one stable cleanup`() = runTest {
        val releaseModule = TestModule(this)
        val releaseMedia = captureConfirmedPhoto(releaseModule, generatedBytes(20_000))
        val releaseGate = CompletableDeferred<Unit>()
        val releaseSink = RecordingSink(writeGate = releaseGate)
        supervisorScope {
            val releaseExport =
                async {
                    releaseModule.core.copyConfirmedMediaToSink(releaseMedia, releaseSink, 52_428_800)
                }
            runCurrent()
            releaseModule.core.releaseMedia(releaseMedia)
            assertEquals(FailureCode.INVALID_STATE, exportFailure(releaseExport))
        }
        assertEquals(1, releaseSink.abortCount)
        releaseModule.core.close()

        val expiryModule = TestModule(this)
        val expiryMedia = captureConfirmedPhoto(expiryModule, generatedBytes(20_000))
        val expirySink = RecordingSink(writeGate = CompletableDeferred())
        supervisorScope {
            val expiryExport =
                async {
                    expiryModule.core.copyConfirmedMediaToSink(expiryMedia, expirySink, 52_428_800)
            }
            runCurrent()
            expiryModule.clock.now += 86_400_001
            assertEquals(
                FailureCode.INVALID_STATE,
                failureCode {
                    expiryModule.core.copyConfirmedMediaToSink(
                        expiryMedia,
                        RecordingSink(),
                        52_428_800,
                    )
                },
            )
            runCurrent()
            assertEquals(FailureCode.INVALID_STATE, exportFailure(expiryExport))
        }
        assertEquals(1, expirySink.abortCount)
        expiryModule.core.close()

        val closeModule = TestModule(this)
        val closeMedia = captureConfirmedPhoto(closeModule, generatedBytes(20_000))
        val closeSink = RecordingSink(writeGate = CompletableDeferred())
        supervisorScope {
            val closeExport =
                async {
                    closeModule.core.copyConfirmedMediaToSink(closeMedia, closeSink, 52_428_800)
                }
            runCurrent()
            closeModule.core.close()
            assertEquals(FailureCode.SYSTEM_INTERRUPTED, exportFailure(closeExport))
        }
        assertEquals(1, closeSink.abortCount)
    }
}

private class RecordingDispatcher(
    private val delegate: CoroutineDispatcher,
) : CoroutineDispatcher() {
    private val active = ThreadLocal.withInitial { false }
    var dispatchCount = 0
        private set
    val isActive: Boolean
        get() = active.get() == true

    override fun dispatch(context: CoroutineContext, block: Runnable) {
        dispatchCount += 1
        delegate.dispatch(context) {
            val previous = active.get()
            active.set(true)
            try {
                block.run()
            } finally {
                active.set(previous)
            }
        }
    }
}

private class CountingSink : MediaCopySink {
    var beginCount = 0
    var writeCount = 0
    var commitCount = 0
    var abortCount = 0
    var written = 0L

    override suspend fun begin(mediaType: MediaType, contentType: String, byteLength: Long) {
        beginCount++
    }

    override suspend fun write(buffer: ByteArray, byteCount: Int) {
        writeCount++
        written += byteCount
    }

    override suspend fun commit(byteLength: Long) {
        assertEquals(written, byteLength)
        commitCount++
    }

    override suspend fun abort() {
        abortCount++
    }
}

private class RecordingSink(
    private val writeGate: CompletableDeferred<Unit>? = null,
    private val commitGate: CompletableDeferred<Unit>? = null,
    private val neverReturnFromWrite: Boolean = false,
    private val ignoreWriteCancellation: Boolean = false,
    private val neverReturnFromCommit: Boolean = false,
    private val neverReturnFromAbort: Boolean = false,
    private val failBegin: Boolean = false,
    private val failWrite: Boolean = false,
    private val failCommit: Boolean = false,
    private val failAbort: Boolean = false,
    private val retainWriteBuffersForContractTest: Boolean = false,
    private val phaseObserver: ((String) -> Unit)? = null,
) : MediaCopySink {
    val output = ArrayList<Byte>()
    val borrowedBuffers = mutableListOf<ByteArray>()
    val phases = mutableListOf<String>()
    var peakWrite = 0
    var beginCount = 0
    var commitAttemptCount = 0
    var commitCount = 0
    var abortCount = 0

    override suspend fun begin(mediaType: MediaType, contentType: String, byteLength: Long) {
        phaseObserver?.invoke("begin")
        beginCount++
        phases += "begin"
        if (failBegin) error("private sink begin detail")
    }

    override suspend fun write(buffer: ByteArray, byteCount: Int) {
        phaseObserver?.invoke("write")
        phases += "write"
        peakWrite = maxOf(peakWrite, byteCount)
        if (failWrite) error("private sink write detail")
        if (neverReturnFromWrite) awaitCancellation()
        if (ignoreWriteCancellation) {
            withContext(NonCancellable) { writeGate?.await() }
        } else {
            writeGate?.await()
        }
        repeat(byteCount) { output += buffer[it] }
        if (retainWriteBuffersForContractTest) borrowedBuffers += buffer
    }

    override suspend fun commit(byteLength: Long) {
        phaseObserver?.invoke("commit")
        commitAttemptCount++
        if (failCommit) error("private sink commit detail")
        if (neverReturnFromCommit) awaitCancellation()
        commitGate?.await()
        commitCount++
        phases += "commit"
    }

    override suspend fun abort() {
        phaseObserver?.invoke("abort")
        abortCount++
        phases += "abort"
        if (failAbort) error("private sink abort detail")
        if (neverReturnFromAbort) awaitCancellation()
    }
}

private fun generatedBytes(size: Int): ByteArray =
    ByteArray(size) { index -> ((index * 31) % 251).toByte() }

private suspend fun TestScope.captureConfirmedGeneratedPhoto(
    module: TestModule,
    declaredLength: Long,
): MediaHandle {
    val reference = FakeStoredMedia(module.framework.photoIndex)
    module.files.generatedStreamingLengths[reference] = declaredLength
    module.framework.nextPhotoMetadata = photoMetadata().copy(byteLength = declaredLength)
    val session = startReady(module, options(enabled = setOf(MediaType.PHOTO)))
    val preview = module.core.takePhoto(session)
    module.core.confirm(preview.mediaHandle)
    module.framework.nextPhotoMetadata = null
    return preview.mediaHandle
}

private suspend fun TestScope.captureConfirmedPhoto(
    module: TestModule,
    bytes: ByteArray,
    declaredLength: Long = bytes.size.toLong(),
): MediaHandle {
    val reference = FakeStoredMedia(module.framework.photoIndex)
    module.files.bytes[reference] = bytes
    module.framework.nextPhotoMetadata = photoMetadata().copy(byteLength = declaredLength)
    val session = startReady(module, options(enabled = setOf(MediaType.PHOTO)))
    val preview = module.core.takePhoto(session)
    module.core.confirm(preview.mediaHandle)
    module.framework.nextPhotoMetadata = null
    return preview.mediaHandle
}

private suspend fun TestScope.captureConfirmedVideo(module: TestModule, bytes: ByteArray): MediaHandle {
    val reference = FakeStoredMedia(module.framework.videoIndex)
    module.files.bytes[reference] = bytes
    val session = startReady(module, options(enabled = setOf(MediaType.VIDEO)))
    module.core.startRecording(session)
    val preview = module.core.stopRecording(session)
    module.core.confirm(preview.mediaHandle)
    return preview.mediaHandle
}

private suspend fun exportFailure(deferred: kotlinx.coroutines.Deferred<*>): FailureCode =
    try {
        deferred.await()
        error("Expected export failure")
    } catch (exception: MediaCaptureException) {
        exception.failure.code
    }
