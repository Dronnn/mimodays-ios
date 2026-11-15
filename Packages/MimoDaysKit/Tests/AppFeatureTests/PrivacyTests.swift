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
    private let container = try! MimoDaysStore.makeContainer(inMemory: true)
    private let fix = GeoPoint(latitude: 40.181112, longitude: 44.513617, horizontalAccuracy: 12)

    private var context: ModelContext { container.mainContext }

    private func review(_ settings: PrivacySettings) async throws -> ReviewModel {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let capture = CaptureResult(
            media: .photo(try await engine.capturePhoto(flash: false, silent: true)), window: .init(),
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
    private let container = try! MimoDaysStore.makeContainer(inMemory: true)
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

        let eraser = AppEraser(context: context, store: store, notifications: notifications, drafts: drafts) {
            privacy.reset()
            memories.reset()
        }
        #expect(eraser.counts() == AppEraser.Counts(moments: 1, collections: 1, movies: 1))
        try await eraser.eraseEverything()

        #expect(eraser.counts() == AppEraser.Counts())
        #expect(try context.fetchCount(FetchDescriptor<MomentLocation>()) == 0)
        #expect(!store.fileExists(file.relativePath))
        #expect(try store.usage().values.reduce(0, +) == 0)
        #expect(!FileManager.default.fileExists(atPath: drafts.root.path))
        #expect(await notifications.pending().isEmpty)
        #expect(!onboarding.load().isCompleted)
        #expect(privacy.value == PrivacySettings() && memories.value == MemoriesSettings())
        #expect(defaults.data(forKey: "privacySettings") == nil && defaults.data(forKey: "memoriesSettings") == nil)
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
