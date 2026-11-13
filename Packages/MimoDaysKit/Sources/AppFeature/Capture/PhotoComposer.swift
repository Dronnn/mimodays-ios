import Core
import DesignSystem
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Where the selfie window's frame (without its handle) sat in the preview when the shutter fired.
struct SelfieWindowFrame: Equatable, Sendable {
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
        return try write(composed)
    }

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
        let size = CGSize(width: main.width, height: main.height)
        let (rect, scale) = placement(of: window, in: size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIImage(cgImage: main).draw(in: CGRect(origin: .zero, size: size))
            let cg = context.cgContext
            // Same as the live window (`SelfiePreviewWindow`): 22 pt corners, 4 pt cream border, -5.4°, shadow.
            cg.translateBy(x: rect.midX, y: rect.midY)
            cg.rotate(by: Size.selfieWindowTilt.radians)
            let outer = CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height)
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: 4 * scale), blur: 14 * scale, color: UIColor.black.withAlphaComponent(0.22).cgColor)
            UIColor(red: 0xFB / 255, green: 0xF6 / 255, blue: 0xEF / 255, alpha: 1).setFill()
            UIBezierPath(roundedRect: outer, cornerRadius: 22 * scale).fill()
            cg.restoreGState()
            let inner = outer.insetBy(dx: 4 * scale, dy: 4 * scale)
            UIBezierPath(roundedRect: inner, cornerRadius: 18 * scale).addClip()
            UIImage(cgImage: selfie).draw(in: aspectFill(CGSize(width: selfie.width, height: selfie.height), in: inner))
        }
        return image.cgImage ?? main
    }

    private static func aspectFill(_ size: CGSize, in rect: CGRect) -> CGRect {
        let scale = max(rect.width / size.width, rect.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2, width: fitted.width, height: fitted.height)
    }

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
