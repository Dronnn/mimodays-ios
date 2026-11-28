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

/// P3.5 X05 / P3.6: makes the chosen videos smaller one moment at a time, in the background of the app; when moving
/// originals, each full-size file is first copied to the person's folder and read back there. A moment's streams are
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
        var total: Int
        var done: Int
        var skipped: Int
        var freed: Int64
        var moving = false
        var stoppedForSpace = false
        var stopped = false
        /// P3.6: the folder couldn't be opened (a drive unplugged, the folder gone).
        var folderUnavailable = false
    }

    /// What is left of a run, saved after each moment.
    struct Job: Codable, Equatable {
        var size: VideoSize
        var remaining: [UUID]
        var total: Int
        var done = 0
        var skipped = 0
        var freed: Int64 = 0
        /// P3.6: originals go to the folder first.
        var moving = false
    }

    enum BringBack: Equatable {
        case done
        case busy
        case noFolder
        case folderUnavailable
        /// The folder doesn't hold this moment's originals, or they didn't check out.
        case notFound
        case failed
    }

    private static let logger = Logger(subsystem: "MimoDays", category: "Storage")
    private static let key = "shrinkJob"
    /// Room kept free besides the new files.
    static let spareBytes: Int64 = 200_000_000

    private(set) var phase = Phase.idle
    private(set) var job: Job?
    var isRunning: Bool { phase == .running || phase == .waiting }

    private let library: MediaLibrary
    let archive: OriginalArchive?
    private let transcoder: any VideoTranscoding
    private let defaults: UserDefaults?
    private let busy: @MainActor () -> Bool
    private let freeSpace: @MainActor () -> Int64?
    private let scratch: URL
    private var task: Task<Void, Never>?
    /// Replaced files kept while something read them.
    private var leftovers: [String] = []

    init(
        library: MediaLibrary, archive: OriginalArchive? = nil, transcoder: any VideoTranscoding = AVVideoTranscoder(), defaults: UserDefaults?,
        busy: @escaping @MainActor () -> Bool = { false },
        freeSpace: @escaping @MainActor () -> Int64? = { CaptureStorage.freeBytes() },
        scratch: URL = FileManager.default.temporaryDirectory
    ) {
        self.library = library
        self.archive = archive
        self.transcoder = transcoder
        self.defaults = defaults
        self.busy = busy
        self.freeSpace = freeSpace
        self.scratch = scratch
        job = defaults?.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(Job.self, from: $0) }
    }

    /// X04 "Make smaller", or a Memory Card's "Make smaller"; with `moving`, X06 "Move originals" (always to Compact).
    func start(_ selection: ShrinkSelection, size: VideoSize, moving: Bool = false) {
        guard !isRunning else { return }
        let size = moving ? .compact : size
        let ids = (try? ShrinkPolicy.candidates(selection, size: size, in: library.context).map(\.id)) ?? []
        job = Job(size: size, remaining: ids, total: ids.count, moving: moving)
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

    /// X05 "Done": back to X04.
    func acknowledge() {
        if case .finished = phase { phase = .idle }
    }

    private func run() {
        phase = .running
        task = Task { [weak self] in
            guard let self else { return }
            var folder: URL?
            if job?.moving == true {
                guard let picked = try? archive?.folder() else {
                    finish(folderUnavailable: true)
                    return
                }
                folder = picked
            }
            let scoped = folder?.startAccessingSecurityScopedResource() ?? false
            defer { if scoped { folder?.stopAccessingSecurityScopedResource() } }
            while let id = job?.remaining.first, !Task.isCancelled {
                while busy(), !Task.isCancelled {
                    phase = .waiting
                    try? await Task.sleep(for: .seconds(1))
                }
                guard !Task.isCancelled else { return }
                phase = .running
                removeLeftovers()
                let result = await shrink(id, folder: folder)
                // Stopped meanwhile: the job may be a new run's already.
                guard !Task.isCancelled else { return }
                switch result {
                case let .done(freed):
                    job?.done += 1
                    job?.freed += freed
                case .skipped:
                    job?.skipped += 1
                case .noSpace:
                    finish(stoppedForSpace: true)
                    return
                case .folderUnavailable:
                    finish(folderUnavailable: true)
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

    private func finish(stoppedForSpace: Bool = false, stopped: Bool = false, folderUnavailable: Bool = false) {
        let job = job ?? Job(size: .compact, remaining: [], total: 0)
        phase = .finished(Outcome(
            total: job.total, done: job.done, skipped: job.skipped, freed: job.freed, moving: job.moving,
            stoppedForSpace: stoppedForSpace, stopped: stopped, folderUnavailable: folderUnavailable
        ))
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
        case folderUnavailable
        case cancelled
    }

    private func shrink(_ id: UUID, folder: URL?) async -> Result {
        guard let job, let candidate = try? ShrinkPolicy.candidates(.chosen([id]), size: job.size, in: library.context).first else {
            // Gone, deleted, or already that small: nothing to do.
            return .done(freed: 0)
        }
        let needed = candidate.estimatedBytes(at: job.size) + Self.spareBytes
        if let free = freeSpace(), free < needed { return .noSpace }
        let work = scratch.appending(path: "Shrink-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: work) }
        var copies: [(stream: ShrinkCandidate.Stream, url: URL)] = []
        var moved: [MovedOriginal] = []
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            for stream in candidate.streams {
                let source = try library.store.url(for: stream.relativePath)
                if let folder {
                    let entry = MovedOriginal(
                        mediaID: stream.mediaID, momentID: id,
                        fileName: OriginalArchive.fileName(capturedAt: candidate.capturedAt, selfie: stream.isSelfie, mediaID: stream.mediaID),
                        checksum: stream.checksum, byteCount: stream.byteCount, pixelWidth: stream.pixelWidth, pixelHeight: stream.pixelHeight,
                        codec: stream.codec, movedAt: .now
                    )
                    do {
                        try await detachedWork { try OriginalArchive.put(source, as: entry.fileName, checksum: entry.checksum, in: folder) }
                    } catch {
                        Self.logger.error("Copying an original to the folder failed: \(error.localizedDescription, privacy: .public)")
                        discard(moved, from: folder)
                        // A folder that can't be written to at all stops the run; one bad file skips its moment.
                        return FileManager.default.isWritableFile(atPath: folder.path) ? .skipped : .folderUnavailable
                    }
                    moved.append(entry)
                }
                let copy = work.appending(path: "\(stream.mediaID.uuidString).mov")
                try await transcoder.transcode(source, to: copy, size: job.size)
                let size = Int64((try? copy.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                guard size > 0, size < stream.byteCount, await TranscodeCheck.matches(original: source, copy: copy, size: job.size) else {
                    Self.logger.notice("A smaller copy didn't stand in; the original stays")
                    discard(moved, from: folder)
                    return .skipped
                }
                copies.append((stream, copy))
            }
        } catch is CancellationError {
            discard(moved, from: folder)
            return .cancelled
        } catch {
            discard(moved, from: folder)
            if Task.isCancelled { return .cancelled }
            Self.logger.error("Making a video smaller failed: \(error.localizedDescription, privacy: .public)")
            return .skipped
        }
        guard !Task.isCancelled else {
            discard(moved, from: folder)
            return .cancelled
        }
        // The moved originals are listed before their phone copies go: ended in between, the list still finds them
        // (rev-data 1). One that can't be listed stays on the phone.
        if let folder, !moved.isEmpty {
            do { try await archive?.record(moved, in: folder) } catch {
                Self.logger.error("Recording moved originals failed: \(error.localizedDescription, privacy: .public)")
                discard(moved, from: folder)
                return .skipped
            }
        }
        let result = await commit(id, copies.map { ($0.stream.mediaID, $0.stream.checksum, $0.url) })
        if case .done = result {} else if let folder, !moved.isEmpty {
            try? await archive?.forget(Set(moved.map(\.mediaID)), in: folder)
            discard(moved, from: folder)
        }
        return result
    }

    /// A moment whose swap didn't happen keeps its original on the phone: its copy in the folder goes.
    private func discard(_ moved: [MovedOriginal], from folder: URL?) {
        guard let folder else { return }
        for entry in moved { OriginalArchive.remove(entry, from: folder) }
    }

    /// The new files in, the records changed in one save, then the old files out. Each file replaces the stream
    /// whose checksum it was made from; a stream changed meanwhile leaves the whole moment as it is.
    private func commit(_ id: UUID, _ files: [(mediaID: UUID, checksum: String, url: URL)]) async -> Result {
        var infos: [UUID: MomentSaver.Info] = [:]
        for file in files {
            guard let info = try? await MomentSaver.videoInfo(file.url) else { return .skipped }
            infos[file.mediaID] = info
        }
        let context = library.context
        guard let moment = try? context.fetch(FetchDescriptor<Moment>(predicate: #Predicate { $0.id == id })).first else { return .done(freed: 0) }
        // Changed since it was read (an edit, a restore): leave it.
        let current = Dictionary(uniqueKeysWithValues: moment.media.map { ($0.id, $0) })
        guard files.allSatisfy({ current[$0.mediaID]?.checksum == $0.checksum }) else { return .skipped }
        var stored: [String] = []
        var replaced: [String] = []
        var freed: Int64 = 0
        // Moved in and hashed off the main actor: a brought-back original can be gigabytes (rev-data 4).
        var news: [UUID: StoredFile] = [:]
        let store = library.store
        do {
            for file in files {
                let url = file.url
                let new = try await detachedWork { try store.store(moving: url, in: .originals, fileExtension: "mov") }
                stored.append(new.relativePath)
                news[file.mediaID] = new
            }
        } catch {
            for path in stored { try? library.store.remove(path) }
            Self.logger.error("Storing a smaller video failed: \(error.localizedDescription, privacy: .public)")
            return .skipped
        }
        // Changed while the files went in: leave it.
        guard files.allSatisfy({ current[$0.mediaID]?.checksum == $0.checksum }) else {
            for path in stored { try? library.store.remove(path) }
            return .skipped
        }
        do {
            for file in files {
                guard let media = current[file.mediaID], let info = infos[file.mediaID], let new = news[file.mediaID] else { continue }
                replaced.append(media.relativePath)
                freed += media.byteCount - new.byteCount
                media.relativePath = new.relativePath
                media.checksum = new.checksum
                media.byteCount = new.byteCount
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
        return .done(freed: freed)
    }

    // MARK: Bring back

    /// P3.6 Memory Card ••• "Bring back the original": the moment's full-size files from the folder, checked, in place
    /// of its Compact copies. Looks in the folder's own list too, for originals moved on another iPhone.
    func bringBack(_ momentID: UUID) async -> BringBack {
        guard !isRunning, !busy() else { return .busy }
        guard let archive, archive.hasFolder else { return .noFolder }
        guard let folder = try? archive.folder() else { return .folderUnavailable }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let media = (try? library.context.fetch(FetchDescriptor<Moment>(predicate: #Predicate { $0.id == momentID })).first)?.media ?? []
        var entries = archive.moved(momentID)
        if entries.isEmpty {
            let ids = Set(media.map(\.id))
            entries = OriginalArchive.manifest(in: folder).filter { ids.contains($0.mediaID) }
        }
        guard !entries.isEmpty else { return .notFound }
        let needed = entries.reduce(Int64(0)) { $0 + $1.byteCount } + Self.spareBytes
        if let free = freeSpace(), free < needed { return .failed }
        let work = scratch.appending(path: "Shrink-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: work) }
        var files: [(mediaID: UUID, checksum: String, url: URL)] = []
        for entry in entries {
            // The phone's copy now, to check nothing changed while the original was read.
            guard let current = media.first(where: { $0.id == entry.mediaID }) else { return .notFound }
            do {
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                // Moved before another folder was picked: from the folder it went to (rev-data 2).
                let source = archive.folder(of: entry, otherThan: folder)
                let scopedSource = source?.startAccessingSecurityScopedResource() ?? false
                defer { if scopedSource { source?.stopAccessingSecurityScopedResource() } }
                let from = source ?? folder
                let copy = try await detachedWork { try OriginalArchive.fetch(entry, from: from, into: work) }
                files.append((entry.mediaID, current.checksum, copy))
            } catch {
                Self.logger.error("Bringing an original back failed: \(error.localizedDescription, privacy: .public)")
                return .notFound
            }
        }
        guard case .done = await commit(momentID, files) else { return .failed }
        do { try await archive.forget(Set(entries.map(\.mediaID)), in: folder) } catch {
            Self.logger.error("Forgetting brought-back originals failed: \(error.localizedDescription, privacy: .public)")
        }
        return .done
    }
}
