import Foundation

internal enum MediaCaptureDiagnostics {
#if DEBUG
    private static let sink = MediaCaptureDiagnosticFileSink()
#endif

    static func emit(
        _ stage: String,
        error: Error? = nil,
        details: String? = nil
    ) {
#if DEBUG
        var fields = ["[MediaCapture]", "stage=\(stage)"]
        if let details, !details.isEmpty {
            fields.append(details)
        }
        if let error {
            fields.append("errors=\(errorChain(error))")
        }
        sink.write(fields.joined(separator: " "))
#endif
    }

    private static func errorChain(_ error: Error) -> String {
        var parts: [String] = []
        var current: NSError? = error as NSError
        for _ in 0 ..< 4 {
            guard let error = current else { break }
            parts.append("\(error.domain):\(error.code)")
            current = error.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return parts.joined(separator: ">")
    }
}

#if DEBUG
private final class MediaCaptureDiagnosticFileSink: @unchecked Sendable {
    private let lock = NSLock()
    private let maximumByteLength = 64 * 1_024
    private var initialized = false
    private var byteLength = 0

    func write(_ message: String) {
        guard let data = (message + "\n").data(using: .utf8),
              data.count <= maximumByteLength
        else { return }

        lock.lock()
        defer { lock.unlock() }
        let cachesDirectory = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first
        guard byteLength + data.count <= maximumByteLength,
              let url = cachesDirectory?
                .appendingPathComponent("media-capture-diagnostics.log")
        else { return }

        do {
            if !initialized {
                try data.write(
                    to: url,
                    options: [.atomic, .completeFileProtectionUnlessOpen]
                )
                initialized = true
            } else {
                let handle = try FileHandle(forWritingTo: url)
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
            byteLength += data.count
        } catch {
            try? FileManager.default.removeItem(at: url)
            initialized = false
            byteLength = 0
        }
    }
}
#endif
