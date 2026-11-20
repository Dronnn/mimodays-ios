import Core
import Foundation
import Observation
import Persistence
import SwiftData

/// E09: what MimoDays keeps on this iPhone, by kind, and the files it can let go of.
@MainActor
@Observable
final class StorageModel {
    struct Usage: Equatable {
        /// Photos, videos and selfie windows of the moments in the archive, with their previews.
        var moments: Int64 = 0
        /// Rendered movie files - each can be made again from its project.
        var movies: Int64 = 0
        var voiceNotes: Int64 = 0
        /// Files made on the way that nothing keeps: the store's cache and the app's temporary folder.
        var temporary: Int64 = 0
        /// Moments in Recently deleted, still on this iPhone until they're gone for good.
        var recentlyDeleted: Int64 = 0
        /// Music picked for movies.
        var soundtracks: Int64 = 0

        var total: Int64 { moments + movies + voiceNotes + temporary + recentlyDeleted + soundtracks }
    }

    private(set) var usage = Usage()
    private(set) var deletedCount = 0
    private(set) var deletedBytes: Int64 = 0
    private(set) var lastBackup: Date?

    let library: MediaLibrary
    private let temporaryDirectory: URL

    init(library: MediaLibrary, temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        self.library = library
        self.temporaryDirectory = temporaryDirectory
        load()
    }

    func load() {
        let moments = (try? library.context.fetch(FetchDescriptor<Moment>())) ?? []
        var usage = Usage()
        var deletedBytes: Int64 = 0
        var deletedCount = 0
        for moment in moments {
            let media = moment.media.reduce(Int64(0)) { $0 + $1.byteCount }
            let voice = moment.voiceNotes.reduce(Int64(0)) { $0 + size(of: $1.relativePath) }
            if moment.deletedAt == nil {
                usage.moments += media
                usage.voiceNotes += voice
            } else {
                deletedCount += 1
                deletedBytes += media + voice
            }
        }
        usage.recentlyDeleted = deletedBytes
        let projects = (try? library.context.fetch(FetchDescriptor<MovieProject>())) ?? []
        usage.movies = projects.reduce(Int64(0)) { sum, project in sum + (project.render.map { size(of: $0.relativePath) } ?? 0) }
        // A track shared by two projects is one file.
        usage.soundtracks = Set(projects.flatMap { $0.audioTracks.map(\.relativePath) }).reduce(Int64(0)) { $0 + size(of: $1) }
        usage.temporary = ((try? library.store.usage()[.cache]) ?? 0) + temporaryFiles().reduce(Int64(0)) { $0 + Self.allocated($1) }
        self.usage = usage
        self.deletedCount = deletedCount
        self.deletedBytes = deletedBytes
        let backups = (try? library.context.fetch(FetchDescriptor<BackupManifest>(predicate: #Predicate { $0.restoredAt == nil }))) ?? []
        lastBackup = backups.map(\.createdAt).max()
    }

    /// Clear temporary files: the cache and the temporary folder. Never originals, previews or movies.
    func clearTemporary() {
        try? library.store.clearCache()
        for url in temporaryFiles() { try? FileManager.default.removeItem(at: url) }
        Task { [thumbnails = library.thumbnails] in await thumbnails.removeAll() }
        load()
    }

    /// The temporary folder's items, leaving out the media store when it lives there (UI tests).
    private func temporaryFiles() -> [URL] {
        let root = library.store.root.standardizedFileURL.path
        let items = (try? FileManager.default.contentsOfDirectory(at: temporaryDirectory, includingPropertiesForKeys: nil)) ?? []
        return items.filter { item in
            let path = item.standardizedFileURL.path
            return root != path && !root.hasPrefix(path + "/")
        }
    }

    private func size(of relativePath: String) -> Int64 {
        guard let url = try? library.store.url(for: relativePath) else { return 0 }
        return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    /// A file's size, or everything inside a folder.
    private static func allocated(_ url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        if let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true { return Int64(values.fileSize ?? 0) }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            if let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true { total += Int64(values.fileSize ?? 0) }
        }
        return total
    }
}
