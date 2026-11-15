@testable import AppFeature
@testable import Core
import DesignSystem
import Foundation
import Persistence
import SwiftData
import SwiftUI
import Testing
import TestSupport

/// Settings: S01, S02, S03 and S09.
@MainActor
@Suite(.tags(.snapshot), .serialized)
struct SettingsSnapshotTests {
    private let container = try! MimoDaysStore.makeContainer(inMemory: true)
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
        assertScreenSnapshots(of: page(SettingsView(model: model, importPhotos: {}, done: {})), variants: variants)
    }

    /// S02.
    @Test func surprises() async {
        let model = await model()
        assertScreenSnapshots(of: page(SurpriseSettingsView(model: model)), variants: variants)
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
}
