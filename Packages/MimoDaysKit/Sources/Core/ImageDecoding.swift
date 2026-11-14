import Foundation
import ImageIO

/// Decodes still images on one serial queue, never on the Swift concurrency pool: decoding blocks its thread,
/// and HEIC through the software decoder (machines without a hardware one, like CI) waits on work of its own.
/// With every pool thread blocked that way, nothing else runs (CI hang, 2026-11-14).
public enum ImageDecoding {
    private static let queue = DispatchQueue(label: "MimoDays.imageDecoding", qos: .userInitiated)

    /// `CGImageSourceCreateThumbnailAtIndex` for the first image in the file; `maxPixelSize` nil keeps the full size.
    public static func thumbnail(_ url: URL, maxPixelSize: Int?, cacheImmediately: Bool = false) async -> CGImage? {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: decode(url, maxPixelSize: maxPixelSize, cacheImmediately: cacheImmediately)) }
        }
    }

    private static func decode(_ url: URL, maxPixelSize: Int?, cacheImmediately: Bool) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else { return nil }
        var size = maxPixelSize
        if size == nil {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
            size = max(width, height)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: cacheImmediately,
            kCGImageSourceThumbnailMaxPixelSize: size ?? 0,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
