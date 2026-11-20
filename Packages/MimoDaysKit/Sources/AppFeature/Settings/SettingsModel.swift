import Core
import Foundation
import Observation
import os
import Persistence
import SwiftData

/// S01's values and S02's surprise settings. Surprise changes are saved at once and the coming surprises are
/// planned again.
@MainActor
@Observable
final class SettingsModel {
    enum Pause: Equatable {
        case off
        case until(Date)
        case indefinitely
    }

    let library: MediaLibrary
    /// S02.
    var reminders = ReminderSchedule() {
        didSet { if reminders != oldValue { saveSchedule() } }
    }

    private(set) var surprisesOn = false
    var expiryMinutes = 15 {
        didSet { if expiryMinutes != oldValue { saveSchedule() } }
    }

    private(set) var pause = Pause.off
    private(set) var notifications = PermissionStatus.notDetermined
    /// S01's Storage and Backup lines; the size is open for snapshots, which can't rely on what tmp holds.
    var storageBytes: Int64?
    private(set) var lastBackup: Date?

    static let expiryChoices = [5, 10, 15, 30, 60]

    /// The plan being drawn again after the last change; tests wait for it.
    @ObservationIgnored private(set) var replanning: Task<Void, Never>?

    private let surprises: SurpriseCoordinator?
    private let permissions: any PermissionService
    private var isLoading = false
    private static let logger = Logger(subsystem: "MimoDays", category: "Settings")

    init(library: MediaLibrary, surprises: SurpriseCoordinator?, permissions: any PermissionService) {
        self.library = library
        self.surprises = surprises
        self.permissions = permissions
    }

    private var context: ModelContext { library.context }

    func load() async {
        // Only while the fields are filled in: a change made while the notification status is read below is saved.
        isLoading = true
        if let stored = schedule() {
            reminders = ReminderSchedule(
                frequency: stored.frequency, weekdayMask: stored.weekdayMask, earliestMinute: stored.earliestMinute, latestMinute: stored.latestMinute
            )
            expiryMinutes = stored.expiryMinutes
            surprisesOn = stored.isEnabled
            pause = stored.isPausedIndefinitely ? .indefinitely : stored.pausedUntil.map(Pause.until) ?? .off
        }
        let backups = (try? context.fetch(FetchDescriptor<BackupManifest>(predicate: #Predicate { $0.restoredAt == nil }))) ?? []
        lastBackup = backups.map(\.createdAt).max()
        isLoading = false
        // Its initializer measures once.
        storageBytes = StorageModel(library: library).usage.total
        notifications = await permissions.status(of: .notifications)
    }

    /// "Surprise me": turning it on asks for notifications the first time, through `request` (the view's explainer).
    func setSurprises(_ isOn: Bool, request: ((Permission) async -> PermissionStatus)? = nil) async {
        surprisesOn = isOn
        if isOn, notifications == .notDetermined {
            notifications = if let request { await request(.notifications) } else { await permissions.request(.notifications) }
        }
        if isOn {
            pause = .off
            if let surprises { await surprises.turnOn() } else { saveSchedule() }
        } else {
            saveSchedule()
        }
    }

    func pause(_ length: SurprisePause) async {
        await surprises?.pause(length)
        await reloadPause()
    }

    /// "Send a surprise now": false when it couldn't be sent (notifications not allowed).
    func sendSurpriseNow() async -> Bool {
        await surprises?.sendNow() ?? false
    }

    func resume() async {
        await surprises?.resume()
        await reloadPause()
    }

    private func reloadPause() async {
        guard let stored = schedule() else { return }
        pause = stored.isPausedIndefinitely ? .indefinitely : stored.pausedUntil.map(Pause.until) ?? .off
    }

    private func saveSchedule() {
        guard !isLoading else { return }
        let stored = schedule() ?? {
            let schedule = SurpriseSchedule()
            context.insert(schedule)
            return schedule
        }()
        stored.frequency = reminders.frequency
        stored.weekdayMask = reminders.weekdayMask
        stored.earliestMinute = reminders.earliestMinute
        stored.latestMinute = reminders.latestMinute
        stored.expiryMinutes = expiryMinutes
        stored.isEnabled = surprisesOn
        do {
            try context.save()
        } catch {
            Self.logger.error("Saving surprise settings failed: \(error.localizedDescription, privacy: .public)")
        }
        if let surprises { replanning = Task { await surprises.settingsChanged() } }
    }

    private func schedule() -> SurpriseSchedule? {
        var descriptor = FetchDescriptor<SurpriseSchedule>()
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
