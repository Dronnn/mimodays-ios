import CoreText
import DesignSystem
import SwiftUI
import Testing
import UIKit

struct DesignSystemTests {
    @Test(arguments: [
        (TextStyle.displayHero, "Fraunces"), (TextStyle.body, "Nunito"),
        (TextStyle.labelCaps, "Inter"), (TextStyle.hand, "Patrick Hand"),
    ])
    func bundledFontsLoad(style: TextStyle, family: String) {
        let font = style.ctFont(pointSize: 17)
        #expect(CTFontCopyFamilyName(font) as String == family)
    }

    @Test func headlinesUseSuperSoftOpticalCut() throws {
        let variation = try #require(CTFontCopyVariation(TextStyle.displayHero.ctFont(pointSize: 38)) as? [NSNumber: NSNumber])
        func axis(_ tag: String) -> Double? {
            variation[NSNumber(value: tag.unicodeScalars.reduce(UInt32(0)) { ($0 << 8) | $1.value })]?.doubleValue
        }
        #expect(axis("wght") == 650)
        #expect(axis("opsz") == 72)
        #expect(axis("SOFT") == 100)
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

/// Settings › Appearance › Fonts (Andrew, 2026-11-18): each language has its own few round faces for headlines,
/// handwriting and body text, all with its letters; Latin languages start with the design's.
struct TypefaceTests {
    static let languages = ["en", "de", "fr", "es", "it", "nl", "sv", "pl", "pt-BR", "ru", "uk", "be", "hy", "ka", "kk", "tr", "he", "ar", "ja", "ko", "zh-Hans", "zh-Hant"]

    @Test(arguments: languages)
    func everyLanguageHasAFewFacesWithItsLetters(language: String) {
        let defaults = Typefaces(language: language)
        for role in [Typeface.Role.heading, .hand, .body] {
            let options = Typefaces.options(role, language: language)
            #expect((1 ... 6).contains(options.count))
            #expect(options.first == defaults[role])
            #expect(options.contains(.sfRounded))
        }
    }

    @Test(arguments: ["en", "de", "fr", "es", "it", "nl", "sv", "pl", "pt-BR", "tr"])
    func latinLanguagesKeepTheDesign(language: String) {
        #expect(Typefaces(language: language) == .design)
    }

    @Test func otherScriptsStartWithTheirOwnFaces() {
        #expect(Typefaces(language: "ru").heading.id == "mplusRounded")
        #expect(Typefaces(language: "ru").hand.id == "neucha")
        #expect(Typefaces(language: "ru").body == .nunito)
        #expect(Typefaces(language: "kk").hand.id == "pangolin")
        #expect(Typefaces(language: "he").heading.id == "fredoka")
        #expect(Typefaces(language: "ar").body.id == "rubik")
        #expect(Typefaces(language: "ko").heading.id == "jua")
        // Fraunces has no Cyrillic; a face made for one script isn't offered to another.
        #expect(!Typefaces.options(.heading, language: "ru").contains(.fraunces))
        #expect(!Typefaces.options(.heading, language: "en").contains { $0.id == "balooBhaijaan" })
    }

    @Test func aSavedChoiceHoldsAndAnUnknownOneFallsBack() {
        #expect(Typefaces(language: "ru", heading: "rubik", hand: "playpen", body: "comfortaa").body.id == "comfortaa")
        #expect(Typefaces(language: "ru", heading: "fraunces").heading.id == "mplusRounded")
    }

    @Test func theChosenFacesReplaceTheDesignsEverywhere() {
        let typefaces = Typefaces(language: "ru", heading: "rubik", body: "comfortaa")
        func family(_ style: TextStyle) -> String {
            CTFontCopyFamilyName(style.ctFont(pointSize: 17, typefaces: typefaces)) as String
        }
        #expect(family(.displayHero) == "Rubik")
        #expect(family(.hand) == "Neucha")
        // Body text and the Inter labels go together.
        #expect(family(.body) == "Comfortaa")
        #expect(family(.labelCaps) == "Comfortaa")
        #expect(CTFontCopyFamilyName(TextStyle.body.ctFont(pointSize: 17, typefaces: .design)) as String == "Nunito")
    }
}
