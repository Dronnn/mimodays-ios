import CoreImage
import Persistence
import DesignSystem
import UIKit

/// The signature selfie window for one canvas (a photo or a video's render size), drawn once and reused for
/// every frame: shadow + cream frame, and the opening the selfie shows through, both hand-cut and already tilted.
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
    /// Moves a full main frame so the part the format shows sits on the canvas.
    private var mainShift = CGAffineTransform.identity

    /// rev-capture 13: on the part of a `main`-sized frame the format shows, as the card does; `window` is placed on
    /// that part.
    init(window: SelfieWindowFrame, main: CGSize, format: CaptureFormat) {
        let crop = MomentComposition.formatCrop(main, format)
        self.init(window: window, canvas: crop.size)
        // Core Image counts from the bottom.
        mainShift = CGAffineTransform(translationX: -crop.minX, y: -(main.height - crop.maxY))
    }

    init(window: SelfieWindowFrame, canvas: CGSize) {
        self.canvas = canvas
        let rect = PhotoComposer.placement(of: window, in: canvas).rect
        let style = SelfieWindowStyle.self
        // Metrics scale with the window's own short side, like `SelfieFrame`, whatever units the frame came in;
        // a window on its side (16:9, U04) is the same frame turned.
        let scale = min(rect.width, rect.height) / style.size.width
        let tilt = style.tilt.radians
        let outer = CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height)
        let inner = outer.insetBy(dx: style.border * scale, dy: style.border * scale)

        // rev-capture 25: only the window's own region is drawn (tilted, with its shadow), not two full canvases.
        let spread = (style.shadowBlur * 2 + abs(style.shadowY)) * scale + 2
        let region = outer.applying(CGAffineTransform(rotationAngle: tilt))
            .offsetBy(dx: rect.midX, dy: rect.midY)
            .insetBy(dx: -spread, dy: -spread)
            .integral
            .intersection(CGRect(origin: .zero, size: canvas))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: region.isNull ? CGSize(width: 1, height: 1) : region.size, format: format)
        let frameImage = renderer.image { context in
            let cg = context.cgContext
            cg.translateBy(x: rect.midX - region.minX, y: rect.midY - region.minY)
            cg.rotate(by: tilt)
            cg.setShadow(
                offset: CGSize(width: 0, height: style.shadowY * scale), blur: style.shadowBlur * scale,
                color: UIColor.black.withAlphaComponent(style.shadowOpacity).cgColor
            )
            UIColor(
                red: CGFloat(style.frameHex >> 16 & 0xFF) / 255, green: CGFloat(style.frameHex >> 8 & 0xFF) / 255,
                blue: CGFloat(style.frameHex & 0xFF) / 255, alpha: 1
            ).setFill()
            UIBezierPath(cgPath: SelfieWindowShape().path(in: outer).cgPath).fill()
        }
        let openingImage = renderer.image { context in
            let cg = context.cgContext
            cg.translateBy(x: rect.midX - region.minX, y: rect.midY - region.minY)
            cg.rotate(by: tilt)
            UIColor.white.setFill()
            UIBezierPath(cgPath: SelfieWindowShape().path(in: inner).cgPath).fill()
        }
        // Core Image counts from the bottom.
        let place = CGAffineTransform(translationX: region.isNull ? 0 : region.minX, y: region.isNull ? 0 : canvas.height - region.maxY)
        frame = region.isNull ? CIImage.empty() : frameImage.cgImage.map { CIImage(cgImage: $0).transformed(by: place) } ?? CIImage.empty()
        opening = region.isNull ? CIImage.empty() : openingImage.cgImage.map { CIImage(cgImage: $0).transformed(by: place) } ?? CIImage.empty()

        // Core Image has its origin at the bottom left: flip the centre, and the same visual tilt is positive.
        let center = CGPoint(x: rect.midX, y: canvas.height - rect.midY)
        openingRect = inner.offsetBy(dx: center.x, dy: center.y)
        rotation = CGAffineTransform(translationX: -center.x, y: -center.y)
            .concatenating(CGAffineTransform(rotationAngle: -tilt))
            .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
    }

    /// `main` must fill the canvas (origin at zero); `selfie` is any upright image.
    func compose(main: CIImage, selfie: CIImage?) -> CIImage {
        let framed = frame.composited(over: main.transformed(by: mainShift))
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
