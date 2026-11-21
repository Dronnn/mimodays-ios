@testable import AppFeature
@testable import Core
import Foundation
import Persistence
import SwiftData
import Testing
import TestSupport

/// 11.2-11.4, 11.6, 11.12: the library (F01) and the wizard (F02-F05, F16). Today is Nov 11, 2026.
@MainActor
struct MoviesModelTests {
    private let container = try! TestStore.container()
    private let store: MediaStore
    private let defaults = UserDefaults(suiteName: "MoviesModelTests-\(UUID().uuidString)")!

    init() throws {
        store = try MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "Movies-\(UUID().uuidString)"))
    }

    private var context: ModelContext { container.mainContext }
    private var library: MediaLibrary { MediaLibrary(context: context, store: store, thumbnails: ThumbnailPipeline()) }
    private var gmt: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private func movies() -> MoviesModel {
        MoviesModel(library: library, clock: TestDateProvider(), calendar: { gmt }, defaults: defaults)
    }

    private func wizard(_ rule: MovieSourceRule? = nil) -> NewMovieModel {
        NewMovieModel(library: library, source: rule, clock: TestDateProvider(), calendar: { gmt }, seed: 1)
    }

    /// Photos at noon UTC on these days (yyyymmdd).
    @discardableResult
    private func save(_ days: [Int]) async throws -> [UUID] {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let saver = MomentSaver(context: context, store: store, clock: TestDateProvider(), freeBytes: { nil })
        var ids: [UUID] = []
        for day in days {
            let date = gmt.date(from: DateComponents(year: day / 10_000, month: day / 100 % 100, day: day % 100, hour: 12))!
            let capture = CaptureResult(
                media: .photo(try await engine.capturePhoto(flash: .off, silent: true)), window: .init(),
                capturedAt: CaptureTime(instant: date, timeZone: .gmt)
            )
            let draft = MomentDraft(
                capture: capture, caption: "",
                window: SelfieWindowFrame(frame: CGRect(x: 266.7, y: 111.1, width: 112, height: 150), preview: CGSize(width: 402, height: 536)),
                promptID: nil
            )
            ids.append(try await saver.save(draft).id)
        }
        return ids
    }

    // MARK: F01

    @Test func withNothingMadeTheLibraryIsEmpty() {
        let model = movies()
        model.refresh()
        #expect(model.isEmpty)
        #expect(model.suggestion == nil)
    }

    @Test func lastMonthIsSuggestedOnceItHasFiveMoments() async throws {
        try await save([20261003, 20261003, 20261010, 20261021])
        let model = movies()
        model.refresh()
        #expect(model.suggestion == nil, "four moments aren't a movie")

        try await save([20261028, 20261105])
        model.refresh()
        let suggestion = try #require(model.suggestion)
        #expect(suggestion.month == 202610)
        #expect(suggestion.candidates.count == 5)
        #expect(suggestion.days == 4)
        #expect(suggestion.seconds == 12.5)
    }

    @Test func notNowPutsThisMonthAway() async throws {
        try await save([20261001, 20261002, 20261003, 20261004, 20261005])
        let model = movies()
        model.refresh()
        model.dismissSuggestion()
        model.refresh()
        #expect(model.suggestion == nil)
    }

    @Test func makeItMakesAQuickDraftOfTheMonthAndTheSuggestionGoes() async throws {
        let ids = try await save([20261001, 20261002, 20261003, 20261004, 20261005, 20261006])
        let model = movies()
        model.refresh()
        let id = try #require(model.makeSuggestion(seed: 1))
        #expect(model.drafts.map(\.id) == [id])
        #expect(model.drafts.first?.title == "October 2026")
        #expect(model.drafts.first?.coverID == ids.first)
        #expect(model.suggestion == nil)
        let project = try #require(try context.fetch(FetchDescriptor<MovieProject>()).first)
        #expect(project.length == .quick)
        #expect(project.aspectRatio == .portrait9x16)
        #expect(project.orderedClips.compactMap(\.moment?.id) == ids)
    }

    // MARK: F02, F03, F16

    @Test func periodsCountTheirMoments() async throws {
        try await save([20261010, 20261012, 20260301, 20250704, 20251231])
        let model = wizard()
        #expect(model.count(of: .lastMonth) == 2)
        #expect(model.count(of: .thisYear) == 3)
        #expect(model.count(of: .lastYear) == 2)
    }

    @Test func anEndBeforeTheStartStopsNext() {
        let model = wizard()
        model.source = .dates
        #expect(!model.canContinue)
        model.from = 20260601
        model.to = 20260503
        #expect(model.datesAreReversed)
        #expect(!model.canContinue)
        model.to = 20260630
        #expect(model.canContinue)
    }

    @Test func tooFewMomentsShowF16() async throws {
        try await save([20261003, 20261004, 20261005])
        let model = wizard()
        model.source = .lastMonth
        #expect(!model.loadCandidates())
        #expect(model.candidates.count == 3)
        #expect(model.notEnoughCount == "Last month has 3 moments.")
    }

    // MARK: F04, F05

    @Test func theLengthDecidesThePickAndFullTakesEveryMoment() async throws {
        let days = (1...28).map { 20261000 + $0 }
        try await save(days)
        let model = wizard()
        #expect(model.loadCandidates())
        model.length = .quick
        model.pickAutomatically()
        #expect(model.picked.count == 24)
        model.length = .full
        model.pickAutomatically()
        #expect(model.picked.count == 28)
        #expect(model.fullSeconds == 70)
        model.length = .custom
        model.customMinutes = 1
        #expect(model.target == 60)
    }

    @Test func buildMakesADraftInTheOrderTheyHappened() async throws {
        let ids = try await save([20261009, 20261002, 20261020, 20261005, 20261030, 20261015])
        let model = wizard()
        #expect(model.loadCandidates())
        model.length = .full
        model.aspectRatio = .landscape16x9
        model.fit = .showAll
        model.pickAutomatically()
        model.toggle(ids[2])
        let id = try #require(model.build())
        let project = try #require(try context.fetch(FetchDescriptor<MovieProject>(predicate: #Predicate { $0.id == id })).first)
        #expect(project.title == "October 2026")
        #expect(project.aspectRatio == .landscape16x9)
        #expect(project.fit == .showAll)
        #expect(project.length == .full)
        #expect(project.orderedClips.compactMap(\.moment?.id) == [ids[1], ids[3], ids[0], ids[5], ids[4]])
    }

    @Test func fewerThanFivePickedCantBeBuilt() async throws {
        let ids = try await save([20261001, 20261002, 20261003, 20261004, 20261005])
        let model = wizard()
        #expect(model.loadCandidates())
        model.pickAutomatically()
        #expect(model.canBuild)
        model.toggle(ids[0])
        #expect(!model.canBuild)
    }

    @Test func aSelectionMadeElsewhereIsTheSource() async throws {
        let ids = try await save([20260101, 20260202, 20260303, 20260404, 20260505, 20261010])
        let chosen = Array(ids.prefix(5))
        let model = wizard(MovieSourceRule(kind: .selection, momentIDs: chosen))
        #expect(model.source == .moments)
        #expect(model.loadCandidates())
        #expect(Set(model.candidates.map(\.id)) == Set(chosen))
        model.pickAutomatically()
        #expect(model.picked == Set(chosen))
        #expect(model.title == NewMovieModel.span(20260101, 20260505))
    }

    @Test func aCollectionOpensWithItsMoments() async throws {
        let ids = try await save([20260101, 20260202, 20260303, 20260404, 20260505, 20261010])
        let id = try #require(try CollectionStore(context: context).create("Lena's firsts", with: Array(ids.prefix(5))))
        let model = wizard(MovieSourceRule(kind: .collection, collectionID: id))
        #expect(model.source == .collection(id))
        model.loadChoices()
        #expect(model.loadCandidates())
        #expect(Set(model.candidates.map(\.id)) == Set(ids.prefix(5)))
        #expect(model.title == "Lena's firsts")
    }

    @Test func aPlaceOpensWithItsMomentsAndName() async throws {
        let ids = try await save([20260101, 20260202, 20260303, 20260404, 20260505])
        for moment in try context.fetch(FetchDescriptor<Moment>()) {
            moment.location = MomentLocation(latitude: 37.8, longitude: -122.27, precision: .city, source: .manual, placeLabel: "Oakland")
        }
        let model = wizard(MovieSourceRule(kind: .place, momentIDs: ids))
        #expect(model.loadCandidates())
        #expect(Set(model.candidates.map(\.id)) == Set(ids))
        #expect(model.title == "Oakland")
    }

    /// P8.3: hidden moments and days are left out of periods, collections and places, and their counts;
    /// choosing by hand still offers them.
    @Test func anAutomaticPickLeavesHiddenMomentsOut() async throws {
        let ids = try await save([20261001, 20261002, 20261003, 20261004, 20261005, 20261006, 20261007])
        let first = ids[0]
        try MemoryVisibility.setHidden(true, try context.fetch(FetchDescriptor<Moment>(predicate: #Predicate { $0.id == first })).first!, in: context)
        try MemoryVisibility.setDayHidden(true, 20261002, in: context)
        let model = wizard()
        #expect(model.count(of: .lastMonth) == 5)
        #expect(model.loadCandidates())
        #expect(Set(model.candidates.map(\.id)) == Set(ids.dropFirst(2)))
        let place = wizard(MovieSourceRule(kind: .place, momentIDs: ids))
        #expect(place.loadCandidates())
        #expect(place.candidates.count == 5)
        let byHand = wizard()
        byHand.source = .moments
        #expect(byHand.loadCandidates())
        #expect(byHand.candidates.count == 7)
        let chosen = wizard(MovieSourceRule(kind: .selection, momentIDs: ids))
        #expect(chosen.loadCandidates())
        #expect(chosen.candidates.count == 7)
    }

    @Test func choosingMomentsByHandStartsWithNone() async throws {
        try await save([20260101, 20260202, 20260303, 20260404, 20260505, 20261010])
        let model = wizard()
        model.source = .moments
        #expect(model.loadCandidates())
        model.pickAutomatically()
        #expect(model.picked.isEmpty)
        #expect(model.items.count == 6)
    }

    /// From a place back to "Choose moments": every moment is offered, not the place's.
    @Test func choosingMomentsAfterAPlaceOffersEveryMoment() async throws {
        let ids = try await save([20260101, 20260202, 20260303, 20260404, 20260505, 20261010])
        let model = wizard(MovieSourceRule(kind: .place, momentIDs: Array(ids.prefix(5))))
        #expect(model.loadCandidates())
        model.source = .moments
        #expect(model.loadCandidates())
        #expect(model.candidates.count == 6)
    }

    /// Back only to change the shape: Next keeps the moments picked by hand.
    @Test func nextAgainKeepsHandPicks() async throws {
        let ids = try await save([20261001, 20261002, 20261003, 20261004, 20261005, 20261006])
        let model = wizard()
        #expect(model.loadCandidates())
        model.pickAutomatically()
        model.toggle(ids[0])
        let picked = model.picked
        model.aspectRatio = .square1x1
        model.pickAutomatically()
        #expect(model.picked == picked)
    }

    @Test func aSecondBuildMakesNoSecondDraft() async throws {
        try await save([20261001, 20261002, 20261003, 20261004, 20261005])
        let model = wizard()
        #expect(model.loadCandidates())
        model.pickAutomatically()
        #expect(model.build() != nil)
        #expect(model.build() == nil)
        #expect(try context.fetchCount(FetchDescriptor<MovieProject>()) == 1)
    }

    @Test func lastYearIsCalledTheWholeYear() {
        let model = wizard()
        model.source = .lastYear
        #expect(model.title == "2025, the whole year")
    }

    /// P8.9: each day of the period with a moment, a surprise first; hidden moments and lost files left out.
    @Test func oneSecondDaysUseTheArchive() async throws {
        let ids = try await save([20261102, 20261102, 20261103, 20261104, 20261201])
        let moments = try context.fetch(FetchDescriptor<Moment>())
        let byID = Dictionary(uniqueKeysWithValues: moments.map { ($0.id, $0) })
        byID[ids[1]]!.origin = .randomPrompt
        try MemoryVisibility.setHidden(true, byID[ids[2]]!, in: context)
        for media in byID[ids[3]]!.media { try store.remove(media.relativePath) }
        let days = try MoviesModel.oneSecondDays(in: context, store: store, days: OneSecondPerDay.days(ofMonth: 202611))
        #expect(days.map(\.day) == [20261102])
        #expect(days.first?.picked == ids[1] && days.first?.choices == [ids[1], ids[0]])
    }

    /// P8.9: one clip a day in order, a second each with cuts; Change moment swaps a day's clip and keeps it a second.
    @Test func aOneSecondMovieHasASecondADay() async throws {
        let ids = try await save([20261103, 20261102, 20261102])
        let days = try MoviesModel.oneSecondDays(in: context, store: store, days: OneSecondPerDay.days(ofMonth: 202611))
        let store = MovieStore(context: context, store: self.store, now: { Date(timeIntervalSince1970: 0) })
        let project = try store.createOneSecond(
            title: "November 2026", period: OneSecondPerDay.days(ofMonth: 202611), days: days, aspectRatio: .portrait9x16, fit: .fill
        )
        #expect(project.sourceRule.kind == .oneSecondPerDay)
        #expect(project.orderedClips.compactMap(\.moment?.localDay) == [20261102, 20261103])
        #expect(project.orderedClips.allSatisfy { $0.trimStart == 0 && $0.trimEnd == 1 && $0.transition == .cut })
        let plan = MoviePlan(project, store: self.store)
        #expect(plan.clips.map(\.duration) == [1, 1])
        let firstDay = try #require(days.first)
        let other = try #require(firstDay.choices.first { $0 != firstDay.picked })
        #expect(Set([ids[1], ids[2]]) == Set(firstDay.choices))
        try store.changeMoment(of: project.orderedClips[0], to: other)
        #expect(project.orderedClips[0].moment?.id == other && project.orderedClips[0].trimEnd == 1)
        #expect(project.sourceRule.momentIDs == [other, ids[0]])
    }

    /// HH02: the last full month at first; months and years step back and forth across the year's end.
    @Test func oneSecondPeriods() {
        let model = wizard()
        #expect(model.oneSecondPeriod == .month(202610))
        #expect(NewMovieModel.OneSecondPeriod.month(202601).shifted(by: -1) == .month(202512))
        #expect(NewMovieModel.OneSecondPeriod.month(202612).shifted(by: 1) == .month(202701))
        #expect(NewMovieModel.OneSecondPeriod.year(2026).shifted(by: -1) == .year(2025))
        #expect(NewMovieModel.OneSecondPeriod.month(202602).days == 20260201...20260228)
    }

    /// HH04-HH06: one day is enough; a day changed by hand keeps its pick and Build makes a second a day.
    @Test func oneSecondWizardBuildsADraft() async throws {
        let ids = try await save([20261003, 20261003, 20261010])
        let model = wizard()
        model.source = .oneSecond
        #expect(model.loadCandidates())
        #expect(model.oneSecondDays.map(\.day) == [20261003, 20261010])
        #expect(model.oneSecondLength == 2)
        let day = try #require(model.oneSecondDays.first)
        let other = try #require(day.choices.first { $0 != day.picked })
        model.choose(other, forDay: day.day)
        #expect(model.changedDays == [20261003])
        // Back and Next again: the hand-made pick stays.
        #expect(model.loadCandidates())
        #expect(model.oneSecondDays.first?.picked == other)
        let id = try #require(model.build())
        let project = try #require(try context.fetch(FetchDescriptor<MovieProject>(predicate: #Predicate { $0.id == id })).first)
        #expect(project.sourceRule.kind == .oneSecondPerDay)
        #expect(project.orderedClips.compactMap(\.moment?.id) == [other, ids[2]])
        #expect(project.title == "October 2026, one second a day")
    }

    /// A period with no moments: nothing to build.
    @Test func oneSecondWithoutMoments() throws {
        let model = wizard()
        model.source = .oneSecond
        model.oneSecondPeriod = .year(2020)
        #expect(!model.loadCandidates())
        #expect(!model.canBuild)
        #expect(try model.oneSecondDays(of: .year(2020)).isEmpty)
    }

    /// Opened from a One second per day movie: its year and picks come back.
    @Test func oneSecondRuleComesBack() async throws {
        let ids = try await save([20250303, 20250303])
        let days = try MoviesModel.oneSecondDays(in: context, store: store, days: OneSecondPerDay.days(ofYear: 2025))
        let other = try #require(days.first?.choices.first { $0 != days.first?.picked })
        let rule = MovieSourceRule(
            kind: .oneSecondPerDay, start: MemoriesView.dayDate(20250101), end: MemoriesView.dayDate(20251231), momentIDs: [other]
        )
        let model = wizard(rule)
        #expect(model.source == .oneSecond && model.oneSecondPeriod == .year(2025))
        #expect(model.loadCandidates())
        #expect(model.oneSecondDays.first?.picked == other && Set(ids).contains(other))
    }
}
