import SwiftUI

/// A hand-cut card of any size: rounded corners of slightly different radii and edges that wander a few points in
/// and out, so it never reads as a plain rounded rectangle. The wobble is in points, not in fractions of the size,
/// so a tall list card bends as little as a short one. The same size always gives the same outline.
public struct HandCutCard: Shape {
    public var cornerRadius: CGFloat
    public var wobble: CGFloat

    public init(cornerRadius: CGFloat = 22, wobble: CGFloat = 2.5) {
        self.cornerRadius = cornerRadius
        self.wobble = wobble
    }

    public func path(in rect: CGRect) -> Path {
        guard rect.width > 1, rect.height > 1 else { return Path(rect) }
        var random = SplitMix(seed: UInt64(rect.width.rounded()) &* 73_856_093 ^ UInt64(rect.height.rounded()) &* 19_349_663)
        let limit = min(rect.width, rect.height) / 2
        // Top-leading, top-trailing, bottom-trailing, bottom-leading.
        let radii = (0..<4).map { _ in min(cornerRadius * (0.8 + 0.4 * random.unit()), limit) }
        let phases = (0..<2).map { _ in random.unit() * 2 * .pi }
        let wobble = min(self.wobble, limit / 4)
        // Two slow waves: long bends that tilt the edges, short ones that make the cut look done by hand.
        func offset(_ distance: CGFloat) -> CGFloat {
            wobble * (0.65 * sin(distance / 61 + phases[0]) + 0.35 * sin(distance / 19 + phases[1]))
        }

        var points: [CGPoint] = []
        var walked: CGFloat = 0
        func add(_ point: CGPoint, normal: CGVector) {
            let push = offset(walked)
            points.append(CGPoint(x: point.x + normal.dx * push, y: point.y + normal.dy * push))
        }
        func edge(from start: CGPoint, to end: CGPoint, normal: CGVector) {
            let length = hypot(end.x - start.x, end.y - start.y)
            let steps = max(Int(length / 14), 1)
            for step in 0..<steps {
                let t = CGFloat(step) / CGFloat(steps)
                add(CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t), normal: normal)
                walked += length / CGFloat(steps)
            }
        }
        func corner(center: CGPoint, radius: CGFloat, from angle: CGFloat) {
            let steps = max(Int(radius * .pi / 2 / 7), 2)
            for step in 0..<steps {
                let a = angle + CGFloat(step) / CGFloat(steps) * .pi / 2
                let normal = CGVector(dx: cos(a), dy: sin(a))
                add(CGPoint(x: center.x + radius * normal.dx, y: center.y + radius * normal.dy), normal: normal)
                walked += radius * .pi / 2 / CGFloat(steps)
            }
        }

        let (minX, minY, maxX, maxY) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
        edge(from: CGPoint(x: minX + radii[0], y: minY), to: CGPoint(x: maxX - radii[1], y: minY), normal: CGVector(dx: 0, dy: -1))
        corner(center: CGPoint(x: maxX - radii[1], y: minY + radii[1]), radius: radii[1], from: -.pi / 2)
        edge(from: CGPoint(x: maxX, y: minY + radii[1]), to: CGPoint(x: maxX, y: maxY - radii[2]), normal: CGVector(dx: 1, dy: 0))
        corner(center: CGPoint(x: maxX - radii[2], y: maxY - radii[2]), radius: radii[2], from: 0)
        edge(from: CGPoint(x: maxX - radii[2], y: maxY), to: CGPoint(x: minX + radii[3], y: maxY), normal: CGVector(dx: 0, dy: 1))
        corner(center: CGPoint(x: minX + radii[3], y: maxY - radii[3]), radius: radii[3], from: .pi / 2)
        edge(from: CGPoint(x: minX, y: maxY - radii[3]), to: CGPoint(x: minX, y: minY + radii[0]), normal: CGVector(dx: -1, dy: 0))
        corner(center: CGPoint(x: minX + radii[0], y: minY + radii[0]), radius: radii[0], from: .pi)

        // A closed Catmull-Rom curve through the points.
        var path = Path()
        let count = points.count
        guard count > 3 else { return Path(roundedRect: rect, cornerRadius: cornerRadius) }
        path.move(to: points[0])
        for index in 0..<count {
            let p0 = points[(index - 1 + count) % count], p1 = points[index]
            let p2 = points[(index + 1) % count], p3 = points[(index + 2) % count]
            path.addCurve(
                to: p2,
                control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            )
        }
        path.closeSubpath()
        return path
    }
}

/// A small seeded generator, so a card keeps its outline from one frame to the next.
private struct SplitMix {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func unit() -> CGFloat {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE5_E9B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return CGFloat((z ^ (z >> 31)) >> 11) / CGFloat(1 << 53)
    }
}
