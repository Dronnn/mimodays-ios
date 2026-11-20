import CoreText
import Foundation
import os
import SwiftUI
import UIKit

/// A face for one role of text. Andrew picked one per alphabet (2026-11-19): languages that share letters share
/// their faces, and there is no choice in Settings. Latin letters keep the design's faces. Bundled ones are SIL OFL;
/// the rest come with iOS.
public struct Typeface: Hashable, Sendable {
    public enum Role: Sendable {
        /// Titles and the primary button.
        case heading
        /// Captions, notes and ribbons.
        case hand
        /// Everything else: body text and controls.
        case body
        /// Small capitals and the notification art (Inter in the design); elsewhere the body face.
        case label
    }

    /// The variable axes a bundled face takes from the style.
    enum Axes: Hashable, Sendable {
        case none
        /// The style's weight on `wght`.
        case weight
        /// Fraunces as designed: the weight, its largest and softest optical cut, no wonky letters.
        case fraunces
        /// Inter as designed: the weight, and the optical size following the point size.
        case inter
    }

    enum Source: Hashable, Sendable {
        /// A font file in the package and the axes it takes.
        case bundled(String, Axes)
        /// A font iOS has, by PostScript name.
        case system(String)
        /// San Francisco, rounded.
        case systemUI
    }

    let source: Source

    /// The face at `pointSize`, at `weight` on the axis of a variable font.
    func font(weight: CGFloat, pointSize: CGFloat) -> CTFont {
        switch source {
        case let .bundled(file, axes):
            guard let base = Self.descriptor(file) else { return UIFont.systemFont(ofSize: pointSize) as CTFont }
            let values: [NSNumber: CGFloat] = switch axes {
            case .none: [:]
            case .weight: [TextStyle.tag("wght"): weight]
            case .fraunces: [TextStyle.tag("wght"): weight, TextStyle.tag("opsz"): 72, TextStyle.tag("SOFT"): 100, TextStyle.tag("WONK"): 0]
            case .inter: [TextStyle.tag("wght"): weight, TextStyle.tag("opsz"): min(max(pointSize, 14), 32)]
            }
            let descriptor = values.isEmpty
                ? base
                : CTFontDescriptorCreateCopyWithAttributes(base, [kCTFontVariationAttribute: values] as CFDictionary)
            return CTFontCreateWithFontDescriptor(descriptor, pointSize, nil)
        case let .system(name):
            return CTFontCreateWithName(name as CFString, pointSize, nil)
        case .systemUI:
            let systemWeight: UIFont.Weight = switch weight {
            case ..<350: .light
            case ..<450: .regular
            case ..<550: .medium
            case ..<650: .semibold
            case ..<750: .bold
            default: .heavy
            }
            let font = UIFont.systemFont(ofSize: pointSize, weight: systemWeight)
            guard let rounded = font.fontDescriptor.withDesign(.rounded) else { return font as CTFont }
            return UIFont(descriptor: rounded, size: pointSize) as CTFont
        }
    }

    // Font descriptors are immutable and thread-safe (Core Text), so one cache serves every thread.
    nonisolated(unsafe) private static let descriptors = NSCache<NSString, CTFontDescriptor>()

    private static func descriptor(_ file: String) -> CTFontDescriptor? {
        if let known = descriptors.object(forKey: file as NSString) { return known }
        guard let url = Bundle.module.url(forResource: file, withExtension: "ttf", subdirectory: "Fonts")
            ?? Bundle.module.url(forResource: file, withExtension: "ttf"),
              let descriptor = (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first
        else { return nil }
        descriptors.setObject(descriptor, forKey: file as NSString)
        return descriptor
    }

    static let fraunces = Typeface(source: .bundled("Fraunces", .fraunces))
    static let nunito = Typeface(source: .bundled("Nunito", .weight))
    static let inter = Typeface(source: .bundled("Inter", .inter))
    static let patrickHand = Typeface(source: .bundled("PatrickHand-Regular", .none))
    static let shantell = Typeface(source: .bundled("ShantellSans", .weight))
    static let comfortaa = Typeface(source: .bundled("Comfortaa", .weight))
    static let balsamiq = Typeface(source: .bundled("BalsamiqSans-Bold", .none))
    static let fredoka = Typeface(source: .bundled("Fredoka", .weight))
    static let playpenHebrew = Typeface(source: .bundled("PlaypenSansHebrew", .weight))
    static let marhey = Typeface(source: .bundled("Marhey", .weight))
    static let balooBhaijaan = Typeface(source: .bundled("BalooBhaijaan2", .weight))
    static let notoSansArmenian = Typeface(source: .bundled("NotoSansArmenian", .weight))
    static let notoSansGeorgian = Typeface(source: .bundled("NotoSansGeorgian", .weight))
    static let mplusRounded = Typeface(source: .bundled("MPLUSRounded1c-Bold", .none))
    static let jua = Typeface(source: .bundled("Jua-Regular", .none))
    static let zcoolKuaiLe = Typeface(source: .bundled("ZCOOLKuaiLe-Regular", .none))
    static let hiraginoMaru = Typeface(source: .system("HiraMaruProN-W4"))
    static let sfRounded = Typeface(source: .systemUI)
}

/// The heading, handwriting, body and label faces for a language's alphabet.
public struct Typefaces: Equatable, Sendable {
    public var heading: Typeface
    public var hand: Typeface
    public var body: Typeface
    public var label: Typeface

    /// `label` is the body face unless given.
    init(heading: Typeface, hand: Typeface, body: Typeface, label: Typeface? = nil) {
        self.heading = heading
        self.hand = hand
        self.body = body
        self.label = label ?? body
    }

    /// English, German, French, Spanish, Italian, Dutch, Swedish, Polish, Portuguese, Turkish: the design's faces.
    public static let latin = Typefaces(heading: .fraunces, hand: .patrickHand, body: .nunito, label: .inter)

    /// The faces for `language` ("ru", "zh-Hant"); one not listed reads Latin letters.
    public init(language: String) {
        self = switch language {
        case "ru", "uk", "be", "kk": Typefaces(heading: .balsamiq, hand: .shantell, body: .comfortaa)
        case "he": Typefaces(heading: .fredoka, hand: .playpenHebrew, body: .fredoka)
        case "ar": Typefaces(heading: .marhey, hand: .marhey, body: .balooBhaijaan)
        case "hy": Typefaces(heading: .notoSansArmenian, hand: .sfRounded, body: .notoSansArmenian)
        case "ka": Typefaces(heading: .notoSansGeorgian, hand: .sfRounded, body: .notoSansGeorgian)
        case "ja": Typefaces(heading: .mplusRounded, hand: .hiraginoMaru, body: .sfRounded)
        case "ko": Typefaces(heading: .sfRounded, hand: .jua, body: .sfRounded)
        case "zh-Hans": Typefaces(heading: .zcoolKuaiLe, hand: .zcoolKuaiLe, body: .sfRounded)
        case "zh-Hant": Typefaces(heading: .hiraginoMaru, hand: .hiraginoMaru, body: .sfRounded)
        default: .latin
        }
    }

    /// The face for a role.
    public subscript(role: Typeface.Role) -> Typeface {
        switch role {
        case .heading: heading
        case .hand: hand
        case .body: body
        case .label: label
        }
    }

    /// The faces for text drawn outside SwiftUI (movie titles), set with the environment's; read from any thread.
    public static var current: Typefaces {
        get { currentLock.withLock { $0 } }
        set { currentLock.withLock { $0 = newValue } }
    }

    private static let currentLock = OSAllocatedUnfairLock(initialState: Typefaces.latin)
}

public extension EnvironmentValues {
    /// Headlines, handwriting and body text for this part of the app; every text style uses them.
    @Entry var typefaces = Typefaces.latin
}
