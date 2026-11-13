import SwiftUI

/// Hand-traced vector icons from the Penpot library (Icons.xcassets, template images).
public enum Icon: String, CaseIterable, Sendable {
    case tabToday
    case tabMemories
    case tabMap
    case tabMovies
    case glyphGear
    case glyphCamera
    /// 24 pt back chevron in `Navigation / Back bar`.
    case glyphBack
    /// 20 pt row disclosure chevron.
    case glyphChevron
    /// 24 pt camera controls (C01-C05, C13b).
    case glyphClose
    case glyphFlash
    case glyphPiP
    case glyphMore
    case glyphFlip
    case glyphSpeaker
    case glyphMute
    case glyphInfo
    /// 18 pt review chip glyphs (C07).
    case glyphPin
    case glyphMic
    case glyphNote
    /// 24 pt coral warning on the C13d card.
    case glyphWarning
    /// 30 pt play triangle on the cream play button.
    case glyphPlay
    /// 24 pt check on the mint disc of the saved toast (C12).
    case glyphCheck
    /// 24 pt remove control on the voice note card (C10).
    case glyphTrash
    /// 56 pt line glyphs on explainer art.
    case explainerCamera
    case explainerMicrophone
    case explainerCameraOff
    case explainerSparkle
    case explainerBell
    /// Explainer art layers, all on the same 150×140 canvas.
    case artBlob
    case markStar
    case markTicks
    /// Standalone marks (own bounds), placed next to heroes and photos.
    case markStarSolo
    case markTicksA
    /// 16 pt star on the camera's surprise chip.
    case markStarSmall
    /// Hand-cut primary button outline (362×54), stretched to the button.
    case shapeButton
    /// Hand-cut segmented control track (362×40) and selected pill (88.5×32), stretched to fit.
    case shapeSegmentTrack
    case shapeSegmentPill

    public var image: Image { Image(rawValue, bundle: .module).renderingMode(.template) }
}
