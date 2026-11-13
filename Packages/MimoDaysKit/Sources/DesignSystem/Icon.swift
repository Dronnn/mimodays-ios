import SwiftUI

/// Hand-traced vector icons from the Penpot library (Icons.xcassets, template images).
public enum Icon: String, CaseIterable, Sendable {
    case tabToday
    case tabMemories
    case tabMap
    case tabMovies
    case glyphGear
    case glyphCamera

    public var image: Image { Image(rawValue, bundle: .module).renderingMode(.template) }
}
