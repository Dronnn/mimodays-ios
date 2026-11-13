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
    /// Retake sits on the photo, so it stops growing at 1.35x like the camera controls.
    public static let reviewRetake = TextStyle(.nunito, size: 15, weight: 700, relativeTo: .subheadline, maximumScale: 1.35)

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
        // SwiftUI can only add space between lines, so tighter-than-natural heights keep the font's own.
        let extra = style.lineHeight.map { max(0, size * $0 - (CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))) } ?? 0
        content
            .font(Font(font))
            .tracking(style.tracking)
            .lineSpacing(extra)
            .textCase(style.isUppercase ? .uppercase : nil)
    }
}

public extension View {
    /// Applies a design-system text style that scales with Dynamic Type.
    func textStyle(_ style: TextStyle) -> some View {
        modifier(TextStyleModifier(style: style))
    }
}
