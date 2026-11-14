import Core
import CoreImage
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Where the selfie window's frame (without its handle) sat in the preview when the shutter fired.
struct SelfieWindowFrame: Codable, Equatable, Sendable {
    var frame: CGRect
    var preview: CGSize
}

/// The composed photo: the whole rear (main) photo with the selfie baked in the signature window - cream border,
/// rounded corners, -5.4° tilt, soft shadow - where it was on screen (Andrew, 2026-11-13). The two sources stay
/// as they are; this is the single image for sharing, export and thumbnails.
enum PhotoComposer {
    enum Failure: Error {
        case unreadable
        case encodingFailed
    }

    /// Reads both files upright (orientation and mirroring applied), composes, writes HEIC (JPEG where HEIC
    /// encoding isn't available). Runs off the main actor.
    static func compose(mainURL: URL, selfieURL: URL, window: SelfieWindowFrame) async throws -> URL {
        guard let main = uprightImage(mainURL), let selfie = uprightImage(selfieURL) else { throw Failure.unreadable }
        let composed = compose(main: main, selfie: selfie, window: window)
        return try await withCheckedThrowingContinuation { continuation in
            encoding.async { continuation.resume(with: Result { try write(composed) }) }
        }
    }

    /// Encoding blocks its thread until the HEVC encoder is done. Several at once on Swift's cooperative threads
    /// stalled the encoder and with it every one of those threads, so encodes run here, one at a time.
    private static let encoding = DispatchQueue(label: "MimoDays.PhotoComposer.encoding", qos: .userInitiated)

    /// The window's frame in photo pixels and the points-to-pixels factor. The preview shows the photo
    /// aspect-filled and centred, so this inverts that.
    static func placement(of window: SelfieWindowFrame, in photo: CGSize) -> (rect: CGRect, scale: CGFloat) {
        let scale = min(photo.width / window.preview.width, photo.height / window.preview.height)
        let origin = CGPoint(x: (photo.width - window.preview.width * scale) / 2, y: (photo.height - window.preview.height * scale) / 2)
        let rect = CGRect(
            x: origin.x + window.frame.minX * scale, y: origin.y + window.frame.minY * scale,
            width: window.frame.width * scale, height: window.frame.height * scale
        )
        return (rect, scale)
    }

    static func compose(main: CGImage, selfie: CGImage, window: SelfieWindowFrame) -> CGImage {
        let canvas = CGSize(width: main.width, height: main.height)
        let art = SelfieWindowArt(window: window, canvas: canvas)
        let image = art.compose(main: CIImage(cgImage: main), selfie: CIImage(cgImage: selfie))
        return context.createCGImage(image, from: CGRect(origin: .zero, size: canvas), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) ?? main
    }

    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// The full-size image with its EXIF orientation applied.
    private static func uprightImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func write(_ image: CGImage) throws -> URL {
        for type in [UTType.heic, .jpeg] {
            let url = try CaptureFiles.temporaryURL(type.preferredFilenameExtension ?? "img")
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
            if CGImageDestinationFinalize(destination) { return url }
            try? FileManager.default.removeItem(at: url)
        }
        throw Failure.encodingFailed
    }
}
