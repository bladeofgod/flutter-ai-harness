package com.example.media_capture

import android.net.Uri
import android.util.Base64
import com.example.mediacapture.api.MediaCopySink
import com.example.mediacapture.api.MediaMetadata
import com.example.mediacapture.api.MediaType
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStream
import java.security.SecureRandom

internal class MediaCaptureTransferStore(
    cacheDirectory: File,
    private val secureRandom: SecureRandom = SecureRandom(),
    private val deleteFile: (File) -> Boolean = File::delete,
) {
    private val cacheRoot = runCatching { cacheDirectory.canonicalFile }.getOrNull()
    private val transferRoot = cacheRoot?.let { File(it, TRANSFER_RELATIVE_PATH) }
    private val expectedRootPath = transferRoot?.absolutePath
    private var generationOpen = initialize()

    val isAvailable: Boolean
        @Synchronized get() = generationOpen && verifyRoot()

    @Synchronized
    fun createReservation(metadata: MediaMetadata): Reservation {
        check(generationOpen && verifyRoot())
        require(metadata.byteLength > 0L)
        require(
            metadata.contentType ==
                if (metadata.mediaType == MediaType.PHOTO) PHOTO_CONTENT_TYPE else VIDEO_CONTENT_TYPE,
        )
        val root = checkNotNull(transferRoot)
        repeat(HANDLE_GENERATION_ATTEMPTS) {
            val handle = generateHandle()
            val extension = if (metadata.mediaType == MediaType.PHOTO) "jpg" else "mp4"
            val staging = File(root, "$handle.partial")
            val final = File(root, "$handle.$extension")
            if (staging.exists() || final.exists()) return@repeat
            if (!isDirectChild(staging) || !isDirectChild(final) || !staging.createNewFile()) {
                return@repeat
            }
            return Reservation(
                exportHandle = handle,
                metadata = metadata,
                stagingFile = staging,
                finalFile = final,
                store = this,
            )
        }
        error("Unable to create transfer target")
    }

    @Synchronized
    fun closeGeneration() {
        generationOpen = false
    }

    @Synchronized
    fun delete(reservation: Reservation): Boolean {
        if (!owns(reservation)) return false
        val stagingDeleted = deleteOwnedFile(reservation.stagingFile)
        val finalDeleted = deleteOwnedFile(reservation.finalFile)
        return stagingDeleted && finalDeleted
    }

    @Synchronized
    fun fileUri(reservation: Reservation): String {
        check(generationOpen && verifyRoot() && owns(reservation))
        check(reservation.committed && reservation.finalFile.isFile)
        check(isDirectChild(reservation.finalFile))
        return Uri.fromFile(reservation.finalFile.canonicalFile).toString().also {
            MediaCaptureWireCodec.requireCanonicalFileUri(it)
        }
    }

    @Synchronized
    internal fun requireWritable(reservation: Reservation, file: File) {
        check(generationOpen && verifyRoot() && owns(reservation))
        check(file === reservation.stagingFile || file === reservation.finalFile)
        check(isDirectChild(file))
    }

    private fun initialize(): Boolean {
        val root = transferRoot ?: return false
        val expected = expectedRootPath ?: return false
        val cache = cacheRoot ?: return false
        if (cache.absolutePath != runCatching { cache.canonicalPath }.getOrNull()) return false
        if (root.exists() && runCatching { root.canonicalPath }.getOrNull() != expected) return false
        if (!root.exists() && !root.mkdirs()) return false
        if (!root.isDirectory || !verifyRoot()) return false
        return root.listFiles()?.all(::deleteTreeWithoutFollowingLinks) == true
    }

    private fun verifyRoot(): Boolean {
        val root = transferRoot ?: return false
        val expected = expectedRootPath ?: return false
        return root.isDirectory &&
            root.absolutePath == expected &&
            runCatching { root.canonicalPath }.getOrNull() == expected
    }

    private fun owns(reservation: Reservation): Boolean = reservation.store === this

    private fun isDirectChild(file: File): Boolean {
        val root = transferRoot ?: return false
        if (file.parentFile?.absolutePath != root.absolutePath) return false
        val canonical = runCatching { file.canonicalFile }.getOrNull() ?: return false
        return canonical.parentFile?.absolutePath == root.absolutePath &&
            canonical.absolutePath == file.absolutePath
    }

    private fun deleteOwnedFile(file: File): Boolean {
        val root = transferRoot ?: return false
        if (!verifyRoot()) return false
        if (file.parentFile?.absolutePath != root.absolutePath) return false
        if (!file.exists()) return true
        val canonical = runCatching { file.canonicalFile }.getOrNull()
        if (canonical == null || canonical.absolutePath != file.absolutePath) {
            return deleteFile(file)
        }
        if (canonical.parentFile?.absolutePath != root.absolutePath || canonical.isDirectory) return false
        return deleteFile(file) || !file.exists()
    }

    private fun deleteTreeWithoutFollowingLinks(file: File): Boolean {
        val root = transferRoot ?: return false
        if (file.parentFile?.absolutePath != root.absolutePath) return false
        val canonical = runCatching { file.canonicalFile }.getOrNull() ?: return false
        if (canonical.absolutePath != file.absolutePath) return deleteFile(file) || !file.exists()
        if (canonical.parentFile?.absolutePath != root.absolutePath) return false
        if (file.isDirectory) {
            val children = file.listFiles() ?: return false
            if (!children.all(::deleteNestedTreeWithoutFollowingLinks)) return false
        }
        return deleteFile(file) || !file.exists()
    }

    private fun deleteNestedTreeWithoutFollowingLinks(file: File): Boolean {
        val rootPath = expectedRootPath ?: return false
        val absolute = file.absolutePath
        if (!absolute.startsWith("$rootPath${File.separator}")) return false
        val canonical = runCatching { file.canonicalFile }.getOrNull() ?: return false
        if (canonical.absolutePath != absolute) return deleteFile(file) || !file.exists()
        if (!canonical.absolutePath.startsWith("$rootPath${File.separator}")) return false
        if (file.isDirectory) {
            val children = file.listFiles() ?: return false
            if (!children.all(::deleteNestedTreeWithoutFollowingLinks)) return false
        }
        return deleteFile(file) || !file.exists()
    }

    private fun generateHandle(): String {
        val bytes = ByteArray(EXPORT_HANDLE_BYTES)
        secureRandom.nextBytes(bytes)
        return Base64.encodeToString(
            bytes,
            Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING,
        )
    }

    internal class Reservation private constructor(
        val exportHandle: String,
        val metadata: MediaMetadata,
        internal val stagingFile: File,
        internal val finalFile: File,
        internal val store: MediaCaptureTransferStore,
    ) {
        private val sink = TransferSink(this, store)

        val mediaSink: MediaCopySink
            get() = sink

        val committed: Boolean
            get() = sink.isCommitted

        internal companion object {
            operator fun invoke(
                exportHandle: String,
                metadata: MediaMetadata,
                stagingFile: File,
                finalFile: File,
                store: MediaCaptureTransferStore,
            ): Reservation = Reservation(exportHandle, metadata, stagingFile, finalFile, store)
        }
    }

    private class TransferSink(
        private val reservation: Reservation,
        private val store: MediaCaptureTransferStore,
    ) : MediaCopySink {
        private var output: OutputStream? = null
        private var written = 0L
        private var begun = false
        private var committed = false
        private var aborted = false

        val isCommitted: Boolean
            @Synchronized get() = committed

        override suspend fun begin(mediaType: MediaType, contentType: String, byteLength: Long) = synchronized(this) {
            check(!begun && !committed && !aborted)
            check(
                mediaType == reservation.metadata.mediaType &&
                    contentType == reservation.metadata.contentType &&
                    byteLength == reservation.metadata.byteLength &&
                    byteLength in 1L..MAX_TRANSFER_FILE_BYTES,
            )
            store.requireWritable(reservation, reservation.stagingFile)
            check(reservation.stagingFile.isFile && reservation.stagingFile.length() == 0L)
            output = FileOutputStream(reservation.stagingFile, false)
            begun = true
        }

        override suspend fun write(buffer: ByteArray, byteCount: Int) = synchronized(this) {
            check(begun && !committed && !aborted)
            require(byteCount in 1..buffer.size)
            val nextLength = written + byteCount.toLong()
            check(nextLength <= reservation.metadata.byteLength && nextLength <= MAX_TRANSFER_FILE_BYTES)
            store.requireWritable(reservation, reservation.stagingFile)
            checkNotNull(output).write(buffer, 0, byteCount)
            written = nextLength
        }

        override suspend fun commit(byteLength: Long) = synchronized(this) {
            check(begun && !committed && !aborted)
            check(byteLength == reservation.metadata.byteLength && written == byteLength)
            store.requireWritable(reservation, reservation.stagingFile)
            val stream = checkNotNull(output)
            stream.flush()
            if (stream is FileOutputStream) stream.fd.sync()
            stream.close()
            output = null
            check(reservation.stagingFile.length() == byteLength)
            store.requireWritable(reservation, reservation.finalFile)
            check(!reservation.finalFile.exists())
            check(reservation.stagingFile.renameTo(reservation.finalFile))
            store.requireWritable(reservation, reservation.finalFile)
            check(reservation.finalFile.isFile && reservation.finalFile.length() == byteLength)
            committed = true
        }

        override suspend fun abort() = synchronized(this) {
            if (aborted) return@synchronized
            aborted = true
            runCatching { output?.close() }
            output = null
            store.delete(reservation)
        }
    }

    private companion object {
        const val TRANSFER_RELATIVE_PATH = "app_media_capture_bridge/exports"
        const val EXPORT_HANDLE_BYTES = 16
        const val HANDLE_GENERATION_ATTEMPTS = 32
        const val MAX_TRANSFER_FILE_BYTES = 52_428_800L
        const val PHOTO_CONTENT_TYPE = "image/jpeg"
        const val VIDEO_CONTENT_TYPE = "video/mp4"
    }
}
