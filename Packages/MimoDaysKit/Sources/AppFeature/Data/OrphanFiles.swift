import Core
import Foundation
import OSLog
import Persistence
import SwiftData

/// Files in the store's originals and derived areas that no record points to: left by a save, an edit or a deletion
/// that iOS ended between writing the files and saving the records (or the other way round). Run once at launch,
/// before any screen exists, so no save is half-way through.
enum OrphanFiles {
    private static let logger = Logger(subsystem: "MimoDays", category: "Storage")

    /// Every path a record keeps: moments' media (Recently Deleted too), voice notes, movie music and renders.
    @MainActor
    static func referenced(in context: ModelContext) throws -> Set<String> {
        var paths = Set<String>()
        var media = FetchDescriptor<MomentMedia>()
        media.propertiesToFetch = [\.relativePath]
        paths.formUnion(try context.fetch(media).map(\.relativePath))
        var voice = FetchDescriptor<MomentVoiceNote>()
        voice.propertiesToFetch = [\.relativePath]
        paths.formUnion(try context.fetch(voice).map(\.relativePath))
        var music = FetchDescriptor<MovieAudioTrack>()
        music.propertiesToFetch = [\.relativePath]
        paths.formUnion(try context.fetch(music).map(\.relativePath))
        paths.formUnion(try context.fetch(FetchDescriptor<MovieProject>()).compactMap { $0.render?.relativePath })
        return paths
    }

    /// What a backup, an export, an import or a capture put in tmp, left when iOS ended the app before it was handed
    /// on. A capture in review lives in the review draft's own folder, so nothing in tmp's Capture is still needed.
    static func removeScratch(in folder: URL = FileManager.default.temporaryDirectory) {
        let scratch = ["Backup-", "Export-", "Movie-", "MimoDays-"]
        for item in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
            let name = item.lastPathComponent
            // MovieFiller-1.mov is the kept filler clip; MovieFiller-<UUID>.mov is one being made.
            let filler = name.hasPrefix("MovieFiller-") && name != "MovieFiller-1.mov"
            guard name == "Import" || name == "Capture" || filler || scratch.contains(where: name.hasPrefix) else { continue }
            try? FileManager.default.removeItem(at: item)
        }
    }

    /// Removes them; how many went. A failed read of the records removes nothing.
    @MainActor
    @discardableResult
    static func remove(context: ModelContext, store: MediaStore) -> Int {
        // No restore runs at launch: what one unpacked before the app was stopped goes too.
        try? store.removeStaging()
        do {
            let orphans = try store.orphans(referenced: try referenced(in: context))
            // One that won't go doesn't keep the rest.
            for path in orphans {
                do { try store.remove(path) } catch { logger.error("Removing a file no record points to failed: \(error.localizedDescription, privacy: .public)") }
            }
            if !orphans.isEmpty { logger.notice("Removed \(orphans.count) files no record points to") }
            return orphans.count
        } catch {
            logger.error("Looking for files no record points to failed: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }
}
