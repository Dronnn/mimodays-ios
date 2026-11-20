import SwiftUI

/// `Glyph / Heart`: filled on a favourite's badge, outlined on the Favorites chip (M01). Drawn in a 20×18 box.
public struct HeartShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let sx = rect.width / 20, sy = rect.height / 18
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        path.move(to: p(17, 11))
        path.addCurve(to: p(20, 5.5), control1: p(18.49, 9.54), control2: p(20, 7.79))
        path.addCurve(to: p(14.5, 0), control1: p(20, 2.46), control2: p(17.54, 0))
        path.addCurve(to: p(10, 2), control1: p(12.74, 0), control2: p(11.5, 0.5))
        path.addCurve(to: p(5.5, 0), control1: p(8.5, 0.5), control2: p(7.26, 0))
        path.addCurve(to: p(0, 5.5), control1: p(2.46, 0), control2: p(0, 2.46))
        path.addCurve(to: p(3, 11), control1: p(0, 7.8), control2: p(1.5, 9.55))
        path.addLine(to: p(10, 18))
        path.closeSubpath()
        return path
    }
}
