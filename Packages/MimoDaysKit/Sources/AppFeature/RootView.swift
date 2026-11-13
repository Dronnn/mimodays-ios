import Core
import DesignSystem
import SwiftUI
import UIKit

/// App shell: four tabs, Settings from the gear on every tab root, Capture on Today.
/// System tab bar on iPhone; floating tab bar / sidebar on iPad.
public struct RootView: View {
    @State private var router: AppRouter
    /// Set while onboarding runs; nil once it is finished or skipped.
    @State private var onboarding: OnboardingFlow?
    private let permissions: any PermissionService
    private let surprises: SurpriseCoordinator
    private let notificationTaps: SurpriseNotificationHandler
    @Environment(\.scenePhase) private var scenePhase

    public init(router: AppRouter = AppRouter(), dependencies: AppDependencies) {
        _router = State(initialValue: router)
        permissions = dependencies.permissions
        let surprises = dependencies.surprises
        self.surprises = surprises
        notificationTaps = dependencies.notificationTaps
        let store = SwiftDataOnboardingStore(context: dependencies.modelContainer.mainContext)
        let flow = OnboardingFlow(permissions: dependencies.permissions, store: store) { await surprises.settingsChanged() }
        _onboarding = State(initialValue: dependencies.skipsOnboarding || flow.isCompleted ? nil : flow)
    }

    public var body: some View {
        Group {
            if let onboarding {
                OnboardingView(flow: onboarding) { tab in
                    router.selectedTab = tab
                    self.onboarding = nil
                }
            } else {
                tabs
            }
        }
        .environment(router)
        .environment(\.permissions, permissions)
        // Launch and every return to the app (notification permission may have changed in Settings).
        .onAppear {
            notificationTaps.listen(openSurprise)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { refreshSurprises() }
        }
        // Midnight, a clock change or a new time zone: hours follow the device.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            refreshSurprises()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            NSTimeZone.resetSystemTimeZone()
            refreshSurprises()
        }
    }

    /// In time it's "A little surprise"; too late it's a plain capture, never backdated (doc 01).
    private func openSurprise(_ promptID: UUID) {
        router.open(.capture(promptID: surprises.open(promptID: promptID) ? promptID : nil))
    }

    private func refreshSurprises() {
        Task { await surprises.refresh() }
    }

    private var tabs: some View {
        @Bindable var router = router
        return TabView(selection: $router.selectedTab) {
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
            CaptureFlowView(request: request)
        }
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

/// Camera access first (C06 explainer → system prompt, or C13a when it's off), then the camera.
struct CaptureFlowView: View {
    let request: CaptureRequest
    @Environment(\.permissions) private var permissions
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var step: CameraAccessStep?

    var body: some View {
        Group {
            switch step {
            case nil:
                ColorToken.canvas.color.ignoresSafeArea()
            case .explain:
                PermissionExplainerView(screen: .camera) {
                    Task { step = CameraAccessStep(await permissions.request(.camera)) }
                } secondary: {
                    dismiss()
                }
            case .openSettings:
                PermissionExplainerView(screen: .cameraOff) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } secondary: {
                    dismiss()
                }
            case .camera:
                CapturePlaceholderView(request: request)
            }
        }
        .task { await refresh() }
        // Coming back from Settings with access turned on.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
    }

    private func refresh() async {
        step = CameraAccessStep(await permissions.status(of: .camera))
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
                    .accessibilityIdentifier("camera.surprise")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 70)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camera")
    }
}
