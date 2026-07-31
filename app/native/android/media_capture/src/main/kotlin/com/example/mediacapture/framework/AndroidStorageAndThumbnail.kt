package com.example.mediacapture.framework

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.exifinterface.media.ExifInterface
import com.example.mediacapture.api.FailureCode
import com.example.mediacapture.api.MediaMetadata
import com.example.mediacapture.api.MediaType
import com.example.mediacapture.api.ScopedMediaRead
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.RandomAccessFile
import java.security.SecureRandom
import java.util.Collections
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.coroutineContext
import kotlin.math.max
import kotlin.math.roundToInt

internal class SystemMediaCaptureClock : MediaCaptureClock {
    override fun nowEpochMillis(): Long = System.currentTimeMillis()
}

internal class SecureOpaqueHandleGenerator(
    private val secureRandom: SecureRandom = SecureRandom(),
) : OpaqueHandleGenerator {
    override fun nextHandle(): String {
        val bytes = ByteArray(HANDLE_BYTES)
        secureRandom.nextBytes(bytes)
        return encodeBase64UrlWithoutPadding(bytes)
    }

    private companion object {
        const val HANDLE_BYTES = 16
    }
}

internal object AndroidPhotoMetadataSanitizer {
    private val sensitiveTags =
        listOf(
            ExifInterface.TAG_GPS_LATITUDE,
            ExifInterface.TAG_GPS_LATITUDE_REF,
            ExifInterface.TAG_GPS_LONGITUDE,
            ExifInterface.TAG_GPS_LONGITUDE_REF,
            ExifInterface.TAG_GPS_ALTITUDE,
            ExifInterface.TAG_GPS_ALTITUDE_REF,
            ExifInterface.TAG_GPS_TIMESTAMP,
            ExifInterface.TAG_GPS_DATESTAMP,
            ExifInterface.TAG_GPS_PROCESSING_METHOD,
            ExifInterface.TAG_DATETIME,
            ExifInterface.TAG_DATETIME_ORIGINAL,
            ExifInterface.TAG_DATETIME_DIGITIZED,
            ExifInterface.TAG_OFFSET_TIME,
            ExifInterface.TAG_OFFSET_TIME_ORIGINAL,
            ExifInterface.TAG_OFFSET_TIME_DIGITIZED,
            ExifInterface.TAG_SUBSEC_TIME,
            ExifInterface.TAG_SUBSEC_TIME_ORIGINAL,
            ExifInterface.TAG_SUBSEC_TIME_DIGITIZED,
            ExifInterface.TAG_MAKE,
            ExifInterface.TAG_MODEL,
            ExifInterface.TAG_SOFTWARE,
            ExifInterface.TAG_BODY_SERIAL_NUMBER,
            ExifInterface.TAG_CAMERA_OWNER_NAME,
            ExifInterface.TAG_LENS_MAKE,
            ExifInterface.TAG_LENS_MODEL,
            ExifInterface.TAG_LENS_SERIAL_NUMBER,
            ExifInterface.TAG_IMAGE_UNIQUE_ID,
            ExifInterface.TAG_MAKER_NOTE,
        )

    fun sanitize(file: File) {
        val exif = ExifInterface(file)
        sensitiveTags.forEach { exif.setAttribute(it, null) }
        exif.saveAttributes()
    }
}

internal class AndroidPrivateMediaStore(
    context: Context,
    private val ioDispatcher: CoroutineDispatcher,
) : MediaFileStore {
    private val root = File(context.cacheDir, DIRECTORY_NAME)
    private val readers = ConcurrentHashMap<AndroidStoredMedia, MutableSet<AndroidRevocableRead>>()

    internal fun allocate(extension: String, contentType: String): AndroidStoredMedia {
        require(extension.matches(EXTENSION))
        return try {
            if (!root.exists() && !root.mkdirs()) throw FrameworkException(FailureCode.STORAGE_FULL)
            AndroidStoredMedia(File.createTempFile(FILE_PREFIX, ".$extension", root), contentType)
        } catch (exception: FrameworkException) {
            throw exception
        } catch (_: Exception) {
            throw FrameworkException(FailureCode.STORAGE_FULL)
        }
    }

    override suspend fun cleanupRestartResidue() =
        withContext(ioDispatcher) {
            root.listFiles()
                ?.filter { it.isFile && it.name.startsWith(FILE_PREFIX) }
                ?.forEach { wipeAndDelete(it) }
            Unit
        }

    override suspend fun delete(reference: StoredMediaReference): Boolean =
        withContext(ioDispatcher) {
            val stored = reference.requireAndroidStoredMedia()
            readers.remove(stored)?.toList()?.forEach { it.revoke() }
            wipeAndDelete(stored.file)
        }

    override suspend fun openRead(
        reference: StoredMediaReference,
        byteLength: Long,
        contentType: String,
    ): ScopedMediaRead {
        val stored = reference.requireAndroidStoredMedia()
        val read =
            AndroidScopedMediaRead(stored, byteLength, contentType, ioDispatcher) {
                readers[stored]?.remove(it)
            }
        val created = Collections.newSetFromMap(ConcurrentHashMap<AndroidRevocableRead, Boolean>())
        val activeReaders = readers.putIfAbsent(stored, created) ?: created
        activeReaders.add(read)
        return read
    }

    override suspend fun openStreamingRead(
        reference: StoredMediaReference,
        byteLength: Long,
        contentType: String,
    ): StreamingMediaRead {
        val stored = reference.requireAndroidStoredMedia()
        val read =
            AndroidStreamingMediaRead(stored, byteLength, contentType, ioDispatcher) {
                readers[stored]?.remove(it)
            }
        val created = Collections.newSetFromMap(ConcurrentHashMap<AndroidRevocableRead, Boolean>())
        val activeReaders = readers.putIfAbsent(stored, created) ?: created
        activeReaders.add(read)
        return read
    }

    override suspend fun revokeReads(reference: StoredMediaReference) {
        val stored = reference.requireAndroidStoredMedia()
        readers.remove(stored)?.toList()?.forEach { it.revoke() }
    }

    private companion object {
        const val DIRECTORY_NAME = "media_capture"
        const val FILE_PREFIX = "capture_"
        val EXTENSION = Regex("^[a-z0-9]{1,8}$")

        fun wipeAndDelete(file: File): Boolean =
            runCatching {
                if (file.exists()) {
                    RandomAccessFile(file, "rw").use { access ->
                        val zeros = ByteArray(8_192)
                        var remaining = access.length()
                        access.seek(0)
                        while (remaining > 0) {
                            val count = minOf(remaining, zeros.size.toLong()).toInt()
                            access.write(zeros, 0, count)
                            remaining -= count
                        }
                        access.fd.sync()
                    }
                    file.delete()
                } else {
                    true
                }
            }.getOrDefault(false)
    }
}

internal data class AndroidStoredMedia(
    val file: File,
    val storedContentType: String,
) : StoredMediaReference

private interface AndroidRevocableRead {
    fun revoke()
}

private class AndroidScopedMediaRead(
    private val stored: AndroidStoredMedia,
    override val byteLength: Long,
    override val contentType: String,
    private val ioDispatcher: CoroutineDispatcher,
    private val onClosed: (AndroidRevocableRead) -> Unit,
) : ScopedMediaRead, AndroidRevocableRead {
    private val closed = AtomicBoolean(false)
    private val activeInput = AtomicReference<FileInputStream?>(null)

    override suspend fun readBytes(): ByteArray =
        withContext(ioDispatcher) {
            if (closed.get()) throw FrameworkException(FailureCode.INVALID_STATE)
            val input = FileInputStream(stored.file)
            if (!activeInput.compareAndSet(null, input) || closed.get()) {
                input.close()
                throw FrameworkException(FailureCode.INVALID_STATE)
            }
            try {
                input.readBytes()
            } finally {
                activeInput.compareAndSet(input, null)
                input.close()
            }
        }

    override suspend fun close() {
        if (closed.compareAndSet(false, true)) {
            runCatching { activeInput.getAndSet(null)?.close() }
            onClosed(this)
        }
    }

    override fun revoke() {
        if (closed.compareAndSet(false, true)) {
            runCatching { activeInput.getAndSet(null)?.close() }
            onClosed(this)
        }
    }
}

private class AndroidStreamingMediaRead(
    private val stored: AndroidStoredMedia,
    override val byteLength: Long,
    override val contentType: String,
    private val ioDispatcher: CoroutineDispatcher,
    private val onClosed: (AndroidRevocableRead) -> Unit,
) : StreamingMediaRead, AndroidRevocableRead {
    private val closed = AtomicBoolean(false)
    private val activeInput = AtomicReference<FileInputStream?>(null)

    override suspend fun read(buffer: ByteArray): Int =
        withContext(ioDispatcher) {
            if (closed.get()) throw FrameworkException(FailureCode.INVALID_STATE)
            val input = activeInput.get() ?: openInput()
            try {
                input.read(buffer)
            } catch (exception: CancellationException) {
                throw exception
            } catch (_: Exception) {
                throw FrameworkException(FailureCode.MEDIA_EXPORT_READ_FAILED)
            }
        }

    override suspend fun close() {
        if (closed.compareAndSet(false, true)) {
            runCatching { activeInput.getAndSet(null)?.close() }
            onClosed(this)
        }
    }

    override fun revoke() {
        if (closed.compareAndSet(false, true)) {
            runCatching { activeInput.getAndSet(null)?.close() }
            onClosed(this)
        }
    }

    private fun openInput(): FileInputStream {
        val input =
            try {
                FileInputStream(stored.file)
            } catch (_: Exception) {
                throw FrameworkException(FailureCode.MEDIA_EXPORT_READ_FAILED)
            }
        if (!activeInput.compareAndSet(null, input) || closed.get()) {
            runCatching { input.close() }
            throw FrameworkException(FailureCode.INVALID_STATE)
        }
        return input
    }
}

internal class AndroidSanitizedThumbnailGenerator(
    private val ioDispatcher: CoroutineDispatcher,
) : ThumbnailGenerator {
    override suspend fun open(
        reference: StoredMediaReference,
        metadata: MediaMetadata,
        request: ThumbnailGenerationRequest,
    ): ThumbnailGenerationWork =
        acquireCancellableResource(
            dispatcher = ioDispatcher,
            acquire = {
                val stored = reference.requireAndroidStoredMedia()
                val descriptor =
                    ParcelFileDescriptor.open(stored.file, ParcelFileDescriptor.MODE_READ_ONLY)
                        ?: throw FrameworkException(FailureCode.THUMBNAIL_GENERATION_FAILED)
                AndroidThumbnailWork(stored, descriptor, metadata, request, ioDispatcher)
            },
            dispose = { it.disposeBeforeOwnershipTransfer() },
        )
}

internal suspend fun <T : Any> acquireCancellableResource(
    dispatcher: CoroutineDispatcher,
    acquire: () -> T,
    afterAcquire: suspend (T) -> Unit = {},
    dispose: (T) -> Unit,
): T =
    suspendCancellableCoroutine { continuation ->
        val acquisition =
            CoroutineScope(continuation.context).launch(dispatcher) {
                var resource: T? = null
                try {
                    resource = acquire()
                    afterAcquire(requireNotNull(resource))
                    coroutineContext.ensureActive()
                    val transferred = requireNotNull(resource)
                    resource = null
                    continuation.resume(transferred) { _, rejected, _ ->
                        runCatching { dispose(rejected) }
                    }
                } catch (exception: CancellationException) {
                    throw exception
                } catch (exception: Throwable) {
                    if (continuation.isActive) continuation.resumeWithException(exception)
                } finally {
                    resource?.let { runCatching { dispose(it) } }
                }
            }
        continuation.invokeOnCancellation { acquisition.cancel() }
    }

private class AndroidThumbnailWork(
    private val stored: AndroidStoredMedia,
    private val descriptor: ParcelFileDescriptor,
    private val metadata: MediaMetadata,
    private val request: ThumbnailGenerationRequest,
    private val ioDispatcher: CoroutineDispatcher,
) : ThumbnailGenerationWork {
    private val sourceRevoked = AtomicBoolean(false)
    private val sourceClosed = AtomicBoolean(false)
    private var decoded: Bitmap? = null
    private var generationBuffer: ByteArray? = null

    override suspend fun generate(): ThumbnailArtifact =
        withContext(ioDispatcher) {
            coroutineContext.ensureActive()
            check(!sourceRevoked.get())
            val generated =
                when (metadata.mediaType) {
                    MediaType.PHOTO -> decodePhoto()
                    MediaType.VIDEO -> decodeVideo()
                }
            decoded = generated.bitmap
            val encoded = encodeBoundedJpeg(generated.bitmap)
            generationBuffer = encoded
            ThumbnailArtifact(
                encodedJpeg = encoded,
                pixelWidth = generated.bitmap.width,
                pixelHeight = generated.bitmap.height,
                orientationDegrees = 0,
                actualPosterFrameMillis = generated.posterFrameMillis,
            )
        }

    override suspend fun revokeSourceAccess() {
        sourceRevoked.set(true)
    }

    override suspend fun cancelAndAwaitDecoder() {
        sourceRevoked.set(true)
    }

    override suspend fun closeSourceHandles() {
        if (sourceClosed.compareAndSet(false, true)) descriptor.close()
    }

    override fun wipeDecodedPixels() {
        decoded?.eraseColor(0)
        decoded?.recycle()
        decoded = null
    }

    override fun wipeGenerationBuffer() {
        generationBuffer?.fill(0)
        generationBuffer = null
    }

    override fun discardPartialCopy() {
        wipeGenerationBuffer()
    }

    override suspend fun closeSourceAccess() {
        sourceRevoked.set(true)
    }

    override suspend fun finishAndCloseDecoder() = Unit

    fun disposeBeforeOwnershipTransfer() {
        sourceRevoked.set(true)
        if (sourceClosed.compareAndSet(false, true)) runCatching { descriptor.close() }
    }

    private fun decodePhoto(): GeneratedBitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(stored.file.absolutePath, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) thumbnailFailure()
        val sample =
            calculateDecodeSample(
                bounds.outWidth,
                bounds.outHeight,
                request.maxPixelEdge,
                request.maxDecodedPixels,
            )
        val options = BitmapFactory.Options().apply { inSampleSize = sample }
        val source = BitmapFactory.decodeFile(stored.file.absolutePath, options) ?: thumbnailFailure()
        val orientation = ExifInterface(stored.file).rotationDegrees.toFloat()
        return GeneratedBitmap(normalizeAndScale(source, orientation), null)
    }

    private fun decodeVideo(): GeneratedBitmap {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(descriptor.fileDescriptor)
            val width = retriever.metadataInt(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
            val height = retriever.metadataInt(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
            val rotation = retriever.metadataInt(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
            if (width <= 0 || height <= 0) thumbnailFailure()
            val (targetWidth, targetHeight) = boundedDimensions(width, height, request.maxPixelEdge)
            val actualMillis = selectPosterFrame(requireNotNull(request.videoTargetFrameMillis))
            val bitmap =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                    retriever.getScaledFrameAtTime(
                        actualMillis * MICROS_PER_MILLI,
                        MediaMetadataRetriever.OPTION_CLOSEST,
                        targetWidth,
                        targetHeight,
                    )
                } else {
                    if (width.toLong() * height > request.maxDecodedPixels) thumbnailFailure()
                    retriever.getFrameAtTime(
                        actualMillis * MICROS_PER_MILLI,
                        MediaMetadataRetriever.OPTION_CLOSEST,
                    )
                } ?: thumbnailFailure()
            return GeneratedBitmap(normalizeAndScale(bitmap, rotation.toFloat()), actualMillis)
        } finally {
            retriever.release()
        }
    }

    private fun selectPosterFrame(targetMillis: Long): Long {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(stored.file.absolutePath)
            val videoTrack =
                (0 until extractor.trackCount).firstOrNull { index ->
                    extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true
                } ?: thumbnailFailure()
            extractor.selectTrack(videoTrack)
            extractor.seekTo(targetMillis * MICROS_PER_MILLI, MediaExtractor.SEEK_TO_NEXT_SYNC)
            val after = extractor.sampleTime.takeIf { it >= 0 }?.div(MICROS_PER_MILLI)
            if (after != null) return selectPosterFrameMillis(targetMillis, after, null) ?: thumbnailFailure()
            extractor.seekTo(targetMillis * MICROS_PER_MILLI, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            val before = extractor.sampleTime.takeIf { it >= 0 }?.div(MICROS_PER_MILLI)
            return selectPosterFrameMillis(targetMillis, null, before) ?: thumbnailFailure()
        } finally {
            extractor.release()
        }
    }

    private fun normalizeAndScale(source: Bitmap, rotationDegrees: Float): Bitmap {
        val rotated =
            if (rotationDegrees == 0f) {
                source
            } else {
                Bitmap.createBitmap(
                    source,
                    0,
                    0,
                    source.width,
                    source.height,
                    Matrix().apply { postRotate(rotationDegrees) },
                    true,
                ).also { if (it !== source) source.recycle() }
            }
        val (width, height) = boundedDimensions(rotated.width, rotated.height, request.maxPixelEdge)
        if (width.toLong() * height > request.maxDecodedPixels) thumbnailFailure()
        if (rotated.width == width && rotated.height == height) return rotated
        return Bitmap.createScaledBitmap(rotated, width, height, true).also {
            if (it !== rotated) rotated.recycle()
        }
    }

    private fun encodeBoundedJpeg(bitmap: Bitmap): ByteArray {
        for (quality in JPEG_QUALITIES) {
            val output = ByteArrayOutputStream()
            if (!bitmap.compress(Bitmap.CompressFormat.JPEG, quality, output)) thumbnailFailure()
            val platformBytes = output.toByteArray()
            val canonicalBytes =
                try {
                    canonicalizeJpegForWire(platformBytes)
                } finally {
                    platformBytes.fill(0)
                }
            if (canonicalBytes.size in 1..MAX_JPEG_BYTES) return canonicalBytes
            canonicalBytes.fill(0)
        }
        thumbnailFailure()
    }

    private fun MediaMetadataRetriever.metadataInt(key: Int): Int =
        extractMetadata(key)?.toIntOrNull() ?: -1

    private data class GeneratedBitmap(val bitmap: Bitmap, val posterFrameMillis: Long?)

    private companion object {
        const val MICROS_PER_MILLI = 1_000L
        const val MAX_JPEG_BYTES = 524_288
        val JPEG_QUALITIES = intArrayOf(90, 80, 70, 60)
    }
}

internal fun canonicalizeJpegForWire(platformBytes: ByteArray): ByteArray {
    if (
        platformBytes.size < 4 || platformBytes.u8(0) != JPEG_MARKER_PREFIX ||
        platformBytes.u8(1) != JPEG_START_OF_IMAGE
    ) {
        thumbnailFailure()
    }
    val output = ByteArrayOutputStream(platformBytes.size + CANONICAL_JFIF_SEGMENT.size)
    output.write(JPEG_MARKER_PREFIX)
    output.write(JPEG_START_OF_IMAGE)
    output.write(CANONICAL_JFIF_SEGMENT)
    var offset = 2
    while (offset < platformBytes.size) {
        if (platformBytes.u8(offset) != JPEG_MARKER_PREFIX) thumbnailFailure()
        while (offset < platformBytes.size && platformBytes.u8(offset) == JPEG_MARKER_PREFIX) {
            offset += 1
        }
        if (offset >= platformBytes.size) thumbnailFailure()
        val marker = platformBytes.u8(offset++)
        if (marker == JPEG_END_OF_IMAGE) thumbnailFailure()
        if (marker == JPEG_START_OF_IMAGE || marker == 0x00 || marker in 0xd0..0xd7) {
            thumbnailFailure()
        }
        if (offset + 2 > platformBytes.size) thumbnailFailure()
        val segmentLength = (platformBytes.u8(offset) shl 8) or platformBytes.u8(offset + 1)
        if (segmentLength < 2 || offset + segmentLength > platformBytes.size) thumbnailFailure()
        val segmentEnd = offset + segmentLength
        if (marker !in JPEG_APP_MARKERS && marker != JPEG_COMMENT) {
            if (marker !in WIRE_JPEG_SEGMENT_MARKERS) thumbnailFailure()
            output.write(JPEG_MARKER_PREFIX)
            output.write(marker)
            output.write(platformBytes, offset, segmentLength)
        }
        offset = segmentEnd
        if (marker == JPEG_START_OF_SCAN) {
            if (
                platformBytes.size - offset < 2 ||
                platformBytes.u8(platformBytes.lastIndex - 1) != JPEG_MARKER_PREFIX ||
                platformBytes.u8(platformBytes.lastIndex) != JPEG_END_OF_IMAGE
            ) {
                thumbnailFailure()
            }
            output.write(platformBytes, offset, platformBytes.size - offset)
            return output.toByteArray()
        }
    }
    thumbnailFailure()
}

private fun ByteArray.u8(index: Int): Int = this[index].toInt() and 0xff

private const val JPEG_MARKER_PREFIX = 0xff
private const val JPEG_START_OF_IMAGE = 0xd8
private const val JPEG_END_OF_IMAGE = 0xd9
private const val JPEG_START_OF_SCAN = 0xda
private const val JPEG_COMMENT = 0xfe
private val JPEG_APP_MARKERS = 0xe0..0xef
private val WIRE_JPEG_START_OF_FRAME_MARKERS =
    setOf(0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf)
private val WIRE_JPEG_SEGMENT_MARKERS =
    WIRE_JPEG_START_OF_FRAME_MARKERS + setOf(0xc4, 0xcc, 0xda, 0xdb, 0xdc, 0xdd, 0xde, 0xdf)
private val CANONICAL_JFIF_SEGMENT =
    byteArrayOf(
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

private fun boundedDimensions(width: Int, height: Int, maxEdge: Int): Pair<Int, Int> {
    if (width <= maxEdge && height <= maxEdge) return width to height
    val scale = maxEdge.toDouble() / max(width, height)
    return max(1, (width * scale).roundToInt()) to max(1, (height * scale).roundToInt())
}

private fun StoredMediaReference.requireAndroidStoredMedia(): AndroidStoredMedia =
    this as? AndroidStoredMedia ?: throw FrameworkException(FailureCode.MEDIA_INVALID)

private fun thumbnailFailure(): Nothing =
    throw FrameworkException(FailureCode.THUMBNAIL_GENERATION_FAILED)

internal fun calculateDecodeSample(
    width: Int,
    height: Int,
    maxEdge: Int,
    maxDecodedPixels: Int,
): Int {
    var sample = 1
    while (max(width / sample, height / sample) > maxEdge ||
        (width / sample).toLong() * (height / sample) > maxDecodedPixels
    ) {
        sample *= 2
    }
    return sample
}

internal fun selectPosterFrameMillis(
    targetMillis: Long,
    nextAtOrAfterMillis: Long?,
    previousMillis: Long?,
): Long? =
    nextAtOrAfterMillis?.takeIf { it >= targetMillis } ?: previousMillis?.takeIf { it <= targetMillis }

private fun encodeBase64UrlWithoutPadding(bytes: ByteArray): String {
    val output = StringBuilder((bytes.size * 4 + 2) / 3)
    var index = 0
    while (index < bytes.size) {
        val first = bytes[index++].toInt() and 0xFF
        val second = if (index < bytes.size) bytes[index++].toInt() and 0xFF else -1
        val third = if (index < bytes.size) bytes[index++].toInt() and 0xFF else -1
        output.append(BASE64_URL_ALPHABET[first ushr 2])
        output.append(BASE64_URL_ALPHABET[((first and 0x03) shl 4) or if (second >= 0) second ushr 4 else 0])
        if (second >= 0) {
            output.append(
                BASE64_URL_ALPHABET[((second and 0x0F) shl 2) or if (third >= 0) third ushr 6 else 0],
            )
        }
        if (third >= 0) output.append(BASE64_URL_ALPHABET[third and 0x3F])
    }
    return output.toString()
}

private const val BASE64_URL_ALPHABET =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
