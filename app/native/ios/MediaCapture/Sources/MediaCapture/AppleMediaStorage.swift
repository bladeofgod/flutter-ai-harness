@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import MobileCoreServices

internal actor AppleMediaFileStore: MediaFileStoring {
    private let fileManager: FileManager
    private let rootDirectory: URL
    private var locations: [StoredMediaReference: URL] = [:]

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        rootDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("MediaCapture", isDirectory: true)
    }

    func removeTemporaryResidue() async {
        try? fileManager.removeItem(at: rootDirectory)
        try? fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        locations.removeAll()
    }

    func recordingDestination() async throws -> URL {
        try ensureRootDirectory()
        return rootDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
    }

    func storePhoto(_ photo: CapturedPhoto) async throws -> StoredMedia {
        try ensureRootDirectory()
        let processed = try AppleImageProcessor.sanitizedPhoto(from: photo.encodedData)
        let reference = StoredMediaReference()
        let url = rootDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        do {
            try processed.data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        } catch {
            throw mapStorageError(error)
        }
        locations[reference] = url
        return StoredMedia(
            reference: reference,
            mediaType: .photo,
            pixelWidth: processed.width,
            pixelHeight: processed.height,
            durationMilliseconds: nil,
            orientationDegrees: 0,
            byteLength: processed.data.count,
            contentType: "image/jpeg"
        )
    }

    func finalizeRecording(at destination: URL) async throws -> StoredMedia {
        try ensureRootDirectory()
        let sanitizedURL = rootDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        do {
            let processed = try await AppleVideoProcessor.sanitizeVideo(
                at: destination,
                outputURL: sanitizedURL
            )
            try Task.checkCancellation()
            try? fileManager.removeItem(at: destination)
            let reference = StoredMediaReference()
            locations[reference] = sanitizedURL
            return StoredMedia(
                reference: reference,
                mediaType: .video,
                pixelWidth: processed.width,
                pixelHeight: processed.height,
                durationMilliseconds: processed.durationMilliseconds,
                orientationDegrees: processed.orientationDegrees,
                byteLength: processed.byteLength,
                contentType: "video/quicktime"
            )
        } catch is CancellationError {
            try? fileManager.removeItem(at: destination)
            try? fileManager.removeItem(at: sanitizedURL)
            throw CancellationError()
        } catch let failure as MediaCaptureFailure {
            try? fileManager.removeItem(at: destination)
            try? fileManager.removeItem(at: sanitizedURL)
            throw failure
        } catch {
            try? fileManager.removeItem(at: destination)
            try? fileManager.removeItem(at: sanitizedURL)
            throw MediaCaptureFailure(.encodingFailed)
        }
    }

    func discardRecording(at destination: URL) async {
        guard destination.deletingLastPathComponent() == rootDirectory else { return }
        try? fileManager.removeItem(at: destination)
    }

    func openSource(_ reference: StoredMediaReference) async throws -> MediaSourceAccess {
        guard let url = locations[reference], fileManager.fileExists(atPath: url.path) else {
            throw MediaCaptureFailure(.mediaInvalid)
        }
        return try MediaSourceAccess(fileURL: url)
    }

    func previewRenderSource(_ media: StoredMedia) async throws -> MediaCaptureRenderSource {
        guard let url = locations[media.reference], fileManager.fileExists(atPath: url.path) else {
            throw MediaCaptureFailure(.mediaInvalid)
        }
        switch media.mediaType {
        case .photo:
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else {
                throw MediaCaptureFailure(.encodingFailed)
            }
            return .photo(image)
        case .video:
            return .video(url)
        }
    }

    func delete(_ reference: StoredMediaReference) async {
        guard let url = locations.removeValue(forKey: reference) else { return }
        try? fileManager.removeItem(at: url)
    }

    private func ensureRootDirectory() throws {
        do {
            try fileManager.createDirectory(
                at: rootDirectory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
        } catch {
            throw mapStorageError(error)
        }
    }

    private func mapStorageError(_ error: Error) -> MediaCaptureFailure {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == NSFileWriteOutOfSpaceError {
            return MediaCaptureFailure(.storageFull)
        }
        return MediaCaptureFailure(.encodingFailed)
    }
}

internal protocol SensitiveJPEGEncoding {
    func encode(_ image: CGImage, quality: Double) throws -> SensitiveDataBuffer
}

internal struct ImageIOSensitiveJPEGEncoder: SensitiveJPEGEncoding {
    func encode(_ image: CGImage, quality: Double) throws -> SensitiveDataBuffer {
        let output = SensitiveDataBuffer()
        do {
            try output.withMutableData { data in
                guard let destination = CGImageDestinationCreateWithData(
                    data as CFMutableData,
                    kUTTypeJPEG,
                    1,
                    nil
                ) else {
                    throw MediaCaptureFailure(.encodingFailed)
                }
                CGImageDestinationAddImage(destination, image, [
                    kCGImageDestinationLossyCompressionQuality: quality,
                ] as CFDictionary)
                guard CGImageDestinationFinalize(destination) else {
                    throw MediaCaptureFailure(.encodingFailed)
                }
            }
            return output
        } catch {
            output.wipe()
            throw error
        }
    }
}

internal enum AppleImageProcessor {
    struct ProcessedImage {
        let data: Data
        let width: Int
        let height: Int
    }

    static func sanitizedPhoto(from data: Data) throws -> ProcessedImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false,
        ] as CFDictionary),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let sourceWidth = properties[kCGImagePropertyPixelWidth] as? Int,
        let sourceHeight = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            throw MediaCaptureFailure(.encodingFailed)
        }
        let maximumDimension = max(sourceWidth, sourceHeight)
        guard maximumDimension > 0,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
                  kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary)
        else {
            throw MediaCaptureFailure(.encodingFailed)
        }
        let encoded = try ImageIOSensitiveJPEGEncoder().encode(image, quality: 0.92)
        defer { encoded.wipe() }
        return ProcessedImage(data: encoded.copy(), width: image.width, height: image.height)
    }

    static func thumbnail(from url: URL, maximumPixelEdge: Int) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false,
        ] as CFDictionary),
        let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelEdge,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary)
        else {
            throw MediaCaptureFailure(.thumbnailGenerationFailed)
        }
        return image
    }

    static func boundedJPEG(
        from original: CGImage,
        maximumPixelEdge: Int,
        cancellation: CancellationSignal,
        encoder: any SensitiveJPEGEncoding = ImageIOSensitiveJPEGEncoder()
    ) throws -> (buffer: SensitiveDataBuffer, width: Int, height: Int) {
        try Task.checkCancellation()
        try cancellation.checkCancellation()
        var image = original
        if max(image.width, image.height) > maximumPixelEdge {
            image = try scaled(image, maximumPixelEdge: maximumPixelEdge)
        }
        var quality = 0.86
        while quality >= 0.2 {
            try Task.checkCancellation()
            try cancellation.checkCancellation()
            let candidate = try ownedCandidate(
                image,
                quality: quality,
                cancellation: cancellation,
                encoder: encoder
            )
            if candidate.count <= 524_288 {
                return (candidate, image.width, image.height)
            }
            candidate.wipe()
            quality -= 0.12
        }
        while max(image.width, image.height) > 64 {
            try Task.checkCancellation()
            try cancellation.checkCancellation()
            image = try scaled(image, maximumPixelEdge: max(64, Int(Double(max(image.width, image.height)) * 0.75)))
            let candidate = try ownedCandidate(
                image,
                quality: 0.72,
                cancellation: cancellation,
                encoder: encoder
            )
            if candidate.count <= 524_288 {
                return (candidate, image.width, image.height)
            }
            candidate.wipe()
        }
        throw MediaCaptureFailure(.thumbnailGenerationFailed)
    }

    private static func ownedCandidate(
        _ image: CGImage,
        quality: Double,
        cancellation: CancellationSignal,
        encoder: any SensitiveJPEGEncoding
    ) throws -> SensitiveDataBuffer {
        let candidate = try encoder.encode(image, quality: quality)
        do {
            try Task.checkCancellation()
            try cancellation.checkCancellation()
            return candidate
        } catch {
            candidate.wipe()
            throw error
        }
    }

    private static func scaled(_ image: CGImage, maximumPixelEdge: Int) throws -> CGImage {
        let scale = min(1, Double(maximumPixelEdge) / Double(max(image.width, image.height)))
        let width = max(1, Int((Double(image.width) * scale).rounded(.down)))
        let height = max(1, Int((Double(image.height) * scale).rounded(.down)))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: width * 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            throw MediaCaptureFailure(.thumbnailGenerationFailed)
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let result = context.makeImage() else {
            throw MediaCaptureFailure(.thumbnailGenerationFailed)
        }
        return result
    }
}

private enum AppleVideoProcessor {
    struct ProcessedVideo {
        let width: Int
        let height: Int
        let durationMilliseconds: Int
        let orientationDegrees: Int
        let byteLength: Int
    }

    static func sanitizeVideo(at inputURL: URL, outputURL: URL) async throws -> ProcessedVideo {
        let asset = AVURLAsset(url: inputURL)
        guard let track = asset.tracks(withMediaType: .video).first else {
            throw MediaCaptureFailure(.encodingFailed)
        }
        let transformedSize = track.naturalSize.applying(track.preferredTransform)
        let width = Int(abs(transformedSize.width).rounded())
        let height = Int(abs(transformedSize.height).rounded())
        let durationMilliseconds = Int((CMTimeGetSeconds(asset.duration) * 1_000).rounded(.down))
        let orientationDegrees = orientation(for: track.preferredTransform)
        guard width > 0, height > 0,
              durationMilliseconds > 0, durationMilliseconds <= 60_000,
              let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough)
        else {
            throw MediaCaptureFailure(.encodingFailed)
        }
        export.outputURL = outputURL
        export.outputFileType = .mov
        export.metadata = []
        let exportBox = UncheckedSendableBox(export)
        let operation = CancellableExportOperation {
            exportBox.value.cancelExport()
        }
        export.exportAsynchronously {
            let result: Result<Void, Error>
            switch exportBox.value.status {
            case .completed:
                result = .success(())
            case .cancelled:
                result = .failure(CancellationError())
            default:
                result = .failure(MediaCaptureFailure(.encodingFailed))
            }
            operation.resolve(result)
        }
        try await operation.value()
        try Task.checkCancellation()
        let values = try outputURL.resourceValues(forKeys: [.fileSizeKey])
        guard let byteLength = values.fileSize, byteLength > 0 else {
            throw MediaCaptureFailure(.encodingFailed)
        }
        return ProcessedVideo(
            width: width,
            height: height,
            durationMilliseconds: durationMilliseconds,
            orientationDegrees: orientationDegrees,
            byteLength: byteLength
        )
    }

    private static func orientation(for transform: CGAffineTransform) -> Int {
        let epsilon: CGFloat = 0.001
        if abs(transform.a) < epsilon, abs(transform.b - 1) < epsilon,
           abs(transform.c + 1) < epsilon, abs(transform.d) < epsilon {
            return 90
        }
        if abs(transform.a + 1) < epsilon, abs(transform.b) < epsilon,
           abs(transform.c) < epsilon, abs(transform.d + 1) < epsilon {
            return 180
        }
        if abs(transform.a) < epsilon, abs(transform.b + 1) < epsilon,
           abs(transform.c - 1) < epsilon, abs(transform.d) < epsilon {
            return 270
        }
        return 0
    }
}

internal final class CancellableExportOperation: @unchecked Sendable {
    private let completion = OperationCompletion<Void>()
    private let cancelBody: @Sendable () -> Void

    init(cancelBody: @escaping @Sendable () -> Void) {
        self.cancelBody = cancelBody
    }

    func value() async throws {
        try await CancellableOperationAwaiter.value(completion, onCancel: cancelBody)
    }

    @discardableResult
    func resolve(_ result: Result<Void, Error>) -> Bool {
        completion.resolve(result)
    }
}

// AVAssetExportSession owns and serializes this completion callback.
private final class UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

internal struct AppleThumbnailGenerator: ThumbnailGenerating {
    func generate(
        from source: MediaSourceAccess,
        media: StoredMedia,
        maximumPixelEdge: Int,
        cancellation: CancellationSignal
    ) async throws -> GeneratedThumbnail {
        try Task.checkCancellation()
        try cancellation.checkCancellation()
        guard let fileURL = source.fileURL else {
            throw MediaCaptureFailure(.thumbnailGenerationFailed)
        }
        let image: CGImage
        let posterFrame: Int?
        switch media.mediaType {
        case .photo:
            image = try AppleImageProcessor.thumbnail(
                from: fileURL,
                maximumPixelEdge: maximumPixelEdge
            )
            posterFrame = nil
        case .video:
            let selection = try videoFrame(
                from: fileURL,
                durationMilliseconds: media.durationMilliseconds ?? 0,
                maximumPixelEdge: maximumPixelEdge
            )
            image = selection.image
            posterFrame = selection.actualMilliseconds
        }
        try Task.checkCancellation()
        try cancellation.checkCancellation()
        let encoded = try AppleImageProcessor.boundedJPEG(
            from: image,
            maximumPixelEdge: maximumPixelEdge,
            cancellation: cancellation
        )
        do {
            try Task.checkCancellation()
            try cancellation.checkCancellation()
            return GeneratedThumbnail(
                buffer: encoded.buffer,
                pixelWidth: encoded.width,
                pixelHeight: encoded.height,
                actualPosterFrameMilliseconds: posterFrame
            )
        } catch {
            encoded.buffer.wipe()
            throw error
        }
    }

    private func videoFrame(
        from url: URL,
        durationMilliseconds: Int,
        maximumPixelEdge: Int
    ) throws -> (image: CGImage, actualMilliseconds: Int) {
        guard durationMilliseconds > 0 else {
            throw MediaCaptureFailure(.thumbnailGenerationFailed)
        }
        let asset = AVURLAsset(url: url)
        let targetMilliseconds = min(1_000, durationMilliseconds / 2)
        let target = CMTime(value: CMTimeValue(targetMilliseconds), timescale: 1_000)
        let tolerance = CMTime(value: CMTimeValue(durationMilliseconds), timescale: 1_000)
        var candidates: [(CGImage, Int)] = []

        let afterGenerator = AVAssetImageGenerator(asset: asset)
        afterGenerator.appliesPreferredTrackTransform = true
        afterGenerator.maximumSize = CGSize(width: maximumPixelEdge, height: maximumPixelEdge)
        afterGenerator.requestedTimeToleranceBefore = .zero
        afterGenerator.requestedTimeToleranceAfter = tolerance
        var actual = CMTime.zero
        if let image = try? afterGenerator.copyCGImage(at: target, actualTime: &actual) {
            candidates.append((image, max(0, Int((CMTimeGetSeconds(actual) * 1_000).rounded()))))
        }

        let beforeGenerator = AVAssetImageGenerator(asset: asset)
        beforeGenerator.appliesPreferredTrackTransform = true
        beforeGenerator.maximumSize = CGSize(width: maximumPixelEdge, height: maximumPixelEdge)
        beforeGenerator.requestedTimeToleranceBefore = tolerance
        beforeGenerator.requestedTimeToleranceAfter = .zero
        actual = .zero
        if let image = try? beforeGenerator.copyCGImage(at: target, actualTime: &actual) {
            candidates.append((image, max(0, Int((CMTimeGetSeconds(actual) * 1_000).rounded()))))
        }

        guard let selectedIndex = PosterFrameSelector.selectedIndex(
            targetMilliseconds: targetMilliseconds,
            candidateMilliseconds: candidates.map(\.1)
        ) else {
            throw MediaCaptureFailure(.thumbnailGenerationFailed)
        }
        return (candidates[selectedIndex].0, candidates[selectedIndex].1)
    }
}

internal enum PosterFrameSelector {
    static func selectedIndex(
        targetMilliseconds: Int,
        candidateMilliseconds: [Int]
    ) -> Int? {
        let indexed = candidateMilliseconds.enumerated().map { (index: $0.offset, value: $0.element) }
        if let atOrAfter = indexed
            .filter({ $0.value >= targetMilliseconds })
            .min(by: { left, right in
                let leftDistance = left.value - targetMilliseconds
                let rightDistance = right.value - targetMilliseconds
                return leftDistance == rightDistance
                    ? left.value < right.value
                    : leftDistance < rightDistance
            }) {
            return atOrAfter.index
        }
        return indexed
            .filter { $0.value < targetMilliseconds }
            .max(by: { left, right in
                left.value == right.value ? left.index > right.index : left.value < right.value
            })?
            .index
    }
}
