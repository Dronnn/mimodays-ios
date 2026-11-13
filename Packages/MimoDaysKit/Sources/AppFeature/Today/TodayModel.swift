import Core
import Foundation
import Observation
import os
import Persistence
import SwiftData
import SwiftUI

/// One saved moment as Today shows it.
struct MomentSummary: Equatable, Identifiable {
    var id: UUID
    var captured: CaptureTime
    var mediaType: MediaType
    var origin: MomentOrigin
    var place: String?
    /// The full-frame stream and the one in the selfie window; a video gives a frame of each.
    var mainPath: String?
    var selfiePath: String?
    /// The composed thumbnail grids and strips show.
    var thumbnailPath: String?

    init(_ moment: Moment) {
        id = moment.id
        captured = CaptureTime(instant: moment.capturedAt, timeZoneID: moment.timeZoneID)
        mediaType = moment.mediaType
        origin = moment.origin
        place = moment.location?.placeLabel
        let windowRole = moment.pipLayout?.source
        let sources = moment.media.filter { $0.role == .rearSource || $0.role == .frontSource }
        selfiePath = windowRole.flatMap { role in sources.first { $0.role == role } }?.relativePath
        mainPath = sources.first { $0.role != windowRole }?.relativePath
        thumbnailPath = moment.media.first { $0.role == .thumbnail }?.relativePath
    }
}

/// T06: the same day in an earlier year.
struct OnThisDay: Equatable {
    var yearsAgo: Int
    var count: Int
    var cover: MomentSummary
}

/// Today (T01-T07): the latest moment, the surprise ribbon, this month's strip, On this day and the movie entry.
/// Reads the store again whenever it saves, so a new moment, an edit or a delete shows without a relaunch.
@MainActor
@Observable
final class TodayModel {
    private(set) var latest: MomentSummary?
    /// This calendar month, newest first.
    private(set) var month: [MomentSummary] = []
    private(set) var count = 0
    private(set) var onThisDay: OnThisDay?
    private(set) var surprise = SurpriseStatus.onItsWay
    /// When the ribbon may change by itself; Today refreshes then.
    private(set) var surpriseChangesAt: Date?
    /// Decoded pictures by stored path and size.
    private(set) var images: [ImageKey: UIImage] = [:]

    struct ImageKey: Hashable {
        var path: String
        var maxPixelSize: Int
    }

    static let monthLimit = 12
    static let heroPixels = 1200
    static let selfiePixels = 400
    static let tilePixels = 300

    private let context: ModelContext
    private let surprises: SurpriseCoordinator
    private let permissions: any PermissionService
    private let store: MediaStore
    private let thumbnails: ThumbnailPipeline
    private let clock: any DateProvider
    private let calendar: () -> Calendar
    private let logger = Logger(subsystem: "MimoDays", category: "Today")

    init(
        context: ModelContext, surprises: SurpriseCoordinator, permissions: any PermissionService, store: MediaStore,
        thumbnails: ThumbnailPipeline, clock: any DateProvider = SystemDateProvider(), calendar: @escaping () -> Calendar = { .current }
    ) {
        self.context = context
        self.surprises = surprises
        self.permissions = permissions
        self.store = store
        self.thumbnails = thumbnails
        self.clock = clock
        self.calendar = calendar
    }

    var isEmpty: Bool { latest == nil }

    /// Today's date line and "Your November" follow this clock, so tests see a fixed day.
    var now: Date { clock.now() }

    /// "Today, 2:37 PM", "Yesterday, 6:42 PM", "Wed, Nov 11 · 6:42 PM": in the moment's own time zone (§H20).
    func timeText(_ time: CaptureTime) -> Text {
        var calendar = calendar()
        calendar.timeZone = time.timeZone
        var clock = Date.FormatStyle(date: .omitted, time: .shortened)
        clock.timeZone = time.timeZone
        if calendar.isDate(time.instant, inSameDayAs: now) {
            return Text("Today, \(Text(time.instant, format: clock))", bundle: .module)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(time.instant, inSameDayAs: yesterday) {
            return Text("Yesterday, \(Text(time.instant, format: clock))", bundle: .module)
        }
        var day = Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day()
        day.timeZone = time.timeZone
        return Text("Day and time: \(Text(time.instant, format: day)) · \(Text(time.instant, format: clock))", bundle: .module)
    }

    func image(_ path: String?, _ maxPixelSize: Int) -> UIImage? {
        path.flatMap { images[ImageKey(path: $0, maxPixelSize: maxPixelSize)] }
    }

    func refresh() async {
        let now = clock.now()
        let calendar = calendar()
        let today = LocalDay(now, in: calendar.timeZone)
        latest = fetch(Self.alive, sort: [SortDescriptor(\.capturedAt, order: .reverse)], limit: 1).first.map(MomentSummary.init)
        count = (try? context.fetchCount(FetchDescriptor<Moment>(predicate: Self.alive))) ?? 0

        let first = today.year * 10_000 + today.month * 100
        let last = first + 99
        month = fetch(
            #Predicate { $0.deletedAt == nil && $0.localDay > first && $0.localDay <= last },
            sort: [SortDescriptor(\.capturedAt, order: .reverse)], limit: Self.monthLimit
        ).map(MomentSummary.init)
        onThisDay = fetchOnThisDay(today)

        let status = await surprises.todayStatus(latestCapture: latest?.captured.instant)
        surprise = status.status
        surpriseChangesAt = status.changesAt
        await loadImages()
    }

    /// Capture from Today. While a surprise is ready the camera answers it (T03).
    func captureRequest() -> UUID? {
        guard case let .ready(promptID) = surprise, surprises.open(promptID: promptID) else { return nil }
        return promptID
    }

    func resume() async {
        await surprises.resume()
        await refresh()
    }

    /// T07 "Turn on". False when only Settings can allow notifications again. A "Don't Allow" given just now
    /// to the system prompt stands: no jump to Settings.
    func turnOn() async -> Bool {
        let status = await permissions.status(of: .notifications)
        if status == .notDetermined {
            guard await permissions.request(.notifications).isUsable else { return true }
        } else if !status.isUsable {
            return !status.needsSettings
        }
        await surprises.turnOn()
        await refresh()
        return true
    }

    // MARK: Store

    private static let alive = #Predicate<Moment> { $0.deletedAt == nil }

    /// The nearest earlier year with moments on today's month and day.
    private func fetchOnThisDay(_ today: LocalDay) -> OnThisDay? {
        let monthDay = today.month * 100 + today.day
        let keys = (1...100).map { (today.year - $0) * 10_000 + monthDay }
        let moments = fetch(
            #Predicate { $0.deletedAt == nil && keys.contains($0.localDay) },
            sort: [SortDescriptor(\.localDay, order: .reverse), SortDescriptor(\.capturedAt, order: .reverse)], limit: nil
        )
        guard let cover = moments.first else { return nil }
        let sameYear = moments.filter { $0.localDay == cover.localDay }
        return OnThisDay(yearsAgo: today.year - cover.localDay / 10_000, count: sameYear.count, cover: MomentSummary(cover))
    }

    private func fetch(_ predicate: Predicate<Moment>, sort: [SortDescriptor<Moment>], limit: Int?) -> [Moment] {
        var descriptor = FetchDescriptor<Moment>(predicate: predicate, sortBy: sort)
        descriptor.fetchLimit = limit
        do {
            return try context.fetch(descriptor)
        } catch {
            logger.error("Reading moments failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    // MARK: Images

    /// Everything Today shows, decoded small; pictures no longer shown are dropped.
    private func loadImages() async {
        var wanted: [ImageKey] = []
        if let latest {
            wanted += [latest.mainPath.map { ImageKey(path: $0, maxPixelSize: Self.heroPixels) }, latest.selfiePath.map { ImageKey(path: $0, maxPixelSize: Self.selfiePixels) }].compactMap(\.self)
        }
        wanted += month.compactMap { $0.thumbnailPath.map { ImageKey(path: $0, maxPixelSize: Self.tilePixels) } }
        if let cover = onThisDay?.cover.mainPath { wanted.append(ImageKey(path: cover, maxPixelSize: Self.heroPixels)) }

        var loaded: [ImageKey: UIImage] = [:]
        for key in wanted {
            if let image = images[key] {
                loaded[key] = image
                continue
            }
            guard let url = try? store.url(for: key.path),
                  let image = try? await thumbnails.thumbnail(for: url, maxPixelSize: key.maxPixelSize) else { continue }
            loaded[key] = UIImage(cgImage: image)
        }
        images = loaded
    }
}
