import Core
import Foundation
import Observation
import os

/// P3.6: one camera stream whose full-size file was moved to the person's folder; MimoDays keeps a Compact copy.
struct MovedOriginal: Codable, Equatable, Sendable {
    var mediaID: UUID
    var momentID: UUID
    /// Inside the folder's "MimoDays Originals".
    var fileName: String
    var checksum: String
    var byteCount: Int64
    var pixelWidth: Int
    var pixelHeight: Int
    var codec: String?
    var movedAt: Date
    /// The folder it went to, for when another folder is picked later (rev-data 2). Only in the app's own list: on
    /// another iPhone the folder's list is read from the folder it is in.
    var folderBookmark: Data?
}

/// P3.6 (Penpot §V3 X06/X07): the folder the person picked and what was moved there. The list is kept in the app and
/// in the folder too ("originals.json"), so originals can be brought back from the folder alone, on another iPhone
/// after a restore. Files are copied and read back before anything leaves the phone.
@MainActor
@Observable
final class OriginalArchive {
    enum ArchiveError: Error, Equatable {
        case noFolder
        case folderUnavailable
        case checksumMismatch
        case notFound
    }

    nonisolated static let subfolder = "MimoDays Originals"
    nonisolated static let manifestName = "originals.json"
    private static let logger = Logger(subsystem: "MimoDays", category: "Storage")

    private(set) var entries: [MovedOriginal] = []
    /// The folder's name, for X03 and X06's Folder row.
    private(set) var folderName: String?
    private let indexURL: URL
    private var bookmark: Data?

    private struct Index: Codable {
        var bookmark: Data?
        var folderName: String?
        var entries: [MovedOriginal]
    }

    init(indexURL: URL) {
        self.indexURL = indexURL
        if let data = try? Data(contentsOf: indexURL), let index = try? JSONDecoder().decode(Index.self, from: data) {
            bookmark = index.bookmark
            folderName = index.folderName
            entries = index.entries
        }
    }

    var hasFolder: Bool { bookmark != nil }

    func moved(_ momentID: UUID) -> [MovedOriginal] { entries.filter { $0.momentID == momentID } }
    func isMoved(mediaID: UUID) -> Bool { entries.contains { $0.mediaID == mediaID } }

    /// X06 Folder › Choose…: the folder from the document picker, kept as a bookmark.
    func setFolder(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        folderName = FileManager.default.displayName(atPath: url.path)
        try save()
    }

    /// The folder `entry` went to, when it isn't the one picked now and can still be found.
    func folder(of entry: MovedOriginal, otherThan current: URL) -> URL? {
        guard let data = entry.folderBookmark else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale),
              url.standardizedFileURL != current.standardizedFileURL else { return nil }
        return url
    }

    /// The picked folder; throws when there is none or its bookmark no longer resolves (a drive unplugged, the folder
    /// gone). The caller wraps its work in the folder's security scope.
    func folder() throws -> URL {
        guard let bookmark else { throw ArchiveError.noFolder }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            throw ArchiveError.folderUnavailable
        }
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            self.bookmark = fresh
            try? save()
        }
        return url
    }

    /// After a moment's streams were swapped for their Compact copies.
    func record(_ moved: [MovedOriginal], in folder: URL) async throws {
        entries.removeAll { entry in moved.contains { $0.mediaID == entry.mediaID } }
        entries.append(contentsOf: moved.map { entry in
            var entry = entry
            entry.folderBookmark = entry.folderBookmark ?? bookmark
            return entry
        })
        try save()
        // The folder may be a slow drive or a cloud: read and written off the main actor (rev-data 3).
        let listed = entries
        try await detachedWork { try Self.writeManifest(listed, in: folder) }
    }

    /// After a moment's originals came back.
    func forget(_ mediaIDs: Set<UUID>, in folder: URL?) async throws {
        entries.removeAll { mediaIDs.contains($0.mediaID) }
        try save()
        let listed = entries
        if let folder { try? await detachedWork { try Self.writeManifest(listed, in: folder) } }
    }

    private func save() throws {
        try FileManager.default.createDirectory(at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(Index(bookmark: bookmark, folderName: folderName, entries: entries)).write(to: indexURL, options: .atomic)
    }

    // MARK: Files, off the main actor

    /// "2026-11-11 12.00.00 main 1A2B3C4D.mov": readable in Files, unique by the stream's id.
    nonisolated static func fileName(capturedAt: Date, selfie: Bool, mediaID: UUID) -> String {
        let format = Date.ISO8601FormatStyle(timeZone: .current).year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: false)
            .timeSeparator(.omitted).dateTimeSeparator(.space)
        let stamp = capturedAt.formatted(format)
        return "\(stamp) \(selfie ? "selfie" : "main") \(mediaID.uuidString.prefix(8)).mov"
    }

    /// Copies `source` into the folder as `name` and reads the copy back: it stays only if its checksum is `checksum`.
    nonisolated static func put(_ source: URL, as name: String, checksum: String, in folder: URL) throws {
        let target = folder.appending(path: subfolder, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let destination = target.appending(path: name)
        let partial = target.appending(path: ".\(name).partial")
        try? FileManager.default.removeItem(at: partial)
        do {
            try FileManager.default.copyItem(at: source, to: partial)
            guard try MediaStore.sha256(of: partial) == checksum else { throw ArchiveError.checksumMismatch }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: partial, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
    }

    /// Copies a moved original back into `scratch` and checks it.
    nonisolated static func fetch(_ entry: MovedOriginal, from folder: URL, into scratch: URL) throws -> URL {
        let source = folder.appending(path: subfolder, directoryHint: .isDirectory).appending(path: entry.fileName)
        guard FileManager.default.fileExists(atPath: source.path) else { throw ArchiveError.notFound }
        let copy = scratch.appending(path: "\(entry.mediaID.uuidString).mov")
        try? FileManager.default.removeItem(at: copy)
        try FileManager.default.copyItem(at: source, to: copy)
        guard try MediaStore.sha256(of: copy) == entry.checksum else {
            try? FileManager.default.removeItem(at: copy)
            throw ArchiveError.checksumMismatch
        }
        return copy
    }

    nonisolated static func remove(_ entry: MovedOriginal, from folder: URL) {
        try? FileManager.default.removeItem(at: folder.appending(path: subfolder, directoryHint: .isDirectory).appending(path: entry.fileName))
    }

    /// The folder's own list, for bringing originals back on another iPhone.
    nonisolated static func manifest(in folder: URL) -> [MovedOriginal] {
        let url = folder.appending(path: subfolder, directoryHint: .isDirectory).appending(path: manifestName)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? Data(contentsOf: url)).flatMap { try? decoder.decode([MovedOriginal].self, from: $0) } ?? []
    }

    /// Merged with what the folder already lists (another iPhone's moves stay).
    nonisolated static func writeManifest(_ entries: [MovedOriginal], in folder: URL) throws {
        let target = folder.appending(path: subfolder, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let ours = Set(entries.map(\.mediaID))
        let theirs = manifest(in: folder).filter { !ours.contains($0.mediaID) && FileManager.default.fileExists(atPath: target.appending(path: $0.fileName).path) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let listed = (theirs + entries).map { entry in
            var entry = entry
            entry.folderBookmark = nil
            return entry
        }
        try encoder.encode(listed.sorted { $0.fileName < $1.fileName }).write(to: target.appending(path: manifestName), options: .atomic)
    }
}
