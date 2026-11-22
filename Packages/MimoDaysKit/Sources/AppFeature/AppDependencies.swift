import Core
import Foundation
import Persistence
import SwiftData
import UserNotifications

/// Everything one launch shares, built once by the app and handed to `RootView`.
@MainActor
public final class AppDependencies {
    let modelContainer: ModelContainer
    let permissions: any PermissionService
    let skipsOnboarding: Bool
    /// UI tests: where `-open-url` sends the app at launch.
    let launchRoute: Route?
    /// UI tests: what the Journaling Suggestions stand-in picker hands back.
    let journalingFixture: LaunchConfiguration.JournalingFixture?
    let surprises: SurpriseCoordinator
    let notificationTaps = SurpriseNotificationHandler()
    let camera: CameraServices
    let momentSaver: MomentSaver
    let thumbnails = ThumbnailPipeline()
    var library: MediaLibrary { MediaLibrary(context: modelContainer.mainContext, store: momentSaver.store, thumbnails: thumbnails, use: mediaUse) }
    /// P3.5: who reads moments' files now (backup, restore, moment export), and Make smaller, which waits for them.
    let mediaUse = MediaUse()
    let shrinks: ShrinkRun
    let memoriesPreferences: MemoriesPreferences
    let moviePreferences: MoviePreferences
    /// P8.13: one movie export at a time, kept while its screen is closed; iOS 26 continues it in the background.
    let movieExports: MovieExportCenter
    let privacyPreferences: PrivacyPreferences
    let appearancePreferences: AppearancePreferences
    /// U16: the home side last shown, and whether the flip hint was shown.
    let homePreferences: HomePreferences
    /// §V17 LL03: shown once after the 1.0.7 update.
    let whatsNewPreferences: WhatsNewPreferences
    let appLock: AppLock
    /// S08 Delete all data.
    let eraser: AppEraser
    /// D01: StoreKit, or fixed US prices in UI tests.
    let tipStore: any TipStore
    /// Finishes tips approved later; lives as long as the app.
    private let tipTransactions: Task<Void, Never>?

    /// UI tests fake the location permission, so the fix and the lookups are faked too.
    private static func places(_ configuration: LaunchConfiguration, context: ModelContext, privacy: PrivacyPreferences) -> PlaceServices {
        var places = configuration.isUITesting ? PlaceServices.simulated : PlaceServices(
            location: SystemLocationProvider(), lookup: MapKitPlaceLookup(), recents: { RecentPlace.load(from: context) }
        )
        places.privacy = { privacy.value }
        return places
    }

    /// The simulator has no microphone worth testing with, and UI tests need a fixed transcript.
    private static func voice(simulated: Bool) -> VoiceServices {
        simulated ? .simulated : VoiceServices(makeRecorder: { AVVoiceRecorder() }, transcriber: OnDeviceTranscriber())
    }

    /// Throws when the store or the media folder can't be opened: the launch shows a way back instead of a crash.
    public init(configuration: LaunchConfiguration = LaunchConfiguration()) throws {
        if configuration.isUITesting, configuration.breaksStore { throw BrokenStoreForTesting() }
        // A setting aside cut short ends first: a new store must never open next to the old media, whose files the
        // orphan sweep below would take.
        if !configuration.isUITesting {
            try Self.finishSettingAside(store: Self.storeURL, media: Self.mediaRoot(configuration), into: URL.applicationSupportDirectory)
        }
        // UI tests start from an empty store on every launch.
        modelContainer = try MimoDaysStore.makeContainer(inMemory: configuration.isUITesting)
        // UI tests can start every permission in a fixed state instead of hitting system prompts.
        if configuration.isUITesting, let status = configuration.permissions {
            permissions = PresetPermissionService(status: status)
        } else {
            permissions = SystemPermissionService()
        }
        skipsOnboarding = configuration.skipsOnboarding
        launchRoute = configuration.isUITesting ? configuration.openURL.flatMap(AppRouter.route(from:)) : nil
        journalingFixture = configuration.isUITesting ? configuration.journaling : nil
        memoriesPreferences = .memories(configuration.isUITesting ? nil : .standard)
        moviePreferences = .movies(configuration.isUITesting ? nil : .standard)
        movieExports = MovieExportCenter(continuation: configuration.isUITesting ? nil : Self.continuedExport())
        let privacyPreferences = PrivacyPreferences.privacy(configuration.isUITesting ? nil : .standard)
        self.privacyPreferences = privacyPreferences
        appearancePreferences = .appearance(configuration.isUITesting ? nil : .standard)
        let homePreferences = HomePreferences.home(configuration.isUITesting ? nil : .standard)
        self.homePreferences = homePreferences
        whatsNewPreferences = configuration.isUITesting
            ? .whatsNew(nil, seen: !configuration.showsWhatsNew) : .whatsNew(.standard, seen: false)
        // UI tests keep notification requests in memory so nothing is left on the simulator.
        let notifications: any NotificationScheduler = configuration.isUITesting
            ? InMemoryNotificationScheduler() : SystemNotificationScheduler()
        surprises = SurpriseCoordinator(
            context: modelContainer.mainContext, notifications: notifications, permissions: permissions,
            defaults: configuration.isUITesting ? nil : .standard
        )
        // The simulator has no cameras; UI tests can ask for the simulated one on devices too.
        #if targetEnvironment(simulator)
        let simulatedCamera = true
        #else
        let simulatedCamera = configuration.usesFakeCamera
        #endif
        #if DEBUG
        let footage = configuration.demoFootage.flatMap { DemoFootage(folder: $0) }
        #else
        let footage: DemoFootage? = nil
        #endif
        let cameraSettings: any CameraSettingsStore = configuration.isUITesting ? InMemoryCameraSettingsStore() : UserDefaultsCameraSettingsStore()
        camera = CameraServices(
            makeEngine: { @MainActor () -> any CaptureEngine in
                simulatedCamera
                    ? SimulatedCaptureEngine(footage: footage)
                    : AVCaptureEngine(videoSize: cameraSettings.load().videoSize)
            },
            // The simulator has no motion data; there the sensor follows the device orientation, which UI tests can set.
            makeOrientation: { MotionOrientationSensor() },
            settings: cameraSettings,
            drafts: ReviewDraftStore(root: Self.reviewRoot(configuration)),
            voice: Self.voice(simulated: simulatedCamera),
            places: Self.places(configuration, context: modelContainer.mainContext, privacy: privacyPreferences),
            videoSizes: VideoSizeMeter(defaults: configuration.isUITesting ? nil : .standard),
            writing: WritingDraftStore(url: Self.reviewRoot(configuration).deletingLastPathComponent().appending(path: configuration.isUITesting ? "UITestWriting-\(UUID().uuidString).json" : "Writing.json"))
        )
        momentSaver = MomentSaver(context: modelContainer.mainContext, store: try MediaStore(root: Self.mediaRoot(configuration)))
        // Before any screen: what a Delete All couldn't remove, and files a save or a deletion left behind when iOS
        // ended the app mid-way.
        // The capture in review goes too when it's older than the erase, which may have been cut short before it; one
        // taken since stays.
        if let since = momentSaver.store.erasePendingSince, let saved = camera.drafts.savedAt, saved <= since { camera.drafts.clear() }
        if let since = momentSaver.store.erasePendingSince, let saved = camera.writing.savedAt, saved <= since { camera.writing.clear() }
        momentSaver.store.finishPendingErase()
        OrphanFiles.remove(context: modelContainer.mainContext, store: momentSaver.store)
        OrphanFiles.removeScratch()
        MovieExportModel.reconcileJobs(in: modelContainer.mainContext, now: Date())
        if !configuration.isUITesting { ImportedFormats.repairOnce(context: modelContainer.mainContext, defaults: .standard) }
        camera.drafts.removeLeftovers()
        let mediaUse = mediaUse, movieExports = movieExports
        shrinks = ShrinkRun(
            library: MediaLibrary(context: modelContainer.mainContext, store: momentSaver.store, thumbnails: thumbnails, use: mediaUse),
            defaults: configuration.isUITesting ? nil : .standard,
            busy: { mediaUse.isReading || movieExports.isExporting }
        )
        // After the sweep above: a run iOS ended goes on from the video it stopped at.
        shrinks.resumeIfNeeded()
        appLock = AppLock(settings: { privacyPreferences.value })
        if configuration.isUITesting {
            tipStore = SampleTipStore()
            tipTransactions = nil
        } else {
            tipStore = StoreKitTipStore()
            tipTransactions = StoreKitTipStore.listenForTransactions()
        }
        let memoriesPreferences = self.memoriesPreferences
        let moviePreferences = self.moviePreferences
        let appearancePreferences = self.appearancePreferences
        eraser = AppEraser(
            context: modelContainer.mainContext, store: momentSaver.store, notifications: notifications, drafts: camera.drafts,
            resetSettings: {
                memoriesPreferences.reset()
                moviePreferences.reset()
                privacyPreferences.reset()
                appearancePreferences.reset()
                homePreferences.reset()
                cameraSettings.save(CameraSettings())
                UserDefaults.standard.removeObject(forKey: BackupReminder.key)
                UserDefaults.standard.removeObject(forKey: MoviesModel.dismissedKey)
            },
            writing: camera.writing,
            temporaryDirectory: FileManager.default.temporaryDirectory
        )
        UNUserNotificationCenter.current().delegate = notificationTaps
        notificationTaps.remindLater = { [surprises] in await surprises.remindLater(promptID: $0) }
        SurpriseNotificationHandler.registerActions()
        if configuration.isUITesting, let tap = configuration.surpriseTap {
            simulate(tap)
        }
        if configuration.isUITesting, configuration.seed == .populated {
            seedMoments()
        }
        if configuration.isUITesting, configuration.seed == .movie {
            seedMovieMoments()
        }
        #if DEBUG
        if configuration.isUITesting, let folder = footage?.folder {
            seedDemoMoments(from: folder)
        }
        #endif
    }

    /// `-seed populated`: a few moments from the simulated camera, saved the normal way. The newest is from
    /// two hours ago in Yerevan, or midnight if that was yesterday: it is always today's; one is from a year ago
    /// today, for On this day.
    private func seedMoments() {
        let calendar = Calendar.current
        let now = Date()
        let dates = [
            calendar.date(byAdding: .year, value: -1, to: now),
            calendar.date(byAdding: .day, value: -3, to: now),
            calendar.date(byAdding: .day, value: -1, to: now),
            max(now.addingTimeInterval(-2 * 3600), calendar.startOfDay(for: now)),
        ].compactMap(\.self)
        let window = SelfieWindowFrame(frame: CGRect(x: 266.7, y: 111.1, width: 112, height: 150), preview: CGSize(width: 402, height: 536))
        Task {
            let engine = SimulatedCaptureEngine()
            _ = await engine.start()
            for (index, date) in dates.enumerated() {
                guard let photo = try? await engine.capturePhoto(flash: .off, silent: true) else { continue }
                let capture = CaptureResult(media: .photo(photo), window: .init(), capturedAt: CaptureTime(instant: date, timeZone: .current))
                let place = index == dates.count - 1
                    ? ReviewPlace.current(city: "Yerevan", at: GeoPoint(latitude: 40.18111, longitude: 44.51361, horizontalAccuracy: 30)) : nil
                _ = try? await momentSaver.save(MomentDraft(capture: capture, caption: "", window: window, promptID: nil, place: place))
            }
        }
    }

    /// `-seed movie`: eight moments an hour apart, ending now - enough this year for a movie (flow 05).
    private func seedMovieMoments() {
        let now = Date()
        let window = SelfieWindowFrame(frame: CGRect(x: 266.7, y: 111.1, width: 112, height: 150), preview: CGSize(width: 402, height: 536))
        Task {
            let engine = SimulatedCaptureEngine()
            _ = await engine.start()
            for index in 0..<8 {
                guard let photo = try? await engine.capturePhoto(flash: .off, silent: true) else { continue }
                let instant = now.addingTimeInterval(Double(index - 7) * 3600)
                let capture = CaptureResult(media: .photo(photo), window: .init(), capturedAt: CaptureTime(instant: instant, timeZone: .current))
                _ = try? await momentSaver.save(MomentDraft(capture: capture, caption: "", window: window, promptID: nil))
            }
        }
    }

    /// Application Support/Media, out of the user's Files view. UI tests use a fresh temporary folder.
    private struct BrokenStoreForTesting: Error {}

    /// Before a restore into a new library, when the store can't be opened: its files and the media folder move to
    /// Application Support/Set aside/<date and time>, nothing deleted, so the launch starts empty. UI tests keep
    /// nothing on disk to move.
    public static func setAside(_ configuration: LaunchConfiguration, now: Date = .now) throws {
        guard !configuration.isUITesting else { return }
        try setAside(store: storeURL, media: mediaRoot(configuration), into: URL.applicationSupportDirectory, now: now)
    }

    private static var storeURL: URL { ModelConfiguration(schema: MimoDaysStore.schema).url }
    /// In a Set aside folder while its moves aren't all done.
    private static let settingAsideMarker = ".moving"

    /// The store's files (the store, its -shm and -wal, its support folder) and the media folder, moved together: the
    /// marker stays until both are, so a launch after the app was ended in between finishes the job.
    static func setAside(store: URL, media: URL, into root: URL, now: Date) throws {
        let files = FileManager.default
        let stamp = now.formatted(.iso8601.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: false).timeSeparator(.omitted))
        let folder = root.appending(path: "Set aside", directoryHint: .isDirectory).appending(path: stamp, directoryHint: .isDirectory)
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        let marker = folder.appending(path: settingAsideMarker)
        try Data().write(to: marker)
        try move(store: store, media: media, into: folder)
        try files.removeItem(at: marker)
    }

    /// What a setting aside cut short left in place moves into its folder.
    static func finishSettingAside(store: URL, media: URL, into root: URL) throws {
        let files = FileManager.default
        let folders = (try? files.contentsOfDirectory(at: root.appending(path: "Set aside", directoryHint: .isDirectory), includingPropertiesForKeys: nil)) ?? []
        for folder in folders where files.fileExists(atPath: folder.appending(path: settingAsideMarker).path(percentEncoded: false)) {
            try move(store: store, media: media, into: folder)
            try files.removeItem(at: folder.appending(path: settingAsideMarker))
        }
    }

    private static func move(store: URL, media: URL, into folder: URL) throws {
        let files = FileManager.default
        let directory = store.deletingLastPathComponent()
        let name = store.lastPathComponent
        for url in (try? files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        where url.lastPathComponent == name || url.lastPathComponent.hasPrefix(name + "-") || url.lastPathComponent.hasPrefix("." + name) {
            try files.moveItem(at: url, to: folder.appending(path: url.lastPathComponent))
        }
        if files.fileExists(atPath: media.path(percentEncoded: false)) {
            try files.moveItem(at: media, to: folder.appending(path: media.lastPathComponent, directoryHint: .isDirectory))
        }
    }

    private static func mediaRoot(_ configuration: LaunchConfiguration) -> URL {
        if configuration.isUITesting {
            return FileManager.default.temporaryDirectory.appending(path: "UITestMedia-\(UUID().uuidString)", directoryHint: .isDirectory)
        }
        return URL.applicationSupportDirectory.appending(path: "Media", directoryHint: .isDirectory)
    }

    /// Application Support/Review; UI tests use a fresh temporary folder.
    private static func reviewRoot(_ configuration: LaunchConfiguration) -> URL {
        if configuration.isUITesting {
            return FileManager.default.temporaryDirectory.appending(path: "UITestReview-\(UUID().uuidString)", directoryHint: .isDirectory)
        }
        return URL.applicationSupportDirectory.appending(path: "Review", directoryHint: .isDirectory)
    }

    /// A prompt that fired a minute ago (or 20 minutes ago, so it has expired), then a tap on it.
    private func simulate(_ tap: LaunchConfiguration.SurpriseTap) {
        let planned = Date().addingTimeInterval(tap == .inTime ? -60 : -20 * 60)
        let prompt = SurprisePrompt(plannedAt: planned, expiresAt: planned.addingTimeInterval(15 * 60), notificationRequestID: "ui-test")
        modelContainer.mainContext.insert(prompt)
        try? modelContainer.mainContext.save()
        notificationTaps.deliver(prompt.id)
    }
}

extension AppDependencies {
    /// iOS 26's continued processing; before it, exports run while MimoDays is open (and a few minutes after).
    @MainActor
    static func continuedExport() -> (any ContinuedExportScheduler)? {
        if #available(iOS 26, *) { return SystemContinuedExport() }
        return nil
    }
}
