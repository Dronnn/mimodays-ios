import CoreImage
import DesignSystem
import UIKit

/// The signature selfie window for one canvas (a photo or a video's render size), drawn once and reused for
/// every frame: shadow + cream frame, and the opening the selfie shows through, both already tilted.
/// Same look as the live window (`SelfiePreviewWindow`): 22 pt corners, 4 pt cream border, -5.4°, soft shadow.
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
        let (rect, scale) = PhotoComposer.placement(of: window, in: canvas)
        let tilt = Size.selfieWindowTilt.radians
        let outer = CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height)
        let inner = outer.insetBy(dx: 4 * scale, dy: 4 * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        let frameImage = renderer.image { context in
            let cg = context.cgContext
            cg.translateBy(x: rect.midX, y: rect.midY)
            cg.rotate(by: tilt)
            cg.setShadow(offset: CGSize(width: 0, height: 4 * scale), blur: 14 * scale, color: UIColor.black.withAlphaComponent(0.22).cgColor)
            UIColor(red: 0xFB / 255, green: 0xF6 / 255, blue: 0xEF / 255, alpha: 1).setFill()
            UIBezierPath(roundedRect: outer, cornerRadius: 22 * scale).fill()
        }
        let openingImage = renderer.image { context in
            let cg = context.cgContext
            cg.translateBy(x: rect.midX, y: rect.midY)
            cg.rotate(by: tilt)
            UIColor.white.setFill()
            UIBezierPath(roundedRect: inner, cornerRadius: 18 * scale).fill()
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
