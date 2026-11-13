import DesignSystem
import SwiftUI

/// OB-01 to OB-06: swipeable pages with progress dots and Skip. `onFinish` leads to reminder setup.
struct OnboardingIntroView: View {
    @Binding var page: OnboardingPage
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            TabView(selection: $page) {
                ForEach(OnboardingPage.allCases) { page in
                    OnboardingPageView(page: page) { advance(from: page) }
                        .tag(page)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
    }

    private var header: some View {
        HStack {
            ProgressDots(count: OnboardingPage.allCases.count, current: page.rawValue)
            Spacer()
            if page.canSkip {
                Button(action: onFinish) {
                    Text("Skip", bundle: .module)
                        .textStyle(TextStyle(.nunito, size: 17, weight: 700, relativeTo: .body))
                        .foregroundStyle(ColorToken.textLink.color)
                        .frame(minWidth: Size.minimumTapTarget, minHeight: Size.minimumTapTarget, alignment: .trailing)
                }
                .accessibilityIdentifier("onboarding.skip")
            }
        }
        .frame(minHeight: Size.minimumTapTarget)
        .padding(.leading, 24)
        .padding(.trailing, Spacing.screenMargin)
        .padding(.top, -10)
    }

    private func advance(from current: OnboardingPage) {
        if let next = current.next {
            withAnimation { page = next }
        } else {
            onFinish()
        }
    }
}

/// One page: art, headline, body; the button stays at the bottom.
struct OnboardingPageView: View {
    let page: OnboardingPage
    let action: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ArtCanvas(layers: page.artLayers)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.top, 16)
                Text(page.title)
                    .textStyle(.displayHeadline)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 26)
                    .padding(.horizontal, 24)
                Text(page.message)
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
            Button(action: action) { Text(page.primaryAction) }
                .buttonStyle(.primary)
                .accessibilityIdentifier("onboarding.continue")
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.top, 12)
                .padding(.bottom, 18)
                .frame(maxWidth: 402)
                .frame(maxWidth: .infinity)
                .background(ColorToken.canvas.color.ignoresSafeArea(edges: .bottom))
        }
    }
}

/// `Onboarding / Dots`: visited plum dots, a coral pill for the current page, pale dots ahead.
struct ProgressDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(color(for: index))
                    .frame(width: index == current ? 22 : 7, height: 7)
            }
        }
        // Same height as the header row, so the VoiceOver element isn't a 7 pt sliver.
        .frame(minHeight: Size.minimumTapTarget)
        .contentShape(.accessibility, Rectangle())
        .accessibilityElement()
        .accessibilityLabel(Text("Page \(current + 1) of \(count)", bundle: .module))
    }

    private func color(for index: Int) -> Color {
        if index == current { return ColorToken.actionCoral.color }
        return index < current ? ColorToken.textPrimary.color : ColorToken.indicatorInactive.color
    }
}
