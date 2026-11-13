import SwiftUI

/// Hand-traced vector icons from the Penpot library (Icons.xcassets, template images).
public enum Icon: String, CaseIterable, Sendable {
    case tabToday
    case tabMemories
    case tabMap
    case tabMovies
    case glyphGear
    case glyphCamera
    /// Hand-cut pill behind the selected tab.
    case shapeTabPill

    public var image: Image { Image(rawValue, bundle: .module).renderingMode(.template) }

    /// Size drawn in the design, in points.
    public var designSize: CGSize {
        switch self {
        case .tabToday: CGSize(width: 22.4, height: 22.7)
        case .tabMemories: CGSize(width: 30.7, height: 23.6)
        case .tabMap: CGSize(width: 22, height: 26)
        case .tabMovies: CGSize(width: 29.8, height: 21.1)
        case .glyphGear, .glyphCamera: CGSize(width: 24, height: 24)
        case .shapeTabPill: CGSize(width: 62.6, height: 30.7)
        }
    }
}
