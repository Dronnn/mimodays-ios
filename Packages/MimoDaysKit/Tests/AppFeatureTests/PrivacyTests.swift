@testable import AppFeature
@testable import Core
import Foundation
import Persistence
import SwiftData
import Testing
import TestSupport
import UIKit

/// 13.6 (S05): the privacy settings are kept and decide what a new moment keeps of where it was taken.
@MainActor
struct PrivacySettingsTests {
    private let container = try! TestStore.container()
    private let fix = GeoPoint(latitude: 40.181112, longitude: 44.513617, horizontalAccuracy: 12)

    private var context: ModelContext { container.mainContext }

    private func review(_ settings: PrivacySettings) async throws -> ReviewModel {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let capture = CaptureResult(
            media: .photo(try await engine.capturePhoto(flash: .off, silent: true)), window: .init(),
            capturedAt: CaptureTime(instant: Date(timeIntervalSince1970: 1_794_407_820), timeZoneID: "Asia/Yerevan")
        )
        var places = PlaceServices(location: FakeLocationProvider(location: fix), lookup: SimulatedPlaceLookup(), recents: { [] })
        places.privacy = { settings }
        return ReviewModel(capture: capture, places: places)
    }

    @Test func settingsAreKeptAcrossLaunches() throws {
        let defaults = try #require(UserDefaults(suiteName: "PrivacySettingsTests"))
        defaults.removePersistentDomain(forName: "PrivacySettingsTests")
        let preferences = PrivacyPreferences.privacy(defaults)
        #expect(preferences.value == PrivacySettings())
        preferences.value.appLock = true
        preferences.value.lockAfter = .fifteenMinutes
        preferences.value.savesPlace = false
        preferences.value.precision = .exact
        #expect(PrivacyPreferences.privacy(defaults).value == preferences.value)
    }

    @Test func settingsSavedByAnEarlierVersionKeepTheirValues() throws {
        let defaults = try #require(UserDefaults(suiteName: "PrivacySettingsUpgradeTests"))
        defaults.removePersistentDomain(forName: "PrivacySettingsUpgradeTests")
        defaults.set(Data(#"{"appLock":true}"#.utf8), forKey: "privacySettings")
        let settings = PrivacyPreferences.privacy(defaults).value
        #expect(settings.appLock && settings.lockAfter == .immediately && settings.savesPlace && settings.precision == .city)
    }

    @Test func exactPrecisionKeepsThePlaceAsMeasured() async throws {
        var settings = PrivacySettings()
        settings.precision = .exact
        let review = try await review(settings)
        defer { review.discard() }
        await review.locate()
        let place = try #require(review.place)
        #expect(place.latitude == fix.latitude && place.longitude == fix.longitude && place.precision == .exact)
        #expect(place.label == "Yerevan")
    }

    @Test func withPlacesOffThePositionIsNotAskedFor() async throws {
        var settings = PrivacySettings()
        settings.savesPlace = false
        let review = try await review(settings)
        defer { review.discard() }
        await review.locate()
        // This iPhone's position isn't even asked for.
        #expect(review.place == nil && review.currentPlace == nil)
    }

    @Test func removingAllPlacesKeepsTheMoments() throws {
        for index in 0..<3 {
            let moment = Moment(
                captured: CaptureTime(instant: Date(timeIntervalSince1970: 1_794_355_200 + Double(index) * 60), timeZone: .gmt),
                origin: .manual, mediaType: .photo, createdAt: .now
            )
            context.insert(moment)
            if index > 0 { moment.location = MomentLocation(latitude: 40.18, longitude: 44.51, precision: .city, source: .gps, placeLabel: "Yerevan") }
        }
        try context.save()
        #expect(PlaceEraser.count(context) == 2)
        #expect(try PlaceEraser.removeAll(context) == 2)
        #expect(PlaceEraser.count(context) == 0)
        let moments = try context.fetch(FetchDescriptor<Moment>())
        #expect(moments.count == 3 && moments.allSatisfy { $0.location == nil })
    }
}

/// 13.6 (S05): App Lock asks at launch and after the chosen time away, and only when it's on.
@MainActor
struct AppLockTests {
    @MainActor
    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_794_355_200)
    }

    @MainActor
    private final class Owner {
        var answers: [Bool]
        private(set) var asked = 0
        init(_ answers: [Bool]) { self.answers = answers }
        func authenticate(_: String) async -> Bool {
            asked += 1
            return answers.isEmpty ? false : answers.removeFirst()
        }
    }

    private func lock(_ settings: PrivacySettings, owner: Owner, clock: Clock) -> AppLock {
        AppLock(settings: { settings }, biometry: .faceID, authenticate: { await owner.authenticate($0) }, now: { clock.now })
    }

    private var on: PrivacySettings {
        var settings = PrivacySettings()
        settings.appLock = true
        return settings
    }

    @Test func offNeverLocksOrAsks() async {
        let owner = Owner([])
        let lock = lock(PrivacySettings(), owner: owner, clock: Clock())
        #expect(!lock.isLocked)
        lock.didEnterBackground()
        await lock.didBecomeActive()
        #expect(!lock.isLocked && owner.asked == 0)
    }

    @Test func launchAsksOnceAndAFailureWaitsForTheButton() async {
        let owner = Owner([false, true])
        let lock = lock(on, owner: owner, clock: Clock())
        #expect(lock.isLocked)
        await lock.didBecomeActive()
        #expect(lock.isLocked && owner.asked == 1)
        // Face ID's own sheet going away makes the app active again; that doesn't ask a second time.
        await lock.didBecomeActive()
        #expect(owner.asked == 1)
        await lock.unlock()
        #expect(!lock.isLocked && owner.asked == 2)
    }

    @Test func withADelayTheAppSwitcherStillSeesTheCover() async {
        var settings = on
        settings.lockAfter = .oneMinute
        let owner = Owner([true])
        let lock = lock(settings, owner: owner, clock: Clock())
        await lock.didBecomeActive()
        lock.didEnterBackground()
        #expect(!lock.isLocked && lock.isCovered)
        await lock.didBecomeActive()
        #expect(!lock.isLocked && !lock.isCovered && owner.asked == 1)
    }

    @Test func timeAwayNeverRunsBackwards() {
        let first = AppLock.uptime()
        #expect(AppLock.uptime() >= first)
    }

    @Test func leavingLocksAtOnceByDefault() async {
        let owner = Owner([true, true])
        let lock = lock(on, owner: owner, clock: Clock())
        await lock.didBecomeActive()
        #expect(!lock.isLocked)
        lock.didEnterBackground()
        // Covered before the app switcher takes its picture.
        #expect(lock.isLocked)
        await lock.didBecomeActive()
        #expect(!lock.isLocked && owner.asked == 2)
    }

    @Test func aDelayLocksOnlyAfterThatLongAway() async {
        var settings = on
        settings.lockAfter = .fifteenMinutes
        let owner = Owner([true, true])
        let clock = Clock()
        let lock = lock(settings, owner: owner, clock: clock)
        await lock.didBecomeActive()
        lock.didEnterBackground()
        #expect(!lock.isLocked)
        clock.now += 14 * 60
        await lock.didBecomeActive()
        #expect(!lock.isLocked && owner.asked == 1)
        lock.didEnterBackground()
        clock.now += 15 * 60
        await lock.didBecomeActive()
        #expect(!lock.isLocked && owner.asked == 2)
    }
}

/// 13.9 (S08): Delete all data leaves nothing behind and onboarding starts again.
@MainActor
struct DeleteAllTests {
    private let container = try! TestStore.container()
    private let store = try! MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "DeleteAll-\(UUID().uuidString)"))
    private let drafts = ReviewDraftStore(root: FileManager.default.temporaryDirectory.appending(path: "DeleteAllDrafts-\(UUID().uuidString)"))

    private var context: ModelContext { container.mainContext }

    @Test func everythingGoes() async throws {
        let defaults = try #require(UserDefaults(suiteName: "DeleteAllTests"))
        defaults.removePersistentDomain(forName: "DeleteAllTests")
        let privacy = PrivacyPreferences.privacy(defaults)
        let memories = MemoriesPreferences.memories(defaults)
        privacy.value.appLock = true
        memories.value.newestFirst = false

        let notifications = InMemoryNotificationScheduler()
        await notifications.schedule(SurpriseNotification(id: "surprise", fireDate: .now.addingTimeInterval(3600)))
        let onboarding = SwiftDataOnboardingStore(context: context)
        var record = onboarding.load()
        record.isCompleted = true
        onboarding.save(record)

        let moment = Moment(
            captured: CaptureTime(instant: Date(timeIntervalSince1970: 1_794_355_200), timeZone: .gmt), origin: .manual, mediaType: .photo, createdAt: .now
        )
        context.insert(moment)
        moment.location = MomentLocation(latitude: 40.18, longitude: 44.51, precision: .city, source: .gps)
        context.insert(MomentCollection(title: "Trip", sortOrder: 0))
        context.insert(MovieProject(title: "November", sourceRule: MovieSourceRule(kind: .selection), aspectRatio: .portrait9x16, length: .short))
        try context.save()
        let file = try store.store(Data("photo".utf8), in: .originals, fileExtension: "heic")
        _ = try drafts.newVoiceURL()

        let temporary = FileManager.default.temporaryDirectory.appending(path: "EraseTmp-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporary.appending(path: "Export-1"), withIntermediateDirectories: true)
        let unpacked = store.root.appending(path: MediaStore.stagingPrefix + "1", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
        try Data("selfie".utf8).write(to: unpacked.appending(path: "a.heic"))
        var eraser = AppEraser(context: context, store: store, notifications: notifications, drafts: drafts) {
            privacy.reset()
            memories.reset()
        }
        eraser.temporaryDirectory = temporary
        #expect(eraser.counts() == AppEraser.Counts(moments: 1, collections: 1, movies: 1))
        try await eraser.eraseEverything()

        #expect(eraser.counts() == AppEraser.Counts())
        #expect(try context.fetchCount(FetchDescriptor<MomentLocation>()) == 0)
        #expect(!store.fileExists(file.relativePath))
        #expect(try store.usage().values.reduce(0, +) == 0)
        #expect(!FileManager.default.fileExists(atPath: drafts.root.path))
        #expect(await notifications.pending().isEmpty)
        // What a restore stopped half-way unpacked, and exports waiting in the temporary folder.
        #expect(!FileManager.default.fileExists(atPath: unpacked.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: temporary.path).isEmpty)
        #expect(!onboarding.load().isCompleted)
        #expect(privacy.value == PrivacySettings() && memories.value == MemoriesSettings())
        #expect(defaults.data(forKey: "privacySettings") == nil && defaults.data(forKey: "memoriesSettings") == nil)
    }

    /// Once the records are committed, a file that won't go doesn't stop the rest: settings reset, the draft goes,
    /// onboarding starts again, and the file no record points to is swept at the next launch.
    @Test func aFileThatWontGoDoesntStopTheErase() async throws {
        let onboarding = SwiftDataOnboardingStore(context: context)
        var record = onboarding.load()
        record.isCompleted = true
        onboarding.save(record)
        let locked = store.root.appending(path: "originals/locked", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try Data("photo".utf8).write(to: locked.appending(path: "a.heic"))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        let kept = try store.store(Data("voice".utf8), in: .originals, fileExtension: "m4a")
        _ = try drafts.newVoiceURL()
        var didReset = false
        let eraser = AppEraser(context: context, store: store, notifications: InMemoryNotificationScheduler(), drafts: drafts) { didReset = true }

        try await eraser.eraseEverything()

        #expect(didReset)
        #expect(!onboarding.load().isCompleted)
        #expect(!FileManager.default.fileExists(atPath: drafts.root.path))
        #expect(!store.fileExists(kept.relativePath))
        #expect(FileManager.default.fileExists(atPath: locked.appending(path: "a.heic").path))
    }

    /// The backup reminder isn't a surprise, so `pending()` doesn't list it; it goes all the same.
    @Test func theBackupReminderGoesToo() async throws {
        let notifications = CancelRecorder()
        let eraser = AppEraser(context: context, store: store, notifications: notifications, drafts: drafts) {}
        try await eraser.eraseEverything()
        #expect(await notifications.cancelled == [BackupReminder.notificationID])
        #expect(await notifications.removedAll)
    }

    /// Lists no requests, like the system scheduler for a time-interval one, and keeps what is cancelled.
    private actor CancelRecorder: NotificationScheduler {
        private(set) var cancelled: [String] = []
        func pending() -> [SurpriseNotification] { [] }
        func schedule(_: SurpriseNotification) {}
        func cancel(ids: [String]) { cancelled += ids }
        private(set) var removedAll = false
        func removeAll() { removedAll = true }
    }
}

/// 13.7 (S04): the appearance is kept and becomes the windows' style.
@MainActor
struct AppearanceSettingsTests {
    @Test func settingsAreKeptAcrossLaunches() throws {
        let defaults = try #require(UserDefaults(suiteName: "AppearanceSettingsTests"))
        defaults.removePersistentDomain(forName: "AppearanceSettingsTests")
        let preferences = AppearancePreferences.appearance(defaults)
        #expect(preferences.value.appearance == .system && !preferences.value.higherContrast)
        preferences.value.appearance = .dark
        preferences.value.higherContrast = true
        #expect(AppearancePreferences.appearance(defaults).value == preferences.value)
        preferences.reset()
        #expect(AppearancePreferences.appearance(defaults).value == AppearanceSettings())
    }

    @Test func eachChoiceIsAWindowStyle() {
        var settings = AppearanceSettings()
        #expect(settings.interfaceStyle == .unspecified)
        settings.appearance = .light
        #expect(settings.interfaceStyle == .light)
        settings.appearance = .dark
        #expect(settings.interfaceStyle == .dark)
    }

    @Test func higherContrastReachesTheWindow() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        var settings = AppearanceSettings()
        settings.appearance = .dark
        settings.higherContrast = true
        WindowAppearance.Anchor.apply(settings, to: window)
        #expect(window.overrideUserInterfaceStyle == .dark && window.traitCollection.accessibilityContrast == .high)
        WindowAppearance.Anchor.apply(AppearanceSettings(), to: window)
        #expect(window.overrideUserInterfaceStyle == .unspecified && !window.traitOverrides.contains(UITraitAccessibilityContrast.self))
    }
}

/// W8: the data-use page links to the full policy on the website, in the app's language.
@MainActor
struct PrivacyPolicyLinkTests {
    @Test(arguments: [
        ("en", "https://mimodays.mrmaier.com/privacy-policy/"), ("de", "https://mimodays.mrmaier.com/de/privacy-policy/"),
        ("de_DE", "https://mimodays.mrmaier.com/de/privacy-policy/"), ("pt-BR", "https://mimodays.mrmaier.com/pt-br/privacy-policy/"),
        ("zh-Hant", "https://mimodays.mrmaier.com/zh-hant/privacy-policy/"), ("fi", "https://mimodays.mrmaier.com/privacy-policy/"),
    ])
    func thePolicyOpensInTheAppsLanguage(_ identifier: String, _ expected: String) {
        #expect(DataUseView.policyURL(Locale(identifier: identifier)).absoluteString == expected)
    }
}
