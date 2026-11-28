import Core
import Foundation
import os
import Persistence
import SwiftData
import UIKit
import WidgetFeature
import WidgetKit

/// P8.2: hands On this day and Random memory what they show. Eligible moments only (not deleted, not hidden); words
/// only unless Show photos in widgets is on; nothing at all under App Lock. The archive stays the source of truth:
/// the shelf is rewritten whole each time.
@MainActor
struct WidgetPublisher {
    let context: ModelContext
    let store: MediaStore
    let shelf: WidgetShelf?
    var reload: () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    private let logger = Logger(subsystem: "MimoDays", category: "Widgets")

    /// On this day is worked out for a week ahead: the widget can't read the archive.
    static let days = 7
    static let randomPool = 24
    static let pixels = 360

    func publish(privacy: PrivacySettings, language: String, now: Date = Date(), calendar: Calendar = .current) async {
        guard let shelf else { return }
        do {
            if privacy.appLock {
                try shelf.write(.locked(language: language), images: [:])
            } else {
                let payload = payload(showsPhotos: privacy.widgetPhotos, language: language, now: now, calendar: calendar)
                try shelf.write(payload, images: await images(for: payload, existing: shelf.imageNames))
            }
        } catch {
            logger.error("Writing the widgets' shelf failed: \(error.localizedDescription, privacy: .public)")
            shelf.purge()
        }
        reload()
    }

    /// Delete all data: the widgets' copies go at once.
    func purge() {
        shelf?.purge()
        reload()
    }

    func payload(showsPhotos: Bool, language: String, now: Date, calendar: Calendar) -> WidgetPayload {
        let visibility = MemoryVisibility(context: context)
        let days = (0..<Self.days).compactMap { calendar.date(byAdding: .day, value: $0, to: now) }
            .map { WidgetContent.dayKey($0, calendar: calendar) }
        // Each day's own earlier years: a week across New Year has days of two years.
        let keys = days.flatMap { day in (1...100).map { (day / 10_000 - $0) * 10_000 + day % 10_000 } }
        let candidates = visibility.visible(fetch(#Predicate { $0.deletedAt == nil && keys.contains($0.localDay) }, limit: nil))
        // The nearest earlier year with moments on the day's month and day, as Today's On this day.
        let onThisDay = days.compactMap { today -> WidgetPayload.Day? in
            let year = today / 10_000
            let sameDay = candidates.filter { $0.localDay % 10_000 == today % 10_000 && $0.localDay / 10_000 < year }
                .sorted { ($0.localDay, $0.capturedAt) > ($1.localDay, $1.capturedAt) }
            guard let cover = sameDay.first else { return nil }
            let count = sameDay.count { $0.localDay == cover.localDay }
            return WidgetPayload.Day(today: today, count: count, cover: memory(cover, showsPhotos: showsPhotos))
        }
        return WidgetPayload(
            showsPhotos: showsPhotos, language: language, firstDay: days[0], lastDay: days[days.count - 1],
            onThisDay: onThisDay, random: randomPool(visibility).map { memory($0, showsPhotos: showsPhotos) }
        )
    }

    /// A sample of the archive, read by offset so a big archive isn't loaded whole.
    private func randomPool(_ visibility: MemoryVisibility) -> [Moment] {
        let alive = #Predicate<Moment> { $0.deletedAt == nil }
        let count = (try? context.fetchCount(FetchDescriptor(predicate: alive))) ?? 0
        guard count > 0 else { return [] }
        let offsets = count <= Self.randomPool * 2 ? Array(0..<count) : Array((0..<count).shuffled().prefix(Self.randomPool * 2))
        var picked: [Moment] = []
        for offset in offsets.shuffled() where picked.count < Self.randomPool {
            var descriptor = FetchDescriptor(predicate: alive, sortBy: [SortDescriptor(\.capturedAt)])
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = 1
            if let moment = try? context.fetch(descriptor).first, !visibility.isHidden(moment) { picked.append(moment) }
        }
        return picked
    }

    private func memory(_ moment: Moment, showsPhotos: Bool) -> WidgetPayload.Memory {
        let kind: WidgetPayload.Kind = switch moment.mediaType {
        case .text: .text
        case .video: .video
        case .photo: moment.media.contains { $0.role == .livePhotoMotion } ? .livePhoto : .photo
        }
        let hasPicture = showsPhotos && kind != .text && moment.media.contains { $0.role == .thumbnail }
        return WidgetPayload.Memory(
            id: moment.id, day: moment.localDay, place: moment.location?.placeLabel, kind: kind,
            image: hasPicture ? "\(moment.id.uuidString).jpg" : nil
        )
    }

    /// Small pictures for those not on the shelf yet, from each moment's own thumbnail.
    private func images(for payload: WidgetPayload, existing: Set<String>) async -> [String: Data] {
        var images: [String: Data] = [:]
        for name in payload.images.subtracting(existing) {
            guard let id = UUID(uuidString: String(name.dropLast(4))),
                  let moment = try? context.fetch(FetchDescriptor<Moment>(predicate: #Predicate { $0.id == id })).first,
                  let path = moment.media.first(where: { $0.role == .thumbnail })?.relativePath,
                  let url = try? store.url(for: path),
                  let image = await ImageDecoding.thumbnail(url, maxPixelSize: Self.pixels),
                  let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.8)
            else { continue }
            images[name] = data
        }
        return images
    }

    private func fetch(_ predicate: Predicate<Moment>, limit: Int?) -> [Moment] {
        var descriptor = FetchDescriptor<Moment>(predicate: predicate)
        descriptor.fetchLimit = limit
        do {
            return try context.fetch(descriptor)
        } catch {
            logger.error("Reading moments for the widgets failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
