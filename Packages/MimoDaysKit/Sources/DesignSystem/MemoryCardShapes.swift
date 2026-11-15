import SwiftUI

/// The Memory Card's hand-cut outline (U20-U35), also the selfie window's on the card. The corners keep their size
/// and the edges keep their small wobbles at any size and shape, so a 9:16, 1:1 or 16:9 card and a window all
/// look cut by the same hand. The wobbles are the Penpot `Memory Card / Front` border's, measured inwards from a
/// straight edge every 25 pt; small shapes wobble less.
public struct MemoryCardOutline: InsettableShape {
    private var inset: CGFloat = 0

    public init() {}

    public func inset(by amount: CGFloat) -> MemoryCardOutline {
        var shape = self
        shape.inset += amount
        return shape
    }

    /// Inset, the same wobbles move inwards, so a border drawn inside follows the clip exactly.
    public func path(in rect: CGRect) -> Path {
        Self.path(in: rect, inset: inset)
    }

    /// Inward offsets along each edge, clockwise from the top left.
    private static let top: [CGFloat] = [1.29, 3.25, 1.48, 5.33, 3.8, 1.58, 3.02, 6.34, 3.16, 2.41, 2.04, 3.72, 0, 1.29]
    private static let right: [CGFloat] = [0.48, 5.13, 0.69, 1.12, 4.13, 0.8, 0.71, 2.34, 3.16, 1.53, 4.3, 3.04, 2.38, 0.67, 1.8, 5.39, 1.38, 0.13]
    private static let bottom: [CGFloat] = [5.73, 6.58, 5.91, 3.47, 3.27, 3.78, 1.84, 3.64, 3.9, 4.18, 2.96, 4.01, 0]
    private static let left: [CGFloat] = [1.94, 1.54, 4.23, 4.28, 4.41, 1.27, 2.42, 0.76, 0.15, 3.23, 0.45, 4.87, 2.79, 2.54, 3.21, 4.92, 1.73, 0.1]
    private static let spacing: CGFloat = 25.2
    /// The design card's short side: smaller shapes scale their wobbles down.
    private static let designShortSide: CGFloat = 359

    static func path(in rect: CGRect, inset: CGFloat = 0) -> Path {
        guard rect.width > 4 + 2 * inset, rect.height > 4 + 2 * inset else { return Path(rect.insetBy(dx: inset, dy: inset)) }
        let amplitude = min(1, min(rect.width, rect.height) / designShortSide)
        let radius = min(14.5, min(rect.width, rect.height) / 4)
        let (minX, minY, maxX, maxY) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
        let edges = [
            edge(from: CGPoint(x: minX + radius, y: minY), to: CGPoint(x: maxX - radius, y: minY), inward: CGVector(dx: 0, dy: 1), top, amplitude, inset),
            edge(from: CGPoint(x: maxX, y: minY + radius), to: CGPoint(x: maxX, y: maxY - radius), inward: CGVector(dx: -1, dy: 0), right, amplitude, inset),
            edge(from: CGPoint(x: maxX - radius, y: maxY), to: CGPoint(x: minX + radius, y: maxY), inward: CGVector(dx: 0, dy: -1), bottom, amplitude, inset),
            edge(from: CGPoint(x: minX, y: maxY - radius), to: CGPoint(x: minX, y: minY + radius), inward: CGVector(dx: 1, dy: 0), left, amplitude, inset),
        ]
        // Each corner bends through a point a little inside the rectangle's own corner.
        let bend = 2.5 * amplitude + inset
        let corners = [
            CGPoint(x: maxX - bend, y: minY + bend), CGPoint(x: maxX - bend, y: maxY - bend),
            CGPoint(x: minX + bend, y: maxY - bend), CGPoint(x: minX + bend, y: minY + bend),
        ]
        var path = Path()
        path.move(to: edges[0][0])
        for (index, points) in edges.enumerated() {
            smooth(points, into: &path)
            let next = edges[(index + 1) % edges.count][0]
            path.addQuadCurve(to: next, control: corners[index])
        }
        path.closeSubpath()
        return path
    }

    /// Points along a straight edge, each pushed inwards by its offset.
    private static func edge(
        from start: CGPoint, to end: CGPoint, inward: CGVector, _ offsets: [CGFloat], _ amplitude: CGFloat, _ inset: CGFloat
    ) -> [CGPoint] {
        let length = hypot(end.x - start.x, end.y - start.y)
        let count = max(2, Int((length / spacing).rounded()))
        return (0...count).map { index in
            let share = CGFloat(index) / CGFloat(count)
            let offset = offsets[index % offsets.count] * amplitude + inset
            return CGPoint(
                x: start.x + (end.x - start.x) * share + inward.dx * offset,
                y: start.y + (end.y - start.y) * share + inward.dy * offset
            )
        }
    }

    /// A smooth curve through the points (Catmull-Rom), from the path's current point at the first one.
    private static func smooth(_ points: [CGPoint], into path: inout Path) {
        for index in 1..<points.count {
            let before = points[max(index - 2, 0)], start = points[index - 1]
            let end = points[index], after = points[min(index + 1, points.count - 1)]
            path.addCurve(
                to: end,
                control1: CGPoint(x: start.x + (end.x - before.x) / 6, y: start.y + (end.y - before.y) / 6),
                control2: CGPoint(x: end.x - (after.x - start.x) / 6, y: end.y - (after.y - start.y) / 6)
            )
        }
    }
}

/// `Card / Flip corner` (U20, U30): the card's folded bottom trailing corner, 44 pt, which flips it when dragged.
/// Drawn for the bottom right; mirror it for right-to-left.
public struct MemoryCardFlipCorner: View {
    public init() {}

    public var body: some View {
        ZStack {
            FlipCornerFold()
                .fill(ColorToken.accentPeach.color)
            FlipCornerCrease()
                .stroke(ColorToken.textPrimary.color.opacity(0.25), lineWidth: 1.5)
            FlipCornerArrow()
                .stroke(Color(hex: 0xC9512B), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 44, height: 44)
    }
}

/// The fold: the corner's triangle, rounded where the card's corner was.
struct FlipCornerFold: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = rect.width / 44
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale) }
        var path = Path()
        path.move(to: p(44, 0))
        path.addLine(to: p(0, 44))
        path.addLine(to: p(28, 44))
        path.addCurve(to: p(44, 28), control1: p(38.67, 44), control2: p(44, 38.67))
        path.closeSubpath()
        return path
    }
}

struct FlipCornerCrease: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
    }
}

/// The little turn arrow on the fold.
struct FlipCornerArrow: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = rect.width / 44
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale) }
        var path = Path()
        path.move(to: p(26, 37))
        path.addLine(to: p(31, 32))
        path.move(to: p(30, 37))
        path.addLine(to: p(35, 37))
        path.addLine(to: p(35, 32))
        return path
    }
}

/// The Memory Card buttons' 24 pt glyphs (U20): two frames with a turn arrow (Swap cameras), a page with a turn
/// arrow around it (Flip). Plum lines with a coral arrow.
public struct MemoryCardGlyph: View {
    public enum Kind {
        case swapCameras
        case flip
    }

    let kind: Kind

    public init(_ kind: Kind) {
        self.kind = kind
    }

    public var body: some View {
        Canvas { context, size in
            let scale = size.width / 24
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * scale, y: y * scale) }
            let line = StrokeStyle(lineWidth: 1.8 * scale, lineCap: .round, lineJoin: .round)
            let plum = GraphicsContext.Shading.color(ColorToken.textPrimary.color)
            let coral = GraphicsContext.Shading.color(Color(hex: 0xC9512B))
            switch kind {
            case .swapCameras:
                context.stroke(Path(roundedRect: CGRect(origin: p(3, 4), size: CGSize(width: 11 * scale, height: 14 * scale)), cornerRadius: 3 * scale), with: plum, style: line)
                context.stroke(Path(roundedRect: CGRect(origin: p(14, 10), size: CGSize(width: 7 * scale, height: 9 * scale)), cornerRadius: 2 * scale), with: plum, style: line)
                var arrow = Path()
                arrow.move(to: p(16, 3.5))
                arrow.addCurve(to: p(20.6, 8.1), control1: p(18.6, 3.7), control2: p(20.4, 5.5))
                arrow.move(to: p(18.6, 6.4))
                arrow.addLine(to: p(20.6, 8.2))
                arrow.addLine(to: p(22.2, 6))
                context.stroke(arrow, with: coral, style: line)
            case .flip:
                var page = Path()
                page.move(to: p(6, 4))
                page.addLine(to: p(15, 4))
                page.addLine(to: p(18, 7))
                page.addLine(to: p(18, 20))
                page.addLine(to: p(6, 20))
                page.closeSubpath()
                page.move(to: p(15, 4))
                page.addLine(to: p(15, 7))
                page.addLine(to: p(18, 7))
                context.stroke(page, with: plum, style: line)
                var arrows = Path()
                arrows.move(to: p(3, 12))
                arrows.addCurve(to: p(6, 8.2), control1: p(3, 10), control2: p(4.2, 8.6))
                arrows.move(to: p(20.5, 15))
                arrows.addCurve(to: p(16.9, 19), control1: p(20.5, 17.2), control2: p(18.9, 18.8))
                context.stroke(arrows, with: coral, style: line)
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}
