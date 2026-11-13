import DesignSystem
import SwiftUI

/// O08b (reminders on) and O08c (off, after Don't Allow or Maybe later). Never a dead end.
struct RemindersResultView: View {
    let outcome: RemindersOutcome
    let schedule: ReminderSchedule
    let next: () -> Void
    let openSettings: () -> Void
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ExplainerArt(glyph: isOn ? .explainerSparkle : .explainerBell, blob: isOn ? .accentMint : .surfaceChip)
                    .padding(.top, 138)
                Text(title)
                    .textStyle(.displaySheet)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 30)
                Text(message)
                    .textStyle(.body)
                    .foregroundStyle(ColorToken.textSecondary.color)
                    .padding(.top, 12)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 36)
            .frame(maxWidth: 402)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                Button(action: next) { Text(LocalizedStringResource("Continue", bundle: .atURL(Bundle.module.bundleURL))) }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("reminders.continue")
                if outcome == .denied {
                    Button(action: openSettings) { Text(LocalizedStringResource("Open iOS Settings", bundle: .atURL(Bundle.module.bundleURL))) }
                        .buttonStyle(.text)
                        .accessibilityIdentifier("reminders.openSettings")
                }
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, 12)
            .padding(.bottom, outcome == .denied ? 30 : 18)
            .frame(maxWidth: 402)
            .frame(maxWidth: .infinity)
            .background(ColorToken.canvas.color.ignoresSafeArea(edges: .bottom))
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
    }

    private var isOn: Bool { outcome == .on }

    private var title: LocalizedStringResource {
        isOn
            ? LocalizedStringResource("Your first surprise is on its way.", bundle: .atURL(Bundle.module.bundleURL))
            : LocalizedStringResource("No reminders for now. That's okay.", bundle: .atURL(Bundle.module.bundleURL))
    }

    private var message: LocalizedStringResource {
        isOn
            ? schedule.summary(calendar: calendar, locale: locale)
            : LocalizedStringResource(
                "You can still capture moments whenever you like. To get surprises later, turn on notifications for MimoDays in Settings.",
                bundle: .atURL(Bundle.module.bundleURL)
            )
    }
}
