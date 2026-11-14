import CoreText
import SwiftUI
import UIKit

/// Bundled typefaces (SIL OFL). Fraunces, Nunito and Inter are variable fonts.
public enum FontFamily: String, CaseIterable, Sendable {
    case fraunces = "Fraunces"
    case nunito = "Nunito"
    case inter = "Inter"
    case patrickHand = "PatrickHand-Regular"

    /// Loaded once from the package bundle. Font descriptors are immutable and thread-safe (Core Text),
    /// so sharing them across isolation domains is safe.
    nonisolated(unsafe) private static let descriptors: [FontFamily: CTFontDescriptor] = {
        var result: [FontFamily: CTFontDescriptor] = [:]
        for family in FontFamily.allCases {
            guard let url = Bundle.module.url(forResource: family.rawValue, withExtension: "ttf", subdirectory: "Fonts")
                ?? Bundle.module.url(forResource: family.rawValue, withExtension: "ttf"),
                let list = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
                let descriptor = list.first
            else { continue }
            result[family] = descriptor
        }
        return result
    }()

    var descriptor: CTFontDescriptor? { Self.descriptors[self] }
}

/// A text style token: family, base size at the default text size, variable-font axes,
/// and the system text style it scales with (Dynamic Type).
public struct TextStyle: Equatable, Sendable {
    public var family: FontFamily
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
        _ family: FontFamily, size: CGFloat, weight: CGFloat = 400, lineHeight: CGFloat? = nil,
        tracking: CGFloat = 0, isUppercase: Bool = false, relativeTo: UIFont.TextStyle, maximumScale: CGFloat? = nil
    ) {
        self.family = family
        self.size = size
        self.weight = weight
        self.lineHeight = lineHeight
        self.tracking = tracking
        self.isUppercase = isUppercase
        self.relativeTo = relativeTo
        self.maximumScale = maximumScale
    }

    // Headlines: Fraunces SuperSoft, 72 pt optical size, weight 650 (plan decision 2026-11-12).
    // They stop growing at 1.35x, as in the large-type frames A01-A10; everything else follows iOS.
    public static let displayHero = TextStyle(.fraunces, size: 38, weight: 650, lineHeight: 0.98, relativeTo: .largeTitle, maximumScale: 1.35)
    public static let displayTitle = TextStyle(.fraunces, size: 34, weight: 650, lineHeight: 1.15, relativeTo: .largeTitle, maximumScale: 1.35)
    public static let displayHeadline = TextStyle(.fraunces, size: 32, weight: 650, lineHeight: 1.12, relativeTo: .title1, maximumScale: 1.35)
    public static let displaySheet = TextStyle(.fraunces, size: 28, weight: 650, lineHeight: 1.15, relativeTo: .title1, maximumScale: 1.35)
    public static let displaySection = TextStyle(.fraunces, size: 20.5, weight: 650, relativeTo: .title3, maximumScale: 1.35)
    public static let buttonPrimary = TextStyle(.fraunces, size: 20, weight: 650, relativeTo: .title3, maximumScale: 1.35)
    public static let body = TextStyle(.nunito, size: 16, weight: 500, lineHeight: 1.4, relativeTo: .body)
    public static let rowTitle = TextStyle(.nunito, size: 16, weight: 700, relativeTo: .body)
    public static let rowDetail = TextStyle(.nunito, size: 15, weight: 500, relativeTo: .subheadline)
    public static let control = TextStyle(.nunito, size: 16, weight: 700, relativeTo: .callout)
    public static let meta = TextStyle(.nunito, size: 13.5, weight: 500, relativeTo: .footnote)
    public static let labelCaps = TextStyle(.inter, size: 11.5, weight: 600, tracking: 2.2, isUppercase: true, relativeTo: .caption2)
    /// Captions, notes and ribbons only; never body text or actions.
    public static let hand = TextStyle(.patrickHand, size: 17, relativeTo: .callout)
    // Camera (C01-C05): controls sit on a fixed layout, so they stop growing at 1.35x.
    public static let cameraMode = TextStyle(.nunito, size: 13, weight: 800, tracking: 1.5, isUppercase: true, relativeTo: .caption1, maximumScale: 1.35)
    public static let cameraChip = TextStyle(.nunito, size: 13, weight: 700, relativeTo: .caption1, maximumScale: 1.35)
    public static let cameraTimer = TextStyle(.nunito, size: 15, weight: 700, relativeTo: .subheadline, maximumScale: 1.35)
    public static let cameraNote = TextStyle(.nunito, size: 14, weight: 500, lineHeight: 1.2, relativeTo: .footnote)
    // Review (C07, C13d).
    public static let reviewField = TextStyle(.patrickHand, size: 18, relativeTo: .body)
    public static let reviewChip = TextStyle(.nunito, size: 14, weight: 600, relativeTo: .subheadline)
    public static let reviewMeta = TextStyle(.nunito, size: 14, weight: 500, relativeTo: .footnote)
    public static let reviewNote = TextStyle(.nunito, size: 15, weight: 500, lineHeight: 1.2, relativeTo: .subheadline)
    /// C08 note text.
    public static let noteBody = TextStyle(.patrickHand, size: 22, lineHeight: 1.3, relativeTo: .body)
    /// `Navigation / Editor bar` (C08): Cancel, title, Done.
    public static let editorCancel = TextStyle(.nunito, size: 17, weight: 600, relativeTo: .body, maximumScale: 1.35)
    public static let editorTitle = TextStyle(.fraunces, size: 18, weight: 650, relativeTo: .headline, maximumScale: 1.35)
    public static let editorDone = TextStyle(.nunito, size: 17, weight: 800, relativeTo: .body, maximumScale: 1.35)
    public static let noteMeta = TextStyle(.nunito, size: 14, weight: 600, relativeTo: .footnote)
    public static let noteCount = TextStyle(.nunito, size: 13, weight: 500, relativeTo: .caption1)
    /// Bottom sheet titles (C04, C09).
    public static let sheetTitle = TextStyle(.fraunces, size: 22, weight: 600, relativeTo: .title2, maximumScale: 1.35)
    /// C09 "0:12 / 1:00".
    public static let voiceTimer = TextStyle(.nunito, size: 16, weight: 700, relativeTo: .callout)
    /// C09 "Tap to stop".
    public static let voiceHint = TextStyle(.patrickHand, size: 17, relativeTo: .body)
    /// C10 "Transcribed on this iPhone".
    public static let voiceCredit = TextStyle(.nunito, size: 12, weight: 500, relativeTo: .caption2)
    /// C11 search field text and placeholder.
    public static let searchField = TextStyle(.patrickHand, size: 17, relativeTo: .body)
    /// Second line of a list row ("Nearby", "Used 4 times") and the note under a list.
    public static let rowCaption = TextStyle(.nunito, size: 13, weight: 500, relativeTo: .footnote)
    /// Retake sits on the photo, so it stops growing at 1.35x like the camera controls.
    public static let reviewRetake = TextStyle(.nunito, size: 15, weight: 700, relativeTo: .subheadline, maximumScale: 1.35)
    // Today (T01-T07).
    /// "surprise" on the hero's mint tag.
    public static let heroTag = TextStyle(.nunito, size: 13, weight: 600, relativeTo: .caption1)
    /// The time under the place on a hero caption.
    public static let heroTime = TextStyle(.patrickHand, size: 15.5, relativeTo: .subheadline)
    /// "Catch a moment" under the capture button.
    public static let captureLabel = TextStyle(.patrickHand, size: 21.6, relativeTo: .title3)
    /// Open / Resume / Turn on on the surprise ribbon.
    public static let ribbonAction = TextStyle(.nunito, size: 14, weight: 700, relativeTo: .subheadline)
    /// "Make my movie".
    public static let cardTitle = TextStyle(.fraunces, size: 17.7, weight: 600, relativeTo: .headline, maximumScale: 1.35)
    /// T01 "Your first moment will live here." and its labels.
    public static let emptyHeroTitle = TextStyle(.patrickHand, size: 19, relativeTo: .body)
    public static let emptyHeroLabel = TextStyle(.patrickHand, size: 15, relativeTo: .subheadline)
    // Memories (M01).
    /// A tab's own big title: "Memories".
    public static let screenTitle = TextStyle(.fraunces, size: 36, weight: 650, relativeTo: .largeTitle, maximumScale: 1.35)
    /// "No memories yet".
    public static let emptyTitle = TextStyle(.fraunces, size: 26, weight: 650, relativeTo: .title1, maximumScale: 1.35)
    /// A month's moment count beside its title.
    public static let sectionCount = TextStyle(.nunito, size: 13, weight: 600, relativeTo: .footnote)
    /// A calendar day's number on its cover photo, and without one (M02); the grid can't grow far.
    public static let calendarDayOnPhoto = TextStyle(.nunito, size: 13, weight: 800, relativeTo: .caption1, maximumScale: 1.35)
    public static let calendarDay = TextStyle(.nunito, size: 15, weight: 600, relativeTo: .subheadline, maximumScale: 1.35)
    /// A month's short name over its dots (M03).
    public static let calendarMonth = TextStyle(.fraunces, size: 16, weight: 650, relativeTo: .headline, maximumScale: 1.35)
    /// A moment's time on a day (M04).
    public static let dayTime = TextStyle(.nunito, size: 13, weight: 700, relativeTo: .footnote)
    /// A moment's caption on a day (M04).
    public static let dayCaption = TextStyle(.patrickHand, size: 20, relativeTo: .body)
    /// The place and the date line under a moment in the viewer (M05).
    public static let viewerPlace = TextStyle(.nunito, size: 14, weight: 700, relativeTo: .footnote)
    public static let viewerMeta = TextStyle(.nunito, size: 14, weight: 500, relativeTo: .footnote)
    /// The video length on a grid tile; it sits on the picture, so it stops growing at 1.35x.
    public static let tileBadge = TextStyle(.nunito, size: 12, weight: 700, relativeTo: .caption2, maximumScale: 1.35)
    /// Search (M08): the words typed, Cancel, and where a moment matched.
    public static let searchQuery = TextStyle(.nunito, size: 16, weight: 600, relativeTo: .body)
    public static let searchCancel = TextStyle(.nunito, size: 16, weight: 700, relativeTo: .body, maximumScale: 1.35)
    public static let searchMatch = TextStyle(.nunito, size: 12.5, weight: 700, relativeTo: .caption1)
    /// "Voice note · 0:12" on the viewer's voice pill (M05/M06).
    public static let voicePill = TextStyle(.nunito, size: 15, weight: 600, relativeTo: .subheadline)
    /// Elapsed and total time under the video scrubber (M06).
    public static let scrubTime = TextStyle(.nunito, size: 12, weight: 600, relativeTo: .caption2, maximumScale: 1.35)
    /// The count on a map marker (P01).
    public static let mapCount = TextStyle(.nunito, size: 12.5, weight: 800, relativeTo: .caption1, maximumScale: 1.2)
    /// A place's name in the map's sheet (P02).
    public static let mapSheetTitle = TextStyle(.fraunces, size: 24, weight: 600, relativeTo: .title2, maximumScale: 1.35)
    /// A place's name under its photo in Recent places (P01).
    public static let mapPlaceName = TextStyle(.nunito, size: 14, weight: 700, relativeTo: .footnote)

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
    public func ctFont(pointSize: CGFloat) -> CTFont {
        guard let base = family.descriptor else {
            return UIFont.systemFont(ofSize: pointSize) as CTFont
        }
        var axes: [NSNumber: CGFloat] = [:]
        switch family {
        case .fraunces:
            axes[Self.tag("wght")] = weight
            axes[Self.tag("opsz")] = 72
            axes[Self.tag("SOFT")] = 100
            axes[Self.tag("WONK")] = 0
        case .nunito:
            axes[Self.tag("wght")] = weight
        case .inter:
            axes[Self.tag("wght")] = weight
            axes[Self.tag("opsz")] = min(max(pointSize, 14), 32)
        case .patrickHand:
            break
        }
        let descriptor = axes.isEmpty
            ? base
            : CTFontDescriptorCreateCopyWithAttributes(base, [kCTFontVariationAttribute: axes] as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, pointSize, nil)
    }

    private static func tag(_ string: String) -> NSNumber {
        NSNumber(value: string.unicodeScalars.reduce(UInt32(0)) { ($0 << 8) | $1.value })
    }
}

private struct TextStyleModifier: ViewModifier {
    let style: TextStyle
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        let size = style.scaledSize(for: dynamicTypeSize)
        let font = style.ctFont(pointSize: size)
        let styled = content
            .font(Font(font))
            .tracking(style.tracking)
            .textCase(style.isUppercase ? .uppercase : nil)
        if #available(iOS 26, *), let lineHeight = style.lineHeight {
            // The design's line height exactly, tighter than the font's own too (Fraunces 38 at 0.98).
            styled.lineHeight(.exact(points: size * lineHeight))
        } else {
            // Before iOS 26 SwiftUI can only add space between lines; tighter heights keep the font's own.
            let natural = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
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
