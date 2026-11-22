@testable import AppFeature
@testable import Core
import Foundation
import Persistence
import SwiftData
import Testing

/// P3.5 X05/X07: a run swaps smaller copies in one moment at a time, waits for backups, stops for space, goes on after a
/// restart, and never leaves a moment without its video.
@MainActor
@Suite(.serialized)
final class ShrinkRunTests {
    /// Stands in for the encoder: the copy is the original itself (a small real clip that passes the checks).
    struct CopyingTranscoder: VideoTranscoding {
        var before: @Sendable () async throws -> Void = {}
        func transcode(_ source: URL, to destination: URL, size: VideoSize) async throws {
            try await before()
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    private let container: ModelContainer
    private let store: MediaStore
    private let scratch: URL
    private let defaults: UserDefaults
    private var library: MediaLibrary { MediaLibrary(context: container.mainContext, store: store, thumbnails: ThumbnailPipeline()) }

    init() throws {
        container = try MimoDaysStore.makeContainer(inMemory: true)
        store = try MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "ShrinkRun-\(UUID().uuidString)"))
        scratch = FileManager.default.temporaryDirectory.appending(path: "ShrinkRunScratch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let suite = "ShrinkRunTests-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
    }

    deinit {
        try? FileManager.default.removeItem(at: store.root)
        try? FileManager.default.removeItem(at: scratch)
    }

    /// A video moment whose record says 1080p at a high bit rate, over a real small clip.
    private func moment(daysAgo: Int = 60) async throws -> Moment {
        let date = Date.now.addingTimeInterval(TimeInterval(-daysAgo * 86_400))
        let moment = Moment(captured: CaptureTime(instant: date, timeZone: .current), origin: .manual, mediaType: .video, createdAt: date)
        container.mainContext.insert(moment)
        for (role, position) in [(MediaRole.rearSource, CameraPosition.back), (.frontSource, .front)] {
            let clip = try await SimulatedMedia.writeClip(position, seconds: 1)
            let file = try store.store(copyOf: clip, in: .originals, fileExtension: "mov")
            try? FileManager.default.removeItem(at: clip)
            moment.media.append(MomentMedia(
                role: role, relativePath: file.relativePath, uniformType: "com.apple.quicktime-movie", pixelWidth: 1080, pixelHeight: 1920,
                checksum: file.checksum, byteCount: 60_000_000, duration: 1
            ))
        }
        try container.mainContext.save()
        return moment
    }

    private func paths(_ moment: Moment) -> Set<String> {
        Set(moment.media.filter { $0.role == .rearSource || $0.role == .frontSource }.map(\.relativePath))
    }

    private func exists(_ path: String) -> Bool {
        (try? store.url(for: path)).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    private func finished(_ run: ShrinkRun) async throws -> ShrinkRun.Outcome {
        for _ in 0..<600 {
            if case let .finished(outcome) = run.phase { return outcome }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("The run never finished")
        throw CancellationError()
    }

    private func leftoverScratch() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: scratch.path)) ?? []).filter { $0.hasPrefix("Shrink-") }
    }

    @Test func aRunSwapsInSmallerFiles() async throws {
        let first = try await moment(), second = try await moment(daysAgo: 90)
        let before = paths(first).union(paths(second))
        let run = ShrinkRun(library: library, transcoder: CopyingTranscoder(), defaults: defaults, freeSpace: { nil }, scratch: scratch)
        run.start(.all, size: .compact)
        let outcome = try await finished(run)
        #expect(outcome.done == 2 && outcome.skipped == 0)
        #expect(outcome.freed > 0)
        let after = paths(first).union(paths(second))
        #expect(after.isDisjoint(with: before))
        #expect(after.allSatisfy(exists))
        #expect(!before.contains(where: exists), "The replaced files are gone")
        let media = try #require(first.media.first { $0.role == .rearSource })
        #expect(media.byteCount < 60_000_000)
        #expect(media.pixelWidth < media.pixelHeight, "Upright size, from the new file")
        #expect(try store.verify(media.relativePath, checksum: media.checksum))
        #expect(run.job == nil && defaults.data(forKey: "shrinkJob") == nil)
        #expect(leftoverScratch().isEmpty)
    }

    /// X07: "Backup, export and Delete wait while a run holds files, and a run waits for them too."
    @Test func aRunWaitsForABackup() async throws {
        let moment = try await moment()
        let before = paths(moment)
        let busy = Flag(true)
        let run = ShrinkRun(library: library, transcoder: CopyingTranscoder(), defaults: defaults, busy: { busy.value }, freeSpace: { nil }, scratch: scratch)
        run.start(.all, size: .compact)
        try await Task.sleep(for: .milliseconds(100))
        #expect(run.phase == .waiting)
        #expect(paths(moment) == before)
        busy.value = false
        #expect(try await finished(run).done == 1)
        #expect(paths(moment).isDisjoint(with: before))
    }

    /// Low space leaves the original and stops the run where it is.
    @Test func lowSpaceStops() async throws {
        let moment = try await moment()
        let before = paths(moment)
        let run = ShrinkRun(library: library, transcoder: CopyingTranscoder(), defaults: defaults, freeSpace: { 1_000 }, scratch: scratch)
        run.start(.all, size: .compact)
        let outcome = try await finished(run)
        #expect(outcome.stoppedForSpace && outcome.done == 0)
        #expect(paths(moment) == before && before.allSatisfy(exists))
    }

    /// A failed copy leaves the original, and the run goes on to the next video.
    @Test func aFailedCopyLeavesTheOriginal() async throws {
        let moment = try await moment()
        let before = paths(moment)
        let failing = CopyingTranscoder(before: { throw TranscodeError.failed })
        let run = ShrinkRun(library: library, transcoder: failing, defaults: defaults, freeSpace: { nil }, scratch: scratch)
        run.start(.all, size: .compact)
        let outcome = try await finished(run)
        #expect(outcome.skipped == 1 && outcome.done == 0)
        #expect(paths(moment) == before && before.allSatisfy(exists))
        #expect(leftoverScratch().isEmpty)
    }

    /// A moment changed while its copy was made (a restore, a repair) is left as it is now.
    @Test func aChangedMomentIsLeft() async throws {
        let moment = try await moment()
        let media = try #require(moment.media.first { $0.role == .rearSource })
        let changing = CopyingTranscoder(before: { @MainActor in media.checksum = "changed" })
        let run = ShrinkRun(library: library, transcoder: changing, defaults: defaults, freeSpace: { nil }, scratch: scratch)
        let before = paths(moment)
        run.start(.all, size: .compact)
        #expect(try await finished(run).skipped == 1)
        #expect(paths(moment) == before && before.allSatisfy(exists))
    }

    /// X05 "Stop": the video being made is dropped, its original stays.
    @Test func stopKeepsTheOriginal() async throws {
        let moment = try await moment()
        let before = paths(moment)
        let slow = CopyingTranscoder(before: { try await Task.sleep(for: .seconds(30)) })
        let run = ShrinkRun(library: library, transcoder: slow, defaults: defaults, freeSpace: { nil }, scratch: scratch)
        run.start(.all, size: .compact)
        try await Task.sleep(for: .milliseconds(100))
        run.stop()
        guard case let .finished(outcome) = run.phase else { Issue.record("Not finished"); return }
        #expect(outcome.stopped && outcome.done == 0)
        #expect(defaults.data(forKey: "shrinkJob") == nil)
        try await Task.sleep(for: .milliseconds(100))
        #expect(paths(moment) == before && before.allSatisfy(exists))
    }

    /// A backup holds the files while it packs them, then lets go.
    @Test func aBackupHoldsTheFilesWhilePacking() async throws {
        _ = try await moment()
        let use = MediaUse()
        let reading = MediaLibrary(context: container.mainContext, store: store, thumbnails: ThumbnailPipeline(), use: use)
        let backup = BackupModel(library: reading, freeSpace: { nil })
        backup.start()
        #expect(use.isReading)
        for _ in 0..<500 where use.isReading { try await Task.sleep(for: .milliseconds(20)) }
        #expect(!use.isReading)
        #expect(backup.phase == .working(.choosing, progress: 0))
    }

    /// "It goes on next time, from the video it stopped at."
    @Test func aRunGoesOnAfterARestart() async throws {
        let first = try await moment(daysAgo: 90), second = try await moment()
        // iOS ended the app after the first video was planned: the saved job is all the next launch has.
        let job = ShrinkRun.Job(size: .compact, remaining: [first.id, second.id], total: 2)
        defaults.set(try JSONEncoder().encode(job), forKey: "shrinkJob")
        let next = ShrinkRun(library: library, transcoder: CopyingTranscoder(), defaults: defaults, freeSpace: { nil }, scratch: scratch)
        #expect(next.job?.total == 2)
        let firstBefore = paths(first)
        next.resumeIfNeeded()
        #expect(try await finished(next).done == 2)
        #expect(paths(first).isDisjoint(with: firstBefore))
    }
}

@MainActor
final class Flag {
    var value: Bool
    init(_ value: Bool) { self.value = value }
}
