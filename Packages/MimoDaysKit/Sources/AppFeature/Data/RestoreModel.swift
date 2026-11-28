import Core
import Foundation
import Observation
import os
import Persistence

/// E07 -> E08: the chosen file is read whole and checked before anything changes; then the missing moments (or
/// everything) are unpacked next to the store and put back. A file that isn't a backup, one from a newer
/// MimoDays, or one that wouldn't fit leaves this iPhone as it was.
@MainActor
@Observable
final class RestoreModel {
    enum Phase: Equatable {
        case checking(Double)
        /// E07.
        case ready(BackupService.Summary)
        case restoring(Double)
        /// E08.
        case done(BackupService.Outcome)
        case failed(Failure)
    }

    enum Failure: Equatable {
        case notABackup
        case newerVersion
        case space(needed: Int64)
        case other
    }

    var phase = Phase.checking(0)
    var mode = BackupService.Mode.addMissing
    let url: URL

    private let library: MediaLibrary
    private let service: BackupService
    private let freeSpace: () -> Int64?
    private var check: BackupArchive.Check?
    private var task: Task<Void, Never>? {
        // P3.5: Make smaller waits while this reads the files, and keeps the ones it replaces.
        didSet {
            if task == nil {
                library.use?.end(reading)
                reading = nil
            } else if reading == nil {
                reading = library.use?.begin()
            }
        }
    }
    private var reading: UUID?
    private static let logger = Logger(subsystem: "MimoDays", category: "Restore")

    /// S09 on this iPhone: restored moments get their day by it, not the one the sending phone stored (rev-library).
    private let days: MemoriesSettings.Days

    init(
        url: URL, library: MediaLibrary, days: MemoriesSettings.Days = .whereTaken, now: @escaping () -> Date = Date.init,
        freeSpace: @escaping () -> Int64? = BackupModel.deviceFreeSpace
    ) {
        self.url = url
        self.library = library
        self.days = days
        self.freeSpace = freeSpace
        service = BackupService(library: library, now: now)
    }

    /// How many moments the chosen way would add (E07's button). Replacing counts only the ones that can come in
    /// whole, so a backup with none can't replace the library with nothing.
    var adding: Int {
        guard case let .ready(summary) = phase else { return 0 }
        return mode == .addMissing ? summary.new : summary.restorable
    }

    /// Whether E07's button has anything to do: moments, or (adding) only movies and collections.
    var canRestore: Bool {
        guard case let .ready(summary) = phase else { return false }
        return adding > 0 || (mode == .addMissing && summary.addsMore)
    }

    /// Reads the whole file once, hashing every entry.
    func start() {
        guard task == nil, case .checking = phase else { return }
        let url = url
        task = Task { [weak self] in
            let report: @Sendable (Double) -> Void = { progress in Task { @MainActor in self?.progress(checking: progress) } }
            let result = await detachedWork { () -> Result<BackupArchive.Check, BackupArchive.Failure> in
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    return .success(try BackupArchive.check(url, progress: report, isCancelled: { Task.isCancelled }))
                } catch let failure as BackupArchive.Failure {
                    return .failure(failure)
                } catch {
                    return .failure(.unreadable)
                }
            }
            guard let self, !Task.isCancelled else { return }
            task = nil
            switch result {
            case let .success(check):
                self.check = check
                phase = .ready(service.summary(check))
            case .failure(.newerVersion):
                phase = .failed(.newerVersion)
            case .failure(.notABackup):
                phase = .failed(.notABackup)
            case .failure:
                phase = .failed(.other)
            }
        }
    }

    /// E07's button: unpack what's needed, then put the records back.
    func restore() {
        guard task == nil, let check, case .ready = phase else { return }
        let moved = library.archive?.entries ?? []
        let wanted = service.files(for: check, mode: mode, moved: moved)
        let needed = Int64(Double(service.bytes(of: wanted, in: check.document)) * 1.05)
        if let free = freeSpace(), free < needed {
            phase = .failed(.space(needed: needed - free))
            return
        }
        let folder = library.store.root.appending(path: MediaStore.stagingPrefix + UUID().uuidString, directoryHint: .isDirectory)
        let url = url
        let mode = mode
        let checksums = check.document.files.mapValues(\.sha256)
        phase = .restoring(0)
        task = Task { [weak self] in
            let report: @Sendable (Double) -> Void = { progress in Task { @MainActor in self?.progress(restoring: progress) } }
            let unpacked = await detachedWork { () -> [String: URL]? in
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                var files: [String: URL] = [:]
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try BackupArchive.extract(url, paths: wanted, checksums: checksums, into: folder, progress: report, isCancelled: { Task.isCancelled }) { path, file in
                        files[path] = file
                    }
                    return files
                } catch {
                    return nil
                }
            }
            defer { try? FileManager.default.removeItem(at: folder) }
            guard let self, !Task.isCancelled else { return }
            task = nil
            guard let unpacked else {
                phase = .failed(.other)
                return
            }
            do {
                let outcome = try service.restore(check, mode: mode, unpacked: unpacked, moved: moved)
                do {
                    try MomentDays.relabel(library.context, days: days)
                } catch {
                    Self.logger.error("Relabelling restored days failed: \(error.localizedDescription, privacy: .public)")
                }
                // P3.6: those are on the phone again.
                if !outcome.broughtBack.isEmpty { try? await library.archive?.forget(outcome.broughtBack, in: nil) }
                phase = .done(outcome)
            } catch {
                Self.logger.error("Restoring failed: \(error.localizedDescription, privacy: .public)")
                phase = .failed(.other)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    /// Waits for the check or the restore (tests).
    func settled() async {
        await task?.value
    }

    private func progress(checking value: Double) {
        if case .checking = phase { phase = .checking(value) }
    }

    private func progress(restoring value: Double) {
        if case .restoring = phase { phase = .restoring(value) }
    }
}
