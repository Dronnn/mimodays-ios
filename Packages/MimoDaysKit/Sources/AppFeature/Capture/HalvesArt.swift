import CoreImage
import Persistence

/// What the composers draw a frame with: the window (`SelfieWindowArt`) or halves (`HalvesArt`).
protocol FrameArt: Sendable {
    var canvas: CGSize { get }
    /// `main` must fill the main stream's whole frame (origin at zero); `selfie` is any upright image.
    func compose(main: CIImage, selfie: CIImage?) -> CIImage
}

extension SelfieWindowArt: FrameArt {}

/// H.8 (Andrew, 2026-11-16): the two cameras each filling half of the format's frame, split across its long side -
/// top and bottom on 9:16, left and right on 16:9 - the main stream first. The canvas is the format's part of the
/// main stream, so what is shared is exactly what the card shows. 1:1 has the window only.
struct HalvesArt: FrameArt {
    let canvas: CGSize

    init(format: CaptureFormat, main: CGSize) {
        canvas = Self.canvas(format: format, main: main)
    }

    /// The format's part of a main frame of `main` size, in whole even pixels (video encoders want even sizes).
    static func canvas(format: CaptureFormat, main: CGSize) -> CGSize {
        let rect = MomentComposition.fitted(aspect: format.aspectRatio, in: CGRect(origin: .zero, size: main), fit: .showAll)
        func even(_ value: CGFloat) -> CGFloat { max(2, (value / 2).rounded(.down) * 2) }
        return CGSize(width: even(rect.width), height: even(rect.height))
    }

    /// The first and second halves of `canvas` (top-left origin): stacked when it's tall or square, side by side when wide.
    static func halves(_ canvas: CGSize) -> (first: CGRect, second: CGRect) {
        let bounds = CGRect(origin: .zero, size: canvas)
        let split = canvas.width > canvas.height
            ? bounds.divided(atDistance: canvas.width / 2, from: .minXEdge)
            : bounds.divided(atDistance: canvas.height / 2, from: .minYEdge)
        return (split.slice, split.remainder)
    }

    func compose(main: CIImage, selfie: CIImage?) -> CIImage {
        let (first, second) = Self.halves(canvas)
        var result = fill(main, into: first)
        if let selfie { result = fill(selfie, into: second).composited(over: result) }
        return result.cropped(to: CGRect(origin: .zero, size: canvas))
    }

    /// The image's centre filling `rect` (top-left origin); Core Image counts from the bottom.
    private func fill(_ image: CIImage, into rect: CGRect) -> CIImage {
        let target = CGRect(x: rect.minX, y: canvas.height - rect.maxY, width: rect.width, height: rect.height)
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return CIImage.empty() }
        let scale = max(target.width / extent.width, target.height / extent.height)
        return image
            .transformed(by: CGAffineTransform(translationX: -extent.midX, y: -extent.midY)
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: target.midX, y: target.midY)))
            .cropped(to: target)
    }
}
