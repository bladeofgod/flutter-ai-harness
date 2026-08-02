import Darwin
import Foundation
import MediaCapture
import Security

package final class MediaCaptureTransferStore: @unchecked Sendable {
    package static let maximumFileBytes = 52_428_800

    private static let containerName = "app_media_capture_bridge"
    private static let rootName = "exports"
    private static let handleByteCount = 16
    private static let handleGenerationAttempts = 32
    private static let protectionClassCompleteUntilFirstAuthentication: Int32 = 3
    private static let rootCoordinator = RootUseCoordinator()

    private let lock = NSLock()
    private let preparationCondition = NSCondition()
    private let deletePermission: (@Sendable (URL) -> Bool)?
    private let writePermission: @Sendable () -> Bool
    private let cacheRoot: URL
    private let transferRoot: URL
    private var rootRegistrationKey: String?
    private var cacheDescriptor: Int32 = -1
    private var containerDescriptor: Int32 = -1
    private var rootDescriptor: Int32 = -1
    private var cacheIdentity: FileIdentity?
    private var containerIdentity: FileIdentity?
    private var rootIdentity: FileIdentity?
    private var generationOpen = false
    private var preparationStatus = PreparationStatus.unprepared
    private var preparationTask: Task<Void, Never>?

    package init(
        cacheDirectory: URL,
        deletePermission: (@Sendable (URL) -> Bool)? = nil,
        writePermission: @escaping @Sendable () -> Bool = { true }
    ) {
        self.deletePermission = deletePermission
        self.writePermission = writePermission
        cacheRoot = cacheDirectory.standardizedFileURL
        transferRoot = cacheRoot
            .appendingPathComponent(Self.containerName, isDirectory: true)
            .appendingPathComponent(Self.rootName, isDirectory: true)
            .standardizedFileURL
        let key = cacheRoot.path
        rootRegistrationKey = key
        Self.rootCoordinator.register(key: key)
        preparationTask = Task.detached(priority: .utility) { [weak self] in
            _ = self?.prepare()
        }
    }

    deinit {
        preparationTask?.cancel()
        if let rootRegistrationKey {
            Self.rootCoordinator.unregister(key: rootRegistrationKey)
        }
        closeDescriptor(&rootDescriptor)
        closeDescriptor(&containerDescriptor)
        closeDescriptor(&cacheDescriptor)
    }

    package var isAvailable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return generationOpen && verifyRootPathLocked()
    }

    package func prepare() -> Bool {
        preparationCondition.lock()
        while preparationStatus == .preparing {
            preparationCondition.wait()
        }
        switch preparationStatus {
        case .ready:
            preparationCondition.unlock()
            return true
        case .failed, .closed:
            preparationCondition.unlock()
            return false
        case .unprepared:
            preparationStatus = .preparing
            preparationCondition.unlock()
        case .preparing:
            preparationCondition.unlock()
            return false
        }

        let descriptorsReady = initializeDescriptors()
        let prepared: Bool
        if descriptorsReady, let rootRegistrationKey {
            prepared = Self.rootCoordinator.prepare(key: rootRegistrationKey) { [self] in
                sweepDirectoryLocked(rootDescriptor)
            }
        } else {
            prepared = false
        }

        preparationCondition.lock()
        let closed = preparationStatus == .closed
        lock.lock()
        generationOpen = prepared && !closed
        lock.unlock()
        preparationStatus = closed ? .closed : (prepared ? .ready : .failed)
        preparationCondition.broadcast()
        preparationCondition.unlock()
        return prepared && !closed
    }

    package func createReservation(metadata: MediaMetadata) throws -> Reservation {
        guard prepare() else { throw StoreFailure.unavailable }
        lock.lock()
        defer { lock.unlock() }
        guard generationOpen, verifyRootPathLocked(), metadata.byteLength > 0
        else {
            throw StoreFailure.unavailable
        }
        for _ in 0 ..< Self.handleGenerationAttempts {
            let handle = try generateHandle()
            let fileExtension = metadata.mediaType == .photo ? "jpg" : "mp4"
            let stagingName = "\(handle).partial"
            let finalName = "\(handle).\(fileExtension)"
            guard Self.isSafeLeafName(stagingName), Self.isSafeLeafName(finalName),
                  !entryExistsLocked(finalName)
            else {
                continue
            }
            let descriptor = Darwin.openat(
                rootDescriptor,
                stagingName,
                O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                mode_t(S_IRUSR | S_IWUSR)
            )
            guard descriptor >= 0 else { continue }
            guard configureFileDescriptor(descriptor),
                  let identity = Self.regularFileIdentity(descriptor),
                  identity.size == 0, identity.linkCount == 1
            else {
                Darwin.close(descriptor)
                _ = Darwin.unlinkat(rootDescriptor, stagingName, 0)
                continue
            }
            return Reservation(
                exportHandle: handle,
                metadata: metadata,
                stagingName: stagingName,
                finalName: finalName,
                stagingDescriptor: descriptor,
                stagingIdentity: identity,
                writePermission: writePermission,
                store: self
            )
        }
        throw StoreFailure.unavailable
    }

    package func closeGeneration() {
        preparationCondition.lock()
        preparationStatus = .closed
        preparationCondition.broadcast()
        preparationCondition.unlock()
        lock.lock()
        generationOpen = false
        lock.unlock()
    }

    package func delete(_ reservation: Reservation) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard reservation.store === self, verifyHeldDescriptorsLocked() else { return false }
        let stagingDeleted = deleteOwnedNameLocked(reservation.stagingName)
        let finalDeleted = deleteOwnedNameLocked(reservation.finalName)
        return stagingDeleted && finalDeleted
    }

    package func fileURI(_ reservation: Reservation) throws -> String {
        guard reservation.store === self,
              let committedIdentity = reservation.committedIdentity
        else {
            throw StoreFailure.unavailable
        }
        lock.lock()
        defer { lock.unlock() }
        guard generationOpen, verifyRootPathLocked(),
              let currentIdentity = entryIdentityLocked(reservation.finalName),
              currentIdentity.isRegularFile,
              currentIdentity.device == committedIdentity.device,
              currentIdentity.inode == committedIdentity.inode,
              currentIdentity.size == committedIdentity.size,
              currentIdentity.linkCount == 1
        else {
            throw StoreFailure.unavailable
        }
        let value = transferRoot
            .appendingPathComponent(reservation.finalName, isDirectory: false)
            .absoluteURL.standardizedFileURL.absoluteString
        try MediaCaptureWireCodec.requireCanonicalFileURI(value)
        return value
    }

    fileprivate func commit(_ reservation: Reservation, expectedIdentity: FileIdentity) throws -> FileIdentity {
        lock.lock()
        defer { lock.unlock() }
        guard generationOpen, reservation.store === self, verifyHeldDescriptorsLocked(),
              let stagingIdentity = entryIdentityLocked(reservation.stagingName),
              stagingIdentity.matches(expectedIdentity), stagingIdentity.linkCount == 1,
              !entryExistsLocked(reservation.finalName)
        else {
            throw StoreFailure.unavailable
        }
        guard Darwin.renameatx_np(
            rootDescriptor,
            reservation.stagingName,
            rootDescriptor,
            reservation.finalName,
            UInt32(RENAME_EXCL)
        ) == 0,
            let finalIdentity = entryIdentityLocked(reservation.finalName),
            finalIdentity.matches(expectedIdentity), finalIdentity.linkCount == 1
        else {
            throw StoreFailure.unavailable
        }
        return finalIdentity
    }

    private func initializeDescriptors() -> Bool {
        guard cacheRoot.path == cacheRoot.resolvingSymlinksInPath().path else { return false }
        cacheDescriptor = Darwin.open(
            cacheRoot.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard cacheDescriptor >= 0,
              let cacheIdentity = Self.directoryIdentity(cacheDescriptor)
        else {
            closeDescriptor(&cacheDescriptor)
            return false
        }
        self.cacheIdentity = cacheIdentity

        containerDescriptor = Self.openOrCreatePrivateDirectory(
            parentDescriptor: cacheDescriptor,
            name: Self.containerName
        )
        guard containerDescriptor >= 0,
              let containerIdentity = Self.directoryIdentity(containerDescriptor)
        else {
            closeDescriptor(&containerDescriptor)
            closeDescriptor(&cacheDescriptor)
            return false
        }
        self.containerIdentity = containerIdentity

        rootDescriptor = Self.openOrCreatePrivateDirectory(
            parentDescriptor: containerDescriptor,
            name: Self.rootName
        )
        guard rootDescriptor >= 0,
              let rootIdentity = Self.directoryIdentity(rootDescriptor)
        else {
            closeDescriptor(&rootDescriptor)
            closeDescriptor(&containerDescriptor)
            closeDescriptor(&cacheDescriptor)
            return false
        }
        self.rootIdentity = rootIdentity
        return verifyRootPathLocked()
    }

    private static func openOrCreatePrivateDirectory(
        parentDescriptor: Int32,
        name: String
    ) -> Int32 {
        guard isSafeLeafName(name) else { return -1 }
        if Darwin.mkdirat(parentDescriptor, name, mode_t(S_IRWXU)) != 0, errno != EEXIST {
            return -1
        }
        let descriptor = Darwin.openat(
            parentDescriptor,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard descriptor >= 0,
              Darwin.fchmod(descriptor, mode_t(S_IRWXU)) == 0,
              setProtectionClass(descriptor),
              directoryIdentity(descriptor) != nil
        else {
            if descriptor >= 0 { Darwin.close(descriptor) }
            return -1
        }
        return descriptor
    }

    private func verifyHeldDescriptorsLocked() -> Bool {
        guard let cacheIdentity, let containerIdentity, let rootIdentity,
              let currentCache = Self.directoryIdentity(cacheDescriptor),
              let currentContainer = Self.directoryIdentity(containerDescriptor),
              let currentRoot = Self.directoryIdentity(rootDescriptor)
        else {
            return false
        }
        return currentCache.matches(cacheIdentity) &&
            currentContainer.matches(containerIdentity) &&
            currentRoot.matches(rootIdentity)
    }

    private func verifyRootPathLocked() -> Bool {
        guard verifyHeldDescriptorsLocked(),
              let cacheIdentity, let containerIdentity, let rootIdentity
        else {
            return false
        }
        let currentCache = Darwin.open(
            cacheRoot.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard currentCache >= 0 else { return false }
        defer { Darwin.close(currentCache) }
        guard Self.directoryIdentity(currentCache)?.matches(cacheIdentity) == true else { return false }

        let currentContainer = Darwin.openat(
            currentCache,
            Self.containerName,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard currentContainer >= 0 else { return false }
        defer { Darwin.close(currentContainer) }
        guard Self.directoryIdentity(currentContainer)?.matches(containerIdentity) == true else { return false }

        let currentRoot = Darwin.openat(
            currentContainer,
            Self.rootName,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard currentRoot >= 0 else { return false }
        defer { Darwin.close(currentRoot) }
        return Self.directoryIdentity(currentRoot)?.matches(rootIdentity) == true
    }

    private func deleteOwnedNameLocked(_ name: String) -> Bool {
        guard Self.isSafeLeafName(name) else { return false }
        guard entryExistsLocked(name) else { return errno == ENOENT }
        let url = transferRoot.appendingPathComponent(name, isDirectory: false)
        if let deletePermission, !deletePermission(url) { return false }
        if Darwin.unlinkat(rootDescriptor, name, 0) == 0 { return true }
        return errno == ENOENT
    }

    private func entryExistsLocked(_ name: String) -> Bool {
        var status = stat()
        return Darwin.fstatat(rootDescriptor, name, &status, AT_SYMLINK_NOFOLLOW) == 0
    }

    private func entryIdentityLocked(_ name: String) -> FileIdentity? {
        var status = stat()
        guard Darwin.fstatat(rootDescriptor, name, &status, AT_SYMLINK_NOFOLLOW) == 0 else {
            return nil
        }
        return FileIdentity(status)
    }

    private func sweepDirectoryLocked(_ descriptor: Int32) -> Bool {
        let duplicate = Darwin.dup(descriptor)
        guard duplicate >= 0, let directory = Darwin.fdopendir(duplicate) else {
            if duplicate >= 0 { Darwin.close(duplicate) }
            return false
        }
        defer { Darwin.closedir(directory) }
        while true {
            errno = 0
            guard let entry = Darwin.readdir(directory) else { return errno == 0 }
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                    String(cString: $0)
                }
            }
            if name == "." || name == ".." { continue }
            guard Self.isSafeLeafName(name), removeEntryTreeLocked(parentDescriptor: descriptor, name: name) else {
                return false
            }
        }
    }

    private func removeEntryTreeLocked(parentDescriptor: Int32, name: String) -> Bool {
        var status = stat()
        guard Darwin.fstatat(parentDescriptor, name, &status, AT_SYMLINK_NOFOLLOW) == 0 else {
            return errno == ENOENT
        }
        let identity = FileIdentity(status)
        if identity.isDirectory {
            let child = Darwin.openat(
                parentDescriptor,
                name,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
            guard child >= 0 else { return false }
            guard Self.directoryIdentity(child)?.matches(identity) == true,
                  sweepDirectoryLocked(child)
            else {
                Darwin.close(child)
                return false
            }
            Darwin.close(child)
            if Darwin.unlinkat(parentDescriptor, name, AT_REMOVEDIR) == 0 { return true }
            return errno == ENOENT
        }
        if Darwin.unlinkat(parentDescriptor, name, 0) == 0 { return true }
        return errno == ENOENT
    }

    private func generateHandle() throws -> String {
        var bytes = [UInt8](repeating: 0, count: Self.handleByteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw StoreFailure.unavailable
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func configureFileDescriptor(_ descriptor: Int32) -> Bool {
        Darwin.fchmod(descriptor, mode_t(S_IRUSR | S_IWUSR)) == 0 &&
            Self.setProtectionClass(descriptor)
    }

    private static func setProtectionClass(_ descriptor: Int32) -> Bool {
        Darwin.fcntl(
            descriptor,
            F_SETPROTECTIONCLASS,
            protectionClassCompleteUntilFirstAuthentication
        ) == 0
    }

    private static func isSafeLeafName(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." &&
            !value.contains("/") && !value.contains("\0")
    }

    private func closeDescriptor(_ descriptor: inout Int32) {
        guard descriptor >= 0 else { return }
        Darwin.close(descriptor)
        descriptor = -1
    }

    private func contentType(for mediaType: MediaType) -> String {
        mediaType == .photo ? "image/jpeg" : "video/mp4"
    }

    fileprivate enum StoreFailure: Error {
        case unavailable
    }

    private enum PreparationStatus {
        case unprepared
        case preparing
        case ready
        case failed
        case closed
    }

    private final class RootUseCoordinator: @unchecked Sendable {
        private struct Entry {
            var userCount: Int
            var status: Status
        }

        private enum Status {
            case pending
            case preparing
            case ready
            case failed
        }

        private let condition = NSCondition()
        private var entries: [String: Entry] = [:]

        func register(key: String) {
            condition.lock()
            if var entry = entries[key] {
                entry.userCount += 1
                entries[key] = entry
            } else {
                entries[key] = Entry(userCount: 1, status: .pending)
            }
            condition.unlock()
        }

        func prepare(key: String, sweep: () -> Bool) -> Bool {
            condition.lock()
            while entries[key]?.status == .preparing {
                condition.wait()
            }
            guard var entry = entries[key] else {
                condition.unlock()
                return false
            }
            switch entry.status {
            case .ready:
                condition.unlock()
                return true
            case .failed:
                condition.unlock()
                return false
            case .pending:
                entry.status = .preparing
                entries[key] = entry
                condition.unlock()
            case .preparing:
                condition.unlock()
                return false
            }

            let result = sweep()
            condition.lock()
            if var current = entries[key] {
                current.status = result ? .ready : .failed
                entries[key] = current
            }
            condition.broadcast()
            condition.unlock()
            return result
        }

        func unregister(key: String) {
            condition.lock()
            defer { condition.unlock() }
            guard var entry = entries[key] else { return }
            if entry.userCount <= 1 {
                entries.removeValue(forKey: key)
            } else {
                entry.userCount -= 1
                entries[key] = entry
            }
        }
    }

    fileprivate struct FileIdentity: Sendable {
        let device: UInt64
        let inode: UInt64
        let size: Int64
        let linkCount: UInt64
        let mode: mode_t

        init(_ status: stat) {
            device = UInt64(status.st_dev)
            inode = UInt64(status.st_ino)
            size = Int64(status.st_size)
            linkCount = UInt64(status.st_nlink)
            mode = status.st_mode
        }

        var isDirectory: Bool { mode & mode_t(S_IFMT) == mode_t(S_IFDIR) }
        var isRegularFile: Bool { mode & mode_t(S_IFMT) == mode_t(S_IFREG) }

        func matches(_ other: FileIdentity) -> Bool {
            device == other.device && inode == other.inode &&
                mode & mode_t(S_IFMT) == other.mode & mode_t(S_IFMT)
        }
    }

    private static func directoryIdentity(_ descriptor: Int32) -> FileIdentity? {
        guard descriptor >= 0 else { return nil }
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0 else { return nil }
        let identity = FileIdentity(status)
        return identity.isDirectory ? identity : nil
    }

    private static func regularFileIdentity(_ descriptor: Int32) -> FileIdentity? {
        guard descriptor >= 0 else { return nil }
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0 else { return nil }
        let identity = FileIdentity(status)
        return identity.isRegularFile ? identity : nil
    }

    package final class Reservation: @unchecked Sendable {
        package let exportHandle: String
        package let metadata: MediaMetadata
        fileprivate let stagingName: String
        fileprivate let finalName: String
        fileprivate unowned let store: MediaCaptureTransferStore
        private let sink: TransferSink

        fileprivate init(
            exportHandle: String,
            metadata: MediaMetadata,
            stagingName: String,
            finalName: String,
            stagingDescriptor: Int32,
            stagingIdentity: FileIdentity,
            writePermission: @escaping @Sendable () -> Bool,
            store: MediaCaptureTransferStore
        ) {
            self.exportHandle = exportHandle
            self.metadata = metadata
            self.stagingName = stagingName
            self.finalName = finalName
            self.store = store
            sink = TransferSink(
                descriptor: stagingDescriptor,
                stagingIdentity: stagingIdentity,
                writePermission: writePermission
            )
            sink.install(reservation: self, store: store)
        }

        package var mediaSink: any MediaCopySink { sink }
        package var committed: Bool { sink.committedIdentity != nil }
        fileprivate var committedIdentity: FileIdentity? { sink.committedIdentity }
    }

    private final class TransferSink: MediaCopySink, @unchecked Sendable {
        private let lock = NSLock()
        private weak var reservation: Reservation?
        private weak var store: MediaCaptureTransferStore?
        private var descriptor: Int32
        private let stagingIdentity: FileIdentity
        private let writePermission: @Sendable () -> Bool
        private var finalIdentity: FileIdentity?
        private var written = 0
        private var begun = false
        private var aborted = false

        init(
            descriptor: Int32,
            stagingIdentity: FileIdentity,
            writePermission: @escaping @Sendable () -> Bool
        ) {
            self.descriptor = descriptor
            self.stagingIdentity = stagingIdentity
            self.writePermission = writePermission
        }

        deinit {
            if descriptor >= 0 { Darwin.close(descriptor) }
        }

        var committedIdentity: FileIdentity? {
            lock.lock()
            defer { lock.unlock() }
            return finalIdentity
        }

        func install(reservation: Reservation, store: MediaCaptureTransferStore) {
            self.reservation = reservation
            self.store = store
        }

        func begin(mediaType: MediaType, contentType: String, byteLength: Int) async throws {
            try Task.checkCancellation()
            try withLock {
                guard let reservation, let store, !begun, finalIdentity == nil, !aborted,
                      mediaType == reservation.metadata.mediaType,
                      contentType == store.contentType(for: reservation.metadata.mediaType),
                      byteLength == reservation.metadata.byteLength,
                      (1 ... MediaCaptureTransferStore.maximumFileBytes).contains(byteLength),
                      let identity = MediaCaptureTransferStore.regularFileIdentity(descriptor),
                      identity.matches(stagingIdentity), identity.size == 0, identity.linkCount == 1
                else {
                    throw StoreFailure.unavailable
                }
                begun = true
            }
        }

        func write(_ chunk: MediaCopyChunk) async throws {
            try Task.checkCancellation()
            var data = try chunk.copyBytes()
            defer {
                data.resetBytes(in: 0 ..< data.count)
                data.removeAll(keepingCapacity: false)
            }
            try withLock {
                guard begun, finalIdentity == nil, !aborted,
                      !data.isEmpty, data.count == chunk.byteCount,
                      written <= (reservation?.metadata.byteLength ?? 0) - data.count,
                      written <= MediaCaptureTransferStore.maximumFileBytes - data.count,
                      let before = MediaCaptureTransferStore.regularFileIdentity(descriptor),
                      before.matches(stagingIdentity), before.size == written, before.linkCount == 1
                else {
                    throw StoreFailure.unavailable
                }
                try writeAll(data, descriptor: descriptor)
                written += data.count
                guard let after = MediaCaptureTransferStore.regularFileIdentity(descriptor),
                      after.matches(stagingIdentity), after.size == written, after.linkCount == 1
                else {
                    throw StoreFailure.unavailable
                }
            }
        }

        func commit(byteLength: Int) async throws {
            try Task.checkCancellation()
            try withLock {
                guard let reservation, let store, begun, finalIdentity == nil, !aborted,
                      byteLength == reservation.metadata.byteLength,
                      written == byteLength,
                      let identity = MediaCaptureTransferStore.regularFileIdentity(descriptor),
                      identity.matches(stagingIdentity), identity.size == byteLength,
                      identity.linkCount == 1,
                      Darwin.fsync(descriptor) == 0
                else {
                    throw StoreFailure.unavailable
                }
                try Task.checkCancellation()
                let committed = try store.commit(reservation, expectedIdentity: identity)
                guard Darwin.close(descriptor) == 0 else { throw StoreFailure.unavailable }
                descriptor = -1
                finalIdentity = committed
            }
        }

        func abort() async throws {
            let cleanup: (Int32, Reservation?, MediaCaptureTransferStore?)? = withLock {
                guard !aborted else { return nil }
                aborted = true
                let cleanup = (descriptor, reservation, store)
                descriptor = -1
                return cleanup
            }
            guard let (descriptor, reservation, store) = cleanup else { return }
            let deleted = reservation.map { store?.delete($0) == true } ?? true
            if descriptor >= 0 { Darwin.close(descriptor) }
            if !deleted { throw StoreFailure.unavailable }
        }

        private func withLock<Value>(_ body: () throws -> Value) rethrows -> Value {
            lock.lock()
            defer { lock.unlock() }
            return try body()
        }

        private func writeAll(_ data: Data, descriptor: Int32) throws {
            guard writePermission() else { throw StoreFailure.unavailable }
            try data.withUnsafeBytes { rawBuffer in
                guard let base = rawBuffer.baseAddress else { throw StoreFailure.unavailable }
                var offset = 0
                while offset < rawBuffer.count {
                    let result = Darwin.write(
                        descriptor,
                        base.advanced(by: offset),
                        rawBuffer.count - offset
                    )
                    if result > 0 {
                        offset += result
                    } else if result < 0, errno == EINTR {
                        continue
                    } else {
                        throw StoreFailure.unavailable
                    }
                }
            }
        }
    }
}
