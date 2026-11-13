import SwiftUI

/// Hand-traced vector icons from the Penpot library (Icons.xcassets, template images).
public enum Icon: String, CaseIterable, Sendable {
    case tabToday
    case tabMemories
    case tabMap
    case tabMovies
    case glyphGear
    case glyphCamera
    /// 56 pt line glyphs on explainer art.
    case explainerCamera
    case explainerMicrophone
    case explainerCameraOff
    /// Explainer art layers, all on the same 150×140 canvas.
    case artBlob
    case markStar
    case markTicks
    /// Hand-cut primary button outline (362×54), stretched to the button.
    case shapeButton

    public var image: Image { Image(rawValue, bundle: .module).renderingMode(.template) }
}
