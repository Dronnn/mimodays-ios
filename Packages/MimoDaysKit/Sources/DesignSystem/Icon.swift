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
    /// C11 place picker: 24 pt search field glyph, 20 pt recent-place clock.
    case glyphSearch
    /// Viewer toolbar (M05/M06).
    case glyphShare
    case glyphHeart
    case glyphHeartFilled
    case glyphPause
    /// Search (M08): the Filters chip.
    case glyphFilter
    /// Collections (M01 chip, M07 row, M11 new, M12 add moments).
    case glyphCollection
    case glyphPlus
    case glyphClock
    /// 16×16, the Map date chip (P01).
    case glyphCalendar
    /// 22×22 arrow, the Map's locate button (P01).
    case glyphLocate
    /// 42×36 film frame on the Make my movie card (T02).
    case glyphFilm
    /// 14×18 solid pin before the place on a hero caption.
    case glyphPinSolid
    /// `Brand / Wordmark` on Today: the letters and the star, two layers on one 103.7×33 canvas.
    case brandWordmark
    case brandWordmarkStar
    /// Today's hand-drawn marks (own bounds): the headline underline, the sage hatch, small tick bursts.
    case markBrush
    case markHatch
    case markTicksB
    case markTicksC
    /// 56 pt line glyphs on explainer art.
    case explainerCamera
    case explainerMicrophone
    case explainerCameraOff
    case explainerSparkle
    case explainerBell
    case explainerSearch
    case explainerHeart
    case explainerClock
    case explainerCollection
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
