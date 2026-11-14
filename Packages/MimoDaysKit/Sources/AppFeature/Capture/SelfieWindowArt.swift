import CoreImage
import DesignSystem
import UIKit

/// The signature selfie window for one canvas (a photo or a video's render size), drawn once and reused for
/// every frame: shadow + cream frame, and the opening the selfie shows through, both already tilted.
/// The same window as `SelfieFrame` on screen: every metric comes from `SelfieWindowStyle`.
struct SelfieWindowArt: @unchecked Sendable {
    /// Shadow and cream frame on a clear canvas.
    let frame: CIImage
    /// White where the selfie shows, clear elsewhere.
    let opening: CIImage
    /// Maps the selfie's extent into the tilted opening; set per source size.
    private let openingRect: CGRect
    private let rotation: CGAffineTransform
    let canvas: CGSize

    init(window: SelfieWindowFrame, canvas: CGSize) {
        self.canvas = canvas
        let rect = PhotoComposer.placement(of: window, in: canvas).rect
        let style = SelfieWindowStyle.self
        // Metrics scale with the window's own width, like `SelfieFrame`, whatever units the frame came in.
        let scale = rect.width / style.size.width
        let tilt = style.tilt.radians
        let outer = CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height)
        let inner = outer.insetBy(dx: style.border * scale, dy: style.border * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        let frameImage = renderer.image { context in
            let cg = context.cgContext
            cg.translateBy(x: rect.midX, y: rect.midY)
            cg.rotate(by: tilt)
            cg.setShadow(
                offset: CGSize(width: 0, height: style.shadowY * scale), blur: style.shadowBlur * scale,
                color: UIColor.black.withAlphaComponent(style.shadowOpacity).cgColor
            )
            UIColor(
                red: CGFloat(style.frameHex >> 16 & 0xFF) / 255, green: CGFloat(style.frameHex >> 8 & 0xFF) / 255,
                blue: CGFloat(style.frameHex & 0xFF) / 255, alpha: 1
            ).setFill()
            UIBezierPath(roundedRect: outer, cornerRadius: style.cornerRadius * scale).fill()
        }
        let openingImage = renderer.image { context in
            let cg = context.cgContext
            cg.translateBy(x: rect.midX, y: rect.midY)
            cg.rotate(by: tilt)
            UIColor.white.setFill()
            UIBezierPath(roundedRect: inner, cornerRadius: style.innerCornerRadius * scale).fill()
        }
        frame = frameImage.cgImage.map { CIImage(cgImage: $0) } ?? CIImage.empty()
        opening = openingImage.cgImage.map { CIImage(cgImage: $0) } ?? CIImage.empty()

        // Core Image has its origin at the bottom left: flip the centre, and the same visual tilt is positive.
        let center = CGPoint(x: rect.midX, y: canvas.height - rect.midY)
        openingRect = inner.offsetBy(dx: center.x, dy: center.y)
        rotation = CGAffineTransform(translationX: -center.x, y: -center.y)
            .concatenating(CGAffineTransform(rotationAngle: -tilt))
            .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
    }

    /// `main` must fill the canvas (origin at zero); `selfie` is any upright image.
    func compose(main: CIImage, selfie: CIImage?) -> CIImage {
        let framed = frame.composited(over: main)
        guard let selfie else { return framed }
        let extent = selfie.extent
        let fill = max(openingRect.width / extent.width, openingRect.height / extent.height)
        let placed = selfie
            .transformed(by: CGAffineTransform(translationX: -extent.midX, y: -extent.midY)
                .concatenating(CGAffineTransform(scaleX: fill, y: fill))
                .concatenating(CGAffineTransform(translationX: openingRect.midX, y: openingRect.midY)))
            .transformed(by: rotation)
        return placed
            .applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: framed, kCIInputMaskImageKey: opening])
            .cropped(to: CGRect(origin: .zero, size: canvas))
    }
}
