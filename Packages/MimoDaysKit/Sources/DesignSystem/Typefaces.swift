import CoreText
import Foundation
import os
import SwiftUI
import UIKit

/// A typeface for the headlines (Fraunces in the design) or the handwriting (Patrick Hand), chosen per language in
/// Settings › Appearance › Fonts (Andrew, 2026-11-18): Fraunces and Patrick Hand have Latin letters only, and the
/// font iOS put in their place for Russian looked wrong. Each language has its own few round, friendly faces. Bundled
/// ones are SIL OFL; the rest come with iOS.
public struct Typeface: Hashable, Sendable, Identifiable {
    public enum Role: Sendable {
        case heading
        case hand
        /// Everything else: body text (Nunito in the design) and small labels (Inter).
        case body
    }

    enum Source: Hashable, Sendable {
        /// The design's own font, with its own axes.
        case design(FontFamily)
        /// A font file in the package; `variable` takes the style's weight on its `wght` axis.
        case bundled(String, variable: Bool)
        /// A font iOS has, by PostScript name.
        case system(String)
        /// San Francisco, rounded.
        case systemUI
    }

    public let id: String
    /// Its own name, shown in itself.
    public let name: String
    let source: Source
    /// Handwriting faces differ a lot in size at the same point size; this evens them out against Patrick Hand.
    let scale: CGFloat
    init(_ id: String, _ name: String, _ source: Source, scale: CGFloat = 1) {
        self.id = id
        self.name = name
        self.source = source
        self.scale = scale
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
            let weight: UIFont.Weight = switch style.weight {
            case ..<350: .light
            case ..<450: .regular
            case ..<550: .medium
            case ..<650: .semibold
            case ..<750: .bold
            default: .heavy
            }
            let font = UIFont.systemFont(ofSize: size, weight: weight)
            guard let rounded = font.fontDescriptor.withDesign(.rounded) else { return font as CTFont }
            return UIFont(descriptor: rounded, size: size) as CTFont
        }
    }

    /// Whether it has every letter of the language (its exemplar characters).
    func covers(_ language: String) -> Bool {
        // San Francisco reaches every script through the fonts iOS adds behind it.
        if source == .systemUI { return true }
        return Self.coverage.withLock { cache in
            let key = "\(id)|\(language)"
            if let known = cache[key] { return known }
            let style = TextStyle(.fraunces, size: 17, relativeTo: .body)
            let characters = CTFontCopyCharacterSet(font(for: style, pointSize: 17)) as CharacterSet
            let needed = Self.letters(of: language)
            // A system font iOS doesn't have comes back as another one: it doesn't count.
            let present: Bool = switch source {
            case let .system(name): CTFontCopyPostScriptName(CTFontCreateWithName(name as CFString, 17, nil)) as String == name
            // A file missing from the bundle would come back as the system font under this face's name.
            case let .bundled(file, _): Self.descriptor(file) != nil
            case .design, .systemUI: true
            }
            let result = present && Self.share(of: needed, in: characters) >= (needed.count > 1000 ? 0.99 : 1)
            cache[key] = result
            return result
        }
    }

    private static let coverage = OSAllocatedLockedCache()

    /// How much of `needed` a font has. Chinese and Japanese ask for thousands of characters; a face with 99% of them
    /// is offered, and Core Text draws a rare missing one in the system font.
    private static func share(of needed: [Unicode.Scalar], in characters: CharacterSet) -> Double {
        guard !needed.isEmpty else { return 1 }
        return Double(needed.count { characters.contains($0) }) / Double(needed.count)
    }

    /// The language's own letters, lowercase and capitals.
    static func letters(of language: String) -> [Unicode.Scalar] {
        letterSets.withLock { cache in
            if let known = cache[language] { return known }
            let scalars = makeLetters(of: language).letterScalars
            cache[language] = scalars
            return scalars
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
        // Combining marks and modifier letters (Turkish İ's dot, Ukrainian ʼ) come from any font, as iOS draws them.
        set = set.intersection(.letters).subtracting(.nonBaseCharacters).subtracting(CharacterSet(charactersIn: "\u{02B0}" ... "\u{02FF}"))
        if language == "ko" {
            // Korean lists all 11,172 syllables; fonts carry the 2,350 in everyday use (KS X 1001), as iOS's own do.
            let everyday = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)))
            let kept = set.letterScalars.filter { String($0).canBeConverted(to: everyday) }
            set = CharacterSet(charactersIn: String(String.UnicodeScalarView(kept)))
        }
        return set
    }

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
    private var values: [String: [Unicode.Scalar]] = [:]
    private let lock = NSLock()

    func withLock<T>(_ body: (inout [String: [Unicode.Scalar]]) -> T) -> T {
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
    static let sfRounded = Typeface("sfRounded", "SF Rounded", .systemUI)
    static let nunito = Typeface("nunito", "Nunito", .design(.nunito))

    /// Every face on offer. Besides the design's two, round and friendly ones (Andrew, 2026-11-18), picked per script.
    static let all: [Typeface] = [
        .fraunces, .patrickHand, .sfRounded, .nunito,
        Typeface("fredoka", "Fredoka", .bundled("Fredoka", variable: true)),
        Typeface("baloo2", "Baloo 2", .bundled("Baloo2", variable: true)),
        Typeface("grandstander", "Grandstander", .bundled("Grandstander", variable: true)),
        Typeface("comfortaa", "Comfortaa", .bundled("Comfortaa", variable: true)),
        Typeface("rubik", "Rubik", .bundled("Rubik", variable: true)),
        Typeface("balsamiq", "Balsamiq Sans", .bundled("BalsamiqSans-Bold", variable: false)),
        Typeface("mplusRounded", "M+ Rounded", .bundled("MPLUSRounded1c-Bold", variable: false)),
        Typeface("varelaRound", "Varela Round", .bundled("VarelaRound-Regular", variable: false)),
        Typeface("balooBhaijaan", "Baloo Bhaijaan", .bundled("BalooBhaijaan2", variable: true)),
        Typeface("lemonada", "Lemonada", .bundled("Lemonada", variable: true)),
        Typeface("marhey", "Marhey", .bundled("Marhey", variable: true)),
        Typeface("notoSansArmenian", "Noto Sans", .bundled("NotoSansArmenian", variable: true)),
        Typeface("notoSansGeorgian", "Noto Sans", .bundled("NotoSansGeorgian", variable: true)),
        Typeface("hiraginoMaru", "ヒラギノ丸ゴ", .system("HiraMaruProN-W4")),
        Typeface("jua", "Jua", .bundled("Jua-Regular", variable: false)),
        Typeface("doHyeon", "Do Hyeon", .bundled("DoHyeon-Regular", variable: false)),
        Typeface("zcoolKuaiLe", "站酷快乐体", .bundled("ZCOOLKuaiLe-Regular", variable: false)),
        Typeface("neucha", "Neucha", .bundled("Neucha", variable: false), scale: 1.05),
        Typeface("pangolin", "Pangolin", .bundled("Pangolin-Regular", variable: false)),
        Typeface("playpen", "Playpen Sans", .bundled("PlaypenSans", variable: true)),
        Typeface("shortStack", "Short Stack", .bundled("ShortStack-Regular", variable: false)),
        Typeface("shantell", "Shantell Sans", .bundled("ShantellSans", variable: true)),
        Typeface("gveretLevin", "Gveret Levin", .bundled("GveretLevin-Regular", variable: false)),
        Typeface("playpenHebrew", "Playpen Sans", .bundled("PlaypenSansHebrew", variable: true)),
        Typeface("playpenArabic", "Playpen Sans", .bundled("PlaypenSansArabic", variable: true)),
    ]

    private static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// Each language's own short list, its default first. Latin languages keep the design's faces first (Andrew,
    /// 2026-11-18: they are tested); a face missing some of a language's letters drops out (Neucha for Ukrainian).
    /// Body text keeps to faces with weights (variable ones and SF), so bold labels stay bolder than the text around
    /// them.
    private static let lists: [String: (headings: [String], hands: [String], body: [String])] = {
        let latin = (
            headings: ["fraunces", "fredoka", "baloo2", "grandstander", "comfortaa", "sfRounded"],
            hands: ["patrickHand", "pangolin", "playpen", "shortStack", "shantell", "sfRounded"],
            body: ["nunito", "rubik", "fredoka", "comfortaa", "sfRounded"]
        )
        let cyrillic = (
            headings: ["mplusRounded", "comfortaa", "rubik", "balsamiq", "sfRounded"],
            hands: ["neucha", "pangolin", "playpen", "shantell", "sfRounded"],
            body: ["nunito", "rubik", "comfortaa", "sfRounded"]
        )
        var lists: [String: (headings: [String], hands: [String], body: [String])] = [
            "he": (
                ["fredoka", "varelaRound", "rubik", "mplusRounded", "sfRounded"], ["gveretLevin", "playpenHebrew", "sfRounded"],
                ["rubik", "fredoka", "sfRounded"]
            ),
            "ar": (
                ["balooBhaijaan", "lemonada", "marhey", "sfRounded"], ["playpenArabic", "marhey", "sfRounded"],
                ["rubik", "balooBhaijaan", "lemonada", "sfRounded"]
            ),
            "hy": (["notoSansArmenian", "sfRounded"], ["sfRounded", "notoSansArmenian"], ["notoSansArmenian", "sfRounded"]),
            "ka": (["notoSansGeorgian", "sfRounded"], ["sfRounded", "notoSansGeorgian"], ["notoSansGeorgian", "sfRounded"]),
            "ja": (["mplusRounded", "hiraginoMaru", "sfRounded"], ["hiraginoMaru", "mplusRounded", "sfRounded"], ["sfRounded"]),
            "ko": (["jua", "doHyeon", "sfRounded"], ["jua", "sfRounded"], ["sfRounded"]),
            "zh-Hans": (["zcoolKuaiLe", "hiraginoMaru", "sfRounded"], ["zcoolKuaiLe", "hiraginoMaru", "sfRounded"], ["sfRounded"]),
            "zh-Hant": (["hiraginoMaru", "sfRounded"], ["hiraginoMaru", "sfRounded"], ["sfRounded"]),
        ]
        for language in ["en", "de", "fr", "es", "it", "nl", "sv", "pl", "pt-BR", "tr"] { lists[language] = latin }
        for language in ["ru", "uk", "be", "kk"] { lists[language] = cyrillic }
        return lists
    }()

    /// The faces offered for `language` ("ru", "zh-Hant"), its default first.
    static func options(_ role: Role, language: String) -> [Typeface] {
        let list = lists[language] ?? lists["en"]!
        let ids = switch role {
        case .heading: list.headings
        case .hand: list.hands
        case .body: list.body
        }
        let faces = ids.compactMap { byID[$0] }.filter { $0.covers(language) }
        return faces.isEmpty ? [.sfRounded] : faces
    }

    static func defaultFace(_ role: Role, language: String) -> Typeface {
        options(role, language: language)[0]
    }
}

/// The headline, handwriting and body faces in use: the language's choice, or its default.
public struct Typefaces: Equatable, Sendable {
    public var heading: Typeface
    public var hand: Typeface
    public var body: Typeface

    /// The design as drawn: Fraunces, Patrick Hand, and Nunito with Inter.
    public static let design = Typefaces(heading: .fraunces, hand: .patrickHand, body: .nunito)

    public init(heading: Typeface, hand: Typeface, body: Typeface = .nunito) {
        self.heading = heading
        self.hand = hand
        self.body = body
    }

    /// `heading`, `hand` and `body` are saved ids; one no longer offered for the language falls back to its default.
    public init(language: String, heading: String? = nil, hand: String? = nil, body: String? = nil) {
        func pick(_ role: Typeface.Role, _ id: String?) -> Typeface {
            Typeface.options(role, language: language).first { $0.id == id } ?? Typeface.defaultFace(role, language: language)
        }
        self.heading = pick(.heading, heading)
        self.hand = pick(.hand, hand)
        self.body = pick(.body, body)
    }

    /// The face for a role.
    public subscript(role: Typeface.Role) -> Typeface {
        switch role {
        case .heading: heading
        case .hand: hand
        case .body: body
        }
    }

    public static func options(_ role: Typeface.Role, language: String) -> [Typeface] {
        Typeface.options(role, language: language)
    }

    /// The faces for text drawn outside SwiftUI (movie titles), set with the environment's; read from any thread.
    public static var current: Typefaces {
        get { currentLock.withLock { $0 } }
        set { currentLock.withLock { $0 = newValue } }
    }

    private static let currentLock = OSAllocatedUnfairLock(initialState: Typefaces.design)
}

public extension EnvironmentValues {
    /// Headlines, handwriting and body text for this part of the app; every text style uses them.
    @Entry var typefaces = Typefaces.design
}

public extension Typeface {
    /// Drawn in itself at `size`, for a list of faces: a headline's weight, handwriting, or body text.
    func sample(_ role: Role, size: CGFloat) -> Font {
        let style = switch role {
        case .heading: TextStyle(.fraunces, size: size, weight: 650, relativeTo: .body)
        case .hand: TextStyle(.patrickHand, size: size, relativeTo: .body)
        case .body: TextStyle(.nunito, size: size, weight: 500, relativeTo: .body)
        }
        return Font(font(for: style, pointSize: size))
    }
}
