import Core
import Foundation
import Observation
import os
import Persistence
import SwiftData

/// P3.5 (Penpot §V3 X07 "Safety"): who reads moments' files right now - a backup, a restore, a moment export. Make
/// smaller waits for them before each video and keeps the files it replaced until they are done.
@MainActor
@Observable
final class MediaUse {
    private(set) var readers: Set<UUID> = []
    var isReading: Bool { !readers.isEmpty }

    func begin() -> UUID {
        let token = UUID()
        readers.insert(token)
        return token
    }

    func end(_ token: UUID?) {
        guard let token else { return }
        readers.remove(token)
    }
}

/// P3.5 X05: makes the chosen videos smaller one moment at a time, in the background of the app. A moment's streams are
/// made again in tmp, checked, then swapped in with one save; the old files go after the save, or once nothing reads
/// them. What is left is saved, so a run goes on after a restart from the video it stopped at; files from a run iOS
/// ended mid-way are left for the launch cleanup (tmp's Shrink- folders, files no record points to).
@MainActor
@Observable
final class ShrinkRun {
    enum Phase: Equatable {
        case idle
        case running
        /// A backup, restore or export holds the files: the next video waits for it.
        case waiting
        case finished(Outcome)
    }

    struct Outcome: Equatable {
        var done: Int
        var skipped: Int
        var freed: Int64
        var stoppedForSpace = false
        var stopped = false
    }

    /// What is left of a run, saved after each moment.
    struct Job: Codable, Equatable {
        var size: VideoSize
        var remaining: [UUID]
        var total: Int
        var done = 0
        var skipped = 0
        var freed: Int64 = 0
    }

    private static let logger = Logger(subsystem: "MimoDays", category: "Storage")
    private static let key = "shrinkJob"
    /// Room kept free besides the new files.
    static let spareBytes: Int64 = 200_000_000

    private(set) var phase = Phase.idle
    private(set) var job: Job?
    var isRunning: Bool { phase == .running || phase == .waiting }

    private let library: MediaLibrary
    private let transcoder: any VideoTranscoding
    private let defaults: UserDefaults?
    private let busy: @MainActor () -> Bool
    private let freeSpace: @MainActor () -> Int64?
    private let scratch: URL
    private var task: Task<Void, Never>?
    /// Replaced files kept while something read them.
    private var leftovers: [String] = []

    init(
        library: MediaLibrary, transcoder: any VideoTranscoding = AVVideoTranscoder(), defaults: UserDefaults?,
        busy: @escaping @MainActor () -> Bool = { false },
        freeSpace: @escaping @MainActor () -> Int64? = { CaptureStorage.freeBytes() },
        scratch: URL = FileManager.default.temporaryDirectory
    ) {
        self.library = library
        self.transcoder = transcoder
        self.defaults = defaults
        self.busy = busy
        self.freeSpace = freeSpace
        self.scratch = scratch
        job = defaults?.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(Job.self, from: $0) }
    }

    /// X04 "Make smaller", or a Memory Card's "Make smaller".
    func start(_ selection: ShrinkSelection, size: VideoSize) {
        guard !isRunning else { return }
        let ids = (try? ShrinkPolicy.candidates(selection, size: size, in: library.context).map(\.id)) ?? []
        job = Job(size: size, remaining: ids, total: ids.count)
        save()
        run()
    }

    /// At launch: a run iOS ended goes on.
    func resumeIfNeeded() {
        guard !isRunning, let job, !job.remaining.isEmpty else { return }
        run()
    }

    /// X05 "Stop": the moment being made is dropped, those done stay smaller.
    func stop() {
        task?.cancel()
        task = nil
        finish(stopped: true)
    }

    private func run() {
        phase = .running
        task = Task { [weak self] in
            guard let self else { return }
            while let id = job?.remaining.first, !Task.isCancelled {
                while busy(), !Task.isCancelled {
                    phase = .waiting
                    try? await Task.sleep(for: .seconds(1))
                }
                guard !Task.isCancelled else { return }
                phase = .running
                removeLeftovers()
                switch await shrink(id) {
                case let .done(freed):
                    job?.done += 1
                    job?.freed += freed
                case .skipped:
                    job?.skipped += 1
                case .noSpace:
                    finish(stoppedForSpace: true)
                    return
                case .cancelled:
                    return
                }
                job?.remaining.removeFirst()
                save()
            }
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    private func finish(stoppedForSpace: Bool = false, stopped: Bool = false) {
        let job = job ?? Job(size: .compact, remaining: [], total: 0)
        phase = .finished(Outcome(done: job.done, skipped: job.skipped, freed: job.freed, stoppedForSpace: stoppedForSpace, stopped: stopped))
        self.job = nil
        save()
        removeLeftovers()
    }

    private func save() {
        guard let defaults else { return }
        if let job, let data = try? JSONEncoder().encode(job) { defaults.set(data, forKey: Self.key) } else { defaults.removeObject(forKey: Self.key) }
    }

    private func removeLeftovers() {
        guard !busy(), !leftovers.isEmpty else { return }
        for path in leftovers {
            do { try library.store.remove(path) } catch {
                Self.logger.error("Removing a replaced video failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        leftovers = []
    }

    // MARK: One moment

    private enum Result {
        case done(freed: Int64)
        case skipped
        case noSpace
        case cancelled
    }

    private func shrink(_ id: UUID) async -> Result {
        guard let job, let candidate = try? ShrinkPolicy.candidates(.chosen([id]), size: job.size, in: library.context).first else {
            // Gone, deleted, or already that small: nothing to do.
            return .done(freed: 0)
        }
        let needed = candidate.estimatedBytes(at: job.size) + Self.spareBytes
        if let free = freeSpace(), free < needed { return .noSpace }
        let folder = scratch.appending(path: "Shrink-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        var copies: [(stream: ShrinkCandidate.Stream, url: URL)] = []
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for stream in candidate.streams {
                let source = try library.store.url(for: stream.relativePath)
                let copy = folder.appending(path: "\(stream.mediaID.uuidString).mov")
                try await transcoder.transcode(source, to: copy, size: job.size)
                let size = Int64((try? copy.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                guard size > 0, size < stream.byteCount, await TranscodeCheck.matches(original: source, copy: copy, size: job.size) else {
                    Self.logger.notice("A smaller copy didn't stand in; the original stays")
                    return .skipped
                }
                copies.append((stream, copy))
            }
        } catch is CancellationError {
            return .cancelled
        } catch {
            if Task.isCancelled { return .cancelled }
            Self.logger.error("Making a video smaller failed: \(error.localizedDescription, privacy: .public)")
            return .skipped
        }
        guard !Task.isCancelled else { return .cancelled }
        return await commit(id, copies)
    }

    /// The new files in, the records changed in one save, then the old files out.
    private func commit(_ id: UUID, _ copies: [(stream: ShrinkCandidate.Stream, url: URL)]) async -> Result {
        var infos: [UUID: MomentSaver.Info] = [:]
        for copy in copies {
            guard let info = try? await MomentSaver.videoInfo(copy.url) else { return .skipped }
            infos[copy.stream.mediaID] = info
        }
        let context = library.context
        guard let moment = try? context.fetch(FetchDescriptor<Moment>(predicate: #Predicate { $0.id == id })).first else { return .done(freed: 0) }
        // Changed since it was read (an edit, a restore): leave it.
        let current = Dictionary(uniqueKeysWithValues: moment.media.map { ($0.id, $0) })
        guard copies.allSatisfy({ current[$0.stream.mediaID]?.checksum == $0.stream.checksum }) else { return .skipped }
        var stored: [String] = []
        var replaced: [String] = []
        var freed: Int64 = 0
        do {
            for copy in copies {
                guard let media = current[copy.stream.mediaID], let info = infos[copy.stream.mediaID] else { continue }
                let file = try library.store.store(moving: copy.url, in: .originals, fileExtension: "mov")
                stored.append(file.relativePath)
                replaced.append(media.relativePath)
                freed += media.byteCount - file.byteCount
                media.relativePath = file.relativePath
                media.checksum = file.checksum
                media.byteCount = file.byteCount
                media.pixelWidth = info.width
                media.pixelHeight = info.height
                media.codec = info.codec
            }
            moment.modifiedAt = .now
            try context.save()
        } catch {
            context.rollback()
            for path in stored { try? library.store.remove(path) }
            Self.logger.error("Saving a smaller video failed: \(error.localizedDescription, privacy: .public)")
            return .skipped
        }
        leftovers.append(contentsOf: replaced)
        removeLeftovers()
        return .done(freed: max(freed, 0))
    }
}
