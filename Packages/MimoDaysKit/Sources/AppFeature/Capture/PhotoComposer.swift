import Core
import Persistence
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
        case renderFailed
        case encodingFailed
    }

    /// Reads both files upright (orientation and mirroring applied), composes, writes HEIC (JPEG where HEIC
    /// encoding isn't available). Runs off the main actor.
    /// What the card shows: the format's part of the main photo (rev-capture 13).
    static func compose(mainURL: URL, selfieURL: URL, window: SelfieWindowFrame, format: CaptureFormat) async throws -> URL {
        try await compose(mainURL: mainURL, selfieURL: selfieURL) {
            render(SelfieWindowArt(window: window, main: CGSize(width: $0.width, height: $0.height), format: format), main: $0, selfie: $1)
        }
    }

    /// H.8: the two photos in halves of the format's frame.
    static func compose(mainURL: URL, selfieURL: URL, halves format: CaptureFormat) async throws -> URL {
        try await compose(mainURL: mainURL, selfieURL: selfieURL) {
            render(HalvesArt(format: format, main: CGSize(width: $0.width, height: $0.height)), main: $0, selfie: $1)
        }
    }

    private static func compose(
        mainURL: URL, selfieURL: URL, _ draw: @Sendable (CGImage, CGImage) -> CGImage?
    ) async throws -> URL {
        // Full size, EXIF orientation applied.
        guard let main = await ImageDecoding.thumbnail(mainURL, maxPixelSize: nil),
              let selfie = await ImageDecoding.thumbnail(selfieURL, maxPixelSize: nil) else { throw Failure.unreadable }
        // A render that failed is a failure, never the main photo passed off as the composite (rev-capture 14).
        guard let composed = draw(main, selfie) else { throw Failure.renderFailed }
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

    /// For thumbnails: the main photo when the render fails.
    static func compose(main: CGImage, selfie: CGImage, window: SelfieWindowFrame) -> CGImage {
        render(SelfieWindowArt(window: window, canvas: CGSize(width: main.width, height: main.height)), main: main, selfie: selfie) ?? main
    }

    static func compose(main: CGImage, selfie: CGImage, halves format: CaptureFormat) -> CGImage {
        render(HalvesArt(format: format, main: CGSize(width: main.width, height: main.height)), main: main, selfie: selfie) ?? main
    }

    private static func render(_ art: some FrameArt, main: CGImage, selfie: CGImage) -> CGImage? {
        let image = art.compose(main: CIImage(cgImage: main), selfie: CIImage(cgImage: selfie))
        return context.createCGImage(image, from: CGRect(origin: .zero, size: art.canvas), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }

    private static let context = CIContext(options: [.cacheIntermediates: false])

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
