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
        let direction: LayoutDirection = language.isRightToLeft ? .rightToLeft : .leftToRight
        content
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, direction)
            .background(SceneLayoutDirection(direction: direction))
    }
}

/// Sheets and full-screen covers take their layout direction from UIKit's traits, not from the environment above
/// them (Settings stayed left to right after a switch to Hebrew, 2026-11-17). The scene's trait override reaches every
/// window and presented screen, at once.
private struct SceneLayoutDirection: UIViewRepresentable {
    let direction: LayoutDirection

    func makeUIView(context: Context) -> Probe { Probe() }

    func updateUIView(_ view: Probe, context: Context) {
        view.direction = direction == .rightToLeft ? .rightToLeft : .leftToRight
    }

    final class Probe: UIView {
        var direction = UITraitEnvironmentLayoutDirection.leftToRight {
            didSet { apply() }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        private func apply() {
            guard let scene = window?.windowScene, scene.traitCollection.layoutDirection != direction else { return }
            scene.traitOverrides.layoutDirection = direction
        }
    }
}
