package com.example.media_capture

import java.io.File
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.StandardOpenOption

internal class TestTransferFileSystem(
    private val beforeWrite: (() -> Unit)? = null,
    private val beforeClose: (() -> Unit)? = null,
) : TransferFileSystem {
    @Synchronized
    override fun openExclusive(file: File): TransferFileHandle? =
        runCatching {
            val channel =
                FileChannel.open(
                    file.toPath(),
                    StandardOpenOption.CREATE_NEW,
                    StandardOpenOption.READ,
                    StandardOpenOption.WRITE,
                )
            val identity =
                snapshot(file)?.identity ?: run {
                    channel.close()
                    Files.deleteIfExists(file.toPath())
                    error("Unable to inspect the exclusive test file")
                }
            TestTransferFileHandle(channel, identity, beforeWrite, beforeClose)
        }.getOrNull()

    override fun snapshot(file: File): TransferFileSnapshot? =
        runCatching {
            val path = file.toPath()
            val attributes =
                Files.readAttributes(
                    path,
                    "unix:dev,ino,nlink,size",
                    LinkOption.NOFOLLOW_LINKS,
                )
            TransferFileSnapshot(
                identity =
                    TransferFileIdentity(
                        device = (attributes.getValue("dev") as Number).toLong(),
                        inode = (attributes.getValue("ino") as Number).toLong(),
                    ),
                size = (attributes.getValue("size") as Number).toLong(),
                links = (attributes.getValue("nlink") as Number).toLong(),
                regular = Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS),
                directory = Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS),
            )
        }.getOrNull()

    private class TestTransferFileHandle(
        private val channel: FileChannel,
        override val identity: TransferFileIdentity,
        private val beforeWrite: (() -> Unit)?,
        private val beforeClose: (() -> Unit)?,
    ) : TransferFileHandle {
        private var open = true
        private var links = 1L

        override val valid: Boolean
            @Synchronized get() = open

        @Synchronized
        override fun snapshot(): TransferFileSnapshot? =
            if (!open) {
                null
            } else {
                TransferFileSnapshot(
                    identity = identity,
                    size = channel.size(),
                    links = links,
                    regular = true,
                    directory = false,
                )
            }

        @Synchronized
        override fun write(buffer: ByteArray, offset: Int, byteCount: Int): Int {
            check(open)
            beforeWrite?.invoke()
            return channel.write(ByteBuffer.wrap(buffer, offset, byteCount))
        }

        @Synchronized
        override fun sync() {
            check(open)
            channel.force(true)
        }

        @Synchronized
        override fun close() {
            if (!open) return
            beforeClose?.invoke()
            open = false
            channel.close()
        }

    }
}

internal fun testTransferStore(
    cacheDirectory: File,
    fileSystem: TransferFileSystem = TestTransferFileSystem(),
    deleteFile: (File) -> Boolean = File::delete,
): MediaCaptureTransferStore =
    MediaCaptureTransferStore(
        cacheDirectory = cacheDirectory,
        fileSystem = fileSystem,
        deleteFile = deleteFile,
    )
