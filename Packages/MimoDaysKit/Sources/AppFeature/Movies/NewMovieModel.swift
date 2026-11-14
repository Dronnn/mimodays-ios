import Core
import Foundation
import OSLog
import Persistence
import SwiftData

/// The wizard (F02-F05, F16): what it's about, how long and what shape, which moments; then a draft.
@MainActor
@Observable
final class NewMovieModel {
    enum Source: Hashable {
        case lastMonth
        case thisYear
        case lastYear
        case dates
        case collection(UUID)
        case place(String)
        case moments
    }

    /// One of F02's rows, with how many moments it holds.
    struct Choice: Identifiable {
        let id: UUID
        let title: String
        let count: Int
    }

    var source: Source = .lastMonth
    /// F03, yyyymmdd; nil until picked.
    var from: Int?
    var to: Int?
    var length: MovieLength = .quick
    /// F04's Custom, in minutes.
    var customMinutes = 2
    var aspectRatio: MovieAspectRatio = .portrait9x16
    var fit: MovieFit = .fill
    /// F05: the moments in the movie.
    var picked: Set<UUID> = []
    /// The source's moments, read when step 3 opens.
    private(set) var candidates: [MovieSelection.Candidate] = []
    /// The same moments as F05's tiles, in the order they happened.
    private(set) var items: [MemoryItem] = []
    private(set) var seed: UInt64
    /// Moments chosen elsewhere (a selection, a place), and the place's name.
    private(set) var presetIDs: [UUID] = []
    private(set) var placeName: String?
    private(set) var collections: [Choice] = []
    private(set) var places: [MapPlace] = []
    let tiles: MemoriesModel
    private let library: MediaLibrary
    private let clock: any DateProvider
    private let calendar: () -> Calendar
    private let logger = Logger(subsystem: "MimoDays", category: "Movies")

    init(
        library: MediaLibrary, source rule: MovieSourceRule? = nil, clock: any DateProvider = SystemDateProvider(),
        calendar: @escaping () -> Calendar = { .current }, seed: UInt64 = .random(in: 0...UInt64(Int.max))
    ) {
        self.library = library
        self.clock = clock
        self.calendar = calendar
        self.seed = seed
        tiles = MemoriesModel(context: library.context, store: library.store, thumbnails: library.thumbnails, clock: clock, calendar: calendar)
        if let rule { apply(rule) }
    }

    // MARK: Step 1 (F02, F03, F16)

    var today: Int { LocalDay(clock.now(), in: calendar().timeZone).key }
    var thisYear: Int { today / 10_000 }
    var lastMonth: Int {
        let month = today / 100
        return month % 100 == 1 ? (month / 100 - 1) * 100 + 12 : month - 1
    }

    /// The days a source covers, inclusive (yyyymmdd); nil for sources that aren't a period.
    func days(of source: Source) -> ClosedRange<Int>? {
        switch source {
        case .lastMonth: lastMonth * 100 + 1...lastMonth * 100 + 31
        case .thisYear: thisYear * 10_000 + 101...thisYear * 10_000 + 1231
        case .lastYear: (thisYear - 1) * 10_000 + 101...(thisYear - 1) * 10_000 + 1231
        case .dates: from.flatMap { from in to.map { from...max(from, $0) } }
        case .collection, .place, .moments: nil
        }
    }

    /// Moments a period holds (F02's details).
    func count(of source: Source) -> Int {
        guard let days = days(of: source) else { return 0 }
        let first = days.lowerBound, last = days.upperBound
        return (try? library.context.fetchCount(FetchDescriptor<Moment>(
            predicate: #Predicate { $0.deletedAt == nil && $0.localDay >= first && $0.localDay <= last }
        ))) ?? 0
    }

    /// F03's error: the end is before the start.
    var datesAreReversed: Bool {
        guard let from, let to else { return false }
        return to < from
    }

    var datesArePicked: Bool { from != nil && to != nil && !datesAreReversed }

    /// Whether Next can go on: a source that can be read (F02's Next; F03 disables it while reversed).
    var canContinue: Bool {
        switch source {
        case .dates: datesArePicked
        default: true
        }
    }

    func loadChoices() {
        do {
            let all = try library.context.fetch(FetchDescriptor<MomentCollection>(sortBy: [SortDescriptor(\.sortOrder)]))
            collections = all.map { collection in
                Choice(id: collection.id, title: collection.title, count: collection.orderedMoments.count(where: { $0.deletedAt == nil }))
            }
        } catch {
            logger.error("Reading collections failed: \(error.localizedDescription, privacy: .public)")
        }
        let map = MapModel(library: library)
        map.refresh()
        places = map.places
    }

    /// Reads the source's moments; false when there are too few for a movie (F16).
    func loadCandidates() -> Bool {
        do {
            candidates = try readCandidates()
            let ids = candidates.map(\.id)
            let moments = try library.context.fetch(FetchDescriptor<Moment>(predicate: #Predicate { ids.contains($0.id) }))
            let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
            items = moments.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }.map {
                MemoryItem(
                    id: $0.id, localDay: $0.localDay, capturedAt: $0.capturedAt, timeZoneID: $0.timeZoneID,
                    mediaType: $0.mediaType, origin: $0.origin, isFavorite: $0.isFavorite
                )
            }
        } catch {
            logger.error("Reading the movie's moments failed: \(error.localizedDescription, privacy: .public)")
            candidates = []
        }
        return candidates.count >= MovieSelection.minimumMoments || (source == .moments && presetIDs.isEmpty)
    }

    private func readCandidates() throws -> [MovieSelection.Candidate] {
        switch source {
        case .lastMonth, .thisYear, .lastYear, .dates:
            guard let days = days(of: source) else { return [] }
            return try MoviesModel.candidates(in: library.context, from: days.lowerBound, through: days.upperBound)
        case let .collection(id):
            let collection = try library.context.fetch(FetchDescriptor<MomentCollection>(predicate: #Predicate { $0.id == id })).first
            return Self.candidates(collection?.orderedMoments ?? [])
        case .place, .moments:
            if presetIDs.isEmpty, source == .moments {
                // Choose moments from everything: none picked until tapped (F05).
                return try MoviesModel.candidates(in: library.context, from: 0, through: 99_999_999)
            }
            let ids = presetIDs
            return Self.candidates(try library.context.fetch(FetchDescriptor<Moment>(predicate: #Predicate { ids.contains($0.id) })))
        }
    }

    private static func candidates(_ moments: [Moment]) -> [MovieSelection.Candidate] {
        moments.filter { $0.deletedAt == nil }
            .sorted { $0.capturedAt < $1.capturedAt }
            .map { moment in
                MovieSelection.Candidate(
                    id: moment.id, capturedAt: moment.capturedAt, day: moment.localDay,
                    videoDuration: moment.mediaType == .video ? (moment.media.compactMap(\.duration).max() ?? MovieSelection.photoSeconds) : nil
                )
            }
    }

    func choosePlace(_ place: MapPlace) {
        source = .place(place.id)
        placeName = place.label
        presetIDs = place.moments.map(\.id)
    }

    // MARK: Step 2 (F04)

    /// Seconds the length aims at; nil for Full.
    var target: Double? {
        switch length {
        case .quick: MoviesModel.quickSeconds
        case .short: 240
        case .full: nil
        case .custom: Double(customMinutes) * 60
        }
    }

    /// Full plays every moment this long (F04: "every moment · 2:40").
    var fullSeconds: Double { MovieSelection.seconds(of: candidates) }

    // MARK: Step 3 (F05)

    /// The automatic pick for the chosen length; choosing moments by hand starts with none.
    func pickAutomatically() {
        if source == .moments, presetIDs.isEmpty {
            picked = []
        } else {
            picked = Set(MovieSelection.pick(candidates, target: target, seed: seed))
        }
    }

    func toggle(_ id: UUID) {
        if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
    }

    var canBuild: Bool { picked.count >= MovieSelection.minimumMoments }

    /// The draft, its moments in the order they happened.
    func build() -> UUID? {
        let ordered = candidates.filter { picked.contains($0.id) }.map(\.id)
        do {
            let project = try MovieStore(context: library.context, store: library.store, now: { [clock] in clock.now() }).create(
                title: title, source: rule, length: length, aspectRatio: aspectRatio, fit: fit, momentIDs: ordered,
                seed: Int(truncatingIfNeeded: seed)
            )
            if length == .custom { project.customLength = Double(customMinutes) * 60 }
            try library.context.save()
            return project.id
        } catch {
            logger.error("Building the movie failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: Naming

    /// What the movie is called at first: "October 2026", "2025, the whole year", a collection's or place's name.
    var title: String {
        switch source {
        case .lastMonth: return MoviesModel.monthTitle(lastMonth)
        case .thisYear: return String(thisYear)
        case .lastYear: return String(localized: "\(String(thisYear - 1)), the whole year", bundle: .module)
        case .dates, .moments:
            let days = candidates.filter { picked.contains($0.id) }.map(\.day)
            guard let first = days.min(), let last = days.max() else { return String(localized: "New movie", bundle: .module) }
            return Self.span(first, last)
        case let .collection(id): return collections.first { $0.id == id }?.title ?? String(localized: "New movie", bundle: .module)
        case .place: return placeName ?? String(localized: "Unnamed place", bundle: .module)
        }
    }

    /// The source in F16's sentence: "Last month has 3 moments."
    var sourceName: String {
        switch source {
        case .lastMonth: String(localized: "Last month", bundle: .module)
        case .thisYear: String(localized: "This year", bundle: .module)
        case .lastYear: String(localized: "Last year", bundle: .module)
        case .dates: String(localized: "These dates", bundle: .module)
        case .collection: String(localized: "This collection", bundle: .module)
        case .place: String(localized: "This place", bundle: .module)
        case .moments: String(localized: "This choice", bundle: .module)
        }
    }

    /// F05: "spread evenly across October".
    var periodName: String {
        switch source {
        case .lastMonth: MoviesModel.monthName(lastMonth)
        case .thisYear: String(thisYear)
        case .lastYear: String(thisYear - 1)
        case let .collection(id): collections.first { $0.id == id }?.title ?? String(localized: "Movie period: this collection", bundle: .module)
        case .place: placeName ?? String(localized: "Movie period: this place", bundle: .module)
        case .dates, .moments: String(localized: "Movie period: these dates", bundle: .module)
        }
    }

    /// "Jun 1 – 30, 2026".
    static func span(_ first: Int, _ last: Int) -> String {
        let start = MemoriesView.dayDate(first)
        guard first != last else { return start.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt)) }
        return (start..<MemoriesView.dayDate(last)).formatted(Date.IntervalFormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt))
    }

    /// What the project remembers it was made from.
    var rule: MovieSourceRule {
        switch source {
        case .lastMonth: return MoviesModel.monthRule(lastMonth)
        case .thisYear, .lastYear, .dates:
            let days = days(of: source) ?? today...today
            return MovieSourceRule(kind: .dateRange, start: MemoriesView.dayDate(days.lowerBound), end: MemoriesView.dayDate(days.upperBound))
        case let .collection(id): return MovieSourceRule(kind: .collection, collectionID: id)
        case .place: return MovieSourceRule(kind: .place, momentIDs: presetIDs)
        case .moments: return MovieSourceRule(kind: .selection, momentIDs: Array(picked))
        }
    }

    /// A source chosen before the wizard opened.
    private func apply(_ rule: MovieSourceRule) {
        switch rule.kind {
        case .dateRange:
            source = .dates
            from = rule.start.map { LocalDay($0, in: .gmt).key }
            to = rule.end.map { LocalDay($0, in: .gmt).key }
        case .collection:
            if let id = rule.collectionID { source = .collection(id) }
        case .place:
            source = .place(rule.momentIDs.first?.uuidString ?? "")
            presetIDs = rule.momentIDs
            placeName = placeLabel(of: rule.momentIDs)
        case .selection, .onThisDay:
            source = .moments
            presetIDs = rule.momentIDs
        }
    }

    private func placeLabel(of ids: [UUID]) -> String? {
        guard let id = ids.first else { return nil }
        let moment = try? library.context.fetch(FetchDescriptor<Moment>(predicate: #Predicate { $0.id == id })).first
        return moment?.location?.placeLabel
    }
}
