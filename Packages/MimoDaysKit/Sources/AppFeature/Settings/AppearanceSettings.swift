import Foundation
import Persistence
import SwiftUI
import UIKit

/// S04: light, dark or as iOS is set, and the higher-contrast colours.
struct AppearanceSettings: Codable, Equatable, Sendable {
    var appearance = AppearancePreference.system
    /// The colours' high-contrast variants even when iOS's Increase Contrast is off.
    var higherContrast = false
    /// H.9: which screens' video tiles play on their own.
    var motion = MotionSettings()

    init() {}

    /// Settings saved by an earlier version lack the newer keys; those keep their defaults.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appearance = try container.decodeIfPresent(AppearancePreference.self, forKey: .appearance) ?? appearance
        higherContrast = try container.decodeIfPresent(Bool.self, forKey: .higherContrast) ?? higherContrast
        motion = try container.decodeIfPresent(MotionSettings.self, forKey: .motion) ?? motion
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch appearance {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
}

typealias AppearancePreferences = DevicePreference<AppearanceSettings>

extension DevicePreference<AppearanceSettings> {
    static func appearance(_ defaults: UserDefaults?) -> AppearancePreferences {
        AppearancePreferences(key: "appearanceSettings", defaults: defaults, initial: AppearanceSettings())
    }
}

/// Puts S04's choice on every window of the scene, so sheets and the lock screen follow it too.
struct WindowAppearance: UIViewRepresentable {
    let settings: AppearanceSettings

    func makeUIView(context: Context) -> Anchor { Anchor() }

    func updateUIView(_ view: Anchor, context: Context) {
        view.settings = settings
    }

    final class Anchor: UIView {
        var settings = AppearanceSettings() {
            didSet { apply() }
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        private func apply() {
            for window in window?.windowScene?.windows ?? [] {
                Self.apply(settings, to: window)
            }
        }

        static func apply(_ settings: AppearanceSettings, to window: UIWindow) {
            window.overrideUserInterfaceStyle = settings.interfaceStyle
            if settings.higherContrast {
                window.traitOverrides.accessibilityContrast = .high
            } else if window.traitOverrides.contains(UITraitAccessibilityContrast.self) {
                window.traitOverrides.remove(UITraitAccessibilityContrast.self)
            }
        }
    }
}
