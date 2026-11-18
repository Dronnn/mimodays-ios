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

/// Settings › Appearance › Fonts (Andrew, 2026-11-18): each language is offered only faces with all its letters, and
/// starts with the design's where they have them.
struct TypefaceTests {
    @Test(arguments: ["en", "de", "fr", "es", "it", "nl", "sv", "pl", "pt-BR", "ru", "uk", "be", "hy", "ka", "kk", "tr", "he", "ar", "ja", "ko", "zh-Hans", "zh-Hant"])
    func everyLanguageHasFacesWithAllItsLetters(language: String) {
        let defaults = Typefaces(language: language)
        for role in [Typeface.Role.heading, .hand] {
            let options = Typefaces.options(role, language: language)
            #expect(!options.isEmpty)
            #expect(options.contains(role == .heading ? defaults.heading : defaults.hand))
        }
    }

    @Test func defaultsFollowTheScript() {
        #expect(Typefaces(language: "en") == .design)
        #expect(Typefaces(language: "ru").heading.id == "lora")
        #expect(Typefaces(language: "ru").hand.id == "neucha")
        #expect(Typefaces(language: "kk").hand.id == "caveat")
        #expect(Typefaces(language: "he").heading.id == "frankRuhl")
        #expect(Typefaces(language: "ar").heading.id == "amiri")
        // Fraunces has no Cyrillic; a face made for one script isn't offered to another.
        #expect(!Typefaces.options(.heading, language: "ru").contains(.fraunces))
        #expect(!Typefaces.options(.heading, language: "en").contains { $0.id == "amiri" })
    }

    @Test func aSavedChoiceHoldsAndAnUnknownOneFallsBack() {
        #expect(Typefaces(language: "ru", heading: "playfair", hand: "caveat").heading.id == "playfair")
        #expect(Typefaces(language: "ru", heading: "fraunces").heading.id == "lora")
    }

    @Test func aChosenHeadingReplacesFraunces() {
        let typefaces = Typefaces(language: "ru", heading: "alegreya")
        let font = TextStyle.displayHero.ctFont(pointSize: 30, typefaces: typefaces)
        #expect(CTFontCopyFamilyName(font) as String == "Alegreya")
        // Body text keeps its face.
        #expect(CTFontCopyFamilyName(TextStyle.body.ctFont(pointSize: 17, typefaces: typefaces)) as String == "Nunito")
    }
}
