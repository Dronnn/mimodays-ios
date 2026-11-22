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
    public static let shared = AppLanguage(
        defaults: .standard, current: { UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?[key] as? [String] }
    )

    /// Every language MimoDays is translated into, English first.
    public static let supported = [
        "en", "de", "fr", "es", "it", "nl", "sv", "pl", "pt-BR", "ru", "uk", "be",
        "hy", "ka", "kk", "tr", "he", "ar", "ja", "ko", "zh-Hans", "zh-Hant",
    ]

    static let key = "AppleLanguages"
    /// The iPhone's own languages, remembered while MimoDays follows them.
    static let deviceKey = "deviceLanguages"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let state: OSAllocatedUnfairLock<String?>
    @ObservationIgnored private let device: [String]
    /// The iPhone's languages as they are now, from the device-wide settings, which a choice made in MimoDays doesn't
    /// cover; nil where they can't be read.
    @ObservationIgnored private let current: @Sendable () -> [String]?

    /// `domain` is where `defaults` keeps the app's own values (the bundle identifier for `.standard`), read
    /// directly so the device-wide language list doesn't count as a choice. `preferred` is what iOS gives this
    /// process: the iPhone's languages, or the app's own choice first once there is one, kept until the next launch.
    public init(
        defaults: UserDefaults, domain: String? = Bundle.main.bundleIdentifier, preferred: [String] = Locale.preferredLanguages,
        current: @escaping @Sendable () -> [String]? = { nil }
    ) {
        self.defaults = defaults
        self.current = current
        let saved = domain.flatMap { defaults.persistentDomain(forName: $0)?[Self.key] as? [String] }
        if saved == nil {
            defaults.set(preferred, forKey: Self.deviceKey)
            device = preferred
        } else {
            device = defaults.stringArray(forKey: Self.deviceKey) ?? preferred
        }
        state = OSAllocatedUnfairLock(initialState: saved?.first.flatMap(Self.match))
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
        Locale(identifier: code ?? systemCode)
    }

    /// Right-to-left scripts (Hebrew, Arabic) flip the layout.
    public var isRightToLeft: Bool {
        locale.language.characterDirection == .rightToLeft
    }

    /// The supported language iOS would pick for the iPhone's languages. With a choice made, iOS reports that choice
    /// as the iPhone's too, so the list remembered while following them is used (Same as iPhone stayed Hebrew
    /// after a switch back, 2026-11-17).
    public var systemCode: String {
        Bundle.preferredLocalizations(from: Self.supported, forPreferences: deviceLanguages).first ?? "en"
    }

    /// A language changed on the iPhone while MimoDays had its own is seen at once (rev-app 18); the list remembered
    /// at launch when the device-wide one can't be read.
    private var deviceLanguages: [String] {
        current().flatMap { $0.isEmpty ? nil : $0 } ?? device
    }

    /// A language's own name, e.g. "Deutsch", "日本語".
    public static func nativeName(_ code: String) -> String {
        let name = Locale(identifier: code).localizedString(forIdentifier: code) ?? code
        return name.prefix(1).uppercased(with: Locale(identifier: code)) + name.dropFirst()
    }
}
