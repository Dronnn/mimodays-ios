import SwiftUI

/// Hand-cut tile behind a What's new row's glyph (§V17 LL03, 48×50); stretches to any rect.
public struct GlyphTileBlob: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        path.move(to: p(0.1734, 0.0000))
        path.addLine(to: p(0.2505, 0.0046))
        path.addLine(to: p(0.3276, 0.0055))
        path.addLine(to: p(0.4046, 0.0038))
        path.addLine(to: p(0.4817, 0.0012))
        path.addLine(to: p(0.5588, 0.0000))
        path.addLine(to: p(0.6361, 0.0020))
        path.addLine(to: p(0.7132, 0.0081))
        path.addLine(to: p(0.7903, 0.0177))
        path.addLine(to: p(0.8607, 0.0353))
        path.addLine(to: p(0.9127, 0.0740))
        path.addLine(to: p(0.9434, 0.1247))
        path.addLine(to: p(0.9540, 0.1803))
        path.addLine(to: p(0.9576, 0.2535))
        path.addLine(to: p(0.9659, 0.3267))
        path.addLine(to: p(0.9768, 0.3998))
        path.addLine(to: p(0.9875, 0.4730))
        path.addLine(to: p(0.9956, 0.5462))
        path.addLine(to: p(0.9996, 0.6196))
        path.addLine(to: p(1.0000, 0.6928))
        path.addLine(to: p(0.9977, 0.7660))
        path.addLine(to: p(0.9879, 0.8383))
        path.addLine(to: p(0.9509, 0.9018))
        path.addLine(to: p(0.8912, 0.9481))
        path.addLine(to: p(0.8151, 0.9704))
        path.addLine(to: p(0.7380, 0.9798))
        path.addLine(to: p(0.6610, 0.9895))
        path.addLine(to: p(0.5839, 0.9968))
        path.addLine(to: p(0.5068, 1.0000))
        path.addLine(to: p(0.4297, 0.9976))
        path.addLine(to: p(0.3524, 0.9901))
        path.addLine(to: p(0.2753, 0.9794))
        path.addLine(to: p(0.1982, 0.9675))
        path.addLine(to: p(0.1230, 0.9502))
        path.addLine(to: p(0.0620, 0.9109))
        path.addLine(to: p(0.0213, 0.8552))
        path.addLine(to: p(0.0052, 0.7896))
        path.addLine(to: p(0.0023, 0.7164))
        path.addLine(to: p(0.0000, 0.6432))
        path.addLine(to: p(0.0000, 0.5700))
        path.addLine(to: p(0.0038, 0.4968))
        path.addLine(to: p(0.0109, 0.4236))
        path.addLine(to: p(0.0192, 0.3503))
        path.addLine(to: p(0.0269, 0.2771))
        path.addLine(to: p(0.0309, 0.2039))
        path.addLine(to: p(0.0357, 0.1414))
        path.addLine(to: p(0.0600, 0.0867))
        path.addLine(to: p(0.1065, 0.0407))
        path.closeSubpath()
        return path
    }
}
