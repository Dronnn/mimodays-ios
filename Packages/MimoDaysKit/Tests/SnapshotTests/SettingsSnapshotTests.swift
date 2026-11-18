@testable import AppFeature
@testable import Core
import Core
import DesignSystem
import Foundation
import Persistence
import SwiftData
import SwiftUI
import Testing
import TestSupport

/// Settings: S01-S09, the help pages, the lock screen and Donations (D01-D04).
@MainActor
@Suite(.tags(.snapshot), .serialized)
struct SettingsSnapshotTests {
    private let container = try! TestStore.container()
    private let store: MediaStore
    private static var containers: [ModelContainer] = []

    init() throws {
        store = try MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "SettingsSnapshots-\(UUID().uuidString)"))
        Self.containers.append(container)
    }

    private var library: MediaLibrary { MediaLibrary(context: container.mainContext, store: store, thumbnails: ThumbnailPipeline()) }

    private func page(_ view: some View) -> some View {
        NavigationStack { view.toolbar(.hidden, for: .navigationBar) }
            .environment(AppRouter())
            .environment(\.mediaLibrary, library)
    }

    /// Surprises on, once a day, every day but Sunday, 9 AM to 9 PM, as S02 shows it.
    private func model(notifications: PermissionStatus = .granted) async -> SettingsModel {
        let model = SettingsModel(library: library, surprises: nil, permissions: PresetPermissionService(status: notifications))
        await model.load()
        await model.setSurprises(true)
        model.reminders.frequency = .onceADay
        if model.reminders.isOn(1) { model.reminders.toggle(1) }
        model.reminders.setLatest(21 * 60)
        model.reminders.setEarliest(9 * 60)
        return model
    }

    private let variants = [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge)]

    /// S01.
    @Test func overview() async {
        container.mainContext.insert(BackupManifest(formatVersion: 1, createdAt: Date.now.addingTimeInterval(-18 * 86_400)))
        let model = await model()
        model.storageBytes = 6_000_000_000
        assertScreenSnapshots(of: page(SettingsView(model: model, importPhotos: {}, done: {})), variants: variants + SnapshotVariant.languages)
    }

    /// S02.
    @Test func surprises() async {
        let model = await model()
        assertScreenSnapshots(of: page(SurpriseSettingsView(model: model)), variants: variants + SnapshotVariant.languages)
    }

    /// S02 when notifications are off in iOS Settings.
    @Test func surprisesWithoutNotifications() async {
        let model = await model(notifications: .denied)
        assertScreenSnapshots(of: page(SurpriseSettingsView(model: model)), variants: [SnapshotVariant(.iPhone, .light)])
    }

    /// S03.
    @Test func camera() {
        var settings = CameraSettings()
        assertScreenSnapshots(
            of: page(CameraSettingsView(settings: Binding { settings } set: { settings = $0 }, access: .allowed)), variants: variants
        )
    }

    /// S09.
    @Test func memories() {
        var settings = MemoriesSettings()
        assertScreenSnapshots(of: page(MemoriesSettingsView(settings: Binding { settings } set: { settings = $0 })), variants: variants)
    }

    /// S06.
    @Test func movies() {
        var defaults = MovieDefaults()
        assertScreenSnapshots(of: page(MovieSettingsView(defaults: Binding { defaults } set: { defaults = $0 })), variants: variants)
    }

    /// S05 with App Lock on, as the board shows it.
    @Test func privacy() {
        var settings = PrivacySettings()
        settings.appLock = true
        assertScreenSnapshots(
            of: page(PrivacySettingsView(
                settings: Binding { settings } set: { settings = $0 }, biometry: .faceID, placeCount: 3, turnOnLock: { true }, removePlaces: {}
            )),
            variants: variants
        )
    }

    /// S05 "How MimoDays uses your data".
    @Test func dataUse() {
        assertScreenSnapshots(of: page(DataUseView()), variants: variants)
    }

    /// S08 halfway through typing DELETE.
    @Test func deleteAll() {
        let counts = AppEraser.Counts(moments: 312, collections: 6, movies: 3)
        assertScreenSnapshots(of: page(DeleteAllView(counts: counts, erase: { false }, typed: "DEL")), variants: variants)
    }

    /// L02.
    @Test func lockScreen() {
        assertScreenSnapshots(of: AppLockView(biometry: .faceID) {}, variants: variants)
    }

    /// S04.
    @Test func appearance() {
        var settings = AppearanceSettings()
        assertScreenSnapshots(
            of: page(AppearanceSettingsView(settings: Binding { settings } set: { settings = $0 }, language: "English")), variants: variants
        )
    }

    /// Appearance › Language: the iPhone's language, then MimoDays' own, each named in its own words.
    @Test func language() {
        assertScreenSnapshots(of: page(LanguageSettingsView(language: AppLanguage(defaults: UserDefaults(suiteName: "language-snapshot")!, domain: nil))), variants: variants)
    }

    /// S05 with Higher contrast: links, secondary words and the coral button get their darker colours.
    @Test func privacyInHigherContrast() {
        var settings = PrivacySettings()
        settings.appLock = true
        assertScreenSnapshots(
            of: page(PrivacySettingsView(
                settings: Binding { settings } set: { settings = $0 }, biometry: .faceID, placeCount: 3, turnOnLock: { true }, removePlaces: {}
            )),
            variants: [SnapshotVariant(.iPhone, .light, highContrast: true), SnapshotVariant(.iPhone, .dark, highContrast: true)]
        )
    }

    /// S07.
    @Test func help() {
        assertScreenSnapshots(of: page(HelpView(version: "1.0 (12)")), variants: variants)
    }

    /// S07's help pages.
    @Test func helpArticles() {
        for article in HelpArticle.allCases {
            assertScreenSnapshots(of: page(HelpArticleView(article: article)), variants: [SnapshotVariant(.iPhone, .light)] + SnapshotVariant.languages, testName: "helpArticle-\(article.rawValue)")
        }
    }

    /// Its payment sheet never answers, so the tile stays in D02.
    private final class WaitingTipStore: TipStore {
        func products() async throws -> [TipProduct] { try await SampleTipStore().products() }
        func purchase(productID _: String) async throws -> PurchaseOutcome {
            try await Task.sleep(for: .seconds(3600))
            return .cancelled
        }
    }

    /// D01.
    @Test func donations() async {
        let model = DonationsModel(store: SampleTipStore())
        await model.load()
        assertScreenSnapshots(of: page(DonationsView(model: model)), variants: variants)
    }

    /// D02: Medium's payment sheet is up.
    @Test func donationsPaying() async {
        let model = DonationsModel(store: WaitingTipStore())
        await model.load()
        let buying = Task { await model.buy(.medium) }
        while model.purchasing == nil { await Task.yield() }
        assertScreenSnapshots(of: page(DonationsView(model: model)), variants: [SnapshotVariant(.iPhone, .light)])
        buying.cancel()
    }

    /// D03.
    @Test func donationsThankYou() {
        assertScreenSnapshots(of: ThankYouSheet(), variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark)])
    }

    /// D04.
    @Test func donationsUnavailable() async {
        let model = DonationsModel(store: FakeTipStore(products: []))
        await model.load()
        assertScreenSnapshots(of: page(DonationsView(model: model)), variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark)])
    }
}
