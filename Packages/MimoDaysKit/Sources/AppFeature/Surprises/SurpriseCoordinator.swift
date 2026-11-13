import Core
import Foundation
import os
import Persistence
import SwiftData

/// Keeps the saved surprise prompts and iOS's pending notifications in line with the person's settings (doc 01 §6).
///
/// Every prompt is a `SurprisePrompt` row before it is a notification, so a relaunch never draws a period twice
/// and notifications can always be rebuilt from the store.
@MainActor
final class SurpriseCoordinator {
    /// iOS keeps at most 64 pending requests per app; the 14-day plan needs at most 42.
    static let notificationLimit = 60

    nonisolated static let title = LocalizedStringResource("A little moment is happening.", bundle: .atURL(Bundle.module.bundleURL))
    nonisolated static let bodies = [
        LocalizedStringResource("Look around. This could be a memory.", bundle: .atURL(Bundle.module.bundleURL)),
        LocalizedStringResource("Whatever today looks like, it counts.", bundle: .atURL(Bundle.module.bundleURL)),
    ]

    private let context: ModelContext
    private let notifications: any NotificationScheduler
    private let permissions: any PermissionService
    private let clock: any DateProvider
    private let deviceCalendar: () -> Calendar
    private var generator: any RandomNumberGenerator
    private var running: Task<Void, Never>?
    private let logger = Logger(subsystem: "MimoDays", category: "Surprises")

    init(
        context: ModelContext,
        notifications: any NotificationScheduler,
        permissions: any PermissionService,
        clock: any DateProvider = SystemDateProvider(),
        calendar: @escaping () -> Calendar = { Calendar.current },
        generator: any RandomNumberGenerator = SystemRandomNumberGenerator()
    ) {
        self.context = context
        self.notifications = notifications
        self.permissions = permissions
        self.clock = clock
        deviceCalendar = calendar
        self.generator = generator
    }

    /// Expires missed prompts, plans what is missing and syncs notifications. Safe to call often:
    /// calls run one after another, and a period that has prompts is never drawn again.
    func refresh() async {
        await serially { await self.performRefresh(replan: false) }
    }

    /// After the person changes their surprise settings: the future plan is dropped and drawn again.
    func settingsChanged() async {
        await serially { await self.performRefresh(replan: true) }
    }

    // MARK: Pause

    /// Pauses quietly: no countdown, no resend of what was skipped (doc 01). Calendar days
    /// (Andrew, 2026-11-13): `.today` lasts until tonight's midnight, `.week` until midnight seven days from today.
    func pause(_ length: SurprisePause) async {
        await serially {
            guard let schedule = self.fetchSchedule() else { return }
            let calendar = self.calendar(for: schedule)
            let today = calendar.startOfDay(for: self.clock.now())
            switch length {
            case .today: schedule.pausedUntil = calendar.date(byAdding: .day, value: 1, to: today)
            case .week: schedule.pausedUntil = calendar.date(byAdding: .day, value: 7, to: today)
            case .indefinitely: schedule.isPausedIndefinitely = true
            }
            await self.performRefresh(replan: false)
        }
    }

    func resume() async {
        await serially {
            guard let schedule = self.fetchSchedule() else { return }
            schedule.pausedUntil = nil
            schedule.isPausedIndefinitely = false
            await self.performRefresh(replan: false)
        }
    }

    /// Today's "Turn on" (T07): surprises back on with the saved settings, or the defaults when there are none.
    func turnOn() async {
        await serially {
            let schedule = self.fetchSchedule() ?? {
                let schedule = SurpriseSchedule()
                self.context.insert(schedule)
                return schedule
            }()
            schedule.isEnabled = true
            schedule.pausedUntil = nil
            schedule.isPausedIndefinitely = false
            await self.performRefresh(replan: true)
        }
    }

    // MARK: Today

    /// What Today's ribbon says (T02-T07), and when that may change on its own (a prompt fires or expires,
    /// a pause ends). `latestCapture` is the newest moment: after it, a missed surprise is no longer news.
    func todayStatus(latestCapture: Date?) async -> (status: SurpriseStatus, changesAt: Date?) {
        let notifications = await permissions.status(of: .notifications)
        let now = clock.now()
        let schedule = fetchSchedule()
        let calendar = calendar(for: schedule)
        let prompts = fetchRecentPrompts(now: now, calendar: calendar)
        let status = SurpriseStatus(
            schedule: schedule, prompts: prompts, notificationsAllowed: notifications.isUsable,
            latestCapture: latestCapture, now: now, calendar: calendar
        )
        let pending = prompts.filter { $0.outcome == .pending }
        let changes = pending.map(\.expiresAt) + pending.map(\.plannedAt) + [schedule?.pausedUntil].compactMap(\.self)
        return (status, changes.filter { $0 > now }.min())
    }

    // MARK: Prompt lifecycle

    /// A notification tap (or Today) opening a prompt. True while it can still be answered as a surprise:
    /// pending and within its expiry window. Closing the camera keeps it answerable until it expires
    /// (Andrew, 2026-11-13); afterwards the person can still capture, just not as this surprise.
    func open(promptID: UUID) -> Bool {
        guard let prompt = fetchPrompt(promptID), prompt.outcome == .pending else { return false }
        let now = clock.now()
        guard now < prompt.expiresAt else {
            prompt.outcome = .expired
            save()
            return false
        }
        if prompt.openedAt == nil { prompt.openedAt = now }
        save()
        return true
    }

    /// Links a saved moment to the prompt it answered. Only a prompt that was opened in time counts,
    /// even when the moment is saved after the window closed; a manual capture never answers a prompt.
    func captured(promptID: UUID, momentID: UUID) {
        guard let prompt = fetchPrompt(promptID), prompt.openedAt != nil,
              prompt.outcome == .pending || prompt.outcome == .expired else { return }
        prompt.outcome = .captured
        prompt.capturedMomentID = momentID
        save()
    }

    // MARK: Refresh

    private func serially(_ work: @escaping @MainActor () async -> Void) async {
        let previous = running
        let task = Task { @MainActor in
            await previous?.value
            await work()
        }
        running = task
        await task.value
    }

    private func performRefresh(replan: Bool) async {
        let status = await permissions.status(of: .notifications)
        let now = clock.now()
        let schedule = fetchSchedule()
        if let pausedUntil = schedule?.pausedUntil, pausedUntil <= now { schedule?.pausedUntil = nil }
        let calendar = calendar(for: schedule)
        let prompts = fetchRecentPrompts(now: now, calendar: calendar)

        for prompt in prompts where prompt.outcome == .pending && prompt.expiresAt <= now {
            prompt.outcome = .expired
        }
        let upcoming = prompts.filter { $0.outcome == .pending && $0.plannedAt > now }

        if let schedule, schedule.isEnabled, !schedule.isPausedIndefinitely, status.isUsable {
            let rules = schedule.rules
            let notBefore = max(now, schedule.pausedUntil ?? now)
            // A plan that no longer fits (new hours, days, pause or time zone) is drawn again from now on.
            if replan || upcoming.contains(where: { !fits($0.plannedAt, rules, calendar, notBefore: notBefore) }) {
                upcoming.forEach { $0.outcome = .cancelled }
            }
            let planned = prompts.filter { $0.outcome != .cancelled }.map(\.plannedAt)
            let times = SurprisePlanner(calendar: calendar).draw(rules, now: notBefore, planned: planned, using: &generator)
            for time in times {
                let id = UUID()
                context.insert(SurprisePrompt(
                    id: id, plannedAt: time,
                    expiresAt: time.addingTimeInterval(TimeInterval(schedule.expiryMinutes * 60)),
                    notificationRequestID: id.uuidString
                ))
            }
        } else {
            upcoming.forEach { $0.outcome = .cancelled }
        }
        save()
        await syncNotifications(now: now)
    }

    /// Schedules the next pending prompts that iOS doesn't have yet and removes every request without one.
    private func syncNotifications(now: Date) async {
        let wanted = fetchUpcomingPending(now: now).map { (id: $0.notificationRequestID, fireDate: $0.plannedAt) }
        let scheduled = await notifications.pending()
        let wantedIDs = Set(wanted.map(\.id))
        let stale = scheduled.map(\.id).filter { !wantedIDs.contains($0) }
        if !stale.isEmpty { await notifications.cancel(ids: stale) }

        let fireDates = Dictionary(scheduled.map { ($0.id, $0.fireDate) }, uniquingKeysWith: { first, _ in first })
        for prompt in wanted where fireDates[prompt.id] != prompt.fireDate {
            let notification = SurpriseNotification(
                id: prompt.id, fireDate: prompt.fireDate,
                title: String(localized: Self.title), body: String(localized: Self.bodies.randomElement(using: &generator)!)
            )
            do {
                try await notifications.schedule(notification)
            } catch {
                logger.error("Scheduling a surprise failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: Rules

    private func calendar(for schedule: SurpriseSchedule?) -> Calendar {
        var calendar = deviceCalendar()
        if schedule?.timeZonePolicy == .fixed, let id = schedule?.fixedTimeZoneID, let zone = TimeZone(identifier: id) {
            calendar.timeZone = zone
        }
        return calendar
    }

    private func fits(_ date: Date, _ rules: SurpriseRules, _ calendar: Calendar, notBefore: Date) -> Bool {
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = parts.weekday, let hour = parts.hour, let minute = parts.minute else { return false }
        return date >= notBefore
            && rules.weekdayMask & (1 << (weekday - 1)) != 0
            && (rules.earliestMinute...rules.latestMinute).contains(hour * 60 + minute)
    }

    // MARK: Store

    private func fetchSchedule() -> SurpriseSchedule? {
        var descriptor = FetchDescriptor<SurpriseSchedule>()
        descriptor.fetchLimit = 1
        return fetch(descriptor).first
    }

    /// Prompts the planner and expiry can still care about: from a week before today, plus any still pending.
    private func fetchRecentPrompts(now: Date, calendar: Calendar) -> [SurprisePrompt] {
        let cutoff = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)) ?? now
        let pending = PromptOutcome.pending.rawValue
        return fetch(FetchDescriptor<SurprisePrompt>(
            predicate: #Predicate { $0.plannedAt >= cutoff || $0.outcomeRaw == pending },
            sortBy: [SortDescriptor(\.plannedAt)]
        ))
    }

    private func fetchPrompt(_ id: UUID) -> SurprisePrompt? {
        var descriptor = FetchDescriptor<SurprisePrompt>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return fetch(descriptor).first
    }

    private func fetchUpcomingPending(now: Date) -> [SurprisePrompt] {
        let pending = PromptOutcome.pending.rawValue
        var descriptor = FetchDescriptor<SurprisePrompt>(
            predicate: #Predicate { $0.outcomeRaw == pending && $0.plannedAt > now },
            sortBy: [SortDescriptor(\.plannedAt)]
        )
        descriptor.fetchLimit = Self.notificationLimit
        return fetch(descriptor)
    }

    private func fetch<Model: PersistentModel>(_ descriptor: FetchDescriptor<Model>) -> [Model] {
        do {
            return try context.fetch(descriptor)
        } catch {
            logger.error("Reading \(String(describing: Model.self), privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func save() {
        do {
            try context.save()
        } catch {
            logger.error("Saving surprises failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// The surprise ribbon on Today. No countdowns and no pressure (doc 03 §H5).
enum SurpriseStatus: Equatable {
    /// T02: one is planned, or will be.
    case onItsWay
    /// T03: a prompt fired and can still be answered.
    case ready(promptID: UUID)
    /// T04: today's last prompt expired and nothing was caught since.
    case passed
    /// T05: until the start of `until`, or until resumed when nil.
    case paused(until: Date?)
    /// T07: notifications aren't allowed, or surprises were never turned on.
    case off

    init(
        schedule: SurpriseSchedule?, prompts: [SurprisePrompt], notificationsAllowed: Bool, latestCapture: Date?,
        now: Date, calendar: Calendar
    ) {
        if let ready = prompts.first(where: { $0.outcome == .pending && $0.plannedAt <= now && now < $0.expiresAt }) {
            self = .ready(promptID: ready.id)
            return
        }
        guard let schedule, schedule.isEnabled, notificationsAllowed else {
            self = .off
            return
        }
        if schedule.isPausedIndefinitely {
            self = .paused(until: nil)
            return
        }
        if let until = schedule.pausedUntil, until > now {
            self = .paused(until: until)
            return
        }
        let last = prompts.filter { $0.plannedAt <= now && $0.outcome != .cancelled }.max { $0.plannedAt < $1.plannedAt }
        if let last, calendar.isDate(last.plannedAt, inSameDayAs: now),
           last.outcome == .expired || (last.outcome == .pending && last.expiresAt <= now),
           (latestCapture ?? .distantPast) < last.plannedAt {
            self = .passed
            return
        }
        self = .onItsWay
    }
}

enum SurprisePause: CaseIterable, Sendable {
    case today
    case week
    case indefinitely
}

extension SurpriseSchedule {
    var rules: SurpriseRules {
        SurpriseRules(cadence: frequency.cadence, weekdayMask: weekdayMask, earliestMinute: earliestMinute, latestMinute: latestMinute)
    }
}

extension SurpriseFrequency {
    var cadence: SurpriseRules.Cadence {
        switch self {
        case .threeAWeek: .weekly(3)
        case .onceADay: .daily(1)
        case .twiceADay: .daily(2)
        case .threeADay: .daily(3)
        }
    }
}
