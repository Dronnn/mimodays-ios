@preconcurrency import AVFoundation
import Core
import Foundation
import ImageIO
import Persistence
import SwiftData
import UniformTypeIdentifiers

/// E01 and E02: moments as files someone else can open. Pictures leave as seen (window in place) or as the
/// camera's own files; voice notes and notes come along when chosen. The exact place is taken out of every
/// file unless the person turns it on - then it's written in, and into the notes and the list.
@MainActor
struct MomentExporter {
    struct Options: Equatable {
        /// The picture as seen in MimoDays, window in place.
        var asSeen = true
        /// The camera's front and back files, each on its own.
        var originals = false
        // Doc 01 §13, §17: voice notes and exact places stay private unless the person adds them.
        var voiceNotes = false
        var notes = true
        var exactPlace = false
    }

    /// One moment's files, worked out on the main actor and written off it.
    struct Item: Sendable {
        enum Source: Sendable {
            case file(URL, isVideo: Bool)
            case composedVideo(main: URL, selfie: URL?, timing: VideoTiming)
        }

        var id: UUID
        /// "2026-10-07 12.00.00", in the moment's own time zone.
        var name: String
        var pictures: [(source: Source, suffix: String, fileExtension: String)]
        var voice: URL?
        var text: String?
        var place: (latitude: Double, longitude: Double)?
        var row: [String]
    }

    let library: MediaLibrary

    nonisolated static let csvHeader = ["file", "date", "time zone", "title", "note", "voice note", "place", "latitude", "longitude", "favorite"]

    func items(_ ids: [UUID], options: Options) -> [Item] {
        var names: [String: Int] = [:]
        return moments(ids).map { moment in
            var name = Self.name(moment)
            names[name, default: 0] += 1
            if let count = names[name], count > 1 { name += " \(count)" }
            return item(moment, name: name, options: options)
        }
    }

    /// What the moments have, so E01 offers only the switches that matter.
    struct Contents: Equatable {
        var isVideo = false
        var voice = false
        var text = false
        var place = false
    }

    func contents(_ ids: [UUID]) -> Contents {
        moments(ids).reduce(into: Contents()) { contents, moment in
            contents.isVideo = contents.isVideo || moment.mediaType == .video
            contents.voice = contents.voice || !moment.voiceNotes.isEmpty
            contents.text = contents.text || moment.title?.isEmpty == false || moment.note?.isEmpty == false
            contents.place = contents.place || moment.location?.latitude != nil
        }
    }

    /// About how much the files will take.
    func estimatedBytes(_ ids: [UUID], options: Options) -> Int64 {
        moments(ids).reduce(Int64(0)) { sum, moment in
            let summary = MomentSummary(moment)
            var bytes: Int64 = 0
            if options.asSeen {
                let seen = moment.media.first { $0.role == .composedPreview && moment.mediaType == .photo }?.byteCount
                bytes += seen ?? moment.media.first { $0.relativePath == summary.mainPath }?.byteCount ?? 0
            }
            if options.originals {
                bytes += moment.media.filter { $0.role == .rearSource || $0.role == .frontSource }.reduce(Int64(0)) { $0 + $1.byteCount }
            }
            if options.voiceNotes {
                bytes += moment.voiceNotes.reduce(Int64(0)) { sum, note in
                    sum + ((try? library.store.url(for: note.relativePath)).map(BackupArchive.size) ?? 0)
                }
            }
            return sum + bytes
        }
    }

    private func moments(_ ids: [UUID]) -> [Moment] {
        let wanted = Set(ids)
        let moments = (try? library.context.fetch(FetchDescriptor<Moment>(sortBy: [SortDescriptor(\.capturedAt)]))) ?? []
        return moments.filter { wanted.contains($0.id) }
    }

    private func item(_ moment: Moment, name: String, options: Options) -> Item {
        let summary = MomentSummary(moment)
        let store = library.store
        func url(_ path: String?) -> URL? { path.flatMap { try? store.url(for: $0) } }
        func ext(_ path: String?) -> String { ((path ?? "") as NSString).pathExtension.lowercased() }
        var pictures: [(Item.Source, String, String)] = []
        let isVideo = moment.mediaType == .video
        if options.asSeen {
            if isVideo, let main = url(summary.mainPath), let media = moment.media.first(where: { $0.relativePath == summary.mainPath }) {
                let selfie = moment.media.first { $0.relativePath == summary.selfiePath }
                let pixelSize = CGSize(width: media.pixelWidth, height: media.pixelHeight)
                let timing = VideoTiming(
                    duration: media.duration ?? 0, selfieOffset: selfie?.startOffset ?? 0, hasAudio: media.hasAudio,
                    mainPosition: media.role == .frontSource ? .front : .back,
                    window: selfie == nil ? nil : moment.pipLayout?.windowFrame(in: pixelSize),
                    halves: selfie != nil && moment.pipLayout?.isHalves == true ? moment.captureFormat : nil
                )
                pictures.append((.composedVideo(main: main, selfie: url(summary.selfiePath), timing: timing), "", "mp4"))
            } else if !isVideo {
                let seen = moment.media.first { $0.role == .composedPreview }?.relativePath ?? summary.mainPath
                if let file = url(seen) { pictures.append((.file(file, isVideo: false), "", ext(seen))) }
            }
        }
        if options.originals {
            for media in moment.media where media.role == .rearSource || media.role == .frontSource {
                guard let file = url(media.relativePath) else { continue }
                let suffix = media.role == .rearSource ? " back" : " front"
                pictures.append((.file(file, isVideo: isVideo), suffix, ext(media.relativePath)))
            }
        }
        let voice = options.voiceNotes ? url(moment.voiceNotes.first?.relativePath) : nil
        let location = moment.location
        let place: (Double, Double)? = options.exactPlace ? location.flatMap { location in
            guard let latitude = location.latitude, let longitude = location.longitude else { return nil }
            return (latitude, longitude)
        } : nil
        let zone = TimeZone(identifier: moment.timeZoneID) ?? .current
        let date = moment.capturedAt.formatted(Date.FormatStyle(date: .complete, time: .shortened, timeZone: zone).locale(AppLanguage.shared.locale))
        let placeLine = options.exactPlace ? location?.placeLabel : nil
        var lines = [date]
        // Notes off leaves out all of the person's words: the caption as well as the note (Andrew, 2026-11-19).
        let title = options.notes ? moment.title : nil
        if let title, !title.isEmpty { lines.append(title) }
        if options.notes, let note = moment.note, !note.isEmpty { lines.append(note) }
        if options.voiceNotes, let transcript = moment.voiceNotes.first?.transcript, !transcript.isEmpty { lines.append(transcript) }
        if let placeLine { lines.append(placeLine) }
        if let place { lines.append(String(format: "%.5f, %.5f", place.0, place.1)) }
        let hasText = (title?.isEmpty == false) || (options.notes && moment.note?.isEmpty == false)
        let firstFile = pictures.first.map { "\(name)\($0.1).\($0.2)" } ?? ""
        let row = [
            firstFile,
            moment.capturedAt.formatted(Date.ISO8601FormatStyle(timeZoneSeparator: .colon, timeZone: zone)),
            moment.timeZoneID,
            title ?? "",
            options.notes ? (moment.note ?? "") : "",
            voice == nil ? "" : "\(name) voice.m4a",
            placeLine ?? "",
            place.map { String(format: "%.6f", $0.0) } ?? "",
            place.map { String(format: "%.6f", $0.1) } ?? "",
            moment.isFavorite ? "yes" : "",
        ]
        return Item(
            id: moment.id, name: name, pictures: pictures.map { (source: $0.0, suffix: $0.1, fileExtension: $0.2) }, voice: voice,
            text: options.notes && hasText ? lines.joined(separator: "\n") + "\n" : nil,
            place: place.map { (latitude: $0.0, longitude: $0.1) }, row: row
        )
    }

    /// "2026-10-07 12.00.00": sorts by date and is safe in every file system.
    static func name(_ moment: Moment) -> String {
        let zone = TimeZone(identifier: moment.timeZoneID) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: moment.capturedAt)
        return String(
            format: "%04d-%02d-%02d %02d.%02d.%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0
        )
    }

    // MARK: Writing

    /// Writes every item into `folder`; with `list`, adds `MimoDays moments.csv`. The files, in order.
    nonisolated static func write(
        _ items: [Item], into folder: URL, list: Bool, progress: @Sendable (Double) -> Void = { _ in }
    ) async throws -> [URL] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var written: [URL] = []
        for (index, item) in items.enumerated() {
            try Task.checkCancellation()
            for picture in item.pictures {
                let target = folder.appending(path: "\(item.name)\(picture.suffix).\(picture.fileExtension)")
                switch picture.source {
                case let .file(url, isVideo):
                    if isVideo {
                        try await copyVideo(AVURLAsset(url: url), preset: AVAssetExportPresetPassthrough, composition: nil, to: target, place: item.place)
                    } else {
                        try copyPhoto(url, to: target, place: item.place)
                    }
                case let .composedVideo(main, selfie, timing):
                    let composed = try await VideoComposer.compose(mainURL: main, selfieURL: selfie, timing: timing)
                    try await copyVideo(composed.asset, preset: AVAssetExportPresetHighestQuality, composition: composed.videoComposition, to: target, place: item.place)
                }
                written.append(target)
            }
            if let voice = item.voice {
                let target = folder.appending(path: "\(item.name) voice.\(voice.pathExtension.isEmpty ? "m4a" : voice.pathExtension)")
                try FileManager.default.copyItem(at: voice, to: target)
                written.append(target)
            }
            if let text = item.text {
                let target = folder.appending(path: "\(item.name) note.txt")
                try Data(text.utf8).write(to: target)
                written.append(target)
            }
            progress(Double(index + 1) / Double(max(items.count, 1)))
        }
        if list {
            let target = folder.appending(path: "MimoDays moments.csv")
            try Data(csv([csvHeader] + items.map(\.row)).utf8).write(to: target)
            written.append(target)
        }
        return written
    }

    /// One `.zip` of `folder`, made by the system (any computer opens it).
    nonisolated static func zip(_ folder: URL, as name: String) throws -> URL {
        let target = folder.deletingLastPathComponent().appending(path: name)
        try? FileManager.default.removeItem(at: target)
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) { zipped in
            do { try FileManager.default.copyItem(at: zipped, to: target) } catch { copyError = error }
        }
        if let error = coordinationError ?? copyError { throw error }
        return target
    }

    nonisolated static func csv(_ rows: [[String]]) -> String {
        rows.map { row in
            row.map { field in
                field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) ? "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\"" : field
            }.joined(separator: ",")
        }.joined(separator: "\r\n") + "\r\n"
    }

    /// A lossless copy without its GPS, or with the moment's place written in. A format Image I/O can't write fails
    /// the export rather than leave with the original's GPS.
    nonisolated static func copyPhoto(_ url: URL, to target: URL, place: (latitude: Double, longitude: Double)?) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let type = CGImageSourceGetType(source),
              let destination = CGImageDestinationCreateWithURL(target as CFURL, type, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var options: [CFString: Any] = [kCGImageMetadataShouldExcludeGPS: true]
        if let place {
            // Merging into the source's metadata doesn't reach HEIC files; a full copy with the place added does.
            let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil).flatMap { CGImageMetadataCreateMutableCopy($0) }
                ?? CGImageMetadataCreateMutable()
            let gps: [(CFString, Any)] = [
                (kCGImagePropertyGPSLatitude, abs(place.latitude)), (kCGImagePropertyGPSLatitudeRef, place.latitude >= 0 ? "N" : "S"),
                (kCGImagePropertyGPSLongitude, abs(place.longitude)), (kCGImagePropertyGPSLongitudeRef, place.longitude >= 0 ? "E" : "W"),
            ]
            for (key, value) in gps {
                CGImageMetadataSetValueMatchingImageProperty(metadata, kCGImagePropertyGPSDictionary, key, value as CFTypeRef)
            }
            options = [kCGImageDestinationMetadata: metadata]
        }
        var error: Unmanaged<CFError>?
        guard CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, &error) else {
            throw error?.takeRetainedValue() ?? CocoaError(.fileWriteUnknown)
        }
    }

    /// A video with no metadata but the place, when asked for.
    nonisolated static func copyVideo(
        _ asset: AVAsset, preset: String, composition: AVVideoComposition?, to target: URL, place: (latitude: Double, longitude: Double)?
    ) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { throw CocoaError(.fileWriteUnknown) }
        session.videoComposition = composition
        if let place {
            let item = AVMutableMetadataItem()
            item.identifier = .quickTimeMetadataLocationISO6709
            item.value = MovieExportModel.iso6709(latitude: place.latitude, longitude: place.longitude) as NSString
            item.dataType = kCMMetadataBaseDataType_UTF8 as String
            session.metadata = [item]
        } else {
            session.metadata = []
            session.metadataItemFilter = .forSharing()
        }
        let type: AVFileType = target.pathExtension.lowercased() == "mp4" ? .mp4 : .mov
        try await session.export(to: target, as: type)
    }
}
