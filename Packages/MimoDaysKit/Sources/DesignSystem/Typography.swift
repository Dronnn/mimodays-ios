import CoreText
import SwiftUI
import UIKit

/// A text style token: the role of its text (which face draws it, per alphabet), base size at the default text
/// size, weight, and the system text style it scales with (Dynamic Type).
public struct TextStyle: Equatable, Sendable {
    public var role: Typeface.Role
    public var size: CGFloat
    /// `wght` axis value (400 regular, 500 medium, 600 semibold, 700 bold).
    public var weight: CGFloat
    /// Line height as a multiple of the size; nil keeps the font's own.
    public var lineHeight: CGFloat?
    public var tracking: CGFloat
    public var isUppercase: Bool
    public var relativeTo: UIFont.TextStyle
    /// Largest growth over `size` at big text sizes; nil follows iOS fully.
    public var maximumScale: CGFloat?

    public init(
        _ role: Typeface.Role, size: CGFloat, weight: CGFloat = 400, lineHeight: CGFloat? = nil,
        tracking: CGFloat = 0, isUppercase: Bool = false, relativeTo: UIFont.TextStyle, maximumScale: CGFloat? = nil
    ) {
        self.role = role
        self.size = size
        self.weight = weight
        self.lineHeight = lineHeight
        self.tracking = tracking
        self.isUppercase = isUppercase
        self.relativeTo = relativeTo
        self.maximumScale = maximumScale
    }

    // They stop growing at 1.35x, as in the large-type frames A01-A10; everything else follows iOS.
    public static let displayHero = TextStyle(.heading, size: 38, weight: 650, lineHeight: 0.98, relativeTo: .largeTitle, maximumScale: 1.35)
    public static let displayTitle = TextStyle(.heading, size: 34, weight: 650, lineHeight: 1.15, relativeTo: .largeTitle, maximumScale: 1.35)
    public static let displayHeadline = TextStyle(.heading, size: 32, weight: 650, lineHeight: 1.12, relativeTo: .title1, maximumScale: 1.35)
    public static let displaySheet = TextStyle(.heading, size: 28, weight: 650, lineHeight: 1.15, relativeTo: .title1, maximumScale: 1.35)
    public static let displaySection = TextStyle(.heading, size: 20.5, weight: 650, relativeTo: .title3, maximumScale: 1.35)
    public static let buttonPrimary = TextStyle(.heading, size: 20, weight: 650, relativeTo: .title3, maximumScale: 1.35)
    public static let body = TextStyle(.body, size: 16, weight: 500, lineHeight: 1.4, relativeTo: .body)
    public static let rowTitle = TextStyle(.body, size: 16, weight: 700, relativeTo: .body)
    public static let rowDetail = TextStyle(.body, size: 15, weight: 500, relativeTo: .subheadline)
    public static let control = TextStyle(.body, size: 16, weight: 700, relativeTo: .callout)
    public static let meta = TextStyle(.body, size: 13.5, weight: 500, relativeTo: .footnote)
    public static let labelCaps = TextStyle(.body, size: 11.5, weight: 600, tracking: 2.2, isUppercase: true, relativeTo: .caption2)
    /// Captions, notes and ribbons only; never body text or actions.
    public static let hand = TextStyle(.hand, size: 17, relativeTo: .callout)
    /// T04's longer ribbon line, one size down so it stays on one line.
    public static let handSmall = TextStyle(.hand, size: 16, relativeTo: .callout)
    // Camera (C01-C05): controls sit on a fixed layout, so they stop growing at 1.35x.
    public static let cameraMode = TextStyle(.body, size: 13, weight: 800, tracking: 1.5, isUppercase: true, relativeTo: .caption1, maximumScale: 1.35)
    public static let cameraChip = TextStyle(.body, size: 13, weight: 700, relativeTo: .caption1, maximumScale: 1.35)
    public static let cameraTimer = TextStyle(.body, size: 15, weight: 700, relativeTo: .subheadline, maximumScale: 1.35)
    public static let cameraNote = TextStyle(.body, size: 14, weight: 500, lineHeight: 1.2, relativeTo: .footnote)
    // Review (C07, C13d).
    public static let reviewField = TextStyle(.hand, size: 18, relativeTo: .body)
    public static let reviewChip = TextStyle(.body, size: 14, weight: 600, relativeTo: .subheadline)
    /// A search chip that is on (M09).
    public static let reviewChipOn = TextStyle(.body, size: 14, weight: 700, relativeTo: .subheadline)
    public static let reviewMeta = TextStyle(.body, size: 14, weight: 500, relativeTo: .footnote)
    public static let reviewNote = TextStyle(.body, size: 15, weight: 500, lineHeight: 1.2, relativeTo: .subheadline)
    /// C08 note text.
    public static let noteBody = TextStyle(.hand, size: 22, lineHeight: 1.3, relativeTo: .body)
    /// `Navigation / Editor bar` (C08): Cancel, title, Done.
    public static let editorCancel = TextStyle(.body, size: 17, weight: 600, relativeTo: .body, maximumScale: 1.35)
    public static let editorTitle = TextStyle(.heading, size: 18, weight: 650, relativeTo: .headline, maximumScale: 1.35)
    public static let editorDone = TextStyle(.body, size: 17, weight: 800, relativeTo: .body, maximumScale: 1.35)
    public static let noteMeta = TextStyle(.body, size: 14, weight: 600, relativeTo: .footnote)
    public static let noteCount = TextStyle(.body, size: 13, weight: 500, relativeTo: .caption1)
    /// Bottom sheet titles (C04, C09).
    public static let sheetTitle = TextStyle(.heading, size: 22, weight: 600, relativeTo: .title2, maximumScale: 1.35)
    /// Full sheet titles (M09 Filters, M11b New collection, M15 Delete).
    public static let largeSheetTitle = TextStyle(.heading, size: 24, weight: 600, relativeTo: .title2, maximumScale: 1.35)
    /// The words under a page's title (M16).
    public static let pageIntro = TextStyle(.body, size: 14, weight: 500, relativeTo: .footnote)
    /// A pushed page's own title: a place (P03), Without a place (P05b).
    public static let pageTitle = TextStyle(.heading, size: 32, weight: 600, tracking: -0.6, relativeTo: .title1, maximumScale: 1.35)
    /// The two lines on M16b's `Card / Deleted info`.
    public static let infoCard = TextStyle(.body, size: 14, weight: 600, lineHeight: 1.2, relativeTo: .footnote)
    /// Sheet explanations (M15): body text at 15, tighter than body copy.
    public static let sheetBody = TextStyle(.body, size: 15, weight: 500, lineHeight: 1.2, relativeTo: .subheadline)
    /// C09 "0:12 / 1:00".
    public static let voiceTimer = TextStyle(.body, size: 16, weight: 700, relativeTo: .callout)
    /// C09 "Tap to stop".
    public static let voiceHint = TextStyle(.hand, size: 17, relativeTo: .body)
    /// C10 "Transcribed on this iPhone".
    public static let voiceCredit = TextStyle(.body, size: 12, weight: 500, relativeTo: .caption2)
    /// C11 search field text and placeholder.
    public static let searchField = TextStyle(.hand, size: 17, relativeTo: .body)
    /// Second line of a list row ("Nearby", "Used 4 times") and the note under a list.
    public static let rowCaption = TextStyle(.body, size: 13, weight: 500, relativeTo: .footnote)
    /// A setting's value at a row's end: From/To dates, the collection (M08b, P04).
    public static let rowValue = TextStyle(.body, size: 15, weight: 500, relativeTo: .subheadline)
    /// Retake sits on the photo, so it stops growing at 1.35x like the camera controls.
    public static let reviewRetake = TextStyle(.body, size: 15, weight: 700, relativeTo: .subheadline, maximumScale: 1.35)
    // Today (T01-T07).
    /// "surprise" on the hero's mint tag.
    public static let heroTag = TextStyle(.body, size: 13, weight: 600, relativeTo: .caption1)
    /// The time under the place on a hero caption.
    public static let heroTime = TextStyle(.hand, size: 15.5, relativeTo: .subheadline)
    /// "Catch a moment" under the capture button.
    public static let captureLabel = TextStyle(.hand, size: 21.6, relativeTo: .title3)
    /// Open / Resume / Turn on on the surprise ribbon.
    public static let ribbonAction = TextStyle(.body, size: 14, weight: 700, relativeTo: .subheadline)
    /// "Make my movie".
    public static let cardTitle = TextStyle(.heading, size: 17.7, weight: 600, relativeTo: .headline, maximumScale: 1.35)
    /// T01 "Your first moment will live here." and its labels.
    public static let emptyHeroTitle = TextStyle(.hand, size: 19, relativeTo: .body)
    public static let emptyHeroLabel = TextStyle(.hand, size: 15, relativeTo: .subheadline)
    // Memories (M01).
    /// A tab's own big title: "Memories".
    public static let screenTitle = TextStyle(.heading, size: 36, weight: 650, relativeTo: .largeTitle, maximumScale: 1.35)
    // Home (U10-U16).
    /// "Today" / "Mosaic" on the home switch.
    public static let homeSwitch = TextStyle(.body, size: 13, weight: 800, relativeTo: .caption1, maximumScale: 1.35)
    /// "Your mosaic".
    public static let mosaicTitle = TextStyle(.heading, size: 30, weight: 600, lineHeight: 1.2, relativeTo: .title1, maximumScale: 1.35)
    /// A month's chapter: "November".
    public static let mosaicChapter = TextStyle(.heading, size: 20, weight: 600, lineHeight: 1.2, relativeTo: .title3, maximumScale: 1.35)
    /// "Your mosaic grows with every moment".
    public static let mosaicNoteTitle = TextStyle(.heading, size: 18, weight: 600, relativeTo: .headline, maximumScale: 1.35)
    /// "No memories yet".
    /// The words under an empty state's title (M09, M10e).
    public static let emptyBody = TextStyle(.body, size: 15, weight: 500, lineHeight: 1.4, relativeTo: .subheadline)
    public static let emptyTitle = TextStyle(.heading, size: 26, weight: 650, relativeTo: .title1, maximumScale: 1.35)
    /// A month's moment count beside its title.
    public static let sectionCount = TextStyle(.body, size: 13, weight: 600, relativeTo: .footnote)
    /// A calendar day's number on its cover photo, and without one (M02); the grid can't grow far.
    public static let calendarDayOnPhoto = TextStyle(.body, size: 13, weight: 800, relativeTo: .caption1, maximumScale: 1.35)
    public static let calendarDay = TextStyle(.body, size: 15, weight: 600, relativeTo: .subheadline, maximumScale: 1.35)
    /// A month's short name over its dots (M03).
    public static let calendarMonth = TextStyle(.heading, size: 16, weight: 650, relativeTo: .headline, maximumScale: 1.35)
    /// A moment's time on a day (M04).
    public static let dayTime = TextStyle(.body, size: 13, weight: 700, relativeTo: .footnote)
    /// A moment's caption on a day (M04).
    public static let dayCaption = TextStyle(.hand, size: 20, relativeTo: .body)
    /// The place and the date line under a moment in the viewer (M05).
    public static let viewerPlace = TextStyle(.body, size: 14, weight: 700, relativeTo: .footnote)
    public static let viewerMeta = TextStyle(.body, size: 14, weight: 500, relativeTo: .footnote)
    // Movies (F01).
    /// "October is ready" on a suggestion card.
    public static let suggestionTitle = TextStyle(.heading, size: 19, weight: 600, relativeTo: .title3, maximumScale: 1.35)
    /// `Button / Small primary`: "Make it".
    public static let buttonSmall = TextStyle(.heading, size: 16, weight: 600, relativeTo: .callout, maximumScale: 1.35)
    /// A quiet action beside a small button: "Not now".
    public static let smallAction = TextStyle(.body, size: 15, weight: 700, relativeTo: .subheadline, maximumScale: 1.35)
    /// A wizard step's question: "What's it about?" (F02-F05).
    public static let wizardQuestion = TextStyle(.heading, size: 28, weight: 600, tracking: -0.4, relativeTo: .title1, maximumScale: 1.35)
    /// F03's days, and a chosen one on its coral disc; the grid can't grow far.
    public static let calendarDay16 = TextStyle(.body, size: 16, weight: 600, relativeTo: .body, maximumScale: 1.35)
    public static let calendarChosenDay = TextStyle(.body, size: 16, weight: 800, relativeTo: .body, maximumScale: 1.35)
    /// The chosen shape's name under its frame (F04).
    public static let shapeLabelOn = TextStyle(.body, size: 13, weight: 700, relativeTo: .footnote)
    /// A section in a tab's library: "Drafts", "Movies".
    public static let librarySection = TextStyle(.heading, size: 21, weight: 600, relativeTo: .title3, maximumScale: 1.35)
    /// "Draft" on a draft's cover; it sits on the picture.
    public static let coverBadge = TextStyle(.body, size: 12, weight: 800, relativeTo: .caption2, maximumScale: 1.35)
    /// The video length on a grid tile; it sits on the picture, so it stops growing at 1.35x.
    public static let tileBadge = TextStyle(.body, size: 12, weight: 700, relativeTo: .caption2, maximumScale: 1.35)
    /// Search (M08): the words typed, Cancel, and where a moment matched.
    public static let searchQuery = TextStyle(.body, size: 16, weight: 600, relativeTo: .body)
    public static let searchCancel = TextStyle(.body, size: 16, weight: 700, relativeTo: .body, maximumScale: 1.35)
    public static let searchMatch = TextStyle(.body, size: 12.5, weight: 700, relativeTo: .caption1)
    /// "Voice note · 0:12" on the viewer's voice pill (M05/M06).
    public static let voicePill = TextStyle(.body, size: 15, weight: 600, relativeTo: .subheadline)
    /// Elapsed and total time under the video scrubber (M06).
    public static let scrubTime = TextStyle(.body, size: 12, weight: 600, relativeTo: .caption2, maximumScale: 1.35)
    /// Retake over the Review card, the Memory Card back's small actions (U20, U30).
    public static let cardButton = TextStyle(.body, size: 14, weight: 800, relativeTo: .subheadline, maximumScale: 1.35)
    /// The day on a Memory Card's back: "Wednesday, Nov 11" (U30).
    public static let cardBackDay = TextStyle(.heading, size: 24, weight: 600, relativeTo: .title2, maximumScale: 1.35)
    /// A collection's name and "Still playing · 0:06" on a Memory Card's back (U30).
    public static let cardBackSmall = TextStyle(.body, size: 13, weight: 700, relativeTo: .footnote)
    /// The count on a map marker (P01).
    public static let mapCount = TextStyle(.body, size: 12.5, weight: 800, relativeTo: .caption1, maximumScale: 1.2)
    /// A place's name in the map's sheet (P02).
    public static let mapSheetTitle = TextStyle(.heading, size: 24, weight: 600, relativeTo: .title2, maximumScale: 1.35)
    /// A place's name under its photo in Recent places (P01).
    public static let mapPlaceName = TextStyle(.body, size: 14, weight: 700, relativeTo: .footnote)

    public static let all: [(name: String, style: TextStyle)] = [
        ("display.hero", .displayHero), ("display.title", .displayTitle), ("display.headline", .displayHeadline),
        ("display.sheet", .displaySheet), ("display.section", .displaySection), ("button.primary", .buttonPrimary),
        ("body", .body), ("row.title", .rowTitle), ("row.detail", .rowDetail), ("control", .control),
        ("meta", .meta), ("label.caps", .labelCaps), ("hand", .hand),
    ]

    /// Size after Dynamic Type scaling for the given text size.
    public func scaledSize(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
        let scaled = UIFontMetrics(forTextStyle: relativeTo).scaledValue(for: size, compatibleWith: traits)
        return maximumScale.map { min(scaled, size * $0) } ?? scaled
    }

    /// The Core Text font at `pointSize` with this style's variation axes.
    /// The space between single-line texts stacked so their lines sit `lineHeight` apart - negative when that is
    /// tighter than the font's own, which one text never draws (see TextStyleModifier).
    public func lineGap(for dynamicTypeSize: DynamicTypeSize, typefaces: Typefaces = .current) -> CGFloat {
        guard let lineHeight else { return 0 }
        let size = scaledSize(for: dynamicTypeSize)
        let font = ctFont(pointSize: size, typefaces: typefaces)
        return size * lineHeight - (CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))
    }

    /// The style's font, in the faces for the language's alphabet (`typefaces`).
    public func ctFont(pointSize: CGFloat, typefaces: Typefaces = .current) -> CTFont {
        typefaces[role].font(weight: weight, pointSize: pointSize)
    }

    static func tag(_ string: String) -> NSNumber {
        NSNumber(value: string.unicodeScalars.reduce(UInt32(0)) { ($0 << 8) | $1.value })
    }
}

private struct TextStyleModifier: ViewModifier {
    let style: TextStyle
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.typefaces) private var typefaces

    func body(content: Content) -> some View {
        let size = style.scaledSize(for: dynamicTypeSize)
        let font = style.ctFont(pointSize: size, typefaces: typefaces)
        let styled = content
            .font(Font(font))
            .tracking(style.tracking)
            .textCase(style.isUppercase ? .uppercase : nil)
        let natural = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
        if #available(iOS 26, *), let lineHeight = style.lineHeight, size * lineHeight >= natural {
            // The design's line height exactly, as a multiple of the size so it follows the text at any size.
            styled.lineHeight(.multiple(factor: lineHeight))
        } else {
            // Lines are never tighter than the font's own: glyphs would reach past the text's bounds, which
            // VoiceOver's audit reports as clipped. Before iOS 26 SwiftUI can only add space between lines.
            styled.lineSpacing(style.lineHeight.map { max(0, size * $0 - natural) } ?? 0)
        }
    }
}

public extension View {
    /// Applies a design-system text style that scales with Dynamic Type.
    func textStyle(_ style: TextStyle) -> some View {
        modifier(TextStyleModifier(style: style))
    }
}
