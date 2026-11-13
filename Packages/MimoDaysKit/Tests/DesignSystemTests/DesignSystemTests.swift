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

    @Test(arguments: ColorToken.allCases)
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
