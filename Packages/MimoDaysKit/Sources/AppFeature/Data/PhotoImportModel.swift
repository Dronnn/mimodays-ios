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

/// E05: photos and videos picked in Photos become moments on the day they were taken, marked "Imported",
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
        /// P8.6: a Live Photo's motion, checked to play; nil for a Live Photo whose motion didn't come or won't play.
        var motionURL: URL?
        var isLivePhoto = false
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
    /// Picked items that couldn't be loaded (an iCloud download that failed) or read: Import then says some didn't come in.
    private(set) var unreadable = 0
    /// P8.6: Live Photos whose motion couldn't be loaded, waiting for Import as still or Skip; Import leaves them out.
    var motionFailed: Set<Int> = []
    /// P8.6: picked Live Photos whose still is already here without motion: "Keep motion" adds it to that moment.
    var motionToAttach: [Int: UUID] = [:]

    /// Every copy the picker handed over, read or not yet, so closing mid-load leaves none behind.
    private var received: [URL] = []
    private var loading: Task<Void, Never>?
    private let library: MediaLibrary
    private let saver: MomentSaver
    private let lookup: any PlaceLookup
    private static let logger = Logger(subsystem: "MimoDays", category: "Import")

    init(library: MediaLibrary, saver: MomentSaver, lookup: any PlaceLookup) {
        self.library = library
        self.saver = saver
        self.lookup = lookup
    }

    /// What "Import N" brings in, oldest first: not what's here already, nor a Live Photo still waiting on its motion.
    var new: [Picked] {
        picked.filter { !skipped.contains($0.id) && !motionFailed.contains($0.id) }.sorted { $0.capturedAt.instant < $1.capturedAt.instant }
    }

    var count: Int { picked.count }
    var videos: Int { picked.count { $0.isVideo } }
    var livePhotos: Int { picked.count(where: \.isLivePhoto) }

    /// "Import as still": the Live Photo comes in as a photo.
    func importAsStill(_ id: Int) {
        motionFailed.remove(id)
    }

    /// "Skip": the Live Photo stays out.
    func skip(_ id: Int) {
        motionFailed.remove(id)
        skipped.insert(id)
    }

    /// "Keep motion": the motion joins the moment that has this still; no second moment.
    func attachMotion(_ id: Int) async -> Bool {
        guard let momentID = motionToAttach[id], let motion = picked.first(where: { $0.id == id })?.motionURL,
              let moment = try? library.context.fetch(FetchDescriptor<Moment>(predicate: #Predicate { $0.id == momentID })).first
        else { return false }
        do {
            try await saver.attachMotion(motion, to: moment)
        } catch {
            Self.logger.error("Keeping a Live Photo's motion failed: \(String(describing: error), privacy: .public)")
            return false
        }
        motionToAttach[id] = nil
        try? FileManager.default.removeItem(at: motion)
        return true
    }

    /// Reads files handed over by tests: date, zone, place, checksum, a thumbnail.
    func load(_ files: [(url: URL, isVideo: Bool)]) async {
        await load(files.map { PickedFile(url: $0.url, isVideo: $0.isVideo) })
    }

    /// Reads files handed over by the picker: date, zone, place, checksum, a thumbnail.
    func load(_ files: [PickedFile]) async {
        let existing = existingStills()
        var seen = Set(existing.keys)
        var picked: [Picked] = []
        var skipped: Set<Int> = []
        var motionFailed: Set<Int> = []
        var motionToAttach: [Int: UUID] = [:]
        received += files.flatMap { [$0.url, $0.motionURL].compactMap(\.self) }.filter { !received.contains($0) }
        for (index, file) in files.enumerated() {
            guard !Task.isCancelled else { return }
            guard let item = await Task.detached(priority: .userInitiated, operation: { await Self.read(file, id: index) }).value else {
                unreadable += 1
                continue
            }
            if !seen.insert(item.checksum).inserted {
                skipped.insert(item.id)
                if item.motionURL != nil, let here = existing[item.checksum], !here.hasMotion, !motionToAttach.values.contains(here.id) {
                    motionToAttach[item.id] = here.id
                }
            } else if item.isLivePhoto, item.motionURL == nil {
                motionFailed.insert(item.id)
            }
            picked.append(item)
            phase = .loading(Double(index + 1) / Double(files.count))
            thumbnails[item.id] = await ReviewModel.still(item.url, maxPixelSize: 300, at: 0)
        }
        guard !Task.isCancelled else { return }
        self.picked = picked
        self.skipped = skipped
        self.motionFailed = motionFailed
        self.motionToAttach = motionToAttach
        phase = picked.isEmpty ? .failed : .ready
    }

    /// The picker's choice, loaded and read until the screen closes.
    func start(_ items: [some PhotoPickerItemLoading]) {
        loading = Task { await load(items) }
    }

    /// Loads what the picker returned, then reads it.
    func load(_ items: [some PhotoPickerItemLoading]) async {
        var files: [PickedFile] = []
        for (index, item) in items.enumerated() {
            let file = Task.isCancelled ? nil : try? await item.loadFile()
            if let file { received.append(file.url) }
            guard !Task.isCancelled else {
                // The screen closed: what was copied, this one included, goes, and nothing more is loaded.
                received.forEach { try? FileManager.default.removeItem(at: $0) }
                received = []
                return
            }
            if let motion = file?.motionURL { received.append(motion) }
            guard let file else {
                unreadable += 1
                continue
            }
            files.append(file)
            phase = .loading(Double(index + 1) / Double(items.count) / 2)
        }
        await load(files)
    }

    /// "Import N": each new file becomes a moment. True when all of them did, and every picked item could be read.
    func importAll() async -> Bool {
        guard phase == .ready else { return false }
        let new = new
        // One choice for the whole batch, as it was when Import was tapped.
        let keepsPlace = keepsPlace
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
                : .photo(CapturedPhoto(mainURL: item.url, mainPosition: .back, selfieURL: nil, motionURL: item.motionURL))
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
        return failures == 0 && unreadable == 0
    }

    /// Stops loading and removes the tmp copies nobody imported.
    func discard() {
        loading?.cancel()
        loading = nil
        (received + picked.flatMap { [$0.url, $0.motionURL].compactMap(\.self) }).forEach { try? FileManager.default.removeItem(at: $0) }
        received = []
    }

    /// The checksums of the camera files here, each with its moment and whether that one has a Live Photo's motion.
    private func existingStills() -> [String: (id: UUID, hasMotion: Bool)] {
        let media = (try? library.context.fetch(FetchDescriptor<MomentMedia>())) ?? []
        var stills: [String: (id: UUID, hasMotion: Bool)] = [:]
        for file in media where file.role == .rearSource || file.role == .frontSource {
            guard let moment = file.moment, moment.deletedAt == nil else { continue }
            stills[file.checksum] = (moment.id, moment.livePhotoMotion != nil)
        }
        return stills
    }

    // MARK: Reading

    /// A picked file read; a Live Photo's motion is kept only if it plays.
    nonisolated static func read(_ file: PickedFile, id: Int) async -> Picked? {
        guard var item = await read(file.url, isVideo: file.isVideo, id: id) else { return nil }
        item.isLivePhoto = file.isLivePhoto || file.motionURL != nil
        if let motion = file.motionURL, await plays(motion) { item.motionURL = motion }
        return item
    }

    nonisolated static func plays(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration).seconds, duration > 0 else { return false }
        return !((try? await asset.loadTracks(withMediaType: .video)) ?? []).isEmpty
    }

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
    /// P8.6: a Live Photo's paired motion.
    var motionURL: URL?
    /// A Live Photo, with or without its motion: without it, E05 asks before importing the still alone.
    var isLivePhoto = false

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in PickedFile(url: try copy(received.file), isVideo: true) }
        FileRepresentation(importedContentType: .image) { received in PickedFile(url: try copy(received.file), isVideo: false) }
    }

    static func target(extension pathExtension: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Import", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "\(UUID().uuidString).\(pathExtension.isEmpty ? "dat" : pathExtension)")
    }

    static func copy(_ file: URL) throws -> URL {
        let target = try target(extension: file.pathExtension)
        try FileManager.default.copyItem(at: file, to: target)
        return target
    }
}
