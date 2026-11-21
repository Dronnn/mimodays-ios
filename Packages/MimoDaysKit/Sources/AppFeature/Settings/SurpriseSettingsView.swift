import Core
import DesignSystem
import Persistence
import SwiftUI

/// S02: whether surprises come, how often, on which days, between which times, how long one stays open, and a pause.
/// Every change is saved at once.
struct SurpriseSettingsView: View {
    @Bindable var model: SettingsModel
    @State private var pausing = false
    @State private var sentNow = false
    @State private var asker = PermissionAsker()
    @State private var picksFallbackTime = false
    @Environment(\.permissions) private var permissions
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

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
                    fallbackCard
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                    fallbackNote
                        .padding(.horizontal, 22)
                        .padding(.top, 10)
                    DataCard {
                        Button { pausing = true } label: {
                            SettingsValueRow(title: Text("Pause surprises", bundle: .module), value: pauseValue)
                        }
                        .disabled(!model.surprisesOn)
                        .accessibilityIdentifier("surprises.pause")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    DataCard {
                        Button { Task { sentNow = await model.sendSurpriseNow() } } label: {
                            SettingsValueRow(title: Text("Send a surprise now", bundle: .module, comment: "Surprises settings (S02): sends one surprise in a few seconds, to see how it works"), value: Text(verbatim: ""))
                        }
                        .disabled(!model.surprisesOn || notificationsBlocked)
                        .accessibilityIdentifier("surprises.sendNow")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    DataNote(text: sentNow
                        ? Text("On its way. It arrives in a few seconds, like any other surprise.", bundle: .module, comment: "Surprises settings (S02): after Send a surprise now")
                        : Text("See how it works: a surprise arrives in a few seconds. Tap it and the camera opens.", bundle: .module, comment: "Surprises settings (S02): under Send a surprise now"))
                        .padding(.horizontal, 22)
                        .padding(.top, 10)
                    if model.surprisesOn, notificationsBlocked {
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
        .permissionExplainers(asker)
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

    private var notificationsBlocked: Bool {
        model.notifications == .denied || model.notifications == .restricted
    }

    private var surprisesOn: Binding<Bool> {
        Binding { model.surprisesOn } set: { isOn in Task { await model.setSurprises(isOn) { await asker.request($0, using: permissions) } } }
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
            SettingsValueRow(title: Text("Time to catch it", bundle: .module), value: Text(Self.minutes(model.expiryMinutes)))
        }
        .accessibilityIdentifier("surprises.expiry")
    }

    // MARK: Fallback reminder (P8.14, §V16 KK01-KK05)

    private var fallbackCard: some View {
        DataCard {
            DataToggleRow(
                title: Text("Fallback reminder", bundle: .module, comment: "Surprises settings (P8.14 KK01): a reminder at a fixed time on days with no surprise"),
                isOn: Binding { model.fallback.isOn } set: { isOn in
                    if !isOn { picksFallbackTime = false }
                    Task { await model.setFallback(isOn: isOn) }
                }
            )
            .accessibilityIdentifier("surprises.fallback")
            if model.fallback.isOn {
                DataSeparator()
                fallbackTimeRow
            }
        }
    }

    @ViewBuilder
    private var fallbackTimeRow: some View {
        Button {
            withAnimation(.snappy) { picksFallbackTime.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text("Reminder time", bundle: .module, comment: "Surprises settings (P8.14 KK01): when the fallback reminder comes")
                    .textStyle(.rowTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                Spacer(minLength: 8)
                Text(verbatim: ReminderSchedule.time(model.fallbackMinute, calendar: calendar, locale: locale))
                    .textStyle(.rowDetail)
                    .foregroundStyle(model.fallbackOutsideHours ? ColorToken.textDestructive.color : ColorToken.textTertiary.color)
                Icon.glyphChevron.image
                    .resizable()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(model.fallbackOutsideHours ? ColorToken.textDestructive.color : ColorToken.textPrimary.color)
                    .rotationEffect(.degrees(picksFallbackTime ? 90 : 0))
                    .flipsForRightToLeftLayoutDirection(true)
                    .accessibilityHidden(true)
            }
            .padding(.leading, 16)
            .padding(.trailing, 14)
            .frame(minHeight: Size.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picksFallbackTime ? .isSelected : [])
        .accessibilityIdentifier("surprises.fallbackTime")
        if picksFallbackTime {
            DatePicker(selection: Binding {
                ReminderSchedule.date(model.fallbackMinute, calendar: calendar)
            } set: { date in
                let minute = ReminderSchedule.minute(of: date, calendar: calendar)
                Task { await model.setFallbackMinute(minute) }
            }, displayedComponents: .hourAndMinute) {
                Text("Reminder time", bundle: .module)
            }
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
        }
    }

    /// What the reminder does, or why it can't: couldn't be set, outside the hours, surprises off (KK05).
    @ViewBuilder
    private var fallbackNote: some View {
        if model.fallback.isOn, model.fallbackFailed {
            VStack(alignment: .leading, spacing: 6) {
                Text("Couldn't set the fallback reminder.", bundle: .module, comment: "Surprises settings (P8.14 KK05): iOS didn't take the reminder")
                    .textStyle(.meta)
                    .foregroundStyle(ColorToken.textDestructive.color)
                    .fixedSize(horizontal: false, vertical: true)
                Button { Task { await model.retryFallback() } } label: {
                    Text("Try again", bundle: .module).textStyle(.rowTitle).foregroundStyle(ColorToken.textLink.color)
                }
                .frame(minHeight: Size.minimumTapTarget)
                .accessibilityIdentifier("surprises.fallbackRetry")
            }
        } else if model.fallbackOutsideHours {
            let earliest = ReminderSchedule.time(model.reminders.earliestMinute, calendar: calendar, locale: locale)
            let latest = ReminderSchedule.time(model.reminders.latestMinute, calendar: calendar, locale: locale)
            Text("Choose a time inside your surprise hours (\(earliest) - \(latest)).", bundle: .module, comment: "Surprises settings (P8.14 KK03): the reminder time is outside Not before - Not after; the two times")
                .textStyle(.meta)
                .foregroundStyle(ColorToken.textDestructive.color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if model.fallback.isOn, !model.surprisesOn {
            DataNote(text: Text("Turn on surprises to use a fallback reminder.", bundle: .module, comment: "Surprises settings (P8.14 KK05): the reminder is kept but waits while surprises are off"))
        } else {
            DataNote(text: Text("A reminder at this time on days with no scheduled surprise.", bundle: .module, comment: "Surprises settings (P8.14 KK01/KK02): under Fallback reminder"))
        }
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
            let day = days < 7 ? date.formatted(.dateTime.weekday(.wide).locale(AppLanguage.shared.locale)) : date.formatted(.dateTime.month(.abbreviated).day().locale(AppLanguage.shared.locale))
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
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated).locale(AppLanguage.shared.locale))
    }
}
