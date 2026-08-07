package com.example.media_capture

import android.net.Uri
import android.system.Os
import android.system.OsConstants
import android.util.Base64
import com.example.mediacapture.api.MediaCopySink
import com.example.mediacapture.api.MediaMetadata
import com.example.mediacapture.api.MediaType
import java.io.File
import java.io.FileDescriptor
import java.security.SecureRandom
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

internal data class TransferFileIdentity(val device: Long, val inode: Long)

internal data class TransferFileSnapshot(
    val identity: TransferFileIdentity,
    val size: Long,
    val links: Long,
    val regular: Boolean,
    val directory: Boolean,
)

internal interface TransferFileHandle {
    val identity: TransferFileIdentity
    val valid: Boolean

    fun snapshot(): TransferFileSnapshot?

    fun write(buffer: ByteArray, offset: Int, byteCount: Int): Int

    fun sync()

    fun close()
}

internal interface TransferFileSystem {
    fun openExclusive(file: File): TransferFileHandle?

    fun snapshot(file: File): TransferFileSnapshot?
}

internal class AndroidTransferFileSystem(
    private val openDescriptor: (File) -> FileDescriptor = { file ->
        Os.open(
            file.absolutePath,
            OsConstants.O_RDWR or
                OsConstants.O_CREAT or
                OsConstants.O_EXCL or
                OsConstants.O_NOFOLLOW or
                LINUX_O_CLOEXEC,
            OsConstants.S_IRUSR or OsConstants.S_IWUSR,
        )
    },
    private val createHandle: (FileDescriptor) -> TransferFileHandle = ::AndroidTransferFileHandle,
    private val closeDescriptor: (FileDescriptor) -> Unit = Os::close,
) : TransferFileSystem {
    override fun openExclusive(file: File): TransferFileHandle? {
        val descriptor = runCatching { openDescriptor(file) }.getOrNull() ?: return null
        val handle =
            try {
                createHandle(descriptor)
            } catch (_: Exception) {
                runCatching { closeDescriptor(descriptor) }
                return null
            }
        return handle.takeIf {
            runCatching { it.snapshot()?.let(::isInitialRegularFile) == true }.getOrDefault(false)
        }
            ?: run {
                handle.close()
                if (snapshot(file)?.identity == handle.identity) {
                    runCatching { Os.remove(file.absolutePath) }
                }
                null
            }
    }

    override fun snapshot(file: File): TransferFileSnapshot? =
        runCatching { Os.lstat(file.absolutePath).toSnapshot() }.getOrNull()

    private fun isInitialRegularFile(snapshot: TransferFileSnapshot): Boolean =
        snapshot.regular && snapshot.links == 1L && snapshot.size == 0L

    private companion object {
        // O_CLOEXEC is stable Linux ABI but Android does not expose the SDK constant before API 27.
        const val LINUX_O_CLOEXEC = 0x00080000
    }
}

private class AndroidTransferFileHandle(
    private val descriptor: FileDescriptor,
) : TransferFileHandle {
    override val identity: TransferFileIdentity =
        Os.fstat(descriptor).let { TransferFileIdentity(it.st_dev, it.st_ino) }

    override val valid: Boolean
        get() = descriptor.valid()

    override fun snapshot(): TransferFileSnapshot? =
        runCatching { Os.fstat(descriptor).toSnapshot() }.getOrNull()

    override fun write(buffer: ByteArray, offset: Int, byteCount: Int): Int =
        Os.write(descriptor, buffer, offset, byteCount)

    override fun sync() = Os.fsync(descriptor)

    override fun close() {
        if (descriptor.valid()) Os.close(descriptor)
    }
}

private fun android.system.StructStat.toSnapshot(): TransferFileSnapshot =
    TransferFileSnapshot(
        identity = TransferFileIdentity(st_dev, st_ino),
        size = st_size,
        links = st_nlink,
        regular = OsConstants.S_ISREG(st_mode),
        directory = OsConstants.S_ISDIR(st_mode),
    )

internal class MediaCaptureTransferStore(
    cacheDirectory: File,
    private val secureRandom: SecureRandom = SecureRandom(),
    private val fileSystem: TransferFileSystem = AndroidTransferFileSystem(),
    private val deleteFile: (File) -> Boolean = File::delete,
) {
    private val cacheRoot = runCatching { cacheDirectory.canonicalFile }.getOrNull()
    private val transferRoot = cacheRoot?.let { File(it, TRANSFER_RELATIVE_PATH) }
    private val expectedRootPath = transferRoot?.absolutePath
    private val rootRegistrationKey = cacheRoot?.absolutePath
    private var rootRegistered = rootRegistrationKey?.let(RootUseCoordinator::register) == true
    private var rootIdentity: TransferFileIdentity? = null
    private val reservations = mutableSetOf<Reservation>()
    private var generationOpen = initializeCoordinated().also { if (!it) unregisterRoot() }

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
            val transfer = File(root, "$handle.$extension")
            if (transfer.exists()) return@repeat
            if (!isDirectChildPath(transfer)) return@repeat
            val descriptor = runCatching { fileSystem.openExclusive(transfer) }.getOrNull() ?: return@repeat
            val identity = descriptorIdentity(descriptor, expectedSize = 0L)
            if (identity == null) {
                descriptor.close()
                deleteReservationFile(transfer, descriptor.identity)
                return@repeat
            }
            return Reservation(
                exportHandle = handle,
                metadata = metadata,
                transferFile = transfer,
                descriptor = descriptor,
                identity = identity,
                store = this,
            ).also(reservations::add)
        }
        error("Unable to create transfer target")
    }

    @Synchronized
    fun closeGeneration() {
        generationOpen = false
        unregisterRootIfIdle()
    }

    fun delete(reservation: Reservation): Boolean {
        if (!owns(reservation)) return false
        reservation.closeDescriptor()
        return synchronized(this) {
            val transferDeleted = deleteReservationFile(reservation.transferFile, reservation.identity)
            if (!reservationFileStillOwned(reservation)) {
                reservations.remove(reservation)
                unregisterRootIfIdle()
            }
            transferDeleted
        }
    }

    fun fileUri(reservation: Reservation): String {
        check(reservation.committed)
        return synchronized(this) {
            check(generationOpen && verifyRoot() && owns(reservation))
            check(pathMatchesIdentity(reservation.transferFile, reservation.identity))
            Uri.fromFile(reservation.transferFile.canonicalFile).toString().also {
                MediaCaptureWireCodec.requireCanonicalFileUri(it)
            }
        }
    }

    @Synchronized
    internal fun requireWritable(
        reservation: Reservation,
        expectedSize: Long,
    ) {
        check(generationOpen && verifyRoot() && owns(reservation))
        check(descriptorIdentity(reservation.descriptor, expectedSize) == reservation.identity)
        check(pathMatchesIdentity(reservation.transferFile, reservation.identity))
    }

    private fun initializeCoordinated(): Boolean {
        val key = rootRegistrationKey ?: return false
        if (!rootRegistered || !RootUseCoordinator.prepare(key, ::initializeAndSweep)) return false
        rootIdentity = directoryIdentity(transferRoot ?: return false)
        return verifyRoot()
    }

    private fun initializeAndSweep(): Boolean {
        val root = transferRoot ?: return false
        val expected = expectedRootPath ?: return false
        val cache = cacheRoot ?: return false
        if (cache.absolutePath != runCatching { cache.canonicalPath }.getOrNull()) return false
        if (root.exists() && runCatching { root.canonicalPath }.getOrNull() != expected) return false
        if (!root.exists() && !root.mkdirs()) return false
        if (
            !root.isDirectory ||
            runCatching { root.canonicalPath }.getOrNull() != expected ||
            directoryIdentity(root) == null
        ) {
            return false
        }
        return root.listFiles()?.all(::deleteTreeWithoutFollowingLinks) == true
    }

    private fun verifyRoot(): Boolean {
        val root = transferRoot ?: return false
        val expected = expectedRootPath ?: return false
        val identity = rootIdentity ?: return false
        return root.isDirectory &&
            root.absolutePath == expected &&
            runCatching { root.canonicalPath }.getOrNull() == expected &&
            directoryIdentity(root) == identity
    }

    private fun owns(reservation: Reservation): Boolean = reservation.store === this

    private fun isDirectChildPath(file: File): Boolean {
        val root = transferRoot ?: return false
        return file.parentFile?.absolutePath == root.absolutePath &&
            file.name.isNotEmpty() &&
            file.name != "." &&
            file.name != ".." &&
            !file.name.contains(File.separatorChar)
    }

    private fun descriptorIdentity(
        descriptor: TransferFileHandle,
        expectedSize: Long,
    ): TransferFileIdentity? =
        descriptor.snapshot()?.takeIf {
            it.regular && it.links == 1L && it.size == expectedSize
        }?.identity

    private fun directoryIdentity(directory: File): TransferFileIdentity? =
        fileSystem.snapshot(directory)?.takeIf { it.directory }?.identity

    private fun pathMatchesIdentity(
        file: File,
        identity: TransferFileIdentity,
    ): Boolean {
        if (!isDirectChildPath(file)) return false
        val snapshot = fileSystem.snapshot(file) ?: return false
        return snapshot.regular && snapshot.links == 1L && snapshot.identity == identity
    }

    private fun deleteReservationFile(file: File, identity: TransferFileIdentity): Boolean {
        if (!verifyRoot() || !isDirectChildPath(file)) return false
        val snapshot = fileSystem.snapshot(file) ?: return !file.exists()
        if (!snapshot.regular || snapshot.identity != identity) return true
        return deleteFile(file) || !file.exists()
    }

    private fun reservationFileStillOwned(reservation: Reservation): Boolean =
        reservation.transferFile.let { file ->
            isDirectChildPath(file) && fileSystem.snapshot(file)?.let { snapshot ->
                snapshot.regular && snapshot.identity == reservation.identity
            } == true
        }

    private fun unregisterRootIfIdle() {
        if (!generationOpen && reservations.isEmpty()) unregisterRoot()
    }

    private fun unregisterRoot() {
        if (!rootRegistered) return
        rootRegistrationKey?.let(RootUseCoordinator::unregister)
        rootRegistered = false
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
        internal val transferFile: File,
        internal val descriptor: TransferFileHandle,
        internal val identity: TransferFileIdentity,
        internal val store: MediaCaptureTransferStore,
    ) {
        private val sink = TransferSink(this, store)

        val mediaSink: MediaCopySink
            get() = sink

        val committed: Boolean
            get() = sink.isCommitted

        internal fun closeDescriptor() = sink.closeDescriptor()

        internal companion object {
            operator fun invoke(
                exportHandle: String,
                metadata: MediaMetadata,
                transferFile: File,
                descriptor: TransferFileHandle,
                identity: TransferFileIdentity,
                store: MediaCaptureTransferStore,
            ): Reservation =
                Reservation(
                    exportHandle,
                    metadata,
                    transferFile,
                    descriptor,
                    identity,
                    store,
                )
        }
    }

    private class TransferSink(
        private val reservation: Reservation,
        private val store: MediaCaptureTransferStore,
    ) : MediaCopySink {
        private var written = 0L
        private var begun = false
        private var committed = false
        private var aborted = false
        private var descriptorOpen = true

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
            store.requireWritable(reservation, expectedSize = 0L)
            begun = true
        }

        override suspend fun write(buffer: ByteArray, byteCount: Int) = synchronized(this) {
            check(begun && !committed && !aborted)
            require(byteCount in 1..buffer.size)
            check(descriptorOpen)
            check(
                written <= reservation.metadata.byteLength - byteCount &&
                    written <= MAX_TRANSFER_FILE_BYTES - byteCount,
            )
            store.requireWritable(reservation, expectedSize = written)
            var offset = 0
            while (offset < byteCount) {
                val count = reservation.descriptor.write(buffer, offset, byteCount - offset)
                check(count > 0)
                offset += count
                written += count
                store.requireWritable(reservation, expectedSize = written)
            }
        }

        override suspend fun commit(byteLength: Long) = synchronized(this) {
            check(begun && !committed && !aborted)
            check(byteLength == reservation.metadata.byteLength && written == byteLength)
            check(descriptorOpen)
            store.requireWritable(reservation, expectedSize = byteLength)
            reservation.descriptor.sync()
            store.requireWritable(reservation, expectedSize = byteLength)
            closeDescriptor()
            committed = true
        }

        override suspend fun abort() = synchronized(this) {
            if (aborted) return@synchronized
            closeDescriptor()
            aborted = true
            store.delete(reservation)
        }

        @Synchronized
        fun closeDescriptor() {
            if (!descriptorOpen) return
            if (reservation.descriptor.valid) reservation.descriptor.close()
            check(!reservation.descriptor.valid)
            descriptorOpen = false
        }
    }

    private object RootUseCoordinator {
        private enum class Status { PENDING, PREPARING, READY, FAILED }

        private data class Entry(var users: Int, var status: Status)

        private val lock = ReentrantLock()
        private val changed = lock.newCondition()
        private val entries = mutableMapOf<String, Entry>()

        fun register(key: String): Boolean =
            lock.withLock {
                val existing = entries[key]
                if (existing == null) {
                    entries[key] = Entry(users = 1, status = Status.PENDING)
                } else {
                    existing.users += 1
                }
                true
            }

        fun prepare(key: String, sweep: () -> Boolean): Boolean {
            lock.withLock {
                while (entries[key]?.status == Status.PREPARING) changed.await()
                val entry = entries[key] ?: return false
                when (entry.status) {
                    Status.READY -> return true
                    Status.FAILED -> return false
                    Status.PENDING -> entry.status = Status.PREPARING
                    Status.PREPARING -> return false
                }
            }

            val result = runCatching(sweep).getOrDefault(false)
            lock.withLock {
                entries[key]?.status = if (result) Status.READY else Status.FAILED
                changed.signalAll()
            }
            return result
        }

        fun unregister(key: String) {
            lock.withLock {
                val entry = entries[key] ?: return
                if (entry.users <= 1) entries.remove(key) else entry.users -= 1
            }
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
