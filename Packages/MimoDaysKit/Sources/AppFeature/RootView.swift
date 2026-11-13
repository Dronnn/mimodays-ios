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
    private let camera: CameraServices
    private let momentSaver: MomentSaver
    @State private var today: TodayModel
    /// C12 toast after a save.
    @State private var showsSavedToast = false
    @Environment(\.scenePhase) private var scenePhase

    public init(router: AppRouter = AppRouter(), dependencies: AppDependencies) {
        _router = State(initialValue: router)
        permissions = dependencies.permissions
        let surprises = dependencies.surprises
        self.surprises = surprises
        notificationTaps = dependencies.notificationTaps
        camera = dependencies.camera
        momentSaver = dependencies.momentSaver
        _today = State(initialValue: TodayModel(
            context: dependencies.modelContainer.mainContext, surprises: surprises, permissions: dependencies.permissions,
            store: dependencies.momentSaver.store, thumbnails: dependencies.thumbnails
        ))
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
        .environment(\.camera, camera)
        .environment(\.momentSaver, momentSaver)
        // Launch and every return to the app (notification permission may have changed in Settings).
        .onAppear {
            notificationTaps.listen(openSurprise)
            // iOS closed the app mid-review: back to it, as it was.
            if onboarding == nil, let draft = camera.drafts.load() {
                router.open(.capture(promptID: draft.promptID))
            }
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
                        if tab == .today {
                            TodayView(model: today)
                        } else {
                            TabRootView(tab: tab)
                        }
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
            CaptureFlowView(request: request) { saved in
                if let promptID = saved.promptID { surprises.captured(promptID: promptID, momentID: saved.momentID) }
                showsSavedToast = true
            }
        }
        .overlay(alignment: .bottom) {
            if showsSavedToast {
                SavedToast()
                    .padding(.bottom, 100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        AccessibilityNotification.Announcement(String(localized: "Saved to today", bundle: .module)).post()
                        try? await Task.sleep(for: .seconds(2.5))
                        withAnimation { showsSavedToast = false }
                    }
            }
        }
        .animation(.snappy, value: showsSavedToast)
    }
}

/// Root of Memories, Map and Movies until their phases build the real screens.
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

/// Camera access first (C06 explainer → system prompt, or C13a when it's off), then the camera, then review (C07).
struct CaptureFlowView: View {
    let request: CaptureRequest
    /// After the save, before the flow closes.
    var onSaved: @MainActor (SavedCapture) -> Void = { _ in }
    @Environment(\.permissions) private var permissions
    @Environment(\.camera) private var services
    @Environment(\.momentSaver) private var saver
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var step: CameraAccessStep?
    @State private var camera: CameraModel?
    @State private var review: ReviewModel?

    var body: some View {
        Group {
            switch step {
            case nil:
                CameraPalette.background.ignoresSafeArea()
            case .explain:
                PermissionExplainerView(screen: .camera) {
                    Task { show(CameraAccessStep(await permissions.request(.camera))) }
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
                if let review {
                    ReviewView(model: review) {
                        self.review = nil
                    } onSave: {
                        try await save(review)
                    }
                } else if let camera {
                    CameraView(model: camera) { dismiss() }
                } else {
                    CameraPalette.background.ignoresSafeArea()
                }
            }
        }
        .task { await refresh() }
        // Coming back from Settings with access turned on.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
    }

    /// Keeps the moment, then closes. A failure leaves review as it is, so Try again works.
    private func save(_ review: ReviewModel) async throws {
        guard let saver else { throw SaveError.failed }
        await review.finishTranscription()
        let moment = try await saver.save(review.momentDraft)
        review.stopPlayback()
        review.clearDraft()
        onSaved(SavedCapture(momentID: moment.id, promptID: review.promptID, main: review.main, selfie: review.selfie, capturedAt: moment.capturedAt))
        dismiss()
    }

    private func refresh() async {
        show(CameraAccessStep(await permissions.status(of: .camera)))
    }

    private func show(_ step: CameraAccessStep) {
        self.step = step
        if step == .camera, camera == nil {
            let services = services ?? .simulated
            // A review iOS closed mid-way comes back first.
            if let draft = services.drafts.load() {
                review = ReviewModel(draft: draft, drafts: services.drafts, voice: services.voice, places: services.places)
            }
            let permissions = permissions
            camera = CameraModel(
                engine: services.makeEngine(), store: services.settings, isSurprise: request.isSurprise,
                microphoneStatus: { await permissions.status(of: .microphone) },
                onCapture: { capture in
                    let drafts = services.drafts
                    let adopted = try? drafts.adopt(capture)
                    review = ReviewModel(capture: adopted ?? capture, promptID: request.promptID, drafts: adopted == nil ? nil : drafts, voice: services.voice, places: services.places)
                }
            )
        }
    }
}

/// A moment that was just saved, for what comes after (C12 toast, O10, the surprise link).
struct SavedCapture {
    var momentID: UUID
    var promptID: UUID?
    var main: UIImage?
    var selfie: UIImage?
    var capturedAt: Date
}
