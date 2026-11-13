import DesignSystem
import SwiftUI

/// O09: an invitation to try the camera, with a way out.
struct FirstCaptureView: View {
    let capture: () -> Void
    let later: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ArtCanvas(layers: Self.artLayers)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.top, 50)
                Text(LocalizedStringResource("Ready for your first little moment?", bundle: .atURL(Bundle.module.bundleURL)))
                    .textStyle(.displayHeadline)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 26)
                    .padding(.horizontal, 24)
                Text(LocalizedStringResource("Try the camera. Save the photo or video only if you like it.", bundle: .atURL(Bundle.module.bundleURL)))
                    .textStyle(.body)
                    .foregroundStyle(ColorToken.textSecondary.color)
                    .padding(.top, 14)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: 402, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                Button(action: capture) {
                    HStack(spacing: 8) {
                        Icon.glyphCamera.image
                            .resizable()
                            .frame(width: 24, height: 24)
                            .accessibilityHidden(true)
                        Text(LocalizedStringResource("Capture my first moment", bundle: .atURL(Bundle.module.bundleURL)))
                    }
                }
                .buttonStyle(.primary)
                .accessibilityIdentifier("firstCapture.capture")
                Button(action: later) { Text(LocalizedStringResource("I'll do it later", bundle: .atURL(Bundle.module.bundleURL))) }
                    .buttonStyle(.text)
                    .accessibilityIdentifier("firstCapture.later")
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

    /// The OB-03 dual-camera art with its own caption (`Onboarding / Art / Dual camera` in O09).
    nonisolated static var artLayers: [ArtLayer] {
        OnboardingPage.dualCamera.artLayers.map { layer in
            guard case let .text(.localized(resource), style, color, _, rotation) = layer, resource.key == "the world around you" else {
                return layer
            }
            return .text(
                .localized(LocalizedStringResource("whatever is in front of you", bundle: .atURL(Bundle.module.bundleURL))),
                style, color, center: CGPoint(x: 109.5, y: 300.5), rotation: rotation
            )
        }
    }
}

/// O10: the first saved moment, then on to the app.
struct FirstMomentView: View {
    let moment: SavedMoment
    let viewMoments: () -> Void
    let done: () -> Void
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                MomentHero(photo: moment.photo, selfie: moment.selfie, caption: Text(caption))
                    .overlay(alignment: .topLeading) {
                        mark(.markStarSolo, width: 39.2, height: 40.4).offset(x: 5, y: -28)
                    }
                    .overlay(alignment: .topTrailing) {
                        mark(.markTicksA, width: 26.7, height: 22.5).offset(x: -6.7, y: -26)
                    }
                    .environment(\.layoutDirection, .leftToRight)
                    .padding(.top, 68)
                    .padding(.horizontal, 13)
                Text(LocalizedStringResource("Your first moment is here.", bundle: .atURL(Bundle.module.bundleURL)))
                    .textStyle(.displaySheet)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 36)
                    .padding(.horizontal, 18)
                Text(LocalizedStringResource("It lives on this iPhone. Come back tomorrow, or whenever a surprise arrives.", bundle: .atURL(Bundle.module.bundleURL)))
                    .textStyle(.body)
                    .foregroundStyle(ColorToken.textSecondary.color)
                    .padding(.top, 12)
                    // 320 in the design; Penpot measures Nunito slightly wider, so 46 keeps its line breaks.
                    .padding(.horizontal, 46)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 402)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                Button(action: viewMoments) { Text(LocalizedStringResource("View my moments", bundle: .atURL(Bundle.module.bundleURL))) }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("firstMoment.view")
                Button(action: done) { Text(LocalizedStringResource("Done", bundle: .atURL(Bundle.module.bundleURL))) }
                    .buttonStyle(.text)
                    .accessibilityIdentifier("firstMoment.done")
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

    /// "Today, 4:12 PM": the moment was saved a moment ago.
    private var caption: LocalizedStringResource {
        var style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar)
        style.timeZone = calendar.timeZone
        let time = moment.capturedAt.formatted(style)
        var resource = LocalizedStringResource("Today, \(time)", bundle: .atURL(Bundle.module.bundleURL))
        resource.locale = locale
        return resource
    }

    private func mark(_ icon: Icon, width: CGFloat, height: CGFloat) -> some View {
        icon.image
            .resizable()
            .frame(width: width, height: height)
            .foregroundStyle(ColorToken.accentApricot.color)
            .accessibilityHidden(true)
    }
}
