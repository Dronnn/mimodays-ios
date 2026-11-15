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
    let surprises: SurpriseCoordinator
    let notificationTaps = SurpriseNotificationHandler()
    let camera: CameraServices
    let momentSaver: MomentSaver
    let thumbnails = ThumbnailPipeline()
    let memoriesPreferences: MemoriesPreferences
    let moviePreferences: MoviePreferences
    let privacyPreferences: PrivacyPreferences
    let appearancePreferences: AppearancePreferences
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

    public init(configuration: LaunchConfiguration = LaunchConfiguration()) {
        do {
            // UI tests start from an empty store on every launch.
            modelContainer = try MimoDaysStore.makeContainer(inMemory: configuration.isUITesting)
        } catch {
            fatalError("MimoDays can't open its store: \(error)")
        }
        // UI tests can start every permission in a fixed state instead of hitting system prompts.
        if configuration.isUITesting, let status = configuration.permissions {
            permissions = PresetPermissionService(status: status)
        } else {
            permissions = SystemPermissionService()
        }
        skipsOnboarding = configuration.skipsOnboarding
        memoriesPreferences = .memories(configuration.isUITesting ? nil : .standard)
        moviePreferences = .movies(configuration.isUITesting ? nil : .standard)
        let privacyPreferences = PrivacyPreferences.privacy(configuration.isUITesting ? nil : .standard)
        self.privacyPreferences = privacyPreferences
        appearancePreferences = .appearance(configuration.isUITesting ? nil : .standard)
        // UI tests keep notification requests in memory so nothing is left on the simulator.
        let notifications: any NotificationScheduler = configuration.isUITesting
            ? InMemoryNotificationScheduler() : SystemNotificationScheduler()
        surprises = SurpriseCoordinator(context: modelContainer.mainContext, notifications: notifications, permissions: permissions)
        // The simulator has no cameras; UI tests can ask for the simulated one on devices too.
        #if targetEnvironment(simulator)
        let simulatedCamera = true
        #else
        let simulatedCamera = configuration.usesFakeCamera
        #endif
        let cameraSettings: any CameraSettingsStore = configuration.isUITesting ? InMemoryCameraSettingsStore() : UserDefaultsCameraSettingsStore()
        camera = CameraServices(
            makeEngine: { @MainActor () -> any CaptureEngine in
                simulatedCamera ? SimulatedCaptureEngine() : AVCaptureEngine(maxFormatWidth: cameraSettings.load().videoQuality.maxFormatWidth)
            },
            // The simulator has no motion data; there the sensor follows the device orientation, which UI tests can set.
            makeOrientation: { MotionOrientationSensor() },
            settings: cameraSettings,
            drafts: ReviewDraftStore(root: Self.reviewRoot(configuration)),
            voice: Self.voice(simulated: simulatedCamera),
            places: Self.places(configuration, context: modelContainer.mainContext, privacy: privacyPreferences)
        )
        do {
            momentSaver = MomentSaver(context: modelContainer.mainContext, store: try MediaStore(root: Self.mediaRoot(configuration)))
        } catch {
            fatalError("MimoDays can't open its media folder: \(error)")
        }
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
                cameraSettings.save(CameraSettings())
            }
        )
        UNUserNotificationCenter.current().delegate = notificationTaps
        if configuration.isUITesting, let tap = configuration.surpriseTap {
            simulate(tap)
        }
        if configuration.isUITesting, configuration.seed == .populated {
            seedMoments()
        }
        if configuration.isUITesting, configuration.seed == .movie {
            seedMovieMoments()
        }
    }

    /// `-seed populated`: a few moments from the simulated camera, saved the normal way. The newest is from
    /// two hours ago in Yerevan; one is from a year ago today, for On this day.
    private func seedMoments() {
        let calendar = Calendar.current
        let now = Date()
        let dates = [
            calendar.date(byAdding: .year, value: -1, to: now),
            calendar.date(byAdding: .day, value: -3, to: now),
            calendar.date(byAdding: .day, value: -1, to: now),
            now.addingTimeInterval(-2 * 3600),
        ].compactMap(\.self)
        let window = SelfieWindowFrame(frame: CGRect(x: 266.7, y: 111.1, width: 112, height: 150), preview: CGSize(width: 402, height: 536))
        Task {
            let engine = SimulatedCaptureEngine()
            _ = await engine.start()
            for (index, date) in dates.enumerated() {
                guard let photo = try? await engine.capturePhoto(flash: false, silent: true) else { continue }
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
                guard let photo = try? await engine.capturePhoto(flash: false, silent: true) else { continue }
                let instant = now.addingTimeInterval(Double(index - 7) * 3600)
                let capture = CaptureResult(media: .photo(photo), window: .init(), capturedAt: CaptureTime(instant: instant, timeZone: .current))
                _ = try? await momentSaver.save(MomentDraft(capture: capture, caption: "", window: window, promptID: nil))
            }
        }
    }

    /// Application Support/Media, out of the user's Files view. UI tests use a fresh temporary folder.
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
