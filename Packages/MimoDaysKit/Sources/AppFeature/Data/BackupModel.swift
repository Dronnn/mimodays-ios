import Core
import Foundation
import Observation
import os
import Persistence
import UserNotifications

/// E06 -> E03 -> E04p -> E04: a backup is packed in the temporary folder, read back and checked, then moved
/// wherever the person picks. Only then is it remembered as made.
@MainActor
@Observable
final class BackupModel {
    enum Step: Int, CaseIterable, Comparable {
        case collecting, packing, checking, choosing

        static func < (lhs: Step, rhs: Step) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    enum Phase: Equatable {
        /// E03.
        case options
        /// E04p; `progress` is the packing step's share done.
        case working(Step, progress: Double)
        /// E04.
        case saved(Saved)
        case failed(Failure)
    }

    struct Saved: Equatable {
        var url: URL
        var bytes: Int64
        var moments: Int
    }

    enum Failure: Equatable {
        /// Not enough room to pack it; about this much more is needed.
        case space(needed: Int64)
        case other
    }

    var phase = Phase.options
    private(set) var contents = BackupService.Contents()
    private(set) var last: Date?
    private(set) var newSince = 0
    var includesRenders = false
    var reminder: BackupReminder {
        didSet {
            reminder.save()
            scheduleReminder(reminder, last ?? now())
        }
    }
    /// The packed file waiting for "Choosing where to save".
    private(set) var packed: URL?

    let library: MediaLibrary
    private let service: BackupService
    private let now: () -> Date
    private let freeSpace: () -> Int64?
    private let scheduleReminder: (BackupReminder, Date) -> Void
    private var task: Task<Void, Never>?
    private var document: BackupDocument?
    private static let logger = Logger(subsystem: "MimoDays", category: "Backup")

    init(
        library: MediaLibrary, now: @escaping () -> Date = Date.init, freeSpace: @escaping () -> Int64? = BackupModel.deviceFreeSpace,
        scheduleReminder: @escaping (BackupReminder, Date) -> Void = { $0.schedule(after: $1) }
    ) {
        self.library = library
        self.now = now
        self.freeSpace = freeSpace
        self.scheduleReminder = scheduleReminder
        service = BackupService(library: library, now: now)
        reminder = BackupReminder.saved
        refresh()
    }

    /// E06's card and E03's sizes.
    func refresh() {
        (last, newSince) = service.status()
        contents = service.contents()
    }

    var estimatedBytes: Int64 { contents.momentBytes + contents.projectBytes + (includesRenders ? contents.renderBytes : 0) }
    var available: Int64? { freeSpace() }

    /// E03 "Back up now" goes back to the options.
    func reset() {
        cancel()
        phase = .options
        refresh()
    }

    /// "Create backup".
    func start() {
        guard task == nil else { return }
        if let free = freeSpace(), Double(free) < Double(estimatedBytes) * 1.05 {
            phase = .failed(.space(needed: Int64(Double(estimatedBytes) * 1.05) - free))
            return
        }
        phase = .working(.collecting, progress: 0)
        let plan = service.plan(includesRenders: includesRenders)
        let url = FileManager.default.temporaryDirectory.appending(path: Self.fileName(plan.document.createdAt))
        task = Task { [weak self] in
            let update: @Sendable (Step, Double) -> Void = { step, progress in
                Task { @MainActor in self?.advance(step, progress) }
            }
            do {
                let written = try await Self.pack(plan.document, files: plan.files.map { Pair(path: $0.path, url: $0.url) }, to: url, update: update)
                guard let self, !Task.isCancelled else { return }
                document = written
                packed = url
                phase = .working(.choosing, progress: 0)
            } catch {
                try? FileManager.default.removeItem(at: url)
                guard let self, !Task.isCancelled else { return }
                Self.logger.error("Backup failed: \(String(describing: error), privacy: .public)")
                phase = .failed(.other)
            }
            self?.task = nil
        }
    }

    /// Steps only move on; a late progress report from an earlier step is dropped.
    private func advance(_ step: Step, _ progress: Double) {
        guard case let .working(current, _) = phase, step >= current, current != .choosing else { return }
        phase = .working(step, progress: progress)
    }

    /// The person picked a place and the file is there: remember the backup.
    func saved(to destination: URL) {
        guard let document else { return }
        service.record(document)
        packed = nil
        scheduleReminder(reminder, document.createdAt)
        phase = .saved(Saved(url: destination, bytes: document.files.values.reduce(Int64(0)) { $0 + $1.bytes }, moments: document.moments.count))
        refresh()
    }

    /// Cancel: stop packing and throw away whatever was packed.
    func cancel() {
        task?.cancel()
        task = nil
        if let packed { try? FileManager.default.removeItem(at: packed) }
        packed = nil
        document = nil
        if case .working = phase { phase = .options }
    }

    /// Waits for packing and checking to end (tests).
    func waitForPacking() async {
        await task?.value
    }

    /// Packs and reads it back; every file must hash to what the manifest says.
    nonisolated private static func pack(
        _ document: BackupDocument, files: [Pair], to url: URL, update: @escaping @Sendable (Step, Double) -> Void
    ) async throws -> BackupDocument {
        try await Task.detached(priority: .userInitiated) {
            update(.packing, 0)
            let written = try BackupArchive.write(
                document, files: files.map { ($0.path, $0.url) }, to: url, progress: { update(.packing, $0) }, isCancelled: { Task.isCancelled }
            )
            update(.checking, 0)
            let check = try BackupArchive.check(url, isCancelled: { Task.isCancelled })
            guard check.damaged.isEmpty, check.document == written else { throw BackupArchive.Failure.unreadable }
            return written
        }.value
    }

    private struct Pair: Sendable {
        let path: String
        let url: URL
    }

    /// "MimoDays-2026-11-11.mimodays".
    static func fileName(_ date: Date) -> String {
        let day = date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
        return "MimoDays-\(day).mimodays"
    }

    nonisolated static func deviceFreeSpace() -> Int64? {
        let values = try? URL.temporaryDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}

/// E06 "Remind me to back up": a local notification this long after the last backup, moved on by each one.
enum BackupReminder: String, CaseIterable {
    case never, weekly, monthly

    static let key = "backupReminder"
    static let notificationID = "backup-reminder"

    static var saved: BackupReminder {
        UserDefaults.standard.string(forKey: key).flatMap(BackupReminder.init(rawValue:)) ?? .monthly
    }

    func save() { UserDefaults.standard.set(rawValue, forKey: Self.key) }

    var days: Int? {
        switch self {
        case .never: nil
        case .weekly: 7
        case .monthly: 30
        }
    }

    /// Replaces the pending reminder; nothing is asked for here - without notification access it just won't show.
    func schedule(after date: Date) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        guard let days else { return }
        let fire = max(date.addingTimeInterval(Double(days) * 86_400).timeIntervalSinceNow, 60)
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Time for a backup", bundle: .module, comment: "Backup reminder notification title")
        content.body = String(localized: "Your newest moments are only on this iPhone. A backup keeps them safe.", bundle: .module, comment: "Backup reminder notification text")
        let request = UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: fire, repeats: false))
        center.add(request)
    }
}
