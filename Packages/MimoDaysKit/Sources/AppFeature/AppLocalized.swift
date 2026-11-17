import Core
import Foundation

extension String {
    /// `String(appLocalized:bundle:comment:)` in the language chosen in MimoDays (`AppLanguage`), which can change while
    /// the app runs; the system call keeps the language MimoDays launched in.
    init(appLocalized keyAndValue: String.LocalizationValue, bundle: Bundle, comment: StaticString? = nil) {
        self.init(appLocalized: LocalizedStringResource(keyAndValue, bundle: .atURL(bundle.bundleURL), comment: comment))
    }

    /// The key/default-value form of `init(appLocalized:bundle:comment:)`. The default is a plain `String`: as a
    /// localization value, Xcode's string extraction would add it to the catalog as a key of its own.
    init(appLocalized key: StaticString, defaultValue: String, bundle: Bundle, comment: StaticString? = nil) {
        self.init(appLocalized: LocalizedStringResource(key, defaultValue: String.LocalizationValue(defaultValue), bundle: .atURL(bundle.bundleURL), comment: comment))
    }

    /// A resource in the language chosen in MimoDays.
    init(appLocalized resource: LocalizedStringResource) {
        var resource = resource
        resource.locale = AppLanguage.shared.locale
        self.init(localized: resource)
    }
}
