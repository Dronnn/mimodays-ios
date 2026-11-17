import Foundation
import Observation
import os

/// The language MimoDays shows, chosen in Settings › Appearance › Language and applied at once (Andrew,
/// 2026-11-17). Views get it as `\.locale` from the root; code that builds strings or formats values reads `locale`
/// here, which a view body observes, so it redraws on a switch too. The choice is kept where iOS keeps an app's own
/// language (the app's `AppleLanguages`), so iOS Settings › MimoDays › Language and this picker agree, and what iOS
/// draws for the app (permission prompts, the share sheet) follows from the next launch.
@Observable
public final class AppLanguage: @unchecked Sendable {
    public static let shared = AppLanguage(defaults: .standard)

    /// Every language MimoDays is translated into, English first.
    public static let supported = [
        "en", "de", "fr", "es", "it", "nl", "sv", "pl", "pt-BR", "ru", "uk", "be",
        "hy", "ka", "kk", "tr", "he", "ar", "ja", "ko", "zh-Hans", "zh-Hant",
    ]

    static let key = "AppleLanguages"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let state: OSAllocatedUnfairLock<String?>

    /// `domain` is where `defaults` keeps the app's own values (the bundle identifier for `.standard`), read
    /// directly so the device-wide language list doesn't count as a choice.
    public init(defaults: UserDefaults, domain: String? = Bundle.main.bundleIdentifier) {
        self.defaults = defaults
        let saved = domain.flatMap { defaults.persistentDomain(forName: $0)?[Self.key] as? [String] }?.first
        state = OSAllocatedUnfairLock(initialState: saved.flatMap(Self.match))
    }

    /// "pt-BR", "zh-Hans", "de" from what iOS stores ("pt-BR", "zh-Hans-CN", "de-DE").
    static func match(_ identifier: String) -> String? {
        // The match falls back to English for anything unknown, so the language itself has to agree.
        guard let best = Bundle.preferredLocalizations(from: supported, forPreferences: [identifier]).first else { return nil }
        return Locale(identifier: identifier).language.languageCode == Locale(identifier: best).language.languageCode ? best : nil
    }

    /// A language from `supported`, or nil to follow iOS.
    public var code: String? {
        get {
            access(keyPath: \.code)
            return state.withLock { $0 }
        }
        set {
            let code = newValue.flatMap { Self.supported.contains($0) ? $0 : nil }
            withMutation(keyPath: \.code) { state.withLock { $0 = code } }
            if let code {
                defaults.set([code], forKey: Self.key)
            } else {
                defaults.removeObject(forKey: Self.key)
            }
        }
    }

    /// The chosen language, or the best match for the device's languages.
    public var locale: Locale {
        Locale(identifier: code ?? Self.systemCode)
    }

    /// Right-to-left scripts (Hebrew, Arabic) flip the layout.
    public var isRightToLeft: Bool {
        locale.language.characterDirection == .rightToLeft
    }

    /// The supported language iOS would pick for this device.
    public static var systemCode: String {
        Bundle.preferredLocalizations(from: supported, forPreferences: Locale.preferredLanguages).first ?? "en"
    }

    /// A language's own name, e.g. "Deutsch", "日本語".
    public static func nativeName(_ code: String) -> String {
        let name = Locale(identifier: code).localizedString(forIdentifier: code) ?? code
        return name.prefix(1).uppercased(with: Locale(identifier: code)) + name.dropFirst()
    }
}
