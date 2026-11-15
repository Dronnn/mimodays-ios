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
            // Light peach in the dark too (U34).
            FlipCornerFold()
                .fill(Color(hex: 0xF8D7C3))
            FlipCornerCrease()
                .stroke(ColorToken.textPrimary.color.opacity(0.25), lineWidth: 1.5)
            FlipCornerArrow()
                .stroke(Color(hex: 0xC9512B), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 44, height: 44)
    }
}

/// U20-U23 `Selfie window`: the hand-cut frame of the selfie window on a Memory Card, upright (the window's -5.4°
/// tilt is applied by the view); 97×125 in the design, stretches to any rect.
public struct CardSelfieBlob: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        path.move(to: p(0.1796, 0.0057))
        path.addCurve(to: p(0.4872, 0.0090), control1: p(0.2436, 0.0000), control2: p(0.3847, 0.0032))
        path.addCurve(to: p(0.7948, 0.0405), control1: p(0.5898, 0.0147), control2: p(0.7325, 0.0325))
        path.addCurve(to: p(0.8612, 0.0568), control1: p(0.8572, 0.0484), control2: p(0.8407, 0.0484))
        path.addCurve(to: p(0.9178, 0.0911), control1: p(0.8817, 0.0652), control2: p(0.9021, 0.0761))
        path.addCurve(to: p(0.9549, 0.1464), control1: p(0.9334, 0.1060), control2: p(0.9468, 0.0981))
        path.addCurve(to: p(0.9664, 0.3809), control1: p(0.9630, 0.1947), control2: p(0.9646, 0.3028))
        path.addCurve(to: p(0.9652, 0.6154), control1: p(0.9681, 0.4591), control2: p(0.9600, 0.5373))
        path.addCurve(to: p(0.9981, 0.8499), control1: p(0.9706, 0.6936), control2: p(0.9960, 0.7972))
        path.addCurve(to: p(0.9773, 0.9321), control1: p(1.0000, 0.9027), control2: p(0.9936, 0.9084))
        path.addCurve(to: p(0.9001, 0.9922), control1: p(0.9610, 0.9558), control2: p(0.9306, 0.9852))
        path.addCurve(to: p(0.7948, 0.9737), control1: p(0.8697, 0.9990), control2: p(0.8636, 0.9744))
        path.addCurve(to: p(0.4872, 0.9877), control1: p(0.7260, 0.9730), control2: p(0.5898, 0.9835))
        path.addCurve(to: p(0.1796, 0.9983), control1: p(0.3847, 0.9918), control2: p(0.2467, 1.0000))
        path.addCurve(to: p(0.0851, 0.9775), control1: p(0.1126, 0.9966), control2: p(0.1123, 0.9901))
        path.addCurve(to: p(0.0169, 0.9232), control1: p(0.0580, 0.9651), control2: p(0.0305, 0.9444))
        path.addCurve(to: p(0.0040, 0.8499), control1: p(0.0034, 0.9019), control2: p(0.0062, 0.9013))
        path.addCurve(to: p(0.0040, 0.6154), control1: p(0.0018, 0.7986), control2: p(0.0000, 0.6936))
        path.addCurve(to: p(0.0281, 0.3809), control1: p(0.0080, 0.5373), control2: p(0.0244, 0.4591))
        path.addCurve(to: p(0.0260, 0.1464), control1: p(0.0318, 0.3028), control2: p(0.0221, 0.1951))
        path.addCurve(to: p(0.0518, 0.0888), control1: p(0.0299, 0.0977), control2: p(0.0389, 0.1060))
        path.addCurve(to: p(0.1033, 0.0433), control1: p(0.0646, 0.0716), control2: p(0.0819, 0.0571))
        path.addCurve(to: p(0.1796, 0.0057), control1: p(0.1246, 0.0294), control2: p(0.1157, 0.0114))
        path.closeSubpath()
        return path
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

/// `Mark / Brush underline` under the date on the card's back (U30): two coral brush strokes, 196×13; stretches
/// to any rect. Generated from the Penpot path.
public struct MemoryCardBrushUnderline: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        path.move(to: p(0.3800, 0.1395))
        path.addCurve(to: p(0.3087, 0.1783), control1: p(0.3617, 0.1395), control2: p(0.3281, 0.1550))
        path.addCurve(to: p(0.2629, 0.2481), control1: p(0.2894, 0.1938), control2: p(0.2720, 0.2326))
        path.addCurve(to: p(0.2562, 0.2403), control1: p(0.2542, 0.2558), control2: p(0.2654, 0.2248))
        path.addCurve(to: p(0.2058, 0.3256), control1: p(0.2466, 0.2481), control2: p(0.2185, 0.2946))
        path.addCurve(to: p(0.1768, 0.3954), control1: p(0.1926, 0.3488), control2: p(0.1849, 0.3798))
        path.addCurve(to: p(0.1584, 0.4186), control1: p(0.1691, 0.4109), control2: p(0.1625, 0.4109))
        path.addCurve(to: p(0.1523, 0.4496), control1: p(0.1544, 0.4264), control2: p(0.1589, 0.4341))
        path.addCurve(to: p(0.1192, 0.5116), control1: p(0.1462, 0.4651), control2: p(0.1263, 0.4961))
        path.addCurve(to: p(0.1105, 0.5581), control1: p(0.1121, 0.5349), control2: p(0.1187, 0.5349))
        path.addCurve(to: p(0.0698, 0.6434), control1: p(0.1024, 0.5736), control2: p(0.0774, 0.6279))
        path.addCurve(to: p(0.0652, 0.6822), control1: p(0.0621, 0.6667), control2: p(0.0678, 0.6744))
        path.addCurve(to: p(0.0560, 0.6977), control1: p(0.0632, 0.6899), control2: p(0.0621, 0.6744))
        path.addCurve(to: p(0.0275, 0.8217), control1: p(0.0494, 0.7209), control2: p(0.0362, 0.7907))
        path.addCurve(to: p(0.0046, 0.8837), control1: p(0.0188, 0.8527), control2: p(0.0087, 0.8605))
        path.addCurve(to: p(0.0015, 0.9380), control1: p(0.0000, 0.9070), control2: p(0.0010, 0.9225))
        path.addCurve(to: p(0.0076, 1.0000), control1: p(0.0020, 0.9612), control2: p(0.0041, 0.9923))
        path.addCurve(to: p(0.0229, 0.9690), control1: p(0.0112, 1.0000), control2: p(0.0188, 0.9690))
        path.addCurve(to: p(0.0311, 0.9768), control1: p(0.0265, 0.9612), control2: p(0.0285, 0.9768))
        path.addCurve(to: p(0.0382, 0.9457), control1: p(0.0331, 0.9690), control2: p(0.0357, 0.9457))
        path.addCurve(to: p(0.0448, 0.9535), control1: p(0.0402, 0.9380), control2: p(0.0402, 0.9612))
        path.addCurve(to: p(0.0678, 0.9070), control1: p(0.0499, 0.9457), control2: p(0.0632, 0.9225))
        path.addCurve(to: p(0.0739, 0.8760), control1: p(0.0723, 0.8992), control2: p(0.0718, 0.8837))
        path.addCurve(to: p(0.0805, 0.8992), control1: p(0.0759, 0.8760), control2: p(0.0774, 0.8992))
        path.addCurve(to: p(0.0932, 0.8450), control1: p(0.0835, 0.8915), control2: p(0.0897, 0.8527))
        path.addCurve(to: p(0.1009, 0.8527), control1: p(0.0963, 0.8372), control2: p(0.0963, 0.8605))
        path.addCurve(to: p(0.1197, 0.8217), control1: p(0.1055, 0.8527), control2: p(0.1156, 0.8295))
        path.addCurve(to: p(0.1253, 0.7830), control1: p(0.1238, 0.8062), control2: p(0.1207, 0.7907))
        path.addCurve(to: p(0.1477, 0.7674), control1: p(0.1299, 0.7752), control2: p(0.1426, 0.7752))
        path.addCurve(to: p(0.1538, 0.7364), control1: p(0.1523, 0.7597), control2: p(0.1386, 0.7597))
        path.addCurve(to: p(0.2389, 0.5892), control1: p(0.1686, 0.7054), control2: p(0.2231, 0.6124))
        path.addCurve(to: p(0.2471, 0.5892), control1: p(0.2542, 0.5659), control2: p(0.2440, 0.5969))
        path.addCurve(to: p(0.2552, 0.5581), control1: p(0.2496, 0.5814), control2: p(0.2348, 0.5814))
        path.addCurve(to: p(0.3678, 0.4496), control1: p(0.2751, 0.5349), control2: p(0.3403, 0.4806))
        path.addCurve(to: p(0.4182, 0.3643), control1: p(0.3948, 0.4186), control2: p(0.4096, 0.3798))
        path.addCurve(to: p(0.4208, 0.3256), control1: p(0.4274, 0.3411), control2: p(0.4203, 0.3488))
        path.addCurve(to: p(0.4208, 0.2016), control1: p(0.4213, 0.2946), control2: p(0.4213, 0.2248))
        path.addCurve(to: p(0.4187, 0.1550), control1: p(0.4203, 0.1705), control2: p(0.4259, 0.1628))
        path.addCurve(to: p(0.3800, 0.1395), control1: p(0.4121, 0.1395), control2: p(0.3984, 0.1318))
        path.closeSubpath()
        path.move(to: p(0.8528, 0.0000))
        path.addCurve(to: p(0.7646, 0.0465), control1: p(0.8248, 0.0000), control2: p(0.7866, 0.0310))
        path.addCurve(to: p(0.7208, 0.0930), control1: p(0.7427, 0.0620), control2: p(0.7290, 0.0853))
        path.addCurve(to: p(0.7137, 0.1163), control1: p(0.7122, 0.1085), control2: p(0.7157, 0.1163))
        path.addCurve(to: p(0.7076, 0.1085), control1: p(0.7112, 0.1240), control2: p(0.7168, 0.0930))
        path.addCurve(to: p(0.6566, 0.2016), control1: p(0.6979, 0.1240), control2: p(0.6684, 0.1860))
        path.addCurve(to: p(0.6363, 0.2171), control1: p(0.6449, 0.2248), control2: p(0.6500, 0.1938))
        path.addCurve(to: p(0.5756, 0.3566), control1: p(0.6230, 0.2481), control2: p(0.5869, 0.3333))
        path.addCurve(to: p(0.5706, 0.3876), control1: p(0.5644, 0.3876), control2: p(0.5721, 0.3876))
        path.addCurve(to: p(0.5644, 0.3798), control1: p(0.5685, 0.3954), control2: p(0.5685, 0.3721))
        path.addCurve(to: p(0.5461, 0.4186), control1: p(0.5604, 0.3876), control2: p(0.5548, 0.3954))
        path.addCurve(to: p(0.5125, 0.5116), control1: p(0.5374, 0.4419), control2: p(0.5227, 0.4806))
        path.addCurve(to: p(0.4855, 0.6124), control1: p(0.5023, 0.5426), control2: p(0.4911, 0.5892))
        path.addCurve(to: p(0.4794, 0.6589), control1: p(0.4799, 0.6357), control2: p(0.4799, 0.6434))
        path.addCurve(to: p(0.4824, 0.6899), control1: p(0.4789, 0.6667), control2: p(0.4789, 0.6822))
        path.addCurve(to: p(0.4997, 0.7054), control1: p(0.4855, 0.6977), control2: p(0.4926, 0.7054))
        path.addCurve(to: p(0.5252, 0.6744), control1: p(0.5069, 0.7054), control2: p(0.5160, 0.6822))
        path.addCurve(to: p(0.5522, 0.6822), control1: p(0.5339, 0.6744), control2: p(0.5461, 0.6822))
        path.addCurve(to: p(0.5609, 0.6512), control1: p(0.5583, 0.6744), control2: p(0.5558, 0.6589))
        path.addCurve(to: p(0.5848, 0.6279), control1: p(0.5665, 0.6434), control2: p(0.5751, 0.6434))
        path.addCurve(to: p(0.6184, 0.5659), control1: p(0.5945, 0.6124), control2: p(0.6001, 0.5969))
        path.addCurve(to: p(0.6933, 0.4496), control1: p(0.6363, 0.5349), control2: p(0.6709, 0.4729))
        path.addCurve(to: p(0.7539, 0.4031), control1: p(0.7157, 0.4186), control2: p(0.7422, 0.4109))
        path.addCurve(to: p(0.7636, 0.3643), control1: p(0.7657, 0.3876), control2: p(0.7575, 0.3721))
        path.addCurve(to: p(0.7886, 0.3643), control1: p(0.7692, 0.3643), control2: p(0.7835, 0.3643))
        path.addCurve(to: p(0.7957, 0.3411), control1: p(0.7942, 0.3566), control2: p(0.7937, 0.3411))
        path.addCurve(to: p(0.8018, 0.3566), control1: p(0.7983, 0.3333), control2: p(0.7947, 0.3566))
        path.addCurve(to: p(0.8385, 0.3256), control1: p(0.8090, 0.3566), control2: p(0.8309, 0.3256))
        path.addCurve(to: p(0.8472, 0.3411), control1: p(0.8462, 0.3256), control2: p(0.8441, 0.3411))
        path.addCurve(to: p(0.8579, 0.3178), control1: p(0.8507, 0.3411), control2: p(0.8421, 0.3178))
        path.addCurve(to: p(0.9409, 0.3178), control1: p(0.8732, 0.3101), control2: p(0.9251, 0.3178))
        path.addCurve(to: p(0.9511, 0.2868), control1: p(0.9562, 0.3101), control2: p(0.9480, 0.2868))
        path.addCurve(to: p(0.9572, 0.2946), control1: p(0.9536, 0.2791), control2: p(0.9501, 0.3023))
        path.addCurve(to: p(0.9924, 0.2558), control1: p(0.9638, 0.2946), control2: p(0.9857, 0.2713))
        path.addCurve(to: p(0.9975, 0.2248), control1: p(0.9995, 0.2481), control2: p(0.9964, 0.2403))
        path.addCurve(to: p(0.9975, 0.1473), control1: p(0.9985, 0.2016), control2: p(1.0000, 0.1628))
        path.addCurve(to: p(0.9837, 0.0930), control1: p(0.9954, 0.1240), control2: p(0.9944, 0.1085))
        path.addCurve(to: p(0.9328, 0.0310), control1: p(0.9725, 0.0775), control2: p(0.9547, 0.0465))
        path.addCurve(to: p(0.8528, 0.0000), control1: p(0.9109, 0.0155), control2: p(0.8808, 0.0000))
        path.closeSubpath()
        return path
    }
}
