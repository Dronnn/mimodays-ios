import DesignSystem
import OSLog
import SwiftUI

/// S09 with the app's preferences.
struct MemoriesSettingsScreen: View {
    @Environment(MemoriesPreferences.self) private var preferences: MemoriesPreferences?
    @Environment(\.mediaLibrary) private var library

    var body: some View {
        if let preferences {
            @Bindable var preferences = preferences
            MemoriesSettingsView(settings: $preferences.value) { days in
                guard let library else { return 0 }
                do {
                    return try MomentDays.newlyHidden(library.context, days: days)
                } catch {
                    Logger(subsystem: "MimoDays", category: "Settings").error("Counting hidden days' moments failed: \(error.localizedDescription, privacy: .public)")
                    return 0
                }
            }
        }
    }
}

/// S09: how Memories opens and sorts, On this day on Today, and which time zone decides a moment's day.
struct MemoriesSettingsView: View {
    @Binding var settings: MemoriesSettings
    /// P8.3: moments the choice would newly put under a hidden day; asked about first.
    var newlyHidden: (MemoriesSettings.Days) -> Int = { _ in 0 }
    @State private var pending: (days: MemoriesSettings.Days, count: Int)?
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
        .alert(
            Text("Hidden days will cover more", bundle: .module),
            isPresented: Binding { pending != nil } set: { if !$0 { pending = nil } },
            presenting: pending
        ) { pending in
            Button { settings.days = pending.days } label: { Text("Change days", bundle: .module) }
            Button(role: .cancel) {} label: { Text("Cancel", bundle: .module) }
        } message: { pending in
            Text("With this choice \(Text("\(pending.count) moments", bundle: .module)) fall on a day you hid, so they leave On this day, widgets and automatic movies too. They stay in the archive.", bundle: .module)
        }
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
            guard !isSelected else { return }
            let count = newlyHidden(days)
            if count > 0 { pending = (days, count) } else { settings.days = days }
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
