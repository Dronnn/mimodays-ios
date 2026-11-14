import Core
import Foundation
import OSLog
import Persistence
import SwiftData

/// A project as F01 shows it: a draft card, or a rendered movie's row.
struct MovieCard: Identifiable, Equatable {
    let id: UUID
    let title: String
    /// The first moment still in it: the draft's cover, the movie's poster.
    let coverID: UUID?
    let updatedAt: Date
    let aspectRatio: MovieAspectRatio
    let render: MovieRender?
}

/// Last month, once it has enough moments and no movie yet (F01's "October is ready").
struct MovieSuggestion: Equatable {
    /// yyyymm.
    let month: Int
    let candidates: [MovieSelection.Candidate]
    let days: Int
    /// How long the Quick pick of it plays.
    let seconds: Double
}

/// F01: drafts, rendered movies, and last month when it's ready to be one.
@MainActor
@Observable
final class MoviesModel {
    private(set) var drafts: [MovieCard] = []
    private(set) var movies: [MovieCard] = []
    private(set) var suggestion: MovieSuggestion?
    private(set) var isLoaded = false
    let tiles: MemoriesModel
    private let library: MediaLibrary
    private let clock: any DateProvider
    private let calendar: () -> Calendar
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "MimoDays", category: "Movies")
    /// The month whose suggestion was put away with Not now.
    static let dismissedKey = "movies.dismissedSuggestion"
    /// About a minute (F01: "About 1 minute"; F04's Quick).
    static let quickSeconds = 60.0

    init(
        library: MediaLibrary, clock: any DateProvider = SystemDateProvider(), calendar: @escaping () -> Calendar = { .current },
        defaults: UserDefaults = .standard
    ) {
        self.library = library
        self.clock = clock
        self.calendar = calendar
        self.defaults = defaults
        tiles = MemoriesModel(context: library.context, store: library.store, thumbnails: library.thumbnails, clock: clock, calendar: calendar)
    }

    private var store: MovieStore { MovieStore(context: library.context, store: library.store, now: { [clock] in clock.now() }) }

    var isEmpty: Bool { isLoaded && drafts.isEmpty && movies.isEmpty }

    /// "Edited 2 days ago" counts from here.
    var now: Date { clock.now() }

    func refresh() {
        do {
            try store.forgetMissingRenders()
            drafts = try store.drafts().map(Self.card)
            movies = try store.movies().map(Self.card)
            suggestion = try findSuggestion()
        } catch {
            logger.error("Reading movies failed: \(error.localizedDescription, privacy: .public)")
        }
        isLoaded = true
    }

    /// Not now: this month isn't offered again; next month will be.
    func dismissSuggestion() {
        guard let suggestion else { return }
        defaults.set(suggestion.month, forKey: Self.dismissedKey)
        self.suggestion = nil
    }

    /// Make it: a Quick 9:16 draft of the suggested month, picked automatically.
    @discardableResult
    func makeSuggestion(seed: UInt64 = .random(in: 0...UInt64(Int.max))) -> UUID? {
        guard let suggestion else { return nil }
        do {
            let picked = MovieSelection.pick(suggestion.candidates, target: Self.quickSeconds, seed: seed)
            let project = try store.create(
                title: Self.monthTitle(suggestion.month), source: Self.monthRule(suggestion.month), length: .quick,
                aspectRatio: .portrait9x16, fit: .fill, momentIDs: picked, seed: Int(seed)
            )
            refresh()
            return project.id
        } catch {
            logger.error("Making the suggested movie failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: Suggestion

    private func findSuggestion() throws -> MovieSuggestion? {
        let today = LocalDay(clock.now(), in: calendar().timeZone).key
        let thisMonth = today / 100
        let month = thisMonth % 100 == 1 ? (thisMonth / 100 - 1) * 100 + 12 : thisMonth - 1
        guard defaults.integer(forKey: Self.dismissedKey) != month else { return nil }
        let rule = Self.monthRule(month)
        let made = try library.context.fetch(FetchDescriptor<MovieProject>()).contains { $0.sourceRule == rule }
        guard !made else { return nil }
        let candidates = try Self.candidates(in: library.context, from: month * 100 + 1, through: month * 100 + 31)
        guard candidates.count >= MovieSelection.minimumMoments else { return nil }
        let quick = MovieSelection.pick(candidates, target: Self.quickSeconds, seed: 0)
        let seconds = MovieSelection.seconds(of: candidates.filter { quick.contains($0.id) })
        return MovieSuggestion(month: month, candidates: candidates, days: Set(candidates.map(\.day)).count, seconds: seconds)
    }

    /// Alive moments on these local days, ready for MovieSelection.
    static func candidates(in context: ModelContext, from first: Int, through last: Int) throws -> [MovieSelection.Candidate] {
        var descriptor = FetchDescriptor<Moment>(
            predicate: #Predicate { $0.deletedAt == nil && $0.localDay >= first && $0.localDay <= last },
            sortBy: [SortDescriptor(\.capturedAt)]
        )
        descriptor.relationshipKeyPathsForPrefetching = [\.media]
        return try context.fetch(descriptor).map { moment in
            MovieSelection.Candidate(
                id: moment.id, capturedAt: moment.capturedAt, day: moment.localDay,
                videoDuration: moment.mediaType == .video ? (moment.media.compactMap(\.duration).max() ?? MovieSelection.photoSeconds) : nil
            )
        }
    }

    /// A whole month as a date range, its days as noon UTC like every day key.
    static func monthRule(_ month: Int) -> MovieSourceRule {
        MovieSourceRule(kind: .dateRange, start: MemoriesView.dayDate(month * 100 + 1), end: MemoriesView.dayDate(month * 100 + lastDay(of: month)))
    }

    static func monthTitle(_ month: Int) -> String {
        MemoriesView.monthDate(month).formatted(Date.FormatStyle(timeZone: .gmt).month(.wide).year())
    }

    static func monthName(_ month: Int) -> String {
        MemoriesView.monthDate(month).formatted(Date.FormatStyle(timeZone: .gmt).month(.wide))
    }

    private static func lastDay(of month: Int) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.range(of: .day, in: .month, for: MemoriesView.monthDate(month))?.count ?? 31
    }

    private static func card(_ project: MovieProject) -> MovieCard {
        MovieCard(
            id: project.id, title: project.title, coverID: MovieStore.liveClips(of: project).first?.moment?.id,
            updatedAt: project.updatedAt, aspectRatio: project.aspectRatio, render: project.render
        )
    }
}
