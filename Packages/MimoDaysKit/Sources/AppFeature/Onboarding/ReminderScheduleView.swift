import DesignSystem
import Persistence
import SwiftUI

/// O07: how often and when surprises may come. It is also the rationale before the notification prompt.
struct ReminderScheduleView: View {
    @Binding var schedule: ReminderSchedule
    let back: () -> Void
    let enable: () -> Void
    let later: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BackButton(action: back)
                    .padding(.top, -8)
                Text(LocalizedStringResource("When should MimoDays surprise you?", bundle: .atURL(Bundle.module.bundleURL)))
                    .textStyle(.displaySheet)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 8)
                    .padding(.horizontal, 24)
                Text(LocalizedStringResource("Pick how often and when. The exact time is always a surprise.", bundle: .atURL(Bundle.module.bundleURL)))
                    .textStyle(.body)
                    .foregroundStyle(ColorToken.textSecondary.color)
                    .padding(.top, 12)
                    .padding(.horizontal, 24)
                sectionLabel(LocalizedStringResource("How often", bundle: .atURL(Bundle.module.bundleURL)))
                    .padding(.top, 24)
                SegmentedControl(selection: $schedule.frequency, options: SurpriseFrequency.allCases) { Text($0.label) }
                    .padding(.top, 6)
                    .padding(.horizontal, Spacing.screenMargin)
                sectionLabel(LocalizedStringResource("On these days", bundle: .atURL(Bundle.module.bundleURL)))
                    .padding(.top, 18)
                WeekdayPicker(schedule: $schedule)
                    .padding(.top, 6)
                    .padding(.leading, 18)
                TimeWindowCard(schedule: $schedule)
                    .padding(.top, 20)
                    .padding(.horizontal, Spacing.cardMargin)
                Text(LocalizedStringResource("Surprises only arrive between these times. Focus modes still apply.", bundle: .atURL(Bundle.module.bundleURL)))
                    .textStyle(.meta)
                    .foregroundStyle(ColorToken.textSecondary.color)
                    .padding(.top, 12)
                    .padding(.horizontal, 22)
            }
            .frame(maxWidth: 402, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                Button(action: enable) { Text(LocalizedStringResource("Enable reminders", bundle: .atURL(Bundle.module.bundleURL))) }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("reminders.enable")
                Button(action: later) { Text(LocalizedStringResource("Maybe later", bundle: .atURL(Bundle.module.bundleURL))) }
                    .buttonStyle(.text)
                    .accessibilityIdentifier("reminders.later")
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, 12)
            .padding(.bottom, 30)
            .frame(maxWidth: 402)
            .frame(maxWidth: .infinity)
            .background(ColorToken.canvas.color.ignoresSafeArea(edges: .bottom))
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
    }

    private func sectionLabel(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .textStyle(.labelCaps)
            .foregroundStyle(ColorToken.textSecondary.color)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 22)
    }
}

/// `Navigation / Back bar`: plum chevron, coral "Back".
struct BackButton: View {
    let action: () -> Void
    @ScaledMetric(relativeTo: .body) private var glyphSize = 24

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Icon.glyphBack.image
                    .resizable()
                    .frame(width: glyphSize, height: glyphSize)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .flipsForRightToLeftLayoutDirection(true)
                Text(LocalizedStringResource("Back", bundle: .atURL(Bundle.module.bundleURL)))
                    .textStyle(TextStyle(.nunito, size: 17, weight: 600, relativeTo: .body))
                    .foregroundStyle(ColorToken.textLink.color)
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .frame(minHeight: Size.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("back")
    }
}

/// `Weekday / On` and `Weekday / Off`, in the locale's week order.
struct WeekdayPicker: View {
    @Binding var schedule: ReminderSchedule
    @Environment(\.calendar) private var calendar

    var body: some View {
        HStack(spacing: 8) {
            ForEach(calendar.orderedWeekdays, id: \.self) { day in
                let isOn = schedule.isOn(day)
                Button {
                    schedule.toggle(day)
                } label: {
                    Text(verbatim: calendar.veryShortStandaloneWeekdaySymbols[day - 1])
                        .textStyle(TextStyle(.nunito, size: 16, weight: isOn ? 800 : 700, relativeTo: .body, maximumScale: 1.35))
                        .foregroundStyle((isOn ? ColorToken.textOnCoral : .textSecondary).color)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill((isOn ? ColorToken.actionCoral : .surfaceChip).color))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: calendar.standaloneWeekdaySymbols[day - 1]))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Earliest / Latest rows; tapping one opens a wheel picker inside the card.
struct TimeWindowCard: View {
    enum Bound { case earliest, latest }

    @Binding var schedule: ReminderSchedule
    @State private var open: Bound?
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 0) {
            row(.earliest)
            ColorToken.separator.color
                .frame(height: 1)
                .padding(.leading, 16)
            row(.latest)
        }
        .background(ColorToken.surfaceCard.color, in: RoundedRectangle(cornerRadius: Radius.card))
    }

    @ViewBuilder
    private func row(_ bound: Bound) -> some View {
        let isOpen = open == bound
        Button {
            withAnimation(.snappy) { open = isOpen ? nil : bound }
        } label: {
            HStack(spacing: 6) {
                Text(title(bound))
                    .textStyle(.rowTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                Spacer(minLength: 8)
                Text(verbatim: ReminderSchedule.time(minute(bound), calendar: calendar, locale: locale))
                    .textStyle(.rowDetail)
                    .foregroundStyle(ColorToken.textTertiary.color)
                Icon.glyphChevron.image
                    .resizable()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .flipsForRightToLeftLayoutDirection(true)
                    .accessibilityHidden(true)
            }
            .padding(.leading, 16)
            .padding(.trailing, 14)
            .frame(minHeight: Size.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOpen ? .isSelected : [])
        if isOpen {
            DatePicker(selection: binding(bound), in: range(bound), displayedComponents: .hourAndMinute) {
                Text(title(bound))
            }
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
        }
    }

    private func title(_ bound: Bound) -> LocalizedStringResource {
        switch bound {
        case .earliest: LocalizedStringResource("Earliest", bundle: .atURL(Bundle.module.bundleURL))
        case .latest: LocalizedStringResource("Latest", bundle: .atURL(Bundle.module.bundleURL))
        }
    }

    private func minute(_ bound: Bound) -> Int {
        bound == .earliest ? schedule.earliestMinute : schedule.latestMinute
    }

    private func range(_ bound: Bound) -> ClosedRange<Date> {
        let minutes = bound == .earliest ? schedule.earliestRange : schedule.latestRange
        return ReminderSchedule.date(minutes.lowerBound, calendar: calendar)...ReminderSchedule.date(minutes.upperBound, calendar: calendar)
    }

    private func binding(_ bound: Bound) -> Binding<Date> {
        Binding {
            ReminderSchedule.date(minute(bound), calendar: calendar)
        } set: { date in
            let value = ReminderSchedule.minute(of: date, calendar: calendar)
            if bound == .earliest { schedule.setEarliest(value) } else { schedule.setLatest(value) }
        }
    }
}
