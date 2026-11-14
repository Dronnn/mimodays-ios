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
    private let container = try! MimoDaysStore.makeContainer(inMemory: true)
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
                media: .photo(try await engine.capturePhoto(flash: false, silent: true)), window: .init(),
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
        #expect(model.sourceName == "Last month")
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

    @Test func choosingMomentsByHandStartsWithNone() async throws {
        try await save([20260101, 20260202, 20260303, 20260404, 20260505, 20261010])
        let model = wizard()
        model.source = .moments
        #expect(model.loadCandidates())
        model.pickAutomatically()
        #expect(model.picked.isEmpty)
        #expect(model.items.count == 6)
    }

    @Test func lastYearIsCalledTheWholeYear() {
        let model = wizard()
        model.source = .lastYear
        #expect(model.title == "2025, the whole year")
    }
}
