import DesignSystem
import SwiftUI

/// App shell: four tabs, Settings from the gear on every tab root, Capture on Today.
/// System tab bar on iPhone; floating tab bar / sidebar on iPad.
public struct RootView: View {
    @State private var router: AppRouter

    public init(router: AppRouter = AppRouter()) {
        _router = State(initialValue: router)
    }

    public var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                Tab(value: tab) {
                    NavigationStack {
                        TabRootView(tab: tab)
                    }
                } label: {
                    Label { Text(tab.title) } icon: { tab.icon.image }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(ColorToken.textLink.color)
        .sheet(isPresented: $router.isSettingsPresented) {
            SettingsPlaceholderView()
        }
        .fullScreenCover(item: $router.capture) { request in
            CapturePlaceholderView(request: request)
        }
        .environment(router)
    }
}

/// Root of each tab until its phase builds the real screen.
struct TabRootView: View {
    let tab: MainTab
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                Text(tab.title)
                    .textStyle(.displayTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                if tab == .today {
                    CaptureButton { router.open(.capture(promptID: nil)) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, 8)
        }
        .background(ColorToken.canvas.color)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.open(.settings) } label: {
                    Icon.glyphGear.image
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .frame(width: Size.minimumTapTarget, height: Size.minimumTapTarget)
                }
                .accessibilityLabel(Text("Settings", bundle: .module))
                .accessibilityIdentifier("settings")
            }
        }
        .toolbarBackground(ColorToken.canvas.color, for: .navigationBar)
    }
}

/// Coral capture disk (80 pt) with the camera glyph. The full Today layout comes in Phase 8.
struct CaptureButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Icon.glyphCamera.image
                .resizable()
                .frame(width: 34, height: 34)
                .foregroundStyle(ColorToken.textOnCoral.color)
                .frame(width: Size.captureButton, height: Size.captureButton)
                .background(LinearGradient.actionCoral, in: Circle())
                .overlay(Circle().strokeBorder(ColorToken.surfaceCard.color, lineWidth: 4))
                .elevation(.photoFrame)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(Text("Capture", bundle: .module))
        .accessibilityIdentifier("capture")
    }
}

struct SettingsPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ColorToken.surfaceSheet.color
                .ignoresSafeArea()
                .navigationTitle(Text("Settings", bundle: .module))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { dismiss() } label: { Text("Done", bundle: .module) }
                            .accessibilityIdentifier("settings.done")
                    }
                }
        }
    }
}

struct CapturePlaceholderView: View {
    let request: CaptureRequest
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            Button { dismiss() } label: {
                Text("Close", bundle: .module)
                    .textStyle(.control)
                    .foregroundStyle(.white)
                    .frame(minWidth: Size.minimumTapTarget, minHeight: Size.minimumTapTarget)
            }
            .padding(Spacing.screenMargin)
            .accessibilityIdentifier("capture.close")
            if request.isSurprise {
                Text("A little surprise", bundle: .module)
                    .textStyle(.hand)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(ColorToken.accentMint.color, in: Capsule())
                    .frame(maxWidth: .infinity)
                    .padding(.top, 70)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camera")
    }
}
