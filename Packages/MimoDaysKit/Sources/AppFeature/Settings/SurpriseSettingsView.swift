import Core
import DesignSystem
import Persistence
import SwiftUI

/// S02: whether surprises come, how often, on which days, between which times, how long one stays open, and a pause.
/// Every change is saved at once.
struct SurpriseSettingsView: View {
    @Bindable var model: SettingsModel
    @State private var pausing = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.calendar) private var calendar

    var body: some View {
        VStack(spacing: 0) {
            BackTitleBar(back: Text("Settings", bundle: .module), title: Text("Surprises", bundle: .module)) { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DataCard {
                        DataToggleRow(title: Text("Surprise me", bundle: .module), isOn: surprisesOn)
                            .accessibilityIdentifier("surprises.toggle")
                    }
                    .padding(.horizontal, 16)
                    DataNote(text: Text("At a random time, MimoDays invites you to capture what is happening. The exact time is always a surprise.", bundle: .module))
                        .padding(.horizontal, 22)
                        .padding(.top, 10)
                    sectionLabel(Text("How often", bundle: .module))
                        .padding(.top, 22)
                    SegmentedControl(selection: $model.reminders.frequency, options: SurpriseFrequency.allCases) { Text($0.label) }
                        .padding(.top, 6)
                        .padding(.horizontal, 20)
                    sectionLabel(Text("On these days", bundle: .module))
                        .padding(.top, 18)
                    WeekdayPicker(schedule: $model.reminders)
                        .padding(.top, 6)
                        .padding(.leading, 18)
                    DataCard {
                        TimeWindowCard(schedule: $model.reminders, inSettings: true)
                        DataSeparator()
                        expiryRow
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    DataCard {
                        Button { pausing = true } label: {
                            valueRow(Text("Pause surprises", bundle: .module), value: pauseValue)
                        }
                        .disabled(!model.surprisesOn)
                        .accessibilityIdentifier("surprises.pause")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    if model.surprisesOn, model.notifications == .denied || model.notifications == .restricted {
                        notificationsOff
                            .padding(.horizontal, 22)
                            .padding(.top, 12)
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .confirmationDialog(Text("Pause surprises", bundle: .module), isPresented: $pausing, titleVisibility: .visible) {
            Button { Task { await model.pause(.today) } } label: { Text("For today", bundle: .module) }
            Button { Task { await model.pause(.week) } } label: { Text("For a week", bundle: .module) }
            Button { Task { await model.pause(.indefinitely) } } label: { Text("Until I resume them", bundle: .module) }
            if model.pause != .off {
                Button { Task { await model.resume() } } label: { Text("Resume now", bundle: .module) }
            }
        } message: {
            Text("No surprises come while paused, and none are sent later for the time missed.", bundle: .module)
        }
    }

    private var surprisesOn: Binding<Bool> {
        Binding { model.surprisesOn } set: { isOn in Task { await model.setSurprises(isOn) } }
    }

    /// "Time to catch it": how long a surprise stays open.
    private var expiryRow: some View {
        Menu {
            Picker(selection: $model.expiryMinutes) {
                ForEach(SettingsModel.expiryChoices, id: \.self) { Text(Self.minutes($0)).tag($0) }
            } label: {
                Text("Time to catch it", bundle: .module)
            }
        } label: {
            valueRow(Text("Time to catch it", bundle: .module), value: Text(Self.minutes(model.expiryMinutes)))
        }
        .accessibilityIdentifier("surprises.expiry")
    }

    private func valueRow(_ title: Text, value: Text) -> some View {
        HStack(spacing: 6) {
            title.textStyle(.rowTitle).foregroundStyle(ColorToken.textPrimary.color)
            Spacer(minLength: 8)
            value.textStyle(.rowDetail).foregroundStyle(ColorToken.textTertiary.color)
            DataChevron()
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .frame(minHeight: Size.rowHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func sectionLabel(_ text: Text) -> some View {
        text.textStyle(.labelCaps)
            .foregroundStyle(ColorToken.textSecondary.color)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 22)
    }

    /// "Off", "Until tomorrow", "Until Friday", "Until Nov 22" or "Until you resume".
    private var pauseValue: Text {
        switch model.pause {
        case .off: return Text("Off", bundle: .module)
        case .indefinitely: return Text("Until you resume", bundle: .module)
        case let .until(date):
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: date)).day ?? 0
            if days <= 1 { return Text("Until tomorrow", bundle: .module) }
            let day = days < 7 ? date.formatted(.dateTime.weekday(.wide)) : date.formatted(.dateTime.month(.abbreviated).day())
            return Text("Until \(day)", bundle: .module)
        }
    }

    /// Turned off in iOS Settings: surprises can't arrive, so say so and link there.
    private var notificationsOff: some View {
        VStack(alignment: .leading, spacing: 6) {
            DataNote(text: Text("Notifications for MimoDays are off in iOS Settings, so surprises can't reach you.", bundle: .module))
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                Text("Open iOS Settings", bundle: .module).textStyle(.rowTitle).foregroundStyle(ColorToken.textLink.color)
            }
            .frame(minHeight: Size.minimumTapTarget)
            .accessibilityIdentifier("surprises.openSettings")
        }
    }

    /// "15 min", "1 hr", in the person's language.
    static func minutes(_ minutes: Int) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}
