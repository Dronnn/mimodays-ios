@testable import AppFeature
@testable import Core
import DesignSystem
import Foundation
import Persistence
import SwiftData
import SwiftUI
import Testing
import TestSupport

/// Export, import, backup, restore and storage: E01, E02, E03, E04p, E04, E06, E07, E08 and E09.
@MainActor
@Suite(.tags(.snapshot), .serialized)
struct DataSnapshotTests {
    private let container = try! TestStore.container()
    private let store: MediaStore
    private static var containers: [ModelContainer] = []

    init() throws {
        store = try MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "DataSnapshots-\(UUID().uuidString)"))
        Self.containers.append(container)
    }

    private var library: MediaLibrary { MediaLibrary(context: container.mainContext, store: store, thumbnails: ThumbnailPipeline()) }

    private func fill(_ count: Int = 6) async throws {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let saver = MomentSaver(context: container.mainContext, store: store, clock: TestDateProvider(), freeBytes: { nil })
        for index in 0..<count {
            let capture = CaptureResult(
                media: .photo(try await engine.capturePhoto(flash: false, silent: true)), window: .init(),
                capturedAt: CaptureTime(instant: Date(timeIntervalSince1970: 1_791_374_400 + Double(index) * 86_400), timeZone: .gmt)
            )
            _ = try await saver.save(MomentDraft(capture: capture, caption: "", window: nil, promptID: nil))
        }
    }

    private func page(_ view: some View) -> some View {
        NavigationStack { view.background(ColorToken.canvas.color.ignoresSafeArea()) }
            .environment(AppRouter())
            .environment(\.mediaLibrary, library)
    }

    private func backupModel() -> BackupModel {
        BackupModel(library: library, freeSpace: { 12_000_000_000 }, scheduleReminder: { _, _ in })
    }

    private let variants = [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge)]

    /// E09.
    @Test func storage() async throws {
        try await fill()
        let empty = FileManager.default.temporaryDirectory.appending(path: "Empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 300_000).write(to: empty.appending(path: "preview.jpg"))
        let model = StorageModel(library: library, temporaryDirectory: empty)
        assertScreenSnapshots(of: page(StorageView(model: model, openMovies: {})), variants: variants)
    }

    /// E06, 18 days after the last backup.
    @Test func backup() async throws {
        try await fill()
        container.mainContext.insert(BackupManifest(formatVersion: 1, createdAt: Date.now.addingTimeInterval(-18 * 86_400)))
        try container.mainContext.save()
        let model = backupModel()
        assertScreenSnapshots(of: page(BackupView(model: model, backUp: {}, restore: {})), variants: variants)
    }

    /// E06 before any backup.
    @Test func backupNever() async throws {
        try await fill()
        assertScreenSnapshots(of: page(BackupView(model: backupModel(), backUp: {}, restore: {})), variants: [SnapshotVariant(.iPhone, .light)])
    }

    /// E03.
    @Test func backupOptions() async throws {
        try await fill()
        assertScreenSnapshots(of: page(BackupOptionsView(model: backupModel(), back: {})), variants: variants)
    }

    /// E04p.
    @Test func backupProgress() {
        assertScreenSnapshots(
            of: page(BackupProgressView(step: .packing, progress: 0.64, moments: 1204, cancel: {}, choose: {})),
            variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark)]
        )
    }

    /// E04.
    @Test func backupSaved() {
        let saved = BackupModel.Saved(url: URL(filePath: "/private/MimoDays Backups/MimoDays-2026-11-11.mimodays"), bytes: 5_200_000_000, moments: 1204)
        assertScreenSnapshots(of: page(BackupSavedView(saved: saved, done: {})), variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark)])
    }

    /// E07.
    @Test func restoreReady() async throws {
        let model = RestoreModel(url: URL(filePath: "/tmp/x.mimodays"), library: library)
        model.phase = .ready(BackupService.Summary(
            createdAt: Date(timeIntervalSince1970: 1_792_843_200), moments: 1140, collections: 6, projects: 3, alreadyHere: 1110, isClean: true
        ))
        assertScreenSnapshots(of: page(RestoreView(model: model, close: {})), variants: variants)
    }

    /// E08.
    @Test func restoreDone() {
        let model = RestoreModel(url: URL(filePath: "/tmp/x.mimodays"), library: library)
        model.phase = .done(BackupService.Outcome(restored: 28, wanted: 30, damagedFiles: 2, alreadyHere: 1110))
        assertScreenSnapshots(of: page(RestoreView(model: model, close: {})), variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark)])
    }

    /// E08's note: a backup from a newer MimoDays.
    @Test func restoreNewer() {
        let model = RestoreModel(url: URL(filePath: "/tmp/x.mimodays"), library: library)
        model.phase = .failed(.newerVersion)
        assertScreenSnapshots(of: page(RestoreView(model: model, close: {})), variants: [SnapshotVariant(.iPhone, .light)])
    }

    /// E01: a photo with a voice note, a note and an exact place.
    @Test func exportMoment() async throws {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let saver = MomentSaver(context: container.mainContext, store: store, clock: TestDateProvider(), freeBytes: { nil })
        let capture = CaptureResult(
            media: .photo(try await engine.capturePhoto(flash: false, silent: true)), window: .init(),
            capturedAt: CaptureTime(instant: Date(timeIntervalSince1970: 1_791_374_400), timeZone: .gmt)
        )
        var draft = MomentDraft(
            capture: capture, caption: "Lunch", window: nil, promptID: nil,
            place: ReviewPlace(label: "Kentron", latitude: 40.1811, longitude: 44.5136, precision: .exact, source: .manual)
        )
        draft.note = "Soup"
        let voice = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).m4a")
        try Data(repeating: 5, count: 3_000).write(to: voice)
        draft.voice = ReviewVoiceNote(url: voice, duration: 1, recordedAt: .now, transcript: nil)
        let moment = try await saver.save(draft)
        let model = MomentExportModel(ids: [moment.id], library: library, freeSpace: { 12_000_000_000 })
        assertScreenSnapshots(of: page(MomentExportSheet(model: model).frame(maxHeight: .infinity, alignment: .bottom)), variants: variants)
    }

    /// E02: twelve moments as one archive.
    @Test func exportMoments() async throws {
        try await fill(12)
        let moments = try container.mainContext.fetch(FetchDescriptor<Moment>())
        // Simulated captures differ in size from run to run; the board's 240 MB is 20 MB a moment.
        for moment in moments {
            for media in moment.media { media.byteCount = 20_000_000 }
        }
        let ids = moments.map(\.id)
        let model = MomentExportModel(ids: ids, library: library, freeSpace: { 12_000_000_000 })
        model.archive = true
        assertScreenSnapshots(of: page(MomentsExportView(model: model, close: {})), variants: variants)
    }

    /// E05: eight picked, one of them a ten-second video, one already here.
    @Test func photoImport() {
        let model = PhotoImportModel(
            library: library, saver: MomentSaver(context: container.mainContext, store: store, freeBytes: { nil }), lookup: SimulatedPlaceLookup()
        )
        let time = CaptureTime(instant: Date(timeIntervalSince1970: 1_794_408_125), timeZone: .gmt)
        model.picked = (0..<8).map { index in
            PhotoImportModel.Picked(
                id: index, url: URL(filePath: "/tmp/\(index).jpg"), isVideo: index == 3, capturedAt: time, point: nil, checksum: "\(index)",
                duration: index == 3 ? 10 : nil, hasAudio: false
            )
        }
        model.skipped = [6]
        model.phase = .ready
        assertScreenSnapshots(of: page(PhotoImportView(model: model, close: {}, imported: {})), variants: variants)
    }
}
