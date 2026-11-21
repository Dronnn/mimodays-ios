import Core
import DesignSystem
import os
import SwiftData
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
    private let memoriesPreferences: MemoriesPreferences
    private let moviePreferences: MoviePreferences
    private let privacyPreferences: PrivacyPreferences
    private let appearancePreferences: AppearancePreferences
    private let appLock: AppLock
    private let eraser: AppEraser
    private let tipStore: any TipStore
    @State private var today: TodayModel
    @State private var memories: MemoriesModel
    /// The home's other side (U13): its own tiles, always newest first.
    @State private var mosaic: MemoriesModel
    /// U16: which home side shows, and the turn between them.
    @State private var home: Home
    /// U40: Mosaic pieces grow into their Memory Card; the stack's destinations need it too.
    @Namespace private var mosaicZoom
    /// C12 toast after a save.
    @State private var showsSavedToast = false
    /// Off on iPhone Duo's outer display, where the status bar sits on the side.
    @State private var statusBarOnTop = true
    /// The launch route and a draft left by iOS have been opened (once, after App Lock if it's on).
    @State private var resumedLaunch = false
    /// A notification tap or link that came while App Lock was on: opened once unlocked.
    @State private var heldRoute: Route?
    private let launchRoute: Route?
    @Environment(\.scenePhase) private var scenePhase

    public init(router: AppRouter = AppRouter(), dependencies: AppDependencies) {
        _router = State(initialValue: router)
        router.isAnswerable = { [surprises = dependencies.surprises] in surprises.open(promptID: $0) }
        permissions = dependencies.permissions
        launchRoute = dependencies.launchRoute
        let surprises = dependencies.surprises
        self.surprises = surprises
        notificationTaps = dependencies.notificationTaps
        camera = dependencies.camera
        momentSaver = dependencies.momentSaver
        _today = State(initialValue: TodayModel(
            context: dependencies.modelContainer.mainContext, surprises: surprises, permissions: dependencies.permissions,
            store: dependencies.momentSaver.store, thumbnails: dependencies.thumbnails
        ))
        let memories = MemoriesModel(
            context: dependencies.modelContainer.mainContext, store: dependencies.momentSaver.store, thumbnails: dependencies.thumbnails
        )
        memoriesPreferences = dependencies.memoriesPreferences
        moviePreferences = dependencies.moviePreferences
        privacyPreferences = dependencies.privacyPreferences
        appearancePreferences = dependencies.appearancePreferences
        appLock = dependencies.appLock
        eraser = dependencies.eraser
        tipStore = dependencies.tipStore
        memories.mode = memoriesPreferences.value.opensIn.memoriesMode
        memories.newestFirst = memoriesPreferences.value.newestFirst
        CaptureTime.followsDeviceTimeZone = memoriesPreferences.value.days == .thisIPhone
        _memories = State(initialValue: memories)
        _mosaic = State(initialValue: MemoriesModel(
            context: dependencies.modelContainer.mainContext, store: dependencies.momentSaver.store, thumbnails: dependencies.thumbnails,
            separatesWindow: true
        ))
        _home = State(initialValue: Home(preferences: dependencies.homePreferences))
        let flow = Self.onboardingFlow(context: dependencies.modelContainer.mainContext, permissions: dependencies.permissions, surprises: surprises)
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
        .onGeometryChange(for: Bool.self, of: { $0.safeAreaInsets.top > 0 }) { statusBarOnTop = $0 }
        .environment(\.statusBarOnTop, statusBarOnTop)
        .environment(router)
        .environment(\.permissions, permissions)
        .environment(\.camera, camera)
        .environment(\.momentSaver, momentSaver)
        .environment(memoriesPreferences)
        .environment(moviePreferences)
        .environment(privacyPreferences)
        .environment(appearancePreferences)
        .environment(appLock)
        .environment(\.appEraser, eraser)
        .environment(\.tipStore, tipStore)
        .environment(\.didEraseEverything, startOver)
        .environment(\.replayOnboarding, replayOnboarding)
        .environment(\.mediaLibrary, memories.library)
        // S05: the lock screen sits in its own window, over sheets too.
        .background(AppLockWindow(lock: appLock, isLocked: appLock.isLocked || appLock.isCovered))
        // The language chosen in Settings › Appearance, at once, for every screen and sheet.
        .appLanguage()
        // S04: light, dark and contrast for every window, sheets and the lock screen included.
        .background(WindowAppearance(settings: appearancePreferences.value))
        // Launch and every return to the app (notification permission may have changed in Settings).
        .onAppear {
            notificationTaps.listen(openSurprise)
            guard !appLock.isLocked else { return }
            resumeLaunch()
            openHeldRoute()
        }
        // Behind App Lock nothing opens: a recovered video in Review would play its sound under the lock screen.
        .onChange(of: appLock.isLocked) { _, locked in
            guard !locked else { return }
            resumeLaunch()
            openHeldRoute()
        }
        // mimodays://today (and the other tabs), …/settings, …/capture?prompt=<uuid>; a prompt is checked as a
        // notification's is. Not during onboarding.
        .onOpenURL { url in
            guard onboarding == nil, let route = AppRouter.route(from: url) else { return }
            open(route)
        }
        // Planned surprises carry their words: scheduled again in the language just chosen.
        .onChange(of: AppLanguage.shared.code) { Task { await surprises.languageChanged() } }
        // S09: Memories follows a change at once.
        .onChange(of: memoriesPreferences.value.opensIn) { _, mode in memories.mode = mode.memoriesMode }
        .onChange(of: memoriesPreferences.value.newestFirst) { _, newestFirst in
            memories.newestFirst = newestFirst
            memories.scrolledRow = nil
            memories.refresh()
        }
        .onChange(of: memoriesPreferences.value.days) { _, days in
            CaptureTime.followsDeviceTimeZone = days == .thisIPhone
            relabelDays(days)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .background { appLock.didEnterBackground() }
            guard phase == .active else { return }
            Task {
                await appLock.didBecomeActive()
                // Held for a lock that didn't come after all.
                if !appLock.isLocked { openHeldRoute() }
            }
            refreshSurprises()
            purgeRecentlyDeleted()
            // The iPhone may be in another zone now.
            if memoriesPreferences.value.days == .thisIPhone { relabelDays(.thisIPhone) }
        }
        // Midnight, a clock change or a new time zone: hours follow the device.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            refreshSurprises()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            NSTimeZone.resetSystemTimeZone()
            refreshSurprises()
            if memoriesPreferences.value.days == .thisIPhone { relabelDays(.thisIPhone) }
        }
    }

    private static func onboardingFlow(context: ModelContext, permissions: any PermissionService, surprises: SurpriseCoordinator) -> OnboardingFlow {
        OnboardingFlow(permissions: permissions, store: SwiftDataOnboardingStore(context: context), surprises: OnboardingSurprises(surprises))
    }

    /// S08: everything is gone, so MimoDays starts again from onboarding with nothing open.
    /// The route the app was opened with, and the review iOS closed the app in, back as it was. Once.
    private func resumeLaunch() {
        guard !resumedLaunch else { return }
        resumedLaunch = true
        if let draft = camera.drafts.load() {
            if let onboarding {
                onboarding.resumeCapture(promptID: draft.promptID)
            } else {
                router.open(.capture(promptID: draft.promptID))
            }
        }
        // After the review: it waits for Review to close.
        if let launchRoute { router.open(launchRoute) }
    }

    private func startOver() {
        router.isSettingsPresented = false
        router.capture = nil
        router.newMovie = nil
        router.moviesPath = []
        router.todayPath = NavigationPath()
        router.selectedTab = .today
        home.reset()
        memories.refresh()
        mosaic.refresh()
        Task { await today.refresh() }
        onboarding = Self.onboardingFlow(context: memories.library.context, permissions: permissions, surprises: surprises)
    }

    /// Help › "Show the introduction again".
    private func replayOnboarding() {
        router.isSettingsPresented = false
        let flow = Self.onboardingFlow(context: memories.library.context, permissions: permissions, surprises: surprises)
        flow.restart()
        onboarding = flow
    }

    /// S09: every moment's day for the chosen time zone; Memories reads them again when any moved.
    private func relabelDays(_ days: MemoriesSettings.Days) {
        do {
            if try MomentDays.relabel(memories.library.context, days: days) > 0 { memories.refresh() }
        } catch {
            Logger(subsystem: "MimoDays", category: "Settings").error("Relabelling days failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Moments in Recently deleted longer than 30 days go for good.
    private func purgeRecentlyDeleted() {
        let library = memories.library
        do {
            try DeletionStore(context: library.context, store: library.store).purgeExpired()
        } catch {
            Logger(subsystem: "MimoDays", category: "Deletion").error("Purging Recently deleted failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// In time it's "A little surprise"; too late it's a plain capture, never backdated (doc 01). During onboarding
    /// its camera opens over the page, which comes back when it closes (P2.0).
    private func openSurprise(_ promptID: UUID) {
        if let onboarding {
            onboarding.openSurprise(promptID)
        } else {
            open(.capture(promptID: promptID))
        }
    }

    private func openHeldRoute() {
        // Not before the launch's review is back, which would then close what this opened.
        guard resumedLaunch, let heldRoute else { return }
        self.heldRoute = nil
        open(heldRoute)
    }

    /// Behind App Lock nothing opens (a recovered Review would play under the lock screen): it waits for the unlock,
    /// and a surprise is checked then. With the camera or Review up, a surprise waits for them to close and opens then
    /// if still in time (P2.0); a plain camera is dropped, and a link waits in the router.
    private func open(_ route: Route) {
        if router.capture != nil, case let .capture(promptID) = route {
            if let promptID { router.heldSurprise = promptID }
            return
        }
        // Before the launch's review is back (a tap iOS kept for the app as it opens), it waits for it.
        guard resumedLaunch, !appLock.isLockedOrDue else {
            heldRoute = route
            return
        }
        if case let .capture(promptID?) = route {
            router.open(.capture(promptID: surprises.open(promptID: promptID) ? promptID : nil))
        } else {
            router.open(route)
        }
    }

    private func refreshSurprises() {
        Task { await surprises.refresh() }
    }

    /// DG.1: the latest moment for the camera's thumbnail; a tap closes the camera and opens it on Today.
    private var lastCapture: LastCapture? {
        guard let latest = today.latest else { return nil }
        let image = today.image(latest.thumbnailPath, TodayModel.tilePixels) ?? today.image(latest.picturePath, TodayModel.heroPixels)
        return LastCapture(image: image) { [router, today] in
            // A tap on the last capture wins over a link that waited for the camera to close.
            router.held = nil
            router.capture = nil
            router.selectedTab = .today
            var path = NavigationPath()
            path.append(MemoriesRoute.moment(today.pager(from: latest.id)))
            router.todayPath = path
        }
    }

    private var tabs: some View {
        @Bindable var router = router
        return TabView(selection: $router.selectedTab) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                Tab(value: tab) {
                    if tab == .movies {
                        // Movies' screens are opened from outside the tab too (a new movie, its export's Done).
                        NavigationStack(path: $router.moviesPath) { MoviesScreen() }
                    } else if tab == .today {
                        // The camera's last capture opens on Today.
                        NavigationStack(path: $router.todayPath) { HomeView(today: today, mosaic: mosaic) }
                            .environment(\.mosaicZoom, mosaicZoom)
                    } else {
                        NavigationStack {
                            switch tab {
                            case .memories: MemoriesView(model: memories)
                            case .map: MapScreen()
                            case .today, .movies: EmptyView()
                            }
                        }
                        .environment(\.mosaicZoom, nil)
                        // H.9: the pages pushed on the tab move as it does.
                        .tileMotionScreen(tab == .map ? .map : .memories)
                    }
                } label: {
                    Label { Text(tab.title) } icon: { tab.icon.image }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(ColorToken.textLink.color)
        .environment(home)
        .sheet(isPresented: $router.isSettingsPresented) {
            SettingsScreen(surprises: surprises)
        }
        .fullScreenCover(item: $router.capture) { request in
            CaptureFlowView(request: request, lastCapture: lastCapture, promptExpiry: request.promptID.flatMap(surprises.expiry)) { saved in
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
                        AccessibilityNotification.Announcement(String(appLocalized: "Saved to today", bundle: .module)).post()
                        try? await Task.sleep(for: .seconds(2.5))
                        withAnimation { showsSavedToast = false }
                    }
            }
        }
        .animation(.snappy, value: showsSavedToast)
    }
}

/// Camera access first (C06 explainer → system prompt, or C13a when it's off), then the camera, then review (C07).
struct CaptureFlowView: View {
    let request: CaptureRequest
    var lastCapture: LastCapture?
    /// The surprise's end: a shot taken from then on isn't its answer.
    var promptExpiry: Date?
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
    @State private var restoredDraft = false
    /// From the camera explainer's Continue until iOS has answered.
    @State private var requestsCamera = false

    var body: some View {
        Group {
            // A capture waiting in Review is saved or dropped whatever camera access is now (taken away in Settings
            // meanwhile, or after a relaunch).
            if let review {
                ReviewView(model: review) {
                    self.review = nil
                } onSave: {
                    try await save(review)
                }
            } else {
                cameraStep
            }
        }
        .task { await refresh() }
        // The screen stays upright; the camera turns its own controls with the phone (C.3).
        .onAppear { OrientationLock.set(.portrait) }
        .onDisappear { OrientationLock.set(nil) }
        // Coming back from Settings with access turned on, or to a camera an error stopped.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await refresh()
                    await camera?.recover()
                }
            }
        }
    }

    @ViewBuilder
    private var cameraStep: some View {
        switch step {
        case nil:
            CameraPalette.background.ignoresSafeArea()
        case .explain:
            PermissionExplainerView(screen: .camera) {
                // The explainer goes first, so the system prompt never shows over it.
                guard !requestsCamera else { return }
                requestsCamera = true
                withAnimation(.easeOut(duration: 0.2)) { step = nil } completion: {
                    Task {
                        let status = await permissions.request(.camera)
                        requestsCamera = false
                        show(CameraAccessStep(status))
                    }
                }
            }
        case .openSettings:
            PermissionExplainerView(screen: .cameraOff) {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } secondary: {
                dismiss()
            }
        case .camera:
            if let camera {
                CameraView(model: camera, lastCapture: lastCapture) { dismiss() }
            } else {
                CameraPalette.background.ignoresSafeArea()
            }
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
        guard !requestsCamera else { return }
        let status = await permissions.status(of: .camera)
        // The system prompt may have come up meanwhile: its answer decides.
        guard !requestsCamera else { return }
        show(CameraAccessStep(status))
    }

    private func show(_ step: CameraAccessStep) {
        self.step = step
        // A review iOS closed mid-way comes back first, with or without camera access.
        if !restoredDraft {
            restoredDraft = true
            let services = services ?? .simulated
            if let draft = services.drafts.load() {
                review = ReviewModel(draft: draft, drafts: services.drafts, voice: services.voice, places: services.places)
            }
        }
        if step == .camera, camera == nil {
            let services = services ?? .simulated
            let permissions = permissions
            camera = CameraModel(
                engine: services.makeEngine(), store: services.settings, isSurprise: request.isSurprise,
                orientation: services.makeOrientation(),
                microphoneStatus: { await permissions.status(of: .microphone) },
                onCapture: { capture in
                    let drafts = services.drafts
                    let adopted = try? drafts.adopt(capture)
                    let inTime = promptExpiry.map { capture.capturedAt.instant < $0 } ?? true
                    review = ReviewModel(capture: adopted ?? capture, promptID: inTime ? request.promptID : nil, drafts: adopted == nil ? nil : drafts, voice: services.voice, places: services.places)
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
