@testable import AppFeature
@testable import Core
import Foundation
import Persistence
import SwiftData
import Testing
import TestSupport

/// E03-E08 flows: a backup is remembered only once it's been saved somewhere; a restore checks first and
/// refuses what isn't a backup or wouldn't fit.
@MainActor
@Suite(.serialized)
struct BackupModelTests {
    private let clock = TestDateProvider(Date(timeIntervalSince1970: 1_794_398_400))
    private static var containers: [ModelContainer] = []

    private func library(moments count: Int) async throws -> MediaLibrary {
        let container = try TestStore.container()
        Self.containers.append(container)
        let store = try MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "BackupModel-\(UUID().uuidString)"))
        let library = MediaLibrary(context: container.mainContext, store: store, thumbnails: ThumbnailPipeline())
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let saver = MomentSaver(context: library.context, store: store, clock: clock, freeBytes: { nil })
        for _ in 0..<count {
            let capture = CaptureResult(
                media: .photo(try await engine.capturePhoto(flash: .off, silent: true)), window: .init(),
                capturedAt: CaptureTime(instant: clock.now(), timeZone: .gmt)
            )
            _ = try await saver.save(MomentDraft(capture: capture, caption: "", window: nil, promptID: nil))
        }
        return library
    }

    private func model(_ library: MediaLibrary, free: Int64? = nil) -> BackupModel {
        BackupModel(library: library, now: { [clock] in clock.now() }, freeSpace: { free }, scheduleReminder: { _, _ in })
    }

    @Test func aBackupIsRememberedOnlyOnceSaved() async throws {
        let library = try await library(moments: 3)
        let model = model(library)
        #expect(model.last == nil && model.newSince == 3)
        model.start()
        await model.waitForPacking()
        #expect(model.phase == .working(.choosing, progress: 0))
        let packed = try #require(model.packed)
        #expect(FileManager.default.fileExists(atPath: packed.path))
        #expect(packed.lastPathComponent == BackupModel.fileName(clock.now()))
        #expect(try library.context.fetchCount(FetchDescriptor<BackupManifest>()) == 0)

        let destination = FileManager.default.temporaryDirectory.appending(path: "Saved-\(UUID().uuidString).mimodays")
        try FileManager.default.moveItem(at: packed, to: destination)
        model.saved(to: destination)
        guard case let .saved(saved) = model.phase else {
            Issue.record("Expected saved, got \(model.phase)")
            return
        }
        #expect(saved.moments == 3)
        #expect(model.last == clock.now() && model.newSince == 0)
        #expect(try BackupArchive.check(destination).damaged.isEmpty)
    }

    /// A real clock's time doesn't survive JSON's seconds-since-1970 to the last bit; the check must not care.
    @Test func aBackupMadeAtAnOddInstantStillChecksOut() async throws {
        let library = try await library(moments: 2)
        let odd = Date(timeIntervalSinceReferenceDate: 816_091_200.4938267)
        let model = BackupModel(library: library, now: { odd }, freeSpace: { nil }, scheduleReminder: { _, _ in })
        model.start()
        await model.waitForPacking()
        #expect(model.phase == .working(.choosing, progress: 0))
    }

    @Test func cancellingThrowsThePackedFileAway() async throws {
        let library = try await library(moments: 2)
        let model = model(library)
        model.start()
        await model.waitForPacking()
        let packed = try #require(model.packed)
        model.cancel()
        #expect(model.phase == .options)
        #expect(!FileManager.default.fileExists(atPath: packed.path))
    }

    @Test func noRoomStopsBeforePacking() async throws {
        let library = try await library(moments: 2)
        let model = model(library, free: 10)
        model.start()
        guard case let .failed(.space(needed)) = model.phase else {
            Issue.record("Expected a space failure, got \(model.phase)")
            return
        }
        #expect(needed > 0)
        #expect(model.packed == nil)
    }

    @Test func restoreChecksThenAddsWhatsMissing() async throws {
        let phone = try await library(moments: 3)
        let backup = model(phone)
        backup.start()
        await backup.waitForPacking()
        let url = try #require(backup.packed)

        let newPhone = try await library(moments: 1)
        let restore = RestoreModel(url: url, library: newPhone, freeSpace: { nil })
        restore.start()
        await restore.settled()
        guard case let .ready(summary) = restore.phase else {
            Issue.record("Expected ready, got \(restore.phase)")
            return
        }
        #expect(summary.moments == 3 && summary.alreadyHere == 0 && summary.isClean)
        #expect(restore.adding == 3)
        restore.restore()
        await restore.settled()
        #expect(restore.phase == .done(BackupService.Outcome(restored: 3, wanted: 3, damagedFiles: 0, alreadyHere: 0)))
        #expect(try newPhone.context.fetchCount(FetchDescriptor<Moment>()) == 4)
        // The unpacking folder is gone.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: newPhone.store.root.path).filter { $0.hasPrefix(".restore-") }
        #expect(leftovers.isEmpty)
    }

    @Test func restoreRefusesWhatWouldntFit() async throws {
        let phone = try await library(moments: 2)
        let backup = model(phone)
        backup.start()
        await backup.waitForPacking()
        let restore = RestoreModel(url: try #require(backup.packed), library: try await library(moments: 0), freeSpace: { 10 })
        restore.start()
        await restore.settled()
        restore.restore()
        guard case .failed(.space) = restore.phase else {
            Issue.record("Expected a space failure, got \(restore.phase)")
            return
        }
    }

    @Test func aPhotoIsNotABackup() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).jpg")
        try Data(repeating: 4, count: 1000).write(to: url)
        let restore = RestoreModel(url: url, library: try await library(moments: 0), freeSpace: { nil })
        restore.start()
        await restore.settled()
        #expect(restore.phase == .failed(.notABackup))
    }

    @Test func theLastBackupIsCountedInDays() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_794_398_400)
        #expect(DataFormat.ago(now, now: now, calendar: calendar) == "today")
        #expect(DataFormat.ago(now.addingTimeInterval(-86_400), now: now, calendar: calendar) == "yesterday")
        #expect(DataFormat.ago(now.addingTimeInterval(-18 * 86_400), now: now, calendar: calendar) == "18 days ago")
    }
}
