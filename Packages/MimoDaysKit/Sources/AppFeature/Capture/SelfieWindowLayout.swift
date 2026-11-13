import CoreGraphics

/// Where the selfie window goes in the preview (C01, C04). Values from the 402 pt design: the top corners sit
/// 49.1 pt below the safe area, the bottom ones 125 pt above the preview's bottom edge (clear of the 10/30/60 s
/// picker), 8.7 pt from the left edge and 23.3 pt from the right one. Size changes keep the corner's edges.
/// Corners are physical: the same in right-to-left languages, as the saved moment is composed.
struct SelfieWindowLayout {
    typealias Corner = CameraSettings.SelfieWindow.Corner
    typealias Scale = CameraSettings.SelfieWindow.Scale

    /// The medium frame; the window adds a 6 pt gap and a 4 pt handle below it.
    static let frame = CGSize(width: 112, height: 150)
    static let handleSpace: CGFloat = 10

    let preview: CGSize
    let topInset: CGFloat
    /// The "A little surprise" chip's corner (top left, top right in right-to-left languages) and bottom edge:
    /// a window in that corner starts below it.
    var chip: (corner: Corner, bottom: CGFloat)?

    static func frameSize(_ scale: Scale) -> CGSize {
        CGSize(width: frame.width * scale.factor, height: frame.height * scale.factor)
    }

    /// Frame plus handle.
    static func windowSize(_ scale: Scale) -> CGSize {
        let frame = frameSize(scale)
        return CGSize(width: frame.width, height: frame.height + handleSpace)
    }

    /// Centre of the whole window (frame and handle).
    func center(_ corner: Corner, _ scale: Scale) -> CGPoint {
        let size = Self.windowSize(scale)
        let x = corner.isLeft ? 8.7 + size.width / 2 : preview.width - 23.3 - size.width / 2
        var top = topInset + 49.1
        if let chip, chip.corner == corner { top = max(top, chip.bottom + 12) }
        let y = corner.isTop ? top + size.height / 2 : preview.height - 125 - size.height / 2
        return CGPoint(x: x, y: y)
    }

    /// Centre of the frame alone, where the C04 targets are drawn.
    func frameCenter(_ corner: Corner, _ scale: Scale) -> CGPoint {
        let center = center(corner, scale)
        return CGPoint(x: center.x, y: center.y - Self.handleSpace / 2)
    }

    /// The frame (without the handle) where the window sits, for composing the photo.
    func windowFrame(_ placement: CameraSettings.SelfieWindow) -> SelfieWindowFrame {
        let center = frameCenter(placement.corner, placement.scale)
        let size = Self.frameSize(placement.scale)
        let frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        return SelfieWindowFrame(frame: frame, preview: preview)
    }

    /// The corner a window centred at `point` snaps to.
    func nearest(to point: CGPoint, _ scale: Scale) -> Corner {
        Corner.allCases.min { distance(center($0, scale), point) < distance(center($1, scale), point) } ?? .topRight
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
