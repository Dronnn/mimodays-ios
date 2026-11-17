import Core
import SwiftUI

extension View {
    /// The language chosen in MimoDays, for everything under this view: its words, dates and numbers, and the
    /// direction of its layout. Reads `AppLanguage.shared`, so a switch redraws at once.
    func appLanguage() -> some View {
        modifier(AppLanguageEnvironment())
    }
}

private struct AppLanguageEnvironment: ViewModifier {
    func body(content: Content) -> some View {
        let language = AppLanguage.shared
        content
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
    }
}
