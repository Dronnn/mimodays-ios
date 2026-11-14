@preconcurrency import AVFoundation
import Core
import CoreTransferable
import Foundation
import ImageIO
import Observation
import os
import Persistence
import SwiftData
import UIKit
import UniformTypeIdentifiers

/// E05: photos and videos picked in Photos become moments on the day they were taken, marked "From Photos",
/// without a selfie window. When and where come from the files themselves, so no Photos access is asked for;
/// the place is kept at city level only when chosen. Files already in MimoDays (same bytes) are skipped.
@MainActor
@Observable
final class PhotoImportModel: Identifiable {
    /// One picked file, read and copied to tmp.
    struct Picked: Identifiable, Sendable {
        let id: Int
        let url: URL
        let isVideo: Bool
        let capturedAt: CaptureTime
        let point: GeoPoint?
        let checksum: String
        let duration: TimeInterval?
        let hasAudio: Bool
    }

    enum Phase: Equatable {
        case loading(Double)
        case ready
        case importing(Double)
        case failed
    }

    var phase = Phase.loading(0)
    var keepsPlace = true
    // Set by `load`; open for snapshots.
    var picked: [Picked] = []
    var thumbnails: [Int: UIImage] = [:]
    /// Picked files whose bytes are already in a moment (or picked twice).
    var skipped: Set<Int> = []

    private let library: MediaLibrary
    private let saver: MomentSaver
    private let lookup: any PlaceLookup
    private static let logger = Logger(subsystem: "MimoDays", category: "Import")

    init(library: MediaLibrary, saver: MomentSaver, lookup: any PlaceLookup) {
        self.library = library
        self.saver = saver
        self.lookup = lookup
    }

    /// What "Import N" brings in, oldest first.
    var new: [Picked] { picked.filter { !skipped.contains($0.id) }.sorted { $0.capturedAt.instant < $1.capturedAt.instant } }

    var count: Int { picked.count }
    var videos: Int { picked.count { $0.isVideo } }

    /// Reads files handed over by the picker (or tests): date, zone, place, checksum, a thumbnail.
    func load(_ files: [(url: URL, isVideo: Bool)]) async {
        let existing = existingChecksums()
        var seen = existing
        var picked: [Picked] = []
        var skipped: Set<Int> = []
        for (index, file) in files.enumerated() {
            guard let item = await Task.detached(priority: .userInitiated, operation: { await Self.read(file.url, isVideo: file.isVideo, id: index) }).value else {
                continue
            }
            if !seen.insert(item.checksum).inserted { skipped.insert(item.id) }
            picked.append(item)
            phase = .loading(Double(index + 1) / Double(files.count))
            thumbnails[item.id] = await ReviewModel.still(item.url, maxPixelSize: 300, at: 0)
        }
        self.picked = picked
        self.skipped = skipped
        phase = picked.isEmpty ? .failed : .ready
    }

    /// Loads what the picker returned, then reads it.
    func load(_ items: [some PhotoPickerItemLoading]) async {
        var files: [(url: URL, isVideo: Bool)] = []
        for (index, item) in items.enumerated() {
            if let file = try? await item.loadFile() { files.append((file.url, file.isVideo)) }
            phase = .loading(Double(index + 1) / Double(items.count) / 2)
        }
        await load(files)
    }

    /// "Import N": each new file becomes a moment. True when all of them did.
    func importAll() async -> Bool {
        guard phase == .ready else { return false }
        let new = new
        phase = .importing(0)
        var cities: [String: String?] = [:]
        var failures = 0
        for (index, item) in new.enumerated() {
            var place: ReviewPlace?
            if keepsPlace, let point = item.point {
                let key = String(format: "%.2f,%.2f", point.latitude, point.longitude)
                if cities[key] == nil { cities[key] = .some(await lookup.city(at: point)) }
                place = ReviewPlace.current(city: cities[key] ?? nil, at: point)
                place?.source = .imported
            }
            let media: CaptureResult.Media = item.isVideo
                ? .video(CapturedVideo(
                    mainURL: item.url, mainPosition: .back, selfieURL: nil, duration: item.duration ?? 0, selfieOffset: 0, hasAudio: item.hasAudio
                ))
                : .photo(CapturedPhoto(mainURL: item.url, mainPosition: .back, selfieURL: nil))
            do {
                _ = try await saver.save(MomentDraft(
                    capture: CaptureResult(media: media, window: nil, capturedAt: item.capturedAt), caption: "", window: nil, promptID: nil,
                    place: place, origin: .imported
                ))
            } catch {
                failures += 1
                Self.logger.error("Importing a file failed: \(String(describing: error), privacy: .public)")
            }
            phase = .importing(Double(index + 1) / Double(new.count))
        }
        phase = failures == 0 ? .ready : .failed
        return failures == 0
    }

    /// Removes the tmp copies nobody imported.
    func discard() {
        picked.forEach { try? FileManager.default.removeItem(at: $0.url) }
    }

    private func existingChecksums() -> Set<String> {
        let media = (try? library.context.fetch(FetchDescriptor<MomentMedia>())) ?? []
        return Set(media.filter { $0.moment?.deletedAt == nil && ($0.role == .rearSource || $0.role == .frontSource) }.map(\.checksum))
    }

    // MARK: Reading

    nonisolated static func read(_ url: URL, isVideo: Bool, id: Int) async -> Picked? {
        guard let checksum = try? MediaStore.sha256(of: url) else { return nil }
        if isVideo {
            let asset = AVURLAsset(url: url)
            guard let duration = try? await asset.load(.duration).seconds, duration > 0 else { return nil }
            let metadata = (try? await asset.load(.metadata)) ?? []
            func value(_ identifier: AVMetadataIdentifier) async -> String? {
                guard let item = metadata.first(where: { $0.identifier == identifier }) else { return nil }
                return try? await item.load(.stringValue)
            }
            let created = await value(.quickTimeMetadataCreationDate)
            var time = created.flatMap(captureTime(iso8601:))
            if time == nil, let item = try? await asset.load(.creationDate), let date = try? await item.load(.dateValue) {
                time = CaptureTime(instant: date, timeZone: .current)
            }
            let location = await value(.quickTimeMetadataLocationISO6709)
            let hasAudio = !((try? await asset.loadTracks(withMediaType: .audio)) ?? []).isEmpty
            return Picked(
                id: id, url: url, isVideo: true, capturedAt: time ?? fileTime(url), point: location.flatMap(point(iso6709:)), checksum: checksum, duration: duration,
                hasAudio: hasAudio
            )
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let time = captureTime(
            exif: (exif?[kCGImagePropertyExifDateTimeOriginal] ?? tiff?[kCGImagePropertyTIFFDateTime]) as? String,
            offset: exif?[kCGImagePropertyExifOffsetTimeOriginal] as? String
        ) ?? fileTime(url)
        return Picked(
            id: id, url: url, isVideo: false, capturedAt: time, point: point(gps: properties[kCGImagePropertyGPSDictionary] as? [CFString: Any]),
            checksum: checksum, duration: nil, hasAudio: false
        )
    }

    /// EXIF's "2026:11:11 18:42:05" with "+04:00"; without an offset, the time is read where this iPhone is.
    nonisolated static func captureTime(exif: String?, offset: String?) -> CaptureTime? {
        guard let exif else { return nil }
        let zone = offset.flatMap(zone(offset:)) ?? .current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        guard let instant = formatter.date(from: exif) else { return nil }
        return CaptureTime(instant: instant, timeZone: zone)
    }

    /// QuickTime's "2026-11-11T18:42:05+0400".
    nonisolated static func captureTime(iso8601 text: String) -> CaptureTime? {
        guard let instant = try? Date(text, strategy: .iso8601) else { return nil }
        let zone = text.firstMatch(of: /([+-]\d{2}):?(\d{2})$/).flatMap { zone(offset: "\($0.1):\($0.2)") } ?? .gmt
        return CaptureTime(instant: instant, timeZone: zone)
    }

    /// "+04:00" as a fixed-offset zone.
    nonisolated static func zone(offset: String) -> TimeZone? {
        guard let match = offset.firstMatch(of: /^([+-])(\d{2}):?(\d{2})$/), let hours = Int(match.2), let minutes = Int(match.3) else { return nil }
        return TimeZone(secondsFromGMT: (match.1 == "-" ? -1 : 1) * (hours * 3600 + minutes * 60))
    }

    nonisolated static func point(gps: [CFString: Any]?) -> GeoPoint? {
        guard let gps, let latitude = number(gps[kCGImagePropertyGPSLatitude]), let longitude = number(gps[kCGImagePropertyGPSLongitude]) else { return nil }
        let south = (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S"
        let west = (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W"
        return GeoPoint(latitude: south ? -latitude : latitude, longitude: west ? -longitude : longitude, horizontalAccuracy: 0)
    }

    /// "+40.1811+044.5136+000.000/".
    nonisolated static func point(iso6709 text: String) -> GeoPoint? {
        guard let match = text.firstMatch(of: /^([+-]\d+(?:\.\d+)?)([+-]\d+(?:\.\d+)?)/),
              let latitude = Double(match.1), let longitude = Double(match.2) else { return nil }
        return GeoPoint(latitude: latitude, longitude: longitude, horizontalAccuracy: 0)
    }

    private nonisolated static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap(Double.init)
    }

    /// No date in the file: when the copy was made.
    private nonisolated static func fileTime(_ url: URL) -> CaptureTime {
        let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
        return CaptureTime(instant: date, timeZone: .current)
    }
}

/// A picked item that can hand over its original file (PhotosPickerItem; a stand-in in tests).
protocol PhotoPickerItemLoading: Sendable {
    func loadFile() async throws -> PickedFile?
}

/// The picked photo or video, copied to tmp as Photos stores it (HEIC stays HEIC, with its EXIF).
struct PickedFile: Transferable {
    let url: URL
    let isVideo: Bool

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in PickedFile(url: try copy(received.file), isVideo: true) }
        FileRepresentation(importedContentType: .image) { received in PickedFile(url: try copy(received.file), isVideo: false) }
    }

    private static func copy(_ file: URL) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Import", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appending(path: "\(UUID().uuidString).\(file.pathExtension.isEmpty ? "dat" : file.pathExtension)")
        try FileManager.default.copyItem(at: file, to: target)
        return target
    }
}
