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
    /// Where a failed "Remind me later" is kept for Today until the day changes; in memory when nil (UI tests).
    private let defaults: UserDefaults?
    private var retryNoteInMemory: [String: Any]?
    private var fallbackInMemory: FallbackReminder?
    private let logger = Logger(subsystem: "MimoDays", category: "Surprises")

    init(
        context: ModelContext,
        notifications: any NotificationScheduler,
        permissions: any PermissionService,
        clock: any DateProvider = SystemDateProvider(),
        calendar: @escaping () -> Calendar = { Calendar.current },
        generator: any RandomNumberGenerator = SystemRandomNumberGenerator(),
        defaults: UserDefaults? = .standard
    ) {
        self.defaults = defaults
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

    /// Another app language: the plan stays, the requests iOS has are given the new words.
    func languageChanged() async {
        await serially { await self.performRefresh(replan: false, rewords: true) }
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
            // One pause at a time: a week chosen after "until I resume them" ends in a week.
            switch length {
            case .today: schedule.pausedUntil = calendar.date(byAdding: .day, value: 1, to: today)
            case .week: schedule.pausedUntil = calendar.date(byAdding: .day, value: 7, to: today)
            case .indefinitely: schedule.pausedUntil = nil
            }
            schedule.isPausedIndefinitely = length == .indefinitely
            await self.performRefresh(replan: false, stopsAll: true)
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

    // MARK: Send one now

    /// How far ahead "Send a surprise now" plans its surprise: time to leave the app and see it arrive.
    static let sendNowDelay: TimeInterval = 10
    /// Marks a sent-now prompt's request: it is extra and doesn't take the place of the day's (or week's) own.
    static let sendNowPrefix = "now-"

    /// "Send a surprise now" (S02): one surprise in a few seconds, whatever the hours and days, so a person (and App
    /// Review) can see how surprises work. It is a prompt like any other: its notification opens the camera, and
    /// what's caught in time is a Surprise. False when notifications aren't allowed.
    func sendNow() async -> Bool {
        var sent = false
        await serially {
            guard await self.permissions.status(of: .notifications).isUsable else { return }
            let now = self.clock.now()
            // A second tap while the first is still on its way sends no second one; on its way means iOS has it.
            // On a whole second: iOS fires on one, and a tap right away mustn't find the prompt not yet due.
            let soon = Date(timeIntervalSinceReferenceDate: now.addingTimeInterval(Self.sendNowDelay).timeIntervalSinceReferenceDate.rounded(.up))
            let scheduled = Set(await self.notifications.pending().map(\.id))
            let dueSoon = self.fetchUpcomingPending(now: now).filter { $0.plannedAt <= soon }
            if dueSoon.contains(where: { scheduled.contains($0.notificationRequestID) }) {
                sent = true
                return
            }
            // One iOS doesn't have won't come once its trigger's second is still ahead: it doesn't go out next to this
            // one either. iOS fires at the whole second the trigger names, before the prompt's fraction, so one whose
            // second has begun may just have been shown (P5.2: one due within the second was kept, never to come).
            let checked = self.clock.now().timeIntervalSinceReferenceDate
            for prompt in dueSoon where prompt.plannedAt.timeIntervalSinceReferenceDate.rounded(.down) > checked { prompt.outcome = .cancelled }
            let id = UUID()
            let time = soon
            let minutes = self.fetchSchedule()?.expiryMinutes ?? SurpriseSchedule().expiryMinutes
            self.context.insert(SurprisePrompt(
                id: id, plannedAt: time, expiresAt: time.addingTimeInterval(TimeInterval(minutes * 60)),
                notificationRequestID: Self.sendNowPrefix + id.uuidString
            ))
            self.save()
            await self.syncNotifications(now: now)
            // iOS turned it down: nothing is on its way, so Settings doesn't say so and Today doesn't wait for it.
            guard await self.notifications.pending().contains(where: { $0.promptID == id.uuidString }) else {
                self.fetchPrompt(id)?.outcome = .cancelled
                self.save()
                return
            }
            sent = true
        }
        return sent
    }

    // MARK: The first surprise (P2)

    /// Marks the onboarding surprise's request (the prompt id stays a UUID). Unlike a sent-now one it counts for its day.
    static let firstPrefix = "first-"

    struct FirstSurprise: Equatable {
        let promptID: UUID
        let plannedAt: Date
        let expiresAt: Date
    }

    /// Onboarding's reminders step chose (on, off or later): the plan follows the choice, and with `firstSurprise` the
    /// first surprise comes a few seconds later, created and counted in the same step as the plan drawn around it
    /// (P2.1, P2.2). Only one ever. True when iOS has its notification; otherwise onboarding shows it in the app (P2.4).
    func remindersChosen(firstSurprise: Bool) async -> Bool {
        var notified = false
        await serially {
            let now = self.clock.now()
            if firstSurprise, self.fetchFirstPrompt() == nil {
                let id = UUID()
                let time = Date(timeIntervalSinceReferenceDate: now.addingTimeInterval(Self.sendNowDelay).timeIntervalSinceReferenceDate.rounded(.up))
                let minutes = self.fetchSchedule()?.expiryMinutes ?? SurpriseSchedule().expiryMinutes
                self.context.insert(SurprisePrompt(
                    id: id, plannedAt: time, expiresAt: time.addingTimeInterval(TimeInterval(minutes * 60)),
                    notificationRequestID: Self.firstPrefix + id.uuidString
                ))
            }
            await self.performRefresh(replan: true)
            guard firstSurprise, let first = self.fetchFirstPrompt(), first.outcome == .pending,
                  await self.permissions.status(of: .notifications).isUsable else { return }
            notified = await self.notifications.pending().contains { $0.id == first.notificationRequestID }
        }
        return notified
    }

    /// The first surprise while it is still to come or can be answered; nil once it's caught, expired or gone.
    func firstSurprise() -> FirstSurprise? {
        guard let prompt = fetchFirstPrompt(), prompt.outcome == .pending, clock.now() < prompt.expiresAt else { return nil }
        return FirstSurprise(promptID: prompt.id, plannedAt: prompt.plannedAt, expiresAt: prompt.expiresAt)
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
            latestCapture: latestCapture, now: now, calendar: calendar, retryFailure: retryFailure(now: now, calendar: calendar)
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
        // Not before it has come either: a link naming a later surprise opens a plain capture.
        guard prompt.plannedAt <= now else { return false }
        guard now < prompt.expiresAt else {
            prompt.outcome = .expired
            save()
            return false
        }
        if prompt.openedAt == nil { prompt.openedAt = now }
        save()
        return true
    }

    /// When the prompt stops being answerable: a shot taken at or after it is a plain capture (Help: "what you capture
    /// in that time is marked Surprise"), even though the camera was opened in time.
    func expiry(of promptID: UUID) -> Date? {
        fetchPrompt(promptID)?.expiresAt
    }

    /// Links a saved moment to the prompt it answered. Only a prompt that was opened in time counts,
    /// even when the moment is saved after the window closed; a manual capture never answers a prompt.
    func captured(promptID: UUID, momentID: UUID) {
        guard let prompt = fetchPrompt(promptID), prompt.openedAt != nil,
              prompt.outcome == .pending || prompt.outcome == .expired,
              let moment = fetchMoment(momentID), moment.capturedAt < prompt.expiresAt else { return }
        prompt.outcome = .captured
        prompt.capturedMomentID = momentID
        save()
        // Answered while it was coming back (P8.7): its notification goes.
        if prompt.notificationRequestID.hasPrefix(Self.retryPrefix) {
            Task { await serially { await self.syncNotifications(now: self.clock.now()) } }
        }
    }

    // MARK: Remind me later (P8.7)

    /// The notification category with the "Remind me later" action, and the action.
    nonisolated static let remindLaterCategory = "surprise"
    nonisolated static let remindLaterAction = "remindLater"
    nonisolated static let remindLaterTitle = LocalizedStringResource("Remind me later", bundle: .atURL(Bundle.module.bundleURL))
    /// Marks a surprise that is coming back; it comes back once.
    nonisolated static let retryPrefix = "retry-"
    static let retryDelay: TimeInterval = 30 * 60
    static let retryNearest: TimeInterval = 5 * 60
    private static let retryNoteKey = "surpriseRetryNote"

    enum RetryFailure: String, Equatable {
        /// No time left today in the hours, the pause or before the next surprise.
        case noTime
        /// iOS didn't take the notification.
        case failed
    }

    enum RetryResult: Equatable {
        case later(Date)
        case failed(RetryFailure)
        /// Not a live ordinary surprise any more (answered, expired, already retried, a stale or repeated press).
        case ignored
    }

    /// Only planned surprises; not "Send a surprise now", onboarding's or one already coming back.
    static func isOrdinary(_ requestID: String) -> Bool {
        ![sendNowPrefix, firstPrefix, retryPrefix].contains { requestID.hasPrefix($0) }
    }

    /// The same surprise (its reservation for the day and its id) comes back 30 minutes on, sooner late in the day,
    /// with a fresh window; never tomorrow. Runs from the notification without opening the app.
    @discardableResult
    func remindLater(promptID: UUID) async -> RetryResult {
        var result = RetryResult.ignored
        await serially { result = await self.performRemindLater(promptID) }
        return result
    }

    private func performRemindLater(_ promptID: UUID) async -> RetryResult {
        let now = clock.now()
        guard let prompt = fetchPrompt(promptID), prompt.outcome == .pending, Self.isOrdinary(prompt.notificationRequestID),
              prompt.plannedAt <= now, now < prompt.expiresAt,
              let schedule = fetchSchedule(), schedule.isEnabled,
              await permissions.status(of: .notifications).isUsable,
              // Answered while iOS was asked.
              prompt.outcome == .pending else { return .ignored }
        let calendar = calendar(for: schedule)
        let window = TimeInterval(schedule.expiryMinutes * 60)
        guard let time = retryTime(now: now, window: window, schedule: schedule, calendar: calendar, prompt: prompt) else {
            noteRetryFailure(.noTime, now: now)
            return .failed(.noTime)
        }
        let original = (prompt.plannedAt, prompt.expiresAt, prompt.notificationRequestID)
        prompt.plannedAt = time
        prompt.expiresAt = time.addingTimeInterval(window)
        prompt.notificationRequestID = Self.retryPrefix + prompt.id.uuidString
        save()
        await syncNotifications(now: now)
        guard await notifications.pending().contains(where: { $0.id == prompt.notificationRequestID }) else {
            // The surprise stays as it came, still open.
            (prompt.plannedAt, prompt.expiresAt, prompt.notificationRequestID) = original
            save()
            noteRetryFailure(.failed, now: now)
            return .failed(.failed)
        }
        noteRetryFailure(nil, now: now)
        return .later(time)
    }

    /// Half an hour on, or the latest time at least 5 minutes away whose whole window fits in today's hours and
    /// before the next surprise; nil when there's none, or surprises are paused.
    private func retryTime(now: Date, window: TimeInterval, schedule: SurpriseSchedule, calendar: Calendar, prompt: SurprisePrompt) -> Date? {
        guard !schedule.isPausedIndefinitely, (schedule.pausedUntil ?? .distantPast) <= now else { return nil }
        // The surprise's own day (one live past midnight stays on it) and its closing time on the clock, as the
        // planner reads it: on a clock-change day minutes from midnight would be an hour off.
        let day = calendar.startOfDay(for: prompt.plannedAt)
        guard let close = calendar.date(bySettingHour: schedule.latestMinute / 60, minute: schedule.latestMinute % 60, second: 0, of: day),
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
        var latest = min(now.addingTimeInterval(Self.retryDelay), close.addingTimeInterval(-window), tomorrow.addingTimeInterval(-window))
        if let next = fetchUpcomingPending(now: now).first(where: { $0.id != prompt.id }) {
            latest = min(latest, next.plannedAt.addingTimeInterval(-window))
        }
        // On a whole second: iOS fires on one.
        latest = Date(timeIntervalSinceReferenceDate: latest.timeIntervalSinceReferenceDate.rounded(.down))
        guard latest >= now.addingTimeInterval(Self.retryNearest), fits(latest, schedule.rules, calendar, notBefore: now) else { return nil }
        return latest
    }

    private func noteRetryFailure(_ failure: RetryFailure?, now: Date) {
        let note: [String: Any]? = failure.map { ["kind": $0.rawValue, "at": now.timeIntervalSinceReferenceDate] }
        if let defaults {
            defaults.set(note, forKey: Self.retryNoteKey)
        } else {
            retryNoteInMemory = note
        }
    }

    /// Today's failed "Remind me later", if any.
    private func retryFailure(now: Date, calendar: Calendar) -> RetryFailure? {
        let note = defaults.map { $0.dictionary(forKey: Self.retryNoteKey) } ?? retryNoteInMemory
        guard let kind = (note?["kind"] as? String).flatMap(RetryFailure.init(rawValue:)), let at = note?["at"] as? Double,
              calendar.isDate(Date(timeIntervalSinceReferenceDate: at), inSameDayAs: now) else { return nil }
        return kind
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

    /// `stopsAll`: the person paused, so even a surprise due within the minute goes.
    private func performRefresh(replan: Bool, stopsAll: Bool = false, rewords: Bool = false) async {
        let status = await permissions.status(of: .notifications)
        let now = clock.now()
        let schedule = fetchSchedule()
        if let pausedUntil = schedule?.pausedUntil, pausedUntil <= now { schedule?.pausedUntil = nil }
        let calendar = calendar(for: schedule)
        let prompts = fetchRecentPrompts(now: now, calendar: calendar)

        for prompt in prompts where prompt.outcome == .pending && prompt.expiresAt <= now {
            prompt.outcome = .expired
        }
        // A prompt due within the minute is left alone: iOS may be delivering it already, and "Send a surprise now"
        // plans one seconds ahead, outside the hours and days.
        // Not when the person paused or turned surprises off: then nothing more comes, however soon it was due.
        let settled = stopsAll || schedule?.isEnabled != true ? now : now.addingTimeInterval(60)
        // The first surprise stays with "Maybe later" and notifications off too: onboarding shows it in the app.
        let upcoming = prompts.filter {
            $0.outcome == .pending && $0.plannedAt > settled && (stopsAll || !$0.notificationRequestID.hasPrefix(Self.firstPrefix))
        }

        if let schedule, schedule.isEnabled, !schedule.isPausedIndefinitely, status.isUsable {
            let rules = schedule.rules
            let notBefore = max(now, schedule.pausedUntil ?? now)
            // A plan that no longer fits (new hours, days, pause or time zone) is drawn again from now on.
            if replan || upcoming.contains(where: { !fits($0.plannedAt, rules, calendar, notBefore: notBefore) }) {
                for prompt in upcoming {
                    // P8.7: a surprise coming back is the same one, already counted for its day; it stays while it
                    // still fits, with the window as it is now.
                    if prompt.notificationRequestID.hasPrefix(Self.retryPrefix), fits(prompt.plannedAt, rules, calendar, notBefore: notBefore) {
                        prompt.expiresAt = prompt.plannedAt.addingTimeInterval(TimeInterval(schedule.expiryMinutes * 60))
                        continue
                    }
                    prompt.outcome = .cancelled
                }
            }
            let planned = prompts
                .filter { $0.outcome != .cancelled && !$0.notificationRequestID.hasPrefix(Self.sendNowPrefix) }
                .map(\.plannedAt)
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
        await syncNotifications(now: now, rewords: rewords)
    }

    /// Schedules the next pending prompts that iOS doesn't have yet and removes every request without one.
    /// `rewords`: every request is scheduled again, in the app's current language.
    private func syncNotifications(now: Date, rewords: Bool = false) async {
        // The first surprise after "Maybe later" (or with surprises switched off since) shows in the app only.
        let remindersOn = fetchSchedule()?.isEnabled == true
        var wanted = fetchUpcomingPending(now: now)
            .filter { remindersOn || !$0.notificationRequestID.hasPrefix(Self.firstPrefix) }
            .map {
                (id: $0.notificationRequestID, promptID: $0.id.uuidString, fireDate: $0.plannedAt,
                 category: Self.isOrdinary($0.notificationRequestID) ? Self.remindLaterCategory : nil)
            }
        let fallbacks = await fallbackTimes(now: now)
        wanted += fallbacks.map { (id: $0.id, promptID: $0.id, fireDate: $0.date, category: nil) }
        var fallbackFailed = false
        let scheduled = await notifications.pending()
        let wantedIDs = Set(wanted.map(\.id))
        let stale = scheduled.map(\.id).filter { !wantedIDs.contains($0) }
        if !stale.isEmpty { await notifications.cancel(ids: stale) }

        let fireDates = Dictionary(scheduled.map { ($0.id, $0.fireDate) }, uniquingKeysWith: { first, _ in first })
        // Requests from before "Remind me later" get its action.
        let categories = Dictionary(scheduled.map { ($0.id, $0.categoryID) }, uniquingKeysWith: { first, _ in first })
        // Not one due within the minute: it may be on its way already, and a replacement would come too late.
        let reworded = now.addingTimeInterval(60)
        for prompt in wanted where (rewords && prompt.fireDate > reworded) || fireDates[prompt.id] != prompt.fireDate
            || categories[prompt.id].map({ $0 != prompt.category }) == true {
            let isFallback = prompt.id.hasPrefix(Self.fallbackPrefix)
            let notification = SurpriseNotification(
                id: prompt.id, promptID: prompt.promptID, fireDate: prompt.fireDate,
                title: String(appLocalized: isFallback ? Self.fallbackTitle : Self.title),
                body: String(appLocalized: isFallback ? Self.fallbackBody : Self.bodies.randomElement(using: &generator)!),
                categoryID: prompt.category
            )
            do {
                try await notifications.schedule(notification)
            } catch {
                if isFallback { fallbackFailed = true }
                logger.error("Scheduling a surprise failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        self.fallbackFailed = fallbackFailed
    }

    // MARK: Fallback reminder (P8.14)

    nonisolated static let fallbackPrefix = "fallback-"
    nonisolated static let fallbackTitle = LocalizedStringResource("A moment for today", bundle: .atURL(Bundle.module.bundleURL))
    nonisolated static let fallbackBody = LocalizedStringResource(
        "If you'd like, take a moment to remember today.", bundle: .atURL(Bundle.module.bundleURL)
    )
    private static let fallbackKey = "surpriseFallback"

    /// Device-local and off at first; a backup never brings it.
    var fallback: FallbackReminder {
        if let defaults {
            return defaults.data(forKey: Self.fallbackKey).flatMap { try? JSONDecoder().decode(FallbackReminder.self, from: $0) } ?? FallbackReminder()
        }
        return fallbackInMemory ?? FallbackReminder()
    }

    /// Delete All: the fallback reminder and a "Remind me later" note go with the other device settings (rev-surprises 4).
    func resetSettings() {
        defaults?.removeObject(forKey: Self.fallbackKey)
        defaults?.removeObject(forKey: Self.retryNoteKey)
        fallbackInMemory = nil
        retryNoteInMemory = nil
    }

    /// The last scheduling of the reminders failed: Settings offers Try again (a refresh).
    private(set) var fallbackFailed = false

    func setFallback(_ value: FallbackReminder) async {
        if let defaults {
            defaults.set(try? JSONEncoder().encode(value), forKey: Self.fallbackKey)
        } else {
            fallbackInMemory = value
        }
        await serially { await self.performRefresh(replan: false) }
    }

    /// One reminder at the chosen time on each enabled, unpaused day of the plan with no surprise of its own (a
    /// surprise coming back later still holds its day); none while surprises are off or the time is outside the hours.
    private func fallbackTimes(now: Date) async -> [(id: String, date: Date)] {
        let fallback = fallback
        guard fallback.isOn, let minute = fallback.minute, let schedule = fetchSchedule(), schedule.isEnabled,
              !schedule.isPausedIndefinitely, (schedule.earliestMinute...schedule.latestMinute).contains(minute),
              await permissions.status(of: .notifications).isUsable else { return [] }
        let calendar = calendar(for: schedule)
        let today = calendar.startOfDay(for: now)
        let nowPrefix = Self.sendNowPrefix
        let cancelled = PromptOutcome.cancelled.rawValue
        let busy = Set(fetch(FetchDescriptor<SurprisePrompt>(predicate: #Predicate { $0.plannedAt >= today && $0.outcomeRaw != cancelled }))
            .filter { !$0.notificationRequestID.hasPrefix(nowPrefix) }
            .map { calendar.startOfDay(for: $0.plannedAt) })
        return (0..<SurprisePlanner(calendar: calendar).horizonDays).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today), !busy.contains(day),
                  schedule.weekdayMask & (1 << (calendar.component(.weekday, from: day) - 1)) != 0,
                  (schedule.pausedUntil ?? .distantPast) <= day,
                  let time = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day),
                  // A time the clock skips that day (DST) is skipped, not moved.
                  calendar.dateComponents([.hour, .minute], from: time) == DateComponents(hour: minute / 60, minute: minute % 60),
                  time > now else { return nil }
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            let key = parts.year! * 10_000 + parts.month! * 100 + parts.day!
            return (Self.fallbackPrefix + String(key), time)
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

    private func fetchMoment(_ id: UUID) -> Moment? {
        var descriptor = FetchDescriptor<Moment>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return fetch(descriptor).first
    }

    private func fetchPrompt(_ id: UUID) -> SurprisePrompt? {
        var descriptor = FetchDescriptor<SurprisePrompt>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return fetch(descriptor).first
    }

    private func fetchFirstPrompt() -> SurprisePrompt? {
        let prefix = Self.firstPrefix
        var descriptor = FetchDescriptor<SurprisePrompt>(predicate: #Predicate { $0.notificationRequestID.starts(with: prefix) })
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
    /// P8.7: "Remind me later" was pressed; the surprise comes back today.
    case later
    /// P8.7: "Remind me later" couldn't bring it back; said until the day changes.
    case retryFailed(SurpriseCoordinator.RetryFailure)

    init(
        schedule: SurpriseSchedule?, prompts: [SurprisePrompt], notificationsAllowed: Bool, latestCapture: Date?,
        now: Date, calendar: Calendar, retryFailure: SurpriseCoordinator.RetryFailure? = nil
    ) {
        if let ready = prompts.first(where: { $0.outcome == .pending && $0.plannedAt <= now && now < $0.expiresAt }) {
            self = .ready(promptID: ready.id)
            return
        }
        if prompts.contains(where: { $0.outcome == .pending && $0.plannedAt > now && $0.notificationRequestID.hasPrefix(SurpriseCoordinator.retryPrefix) }) {
            self = .later
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
        // After Turn on and Resume: their buttons matter more than a failed "Remind me later".
        if let retryFailure {
            self = .retryFailed(retryFailure)
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

/// P8.14: a reminder at a fixed time on days with no surprise planned.
struct FallbackReminder: Codable, Equatable {
    var isOn = false
    /// Minutes after midnight, in the surprises' time; nil until chosen.
    var minute: Int?

    /// 8:00 PM when the hours allow it, else the nearest time inside them.
    static func defaultMinute(earliest: Int, latest: Int) -> Int {
        min(max(20 * 60, earliest), latest)
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
