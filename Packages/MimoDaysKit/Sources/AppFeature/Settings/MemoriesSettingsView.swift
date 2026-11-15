import DesignSystem
import SwiftUI

/// S09 with the app's preferences.
struct MemoriesSettingsScreen: View {
    @Environment(MemoriesPreferences.self) private var preferences: MemoriesPreferences?

    var body: some View {
        if let preferences {
            @Bindable var preferences = preferences
            MemoriesSettingsView(settings: $preferences.value)
        }
    }
}

/// S09: how Memories opens and sorts, On this day on Today, and which time zone decides a moment's day.
struct MemoriesSettingsView: View {
    @Binding var settings: MemoriesSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            BackTitleBar(back: Text("Settings", bundle: .module), title: Text("Memories", bundle: .module)) { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionLabel(Text("Memories opens in", bundle: .module))
                    SegmentedControl(selection: $settings.opensIn, options: MemoriesSettings.Mode.allCases) { mode in
                        switch mode {
                        case .timeline: Text("Timeline", bundle: .module)
                        case .calendar: Text("Calendar", bundle: .module)
                        }
                    }
                    .padding(.top, 6)
                    .padding(.horizontal, 20)
                    .accessibilityIdentifier("memoriesSettings.opensIn")
                    DataCard {
                        DataToggleRow(title: Text("Newest first", bundle: .module), isOn: $settings.newestFirst)
                            .accessibilityIdentifier("memoriesSettings.newestFirst")
                        DataSeparator()
                        DataToggleRow(title: Text("On this day on Today", bundle: .module), isOn: $settings.onThisDayOnToday)
                            .accessibilityIdentifier("memoriesSettings.onThisDay")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    sectionLabel(Text("Time zones", bundle: .module))
                        .padding(.top, 26)
                    DataCard {
                        choice(Text("Days follow where you were", bundle: .module), .whereTaken, id: "memoriesSettings.whereTaken")
                        DataSeparator()
                        choice(Text("Days follow this iPhone's time zone", bundle: .module), .thisIPhone, id: "memoriesSettings.thisIPhone")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    DataNote(text: note)
                        .padding(.horizontal, 22)
                        .padding(.top, 12)
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
    }

    private func sectionLabel(_ text: Text) -> some View {
        text.textStyle(.labelCaps)
            .foregroundStyle(ColorToken.textSecondary.color)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 22)
    }

    private func choice(_ title: Text, _ days: MemoriesSettings.Days, id: String) -> some View {
        let isSelected = settings.days == days
        return Button {
            settings.days = days
        } label: {
            HStack(spacing: 8) {
                title.textStyle(.rowTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if isSelected {
                    Icon.glyphCheck.image
                        .resizable()
                        .frame(width: 22, height: 22)
                        .foregroundStyle(ColorToken.textLink.color)
                        .accessibilityHidden(true)
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 16)
            .padding(.vertical, 8)
            .frame(minHeight: Size.rowHeight)
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    /// What the chosen way means, by example.
    private var note: Text {
        switch settings.days {
        case .whereTaken: Text("A photo taken at 11 PM in New York stays on that day, even if you are in Tbilisi now.", bundle: .module)
        case .thisIPhone: Text("Days and times follow wherever this iPhone is now, so a photo taken late in the evening can move to the next day.", bundle: .module)
        }
    }
}
