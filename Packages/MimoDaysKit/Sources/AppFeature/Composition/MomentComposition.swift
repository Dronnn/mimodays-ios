import CoreGraphics
import Persistence

/// B.3: where a moment's two pictures go on a canvas. The Memory Card, the editor preview and the exported movie all
/// lay a moment out here, so what is shown is what is exported. Pure geometry, in any unit: the same input on a
/// 402 pt card and on a 1080 px frame gives the same layout, scaled.
///
/// "Main" is the stream recorded full-frame, "selfie" the one recorded in the window (`MomentSummary`).
/// Corners are physical, the same in right-to-left languages, as the camera records them.
struct MomentComposition: Equatable, Sendable {
    enum Stream: Equatable, Sendable {
        case main
        case selfie
    }

    struct Picture: Equatable, Sendable {
        var stream: Stream
        /// The part of the stream that shows, as a share of its upright frame (top-left origin).
        var crop: CGRect
        /// Where that part is drawn on the canvas (top-left origin). It can reach past the canvas, which clips it.
        var frame: CGRect
        /// Degrees about the frame's centre; the window's -5.4.
        var rotation: Double = 0
    }

    struct Input: Equatable, Sendable {
        /// Upright sizes of the two streams; `selfie` is nil for one camera.
        var main: CGSize
        var selfie: CGSize?
        var format: CaptureFormat
        var layout: ClipCameraLayout = .window
        /// The window's centre on the picture and its size; nil puts it where the camera starts it, top right.
        var window: PiPLayout?
    }

    /// Back to front: one picture, or the two halves of side by side.
    var pictures: [Picture]
    /// The window over them. Nil for main only, selfie only, side by side and one camera.
    var window: Picture?

    /// The camera's window, 112 x 150 pt on a 402 pt wide screen: its short side as a share of the frame's short side.
    static let defaultWindowScale = 112.0 / 402
    /// Long side over short side.
    static let windowAspect: CGFloat = 150.0 / 112
    /// Where the camera starts the window: 23.3 pt from the right edge, 49.1 pt from the top, on a 402 pt short side.
    static let defaultWindowInsets = (right: 23.3 / 402, top: 49.1 / 402)

    init(pictures: [Picture], window: Picture?) {
        self.pictures = pictures
        self.window = window
    }

    init(_ input: Input, canvas: CGSize, fit: MovieFit = .fill) {
        let bounds = CGRect(origin: .zero, size: canvas)
        let aspect = input.format.aspectRatio
        guard let selfie = input.selfie, canvas.width > 0, canvas.height > 0 else {
            self.init(pictures: [Self.picture(.main, input.main, aspect: aspect, in: bounds, fit: fit)], window: nil)
            return
        }
        switch input.layout {
        case .mainOnly:
            self.init(pictures: [Self.picture(.main, input.main, aspect: aspect, in: bounds, fit: fit)], window: nil)
        case .selfieOnly:
            self.init(pictures: [Self.picture(.selfie, selfie, aspect: aspect, in: bounds, fit: fit)], window: nil)
        case .sideBySide:
            // Split across the long side, main first: stacked on portrait and square, next to each other on landscape.
            let stacked = canvas.height >= canvas.width
            let (first, second) = stacked
                ? bounds.divided(atDistance: canvas.height / 2, from: .minYEdge)
                : bounds.divided(atDistance: canvas.width / 2, from: .minXEdge)
            self.init(
                pictures: [
                    Picture(stream: .main, crop: Self.crop(input.main, to: first.width / first.height), frame: first),
                    Picture(stream: .selfie, crop: Self.crop(selfie, to: second.width / second.height), frame: second),
                ],
                window: nil
            )
        case .window, .swapped:
            let swapped = input.layout == .swapped
            let big = swapped ? (Stream.selfie, selfie) : (Stream.main, input.main)
            let small = swapped ? (Stream.main, input.main) : (Stream.selfie, selfie)
            let picture = Self.picture(big.0, big.1, aspect: aspect, in: bounds, fit: fit)
            let frame = Self.windowFrame(input.window, picture: picture.frame, canvas: canvas, landscape: aspect > 1)
            let window = Picture(
                stream: small.0, crop: Self.crop(small.1, to: frame.width / frame.height), frame: frame,
                rotation: input.window?.rotation ?? -5.4
            )
            self.init(pictures: [picture], window: window)
        }
    }

    /// The centred part of a `source` frame with the given width-over-height `aspect`, as a share of the frame.
    static func crop(_ source: CGSize, to aspect: CGFloat) -> CGRect {
        guard source.width > 0, source.height > 0, aspect > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let sourceAspect = source.width / source.height
        if sourceAspect > aspect {
            let width = aspect / sourceAspect
            return CGRect(x: (1 - width) / 2, y: 0, width: width, height: 1)
        }
        let height = sourceAspect / aspect
        return CGRect(x: 0, y: (1 - height) / 2, width: 1, height: height)
    }

    /// rev-capture 13: the part of a full frame of `size` the card shows for `format`, centred, in whole pixels (top-left
    /// origin). "As seen" pictures are this part, and a saved window's place is a share of it.
    static func formatCrop(_ size: CGSize, _ format: CaptureFormat) -> CGRect {
        let rect = fitted(aspect: format.aspectRatio, in: CGRect(origin: .zero, size: size), fit: .showAll)
        let width = min(size.width, rect.width.rounded()), height = min(size.height, rect.height.rounded())
        return CGRect(x: ((size.width - width) / 2).rounded(.down), y: ((size.height - height) / 2).rounded(.down), width: width, height: height)
    }

    /// A rectangle of `aspect` on `bounds`: Fill covers it and reaches past it, Show all fits inside.
    static func fitted(aspect: CGFloat, in bounds: CGRect, fit: MovieFit) -> CGRect {
        let boundsAspect = bounds.width / bounds.height
        let widthFirst = fit == .fill ? aspect < boundsAspect : aspect > boundsAspect
        let size = widthFirst
            ? CGSize(width: bounds.width, height: bounds.width / aspect)
            : CGSize(width: bounds.height * aspect, height: bounds.height)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }

    private static func picture(_ stream: Stream, _ size: CGSize, aspect: CGFloat, in bounds: CGRect, fit: MovieFit) -> Picture {
        Picture(stream: stream, crop: crop(size, to: aspect), frame: fitted(aspect: aspect, in: bounds, fit: fit))
    }

    /// The window on the canvas: its centre where it was put on the picture, its short side a share of the canvas's
    /// short side (the same size on screen whatever the shape), upright on portrait and square, on its side on
    /// landscape. It stays inside the canvas.
    private static func windowFrame(_ layout: PiPLayout?, picture: CGRect, canvas: CGSize, landscape: Bool) -> CGRect {
        let short = min(canvas.width, canvas.height)
        let side = CGFloat(layout?.scale ?? defaultWindowScale) * short
        let size = landscape ? CGSize(width: side * windowAspect, height: side) : CGSize(width: side, height: side * windowAspect)
        let center: CGPoint = if let layout {
            CGPoint(x: picture.minX + CGFloat(layout.centerX) * picture.width, y: picture.minY + CGFloat(layout.centerY) * picture.height)
        } else {
            CGPoint(
                x: min(picture.maxX, canvas.width) - defaultWindowInsets.right * short - size.width / 2,
                y: max(picture.minY, 0) + defaultWindowInsets.top * short + size.height / 2
            )
        }
        let x = min(max(center.x - size.width / 2, 0), max(canvas.width - size.width, 0))
        let y = min(max(center.y - size.height / 2, 0), max(canvas.height - size.height, 0))
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}

extension CaptureFormat {
    /// Width over height.
    var aspectRatio: CGFloat {
        switch self {
        case .portrait: 9.0 / 16
        case .landscape: 16.0 / 9
        case .square: 1
        }
    }
}
