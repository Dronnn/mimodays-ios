import Foundation
import os
import Persistence
import SwiftData

/// What onboarding keeps between launches.
struct OnboardingRecord: Equatable {
    var isCompleted = false
    /// Where to resume: intro pages 0-5, then the schedule (6), then the first capture (7).
    var step = 0
    var schedule = ReminderSchedule()
    /// The person chose "Enable reminders" (even if iOS then said no); "Maybe later" leaves it off.
    var remindersEnabled = false
}

@MainActor
protocol OnboardingStore: AnyObject {
    func load() -> OnboardingRecord
    func save(_ record: OnboardingRecord)
}

/// Progress kept only for this launch: previews and tests.
@MainActor
final class InMemoryOnboardingStore: OnboardingStore {
    private(set) var record: OnboardingRecord

    init(_ record: OnboardingRecord = OnboardingRecord()) {
        self.record = record
    }

    func load() -> OnboardingRecord { record }
    func save(_ record: OnboardingRecord) { self.record = record }
}

/// The single `AppPreferences` and `SurpriseSchedule` rows in the app's SwiftData store.
@MainActor
final class SwiftDataOnboardingStore: OnboardingStore {
    private let context: ModelContext
    private let logger = Logger(subsystem: "MimoDays", category: "Onboarding")

    init(context: ModelContext) {
        self.context = context
    }

    func load() -> OnboardingRecord {
        var record = OnboardingRecord()
        if let preferences = fetch(AppPreferences.self) {
            record.isCompleted = preferences.hasCompletedOnboarding
            record.step = preferences.onboardingStep
        }
        if let stored = fetch(SurpriseSchedule.self) {
            record.schedule = ReminderSchedule(
                frequency: stored.frequency, weekdayMask: stored.weekdayMask,
                earliestMinute: stored.earliestMinute, latestMinute: stored.latestMinute
            )
            record.remindersEnabled = stored.isEnabled
        }
        return record
    }

    func save(_ record: OnboardingRecord) {
        let preferences = fetch(AppPreferences.self) ?? insert(AppPreferences())
        preferences.hasCompletedOnboarding = record.isCompleted
        preferences.onboardingStep = record.step
        let stored = fetch(SurpriseSchedule.self) ?? insert(SurpriseSchedule())
        stored.frequency = record.schedule.frequency
        stored.weekdayMask = record.schedule.weekdayMask
        stored.earliestMinute = record.schedule.earliestMinute
        stored.latestMinute = record.schedule.latestMinute
        stored.isEnabled = record.remindersEnabled
        do {
            try context.save()
        } catch {
            logger.error("Saving onboarding progress failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fetch<Model: PersistentModel>(_: Model.Type) -> Model? {
        var descriptor = FetchDescriptor<Model>()
        descriptor.fetchLimit = 1
        do {
            return try context.fetch(descriptor).first
        } catch {
            logger.error("Reading \(String(describing: Model.self), privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func insert<Model: PersistentModel>(_ model: Model) -> Model {
        context.insert(model)
        return model
    }
}
