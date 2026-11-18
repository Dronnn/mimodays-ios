import CoreText
import Foundation
import SwiftUI
import UIKit

/// A typeface for the headlines (Fraunces in the design) or the handwriting (Patrick Hand), chosen per language in
/// Settings › Appearance › Fonts (Andrew, 2026-11-18): Fraunces and Patrick Hand have Latin letters only, and the
/// font iOS put in their place for Russian looked wrong. Bundled ones are SIL OFL; the rest come with iOS.
public struct Typeface: Hashable, Sendable, Identifiable {
    public enum Role: Sendable {
        case heading
        case hand
    }

    enum Source: Hashable, Sendable {
        /// The design's own font, with its own axes.
        case design(FontFamily)
        /// A font file in the package; `variable` takes the style's weight on its `wght` axis.
        case bundled(String, variable: Bool)
        /// A font iOS has, by PostScript name.
        case system(String)
        /// San Francisco: semibold for headlines, rounded for handwriting.
        case systemUI
    }

    public let id: String
    /// Its own name, shown in itself.
    public let name: String
    let source: Source
    /// Handwriting faces differ a lot in size at the same point size; this evens them out against Patrick Hand.
    let scale: CGFloat
    /// A face made for one script is offered to its languages only (Amiri for Arabic, not for English).
    let languages: Set<String>?

    init(_ id: String, _ name: String, _ source: Source, scale: CGFloat = 1, only languages: Set<String>? = nil) {
        self.id = id
        self.name = name
        self.source = source
        self.scale = scale
        self.languages = languages
    }

    /// The font for a style at `pointSize`: `weight` on the axis of a variable font.
    func font(for style: TextStyle, pointSize: CGFloat) -> CTFont {
        let size = pointSize * scale
        switch source {
        case let .design(family):
            var designStyle = style
            designStyle.family = family
            return designStyle.ctFont(pointSize: size, typefaces: .design)
        case let .bundled(file, variable):
            guard let base = Self.descriptor(file) else { return UIFont.systemFont(ofSize: size) as CTFont }
            let descriptor = variable
                ? CTFontDescriptorCreateCopyWithAttributes(base, [kCTFontVariationAttribute: [TextStyle.tag("wght"): style.weight]] as CFDictionary)
                : base
            return CTFontCreateWithFontDescriptor(descriptor, size, nil)
        case let .system(name):
            return CTFontCreateWithName(name as CFString, size, nil)
        case .systemUI:
            let weight: UIFont.Weight = style.weight >= 600 ? .semibold : style.weight >= 500 ? .medium : .regular
            let font = UIFont.systemFont(ofSize: size, weight: weight)
            guard style.family == .patrickHand, let rounded = font.fontDescriptor.withDesign(.rounded) else { return font as CTFont }
            return UIFont(descriptor: rounded, size: size) as CTFont
        }
    }

    /// Whether it has every letter of the language (its exemplar characters).
    func covers(_ language: String) -> Bool {
        if let languages, !languages.contains(language) { return false }
        // San Francisco reaches every script through the fonts iOS adds behind it.
        if source == .systemUI { return true }
        return Self.coverage.withLock { cache in
            let key = "\(id)|\(language)"
            if let known = cache[key] { return known }
            let style = TextStyle(.fraunces, size: 17, relativeTo: .body)
            let characters = CTFontCopyCharacterSet(font(for: style, pointSize: 17)) as CharacterSet
            let needed = Self.letters(of: language)
            // A system font iOS doesn't have comes back as another one: it doesn't count.
            let present: Bool = if case let .system(name) = source {
                CTFontCopyPostScriptName(CTFontCreateWithName(name as CFString, 17, nil)) as String == name
            } else {
                true
            }
            let result = present && characters.isSuperset(of: needed)
            cache[key] = result
            return result
        }
    }

    private static let coverage = OSAllocatedLockedCache()

    /// The language's own letters, lowercase and capitals.
    static func letters(of language: String) -> CharacterSet {
        letterSets.withLock { cache in
            if let known = cache[language] { return known }
            let set = makeLetters(of: language)
            cache[language] = set
            return set
        }
    }

    private static let letterSets = LockedLetterSets()

    private static func makeLetters(of language: String) -> CharacterSet {
        guard var set = (NSLocale(localeIdentifier: language).object(forKey: .exemplarCharacterSet) as? CharacterSet) else {
            return CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz")
        }
        // Exemplar sets list some letters as sequences; their single scalars are what a font needs.
        let capitals = String(set.letterScalars.map(Character.init)).uppercased(with: Locale(identifier: language))
        set.formUnion(CharacterSet(charactersIn: capitals))
        return set.intersection(.letters)
    }

    nonisolated(unsafe) private static let descriptors = NSCache<NSString, CTFontDescriptor>()

    private static func descriptor(_ file: String) -> CTFontDescriptor? {
        if let known = descriptors.object(forKey: file as NSString) { return known }
        guard let url = Bundle.module.url(forResource: file, withExtension: "ttf"),
              let descriptor = (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first
        else { return nil }
        descriptors.setObject(descriptor, forKey: file as NSString)
        return descriptor
    }
}

private extension CharacterSet {
    /// Every scalar in the set (exemplar sets are small; CJK ones a few thousand).
    var letterScalars: [Unicode.Scalar] {
        var result: [Unicode.Scalar] = []
        for plane in UInt8(0) ... 16 where hasMember(inPlane: plane) {
            for value in UInt32(plane) << 16 ..< (UInt32(plane) + 1) << 16 {
                if let scalar = Unicode.Scalar(value), contains(scalar) { result.append(scalar) }
            }
        }
        return result
    }
}

final class LockedLetterSets: @unchecked Sendable {
    private var values: [String: CharacterSet] = [:]
    private let lock = NSLock()

    func withLock<T>(_ body: (inout [String: CharacterSet]) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&values)
    }
}

/// A small lock around a dictionary, for coverage answers shared across threads.
final class OSAllocatedLockedCache: @unchecked Sendable {
    private var values: [String: Bool] = [:]
    private let lock = NSLock()

    func withLock<T>(_ body: (inout [String: Bool]) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&values)
    }
}

public extension Typeface {
    static let fraunces = Typeface("fraunces", "Fraunces", .design(.fraunces))
    static let patrickHand = Typeface("patrickHand", "Patrick Hand", .design(.patrickHand))

    /// Headlines, the design's first. Each language lists the ones that have all its letters.
    static let headings: [Typeface] = [
        .fraunces,
        Typeface("lora", "Lora", .bundled("Lora", variable: true)),
        Typeface("alegreya", "Alegreya", .bundled("Alegreya", variable: true)),
        Typeface("playfair", "Playfair Display", .bundled("PlayfairDisplay", variable: true)),
        Typeface("ptSerif", "PT Serif", .bundled("PTSerif-Bold", variable: false)),
        Typeface("yeseva", "Yeseva One", .bundled("YesevaOne-Regular", variable: false)),
        Typeface("frankRuhl", "Frank Ruhl Libre", .bundled("FrankRuhlLibre", variable: true), only: ["he"]),
        Typeface("amiri", "Amiri", .bundled("Amiri-Bold", variable: false), only: ["ar"]),
        Typeface("notoSerifArmenian", "Noto Serif Armenian", .bundled("NotoSerifArmenian", variable: true), only: ["hy"]),
        Typeface("notoSerifGeorgian", "Noto Serif Georgian", .bundled("NotoSerifGeorgian", variable: true), only: ["ka"]),
        Typeface("georgia", "Georgia", .system("Georgia-Bold")),
        Typeface("charter", "Charter", .system("Charter-Bold")),
        Typeface("hiraginoMincho", "ヒラギノ明朝", .system("HiraMinProN-W6"), only: ["ja"]),
        Typeface("hiraginoSans", "ヒラギノ角ゴ", .system("HiraginoSans-W6"), only: ["ja"]),
        Typeface("pingFangSC", "苹方-简", .system("PingFangSC-Semibold"), only: ["zh-Hans"]),
        Typeface("pingFangTC", "蘋方-繁", .system("PingFangTC-Semibold"), only: ["zh-Hant"]),
        Typeface("appleSDGothic", "Apple SD 산돌고딕 Neo", .system("AppleSDGothicNeo-Bold"), only: ["ko"]),
        Typeface("geezaPro", "Geeza Pro", .system("GeezaPro-Bold"), only: ["ar"]),
        Typeface("damascus", "Damascus", .system("DamascusBold"), only: ["ar"]),
        Typeface("arialHebrew", "Arial Hebrew", .system("ArialHebrew-Bold"), only: ["he"]),
        Typeface("system", "San Francisco", .systemUI),
    ]

    /// Handwriting, the design's first.
    static let hands: [Typeface] = [
        .patrickHand,
        Typeface("neucha", "Neucha", .bundled("Neucha", variable: false), scale: 1.05),
        Typeface("caveat", "Caveat", .bundled("Caveat", variable: true), scale: 1.2),
        Typeface("marck", "Marck Script", .bundled("MarckScript-Regular", variable: false), scale: 1.05),
        Typeface("amatic", "Amatic SC", .bundled("AmaticSC-Bold", variable: false), scale: 1.3),
        Typeface("noteworthy", "Noteworthy", .system("Noteworthy-Bold")),
        Typeface("chalkboard", "Chalkboard SE", .system("ChalkboardSE-Regular")),
        Typeface("hiraginoMaru", "ヒラギノ丸ゴ", .system("HiraMaruProN-W4"), only: ["ja"]),
        Typeface("systemRounded", "SF Rounded", .systemUI),
    ]

    /// What a language starts with: the design's fonts where they have its letters, otherwise the closest.
    private static let preferredHeadings: [String: [String]] = [
        "ru": ["lora"], "uk": ["lora"], "be": ["lora"], "kk": ["lora"],
        "hy": ["notoSerifArmenian"], "ka": ["notoSerifGeorgian"], "he": ["frankRuhl"], "ar": ["amiri"],
        "ja": ["hiraginoMincho"], "ko": ["appleSDGothic"], "zh-Hans": ["pingFangSC"], "zh-Hant": ["pingFangTC"],
    ]
    private static let preferredHands: [String: [String]] = [
        "ru": ["neucha", "caveat"], "uk": ["neucha", "caveat"], "be": ["neucha", "caveat"], "kk": ["caveat"],
        "he": ["amatic"], "ja": ["hiraginoMaru"],
    ]

    /// The faces that have every letter of `language` ("ru", "zh-Hant").
    static func options(_ role: Role, language: String) -> [Typeface] {
        (role == .heading ? headings : hands).filter { $0.covers(language) }
    }

    static func defaultFace(_ role: Role, language: String) -> Typeface {
        let options = options(role, language: language)
        let preferred = (role == .heading ? preferredHeadings : preferredHands)[language] ?? []
        let design: Typeface = role == .heading ? .fraunces : .patrickHand
        return preferred.lazy.compactMap { id in options.first { $0.id == id } }.first
            ?? (options.contains(design) ? design : nil)
            ?? options.last
            ?? design
    }
}

/// The headline and handwriting faces in use: the language's choice, or its default.
public struct Typefaces: Equatable, Sendable {
    public var heading: Typeface
    public var hand: Typeface

    /// The design as drawn: Fraunces and Patrick Hand.
    public static let design = Typefaces(heading: .fraunces, hand: .patrickHand)

    public init(heading: Typeface, hand: Typeface) {
        self.heading = heading
        self.hand = hand
    }

    /// `heading` and `hand` are saved ids; one no longer offered for the language falls back to its default.
    public init(language: String, heading: String? = nil, hand: String? = nil) {
        let headings = Typeface.options(.heading, language: language)
        let hands = Typeface.options(.hand, language: language)
        self.heading = headings.first { $0.id == heading } ?? Typeface.defaultFace(.heading, language: language)
        self.hand = hands.first { $0.id == hand } ?? Typeface.defaultFace(.hand, language: language)
    }

    public static func options(_ role: Typeface.Role, language: String) -> [Typeface] {
        Typeface.options(role, language: language)
    }

    /// The faces for text drawn outside SwiftUI (movie titles), set with the environment's.
    nonisolated(unsafe) public static var current = Typefaces.design
}

public extension EnvironmentValues {
    /// Headlines and handwriting for this part of the app; text styles in Fraunces or Patrick Hand use them.
    @Entry var typefaces = Typefaces.design
}

public extension Typeface {
    /// Drawn in itself at `size`, for a list of faces: a headline's weight, or handwriting.
    func sample(_ role: Role, size: CGFloat) -> Font {
        let style = role == .heading
            ? TextStyle(.fraunces, size: size, weight: 650, relativeTo: .body)
            : TextStyle(.patrickHand, size: size, relativeTo: .body)
        return Font(font(for: style, pointSize: size))
    }
}
