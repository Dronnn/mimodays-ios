@testable import Core
import Foundation
import Testing

struct AppLanguageTests {
    private func defaults() -> (UserDefaults, String) {
        let suite = "AppLanguageTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test func followsIOSUntilAChoice() {
        let (defaults, suite) = defaults()
        let language = AppLanguage(defaults: defaults, domain: suite)
        #expect(language.code == nil)
        #expect(language.locale.identifier == AppLanguage.systemCode)
    }

    @Test func aChoiceIsKeptWhereIOSKeepsTheAppLanguage() {
        let (defaults, suite) = defaults()
        AppLanguage(defaults: defaults, domain: suite).code = "pt-BR"
        #expect(defaults.persistentDomain(forName: suite)?["AppleLanguages"] as? [String] == ["pt-BR"])
        #expect(AppLanguage(defaults: defaults, domain: suite).code == "pt-BR")
    }

    @Test func backToIOSRemovesTheChoice() {
        let (defaults, suite) = defaults()
        let language = AppLanguage(defaults: defaults, domain: suite)
        language.code = "de"
        language.code = nil
        #expect(defaults.persistentDomain(forName: suite)?["AppleLanguages"] == nil)
        #expect(AppLanguage(defaults: defaults, domain: suite).code == nil)
    }

    @Test(arguments: [("de-DE", "de"), ("zh-Hant-TW", "zh-Hant"), ("zh-Hans-CN", "zh-Hans"), ("pt-BR", "pt-BR"), ("he", "he"), ("fi", nil)])
    func readsWhatIOSStores(stored: String, code: String?) {
        let (defaults, suite) = defaults()
        defaults.set([stored], forKey: "AppleLanguages")
        #expect(AppLanguage(defaults: defaults, domain: suite).code == code)
    }

    @Test func unsupportedChoicesAreIgnored() {
        let (defaults, suite) = defaults()
        let language = AppLanguage(defaults: defaults, domain: suite)
        language.code = "xx"
        #expect(language.code == nil)
    }

    @Test func rightToLeftAndNativeNames() {
        let (defaults, suite) = defaults()
        let language = AppLanguage(defaults: defaults, domain: suite)
        language.code = "ar"
        #expect(language.isRightToLeft)
        language.code = "ja"
        #expect(!language.isRightToLeft)
        #expect(AppLanguage.nativeName("de") == "Deutsch")
        #expect(AppLanguage.nativeName("ja") == "日本語")
    }
}
