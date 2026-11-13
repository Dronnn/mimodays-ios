import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ThumbnailError: Error, Equatable, Sendable {
    case unreadable(String)
    case encodingFailed
}

/// Makes small images for grids, strips and previews without decoding full-size media.
/// Results are cached in memory by file and size; the cache drops entries under memory pressure.
public actor ThumbnailPipeline {
    private struct Key: Hashable {
        var path: String
        var maxPixelSize: Int
    }

    private var cache: [Key: CGImage] = [:]
    private var order: [Key] = []
    private let capacity: Int
    /// How many images were actually decoded (for tests and diagnostics).
    public private(set) var renderCount = 0

    public init(capacity: Int = 300) {
        self.capacity = capacity
    }

    /// A thumbnail whose longer side is at most `maxPixelSize`, keeping the aspect ratio and orientation.
    public func thumbnail(for url: URL, maxPixelSize: Int) async throws -> CGImage {
        let key = Key(path: url.standardizedFileURL.path, maxPixelSize: maxPixelSize)
        if let cached = cache[key] {
            order.removeAll { $0 == key }
            order.append(key)
            return cached
        }
        let image = try await Self.render(url, maxPixelSize: maxPixelSize)
        renderCount += 1
        cache[key] = image
        order.append(key)
        if order.count > capacity {
            cache[order.removeFirst()] = nil
        }
        return image
    }

    /// Writes a JPEG thumbnail into the store's derived area, for records that keep a thumbnail file.
    public func storeThumbnail(for url: URL, maxPixelSize: Int, in store: MediaStore) async throws -> StoredFile {
        let image = try await thumbnail(for: url, maxPixelSize: maxPixelSize)
        return try store.store(Self.jpegData(image), in: .derived, fileExtension: "jpg")
    }

    public func removeAll() {
        cache.removeAll()
        order.removeAll()
    }

    // MARK: Rendering

    private static func render(_ url: URL, maxPixelSize: Int) async throws -> CGImage {
        let type = UTType(filenameExtension: url.pathExtension)
        if type?.conforms(to: .movie) == true || type?.conforms(to: .audiovisualContent) == true {
            return try await videoFrame(url, maxPixelSize: maxPixelSize)
        }
        return try imageThumbnail(url, maxPixelSize: maxPixelSize)
    }

    private static func imageThumbnail(_ url: URL, maxPixelSize: Int) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { throw ThumbnailError.unreadable(url.lastPathComponent) }
        return image
    }

    /// A frame a little into the clip, so fades from black don't become the poster.
    private static func videoFrame(_ url: URL, maxPixelSize: Int) async throws -> CGImage {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        do {
            let duration = try await asset.load(.duration)
            let time = CMTime(seconds: min(0.5, duration.seconds / 2), preferredTimescale: 600)
            return try await generator.image(at: time).image
        } catch {
            throw ThumbnailError.unreadable(url.lastPathComponent)
        }
    }

    public static func jpegData(_ image: CGImage, quality: Double = 0.8) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ThumbnailError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ThumbnailError.encodingFailed }
        return data as Data
    }
}
