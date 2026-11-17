import Core
import DesignSystem
import Persistence
import SwiftUI
import UIKit

/// S04 with the app's preferences.
struct AppearanceSettingsScreen: View {
    @Environment(AppearancePreferences.self) private var preferences: AppearancePreferences?

    var body: some View {
        if let preferences {
            @Bindable var preferences = preferences
            AppearanceSettingsView(settings: $preferences.value, language: AppLanguage.nativeName(AppLanguage.shared.locale.identifier))
        }
    }
}

/// S04: Light, Dark or System, higher contrast, and the language.
struct AppearanceSettingsView: View {
    @Binding var settings: AppearanceSettings
    let language: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            BackTitleBar(back: Text("Settings", bundle: .module), title: Text("Appearance", bundle: .module)) { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(AppearancePreference.displayOrder, id: \.self) { appearance in
                            ThemeChoice(appearance: appearance, isSelected: settings.appearance == appearance) {
                                settings.appearance = appearance
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 14)
                    DataCard {
                        DataToggleRow(title: Text("Higher contrast", bundle: .module), isOn: $settings.higherContrast)
                            .accessibilityIdentifier("appearanceSettings.contrast")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    DataNote(text: Text("Text size follows iOS Settings › Display & Brightness.", bundle: .module))
                        .padding(.horizontal, 22)
                        .padding(.top, 12)
                    motion
                        .padding(.top, 26)
                    DataCard {
                        NavigationLink(value: SettingsRoute.language) {
                            SettingsValueRow(title: Text("Language", bundle: .module), value: Text(verbatim: language))
                        }
                        .accessibilityIdentifier("appearanceSettings.language")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 26)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
    }
}

extension AppearanceSettingsView {
    /// H.9: a switch per screen for the videos that play in its tiles.
    var motion: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Motion", bundle: .module, comment: "Settings › Appearance (H.9): section title over the switches for videos playing in tiles")
                .textStyle(.labelCaps)
                .foregroundStyle(ColorToken.textSecondary.color)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 22)
                .padding(.bottom, 8)
            DataCard {
                ForEach(Array(MotionScreen.allCases.enumerated()), id: \.offset) { index, screen in
                    if index > 0 { DataSeparator() }
                    DataToggleRow(title: screen.title, isOn: $settings.motion[screen])
                        .accessibilityIdentifier("appearanceSettings.motion.\(index)")
                }
            }
            .padding(.horizontal, 16)
            DataNote(text: Text(
                "Videos play in their tiles, four at a time, without sound - never in Low Power Mode or with Reduce Motion. Touch and hold a video to play it larger.",
                bundle: .module, comment: "Settings › Appearance (H.9): the note under the Motion switches"
            ))
            .padding(.horizontal, 22)
            .padding(.top, 12)
        }
    }
}

/// One of S04's three phones and its name.
private struct ThemeChoice: View {
    let appearance: AppearancePreference
    let isSelected: Bool
    let action: () -> Void

    /// The phones show the themes themselves, so their colours don't follow the current one.
    private static let lightScreen = Color(red: 0xFB / 255, green: 0xF6 / 255, blue: 0xEF / 255)
    private static let darkScreen = Color(red: 0x2A / 255, green: 0x1B / 255, blue: 0x21 / 255)
    private static let plum = Color(red: 0x4B / 255, green: 0x29 / 255, blue: 0x38 / 255)
    private static let lightPhoto = Color(red: 0xC9 / 255, green: 0xB8 / 255, blue: 0xAA / 255)
    private static let darkPhoto = Color(red: 0x6E / 255, green: 0x58 / 255, blue: 0x50 / 255)
    private static let frame = Color(red: 0xD9 / 255, green: 0xC9 / 255, blue: 0xBC / 255)

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                phone
                title
                    .textStyle(TextStyle(.nunito, size: 14, weight: isSelected ? 800 : 600, relativeTo: .subheadline))
                    .foregroundStyle((isSelected ? ColorToken.textLink : ColorToken.textPrimary).color)
            }
            .padding(.top, 4)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("appearanceSettings.\(appearance.rawValue)")
    }

    private var title: Text {
        switch appearance {
        case .light: Text("Light", bundle: .module)
        case .dark: Text("Dark", bundle: .module)
        case .system: Text("System", bundle: .module)
        }
    }

    private var phone: some View {
        let isDark = appearance == .dark
        let ink = isDark ? Self.lightScreen : Self.plum
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(ink).frame(width: 34, height: 6)
            Capsule().fill(ink.opacity(0.5)).frame(width: 46, height: 4).padding(.top, 6)
            RoundedRectangle(cornerRadius: 3).fill(isDark ? Self.darkPhoto : Self.lightPhoto).frame(width: 54, height: 40).padding(.top, 12)
            Capsule().fill(ink.opacity(0.5)).frame(width: 46, height: 4).padding(.top, 4)
        }
        .padding(.top, 36)
        .padding(.leading, 8)
        .frame(width: 70, height: 128, alignment: .topLeading)
        .background {
            ZStack(alignment: .trailing) {
                isDark ? Self.darkScreen : Self.lightScreen
                if appearance == .system { Self.darkScreen.frame(width: 35) }
            }
            .clipShape(shape)
        }
        .overlay { shape.strokeBorder(isSelected ? ColorToken.actionCoral.color : Self.frame, lineWidth: isSelected ? 3 : 1.5) }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }
}

extension AppearancePreference {
    /// S04's order: Light, Dark, System.
    static let displayOrder: [AppearancePreference] = [.light, .dark, .system]
}
