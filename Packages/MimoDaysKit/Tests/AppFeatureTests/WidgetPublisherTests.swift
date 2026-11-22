@testable import AppFeature
import Core
import Foundation
import Persistence
import SwiftData
import Testing
import TestSupport
import UIKit
import WidgetFeature

/// P8.2: what the app hands the widgets.
@MainActor
struct WidgetPublisherTests {
    private let container = try! TestStore.container()
    private var context: ModelContext { container.mainContext }
    private let root = FileManager.default.temporaryDirectory.appending(path: "WidgetPublisher-\(UUID().uuidString)")
    private var shelf: WidgetShelf { WidgetShelf(directory: root.appending(path: "Shelf")) }
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 2026-11-22 10:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_795_341_600)

    private func publisher() throws -> WidgetPublisher {
        WidgetPublisher(context: context, store: try MediaStore(root: root.appending(path: "Media")), shelf: shelf, reload: {})
    }

    @discardableResult
    private func insert(_ day: (Int, Int, Int), type: MediaType = .photo, place: String? = nil, thumbnail: Bool = false) throws -> Moment {
        let date = calendar.date(from: DateComponents(year: day.0, month: day.1, day: day.2, hour: 12))!
        let moment = Moment(captured: CaptureTime(instant: date, timeZone: calendar.timeZone), origin: .manual, mediaType: type, createdAt: date)
        context.insert(moment)
        if let place {
            moment.location = MomentLocation(latitude: 1, longitude: 1, precision: .city, source: .gps, placeLabel: place)
        }
        if thumbnail {
            let path = "thumbs/\(moment.id.uuidString).jpg"
            let url = root.appending(path: "Media").appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { context in
                UIColor.systemTeal.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
            }
            try image.jpegData(compressionQuality: 0.9)!.write(to: url)
            let media = MomentMedia(
                role: .thumbnail, relativePath: path, uniformType: "public.jpeg", pixelWidth: 40, pixelHeight: 30, checksum: "x", byteCount: 1
            )
            moment.media.append(media)
        }
        try context.save()
        return moment
    }

    private var privacy: PrivacySettings { PrivacySettings() }

    @Test func onThisDayIsTheNearestEarlierYearForEachDayOfTheWeek() throws {
        let older = try insert((2024, 11, 22))
        let cover = try insert((2025, 11, 22), place: "Paris")
        try insert((2025, 11, 22), type: .video)
        let tomorrow = try insert((2023, 11, 23), type: .text)
        try insert((2026, 11, 22))  // today itself: not "on this day"

        let payload = try publisher().payload(showsPhotos: false, language: "en", now: now, calendar: calendar)
        #expect(payload.firstDay == 2026_11_22 && payload.lastDay == 2026_11_28)
        #expect(payload.onThisDay.count == 2)
        let today = try #require(payload.onThisDay.first { $0.today == 2026_11_22 })
        #expect(today.cover.id == cover.id && today.count == 2 && today.cover.place == "Paris")
        #expect(today.cover.id != older.id)
        let next = try #require(payload.onThisDay.first { $0.today == 2026_11_23 })
        #expect(next.cover.id == tomorrow.id && next.cover.kind == .text)
    }

    @Test func hiddenAndDeletedMomentsNeverShow() throws {
        let hidden = try insert((2025, 11, 22))
        hidden.isHiddenFromMemories = true
        let deleted = try insert((2024, 11, 22))
        deleted.deletedAt = now
        let hiddenDay = try insert((2023, 11, 22))
        try MemoryVisibility.setDayHidden(true, hiddenDay.localDay, in: context)
        try context.save()

        let payload = try publisher().payload(showsPhotos: true, language: "en", now: now, calendar: calendar)
        #expect(payload.onThisDay.isEmpty)
        #expect(payload.random.isEmpty)
    }

    @Test func picturesOnlyWithPhotosOnAndNeverForWords() async throws {
        let photo = try insert((2025, 11, 22), thumbnail: true)
        try insert((2025, 3, 8), type: .text)
        let publisher = try publisher()

        var settings = privacy
        await publisher.publish(privacy: settings, language: "de", now: now, calendar: calendar)
        var payload = try #require(shelf.read())
        #expect(payload.language == "de" && !payload.showsPhotos)
        #expect(payload.images.isEmpty && shelf.imageNames.isEmpty)

        settings.widgetPhotos = true
        await publisher.publish(privacy: settings, language: "de", now: now, calendar: calendar)
        payload = try #require(shelf.read())
        #expect(payload.images == ["\(photo.id.uuidString).jpg"])
        #expect(shelf.imageNames == payload.images)
        #expect(payload.random.first { $0.kind == .text }?.image == nil)

        // Off again: the pictures go at once.
        settings.widgetPhotos = false
        await publisher.publish(privacy: settings, language: "de", now: now, calendar: calendar)
        #expect(shelf.imageNames.isEmpty)
    }

    @Test func appLockLeavesNothingPrivate() async throws {
        try insert((2025, 11, 22), place: "Paris", thumbnail: true)
        var settings = privacy
        settings.widgetPhotos = true
        let publisher = try publisher()
        await publisher.publish(privacy: settings, language: "en", now: now, calendar: calendar)
        #expect(!shelf.imageNames.isEmpty)

        settings.appLock = true
        await publisher.publish(privacy: settings, language: "en", now: now, calendar: calendar)
        #expect(shelf.read() == .locked(language: "en"))
        #expect(shelf.imageNames.isEmpty)
    }

    @Test func deleteAllDataEmptiesTheShelf() async throws {
        try insert((2025, 11, 22))
        let publisher = try publisher()
        await publisher.publish(privacy: privacy, language: "en", now: now, calendar: calendar)
        #expect(shelf.read() != nil)
        publisher.purge()
        #expect(shelf.read() == nil)
    }

    @Test func randomIsASampleOfTheWholeArchive() throws {
        for day in 1...40 { try insert((2020, 1, day % 28 + 1)) }
        let payload = try publisher().payload(showsPhotos: false, language: "en", now: now, calendar: calendar)
        #expect(payload.random.count == WidgetPublisher.randomPool)
        #expect(Set(payload.random.map(\.id)).count == payload.random.count)
    }

    @Test func oldSettingsKeepPhotosOff() throws {
        let saved = Data(#"{"appLock":false,"lockAfter":0,"savesPlace":true,"precision":"city"}"#.utf8)
        #expect(try JSONDecoder().decode(PrivacySettings.self, from: saved).widgetPhotos == false)
    }
}
