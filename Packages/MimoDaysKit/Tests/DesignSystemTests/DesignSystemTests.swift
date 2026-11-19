import CoreText
@testable import DesignSystem
import Foundation
import SwiftUI
import Testing
import UIKit

struct DesignSystemTests {
    /// Latin letters keep the design's faces (Andrew, 2026-11-19).
    @Test(arguments: [
        (TextStyle.displayHero, "Fraunces"), (TextStyle.body, "Nunito"),
        (TextStyle.labelCaps, "Inter"), (TextStyle.hand, "Patrick Hand"),
    ])
    func latinFacesLoad(style: TextStyle, family: String) {
        #expect(CTFontCopyFamilyName(style.ctFont(pointSize: 17, typefaces: .latin)) as String == family)
    }

    @Test func headlinesUseSuperSoftOpticalCut() throws {
        let font = TextStyle.displayHero.ctFont(pointSize: 38, typefaces: .latin)
        let variation = try #require(CTFontCopyVariation(font) as? [NSNumber: NSNumber])
        #expect(variation[TextStyle.tag("wght")]?.doubleValue == 650)
        #expect(variation[TextStyle.tag("opsz")]?.doubleValue == 72)
        #expect(variation[TextStyle.tag("SOFT")]?.doubleValue == 100)
    }

    @Test func otherAlphabetsTakeTheStylesWeight() throws {
        let font = TextStyle.body.ctFont(pointSize: 16, typefaces: Typefaces(language: "ru"))
        let variation = try #require(CTFontCopyVariation(font) as? [NSNumber: NSNumber])
        #expect(CTFontCopyFamilyName(font) as String == "Comfortaa")
        #expect(variation[TextStyle.tag("wght")]?.doubleValue == 500)
        // Labels follow the body face outside Latin letters.
        #expect(CTFontCopyFamilyName(TextStyle.labelCaps.ctFont(pointSize: 12, typefaces: Typefaces(language: "ru"))) as String == "Comfortaa")
    }

    @Test func textScalesWithDynamicType() {
        let style = TextStyle.body
        #expect(style.scaledSize(for: .large) == style.size)
        #expect(style.scaledSize(for: .accessibility3) > style.size * 1.5)
        #expect(style.scaledSize(for: .xSmall) < style.size)
    }

    @Test func headlinesStopGrowingAtOnePointThreeFive() {
        let hero = TextStyle.displayHero
        #expect(hero.scaledSize(for: .accessibility5) == hero.size * 1.35)
        #expect(hero.scaledSize(for: .large) == hero.size)
    }

    // UIColor(Color) uses a SwiftUI cache that is not thread-safe; parallel cases crashed off the main actor.
    @MainActor @Test(arguments: ColorToken.allCases)
    func everyTokenResolvesInBothAppearances(token: ColorToken) {
        let color = UIColor(token.color)
        let light = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let dark = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        var alpha: CGFloat = 0
        #expect(light.getRed(nil, green: nil, blue: nil, alpha: &alpha) && alpha > 0)
        let staysTheSame: Set<ColorToken> = [.textOnCoral, .mediaScrim]
        #expect((light == dark) == staysTheSame.contains(token))
    }
}

/// One set of faces per alphabet, picked by Andrew (2026-11-19); no choice in Settings.
struct TypefaceTests {
    static let languages = ["en", "de", "fr", "es", "it", "nl", "sv", "pl", "pt-BR", "tr", "ru", "uk", "be", "kk", "he", "ar", "hy", "ka", "ja", "ko", "zh-Hans", "zh-Hant"]

    @Test func languagesThatShareLettersShareFaces() {
        for language in ["de", "fr", "es", "it", "nl", "sv", "pl", "pt-BR", "tr", "xx"] {
            #expect(Typefaces(language: language) == .latin)
        }
        for language in ["uk", "be", "kk"] {
            #expect(Typefaces(language: language) == Typefaces(language: "ru"))
        }
        #expect(Typefaces(language: "ru") == Typefaces(heading: .balsamiq, hand: .shantell, body: .comfortaa))
        #expect(Typefaces(language: "ko").hand == .jua)
    }

    /// Every bundled face is in the package and has all of its language's letters (CJK is drawn as iOS cascades).
    @Test(arguments: languages)
    func everyFaceLoadsWithTheLanguagesLetters(language: String) throws {
        let typefaces = Typefaces(language: language)
        for role in [Typeface.Role.heading, .hand, .body, .label] {
            guard case let .bundled(file, _) = typefaces[role].source else { continue }
            let font = typefaces[role].font(weight: 500, pointSize: 17)
            #expect(CTFontCopyPostScriptName(font) as String != CTFontCopyPostScriptName(UIFont.systemFont(ofSize: 17)) as String, "\(file) missing")
            guard !["ja", "ko", "zh-Hans", "zh-Hant"].contains(language) else { continue }
            let exemplar = try #require(NSLocale(localeIdentifier: language).object(forKey: .exemplarCharacterSet) as? CharacterSet)
            let letters = exemplar.intersection(.letters).subtracting(.nonBaseCharacters)
            let characters = CTFontCopyCharacterSet(font) as CharacterSet
            let missing = (0x20 ... 0x2FFF).compactMap(Unicode.Scalar.init).filter { letters.contains($0) && !characters.contains($0) }
            #expect(missing.isEmpty, "\(file) lacks \(String(String.UnicodeScalarView(missing))) for \(language)")
        }
    }
}
