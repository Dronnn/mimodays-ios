import Core
import Foundation
import os
import Persistence
import SwiftData

/// The archive's side of backup and restore: what goes into a backup, the record that one was made, and
/// putting a checked backup's records back.
@MainActor
struct BackupService {
    let library: MediaLibrary
    var now: () -> Date = Date.init

    private static let logger = Logger(subsystem: "MimoDays", category: "Backup")

    private var context: ModelContext { library.context }
    private var store: MediaStore { library.store }

    // MARK: Backing up

    /// E03's rows: moments with their notes and voice, the movie projects, the rendered movies.
    struct Contents: Equatable {
        var moments = 0
        var momentBytes: Int64 = 0
        var projectBytes: Int64 = 0
        var renderBytes: Int64 = 0
    }

    func contents() -> Contents {
        var contents = Contents()
        for moment in liveMoments() {
            contents.moments += 1
            contents.momentBytes += moment.media.reduce(Int64(0)) { $0 + $1.byteCount }
                + moment.voiceNotes.reduce(Int64(0)) { $0 + size($1.relativePath) }
        }
        for project in projects() {
            contents.projectBytes += project.audioTracks.reduce(Int64(0)) { $0 + size($1.relativePath) } + 2_000
            contents.renderBytes += project.render.map { size($0.relativePath) } ?? 0
        }
        return contents
    }

    /// The manifest's records and the files to pack (store path -> file). Recently deleted moments stay out.
    /// The manifest, the files to pack, and whether any file a record points to was already gone from this iPhone
    /// (so the backup can't bring it back).
    func plan(includesRenders: Bool) -> (document: BackupDocument, files: [(path: String, url: URL)], missesFiles: Bool) {
        var document = BackupDocument(createdAt: now())
        let records = liveMoments().map(BackupDocument.MomentRecord.init)
        document.moments = records.map { $0.leavingOut { !exists($0) } }
        document.collections = ((try? context.fetch(FetchDescriptor<MomentCollection>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? [])
            .map(BackupDocument.CollectionRecord.init)
        document.movies = projects().map { BackupDocument.MovieRecord($0, includesRender: includesRenders) }
        let hiddenDays = ((try? context.fetch(FetchDescriptor<HiddenDay>())) ?? []).map(\.localDay).sorted()
        document.hiddenDays = hiddenDays.isEmpty ? nil : hiddenDays
        document.formatVersion = document.neededVersion
        let paths = document.moments.flatMap(\.paths) + document.movies.flatMap(\.paths)
        var seen: Set<String> = []
        let files = paths.compactMap { path -> (path: String, url: URL)? in
            guard seen.insert(path).inserted, let url = try? store.url(for: path), FileManager.default.fileExists(atPath: url.path) else { return nil }
            return (path, url)
        }
        let missesFiles = (records.flatMap(\.paths) + document.movies.flatMap(\.paths)).contains { !exists($0) }
        return (document, files, missesFiles)
    }

    private func exists(_ relativePath: String) -> Bool {
        guard let url = try? store.url(for: relativePath) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Remembers a finished backup, for E06's "Last backup" and the moments made since.
    func record(_ document: BackupDocument) {
        context.insert(BackupManifest(
            archiveID: document.archiveID, formatVersion: document.formatVersion, createdAt: document.createdAt,
            checksums: document.files.mapValues(\.sha256), entityCounts: Self.counts(document)
        ))
        try? context.save()
    }

    /// E06: when the last backup was made, and how many moments came after it.
    func status() -> (last: Date?, newSince: Int) {
        let backups = (try? context.fetch(FetchDescriptor<BackupManifest>(predicate: #Predicate { $0.restoredAt == nil }))) ?? []
        let moments = liveMoments()
        guard let last = backups.max(by: { $0.createdAt < $1.createdAt }) else { return (nil, moments.count) }
        // By what the last backup holds, not by date: a moment recovered from Recently deleted afterwards is older
        // than the backup and still not in it.
        let files = Set(last.checksums.keys)
        return (last.createdAt, moments.count { moment in !moment.media.contains { files.contains($0.relativePath) } })
    }

    // MARK: Restoring

    enum Mode: Hashable {
        /// Moments already here are left as they are.
        case addMissing
        /// This iPhone ends up holding exactly what the backup does.
        case replaceEverything
    }

    /// E07: what's in the backup and how much of it is already here.
    struct Summary: Equatable {
        var createdAt: Date
        var moments: Int
        var collections: Int
        var projects: Int
        var alreadyHere: Int
        var isClean: Bool
        /// Moments none of whose files is damaged: what Replace everything would bring.
        var restorable: Int
        /// Movies, collections or collection places the backup has and this iPhone doesn't.
        var addsMore = false
        var new: Int { moments - alreadyHere }
    }

    func summary(_ check: BackupArchive.Check) -> Summary {
        let here = existingMomentIDs()
        let document = check.document
        let projectsHere = existingProjectIDs()
        let collectionsHere = Dictionary(
            ((try? context.fetch(FetchDescriptor<MomentCollection>())) ?? []).map { ($0.id, Set($0.memberships.compactMap { $0.moment?.id })) },
            uniquingKeysWith: { first, _ in first }
        )
        let addsMore = document.movies.contains { !projectsHere.contains($0.id) } || document.collections.contains { record in
            guard let members = collectionsHere[record.id] else { return true }
            return record.members.contains { !members.contains($0.momentID) && here.contains($0.momentID) }
        }
        // A record with no picture is no moment: it isn't counted, so Add doesn't offer it.
        let moments = document.moments.filter(\.hasContent)
        return Summary(
            createdAt: document.createdAt, moments: moments.count, collections: document.collections.count,
            projects: document.movies.count, alreadyHere: moments.count { here.contains($0.id) }, isClean: check.damaged.isEmpty,
            restorable: moments.count { !$0.paths.contains(where: check.damaged.contains) }, addsMore: addsMore
        )
    }

    /// The files a restore unpacks: those of the moments and projects it adds, left out the damaged ones.
    func files(for check: BackupArchive.Check, mode: Mode) -> Set<String> {
        let here = mode == .addMissing ? existingMomentIDs() : []
        let projectsHere = mode == .addMissing ? existingProjectIDs() : []
        let moments = check.document.moments.filter { $0.hasContent && !here.contains($0.id) }.flatMap(\.paths)
        let projects = check.document.movies.filter { !projectsHere.contains($0.id) }.flatMap(\.paths)
        return Set(moments + projects).subtracting(check.damaged)
    }

    func bytes(of paths: Set<String>, in document: BackupDocument) -> Int64 {
        paths.reduce(Int64(0)) { $0 + (document.files[$1]?.bytes ?? 0) }
    }

    /// E08: how it went.
    struct Outcome: Equatable {
        var restored: Int
        var wanted: Int
        var damagedFiles: Int
        var alreadyHere: Int
        /// When the moments left out were taken, so the person knows which.
        var skipped: [Date] = []
    }

    /// Puts the records back, their files moved in from `unpacked` (backup path -> unpacked file). A moment
    /// any of whose files is damaged is skipped whole; links to it are dropped.
    func restore(_ check: BackupArchive.Check, mode: Mode, unpacked: [String: URL]) throws -> Outcome {
        let document = check.document
        // Replacing: what is here goes in the same save as the backup comes in, so a failed save keeps it all; its
        // files go only after that save. Until then the fetches below leave it out.
        let replacing = mode == .replaceEverything
        // Replacing still keeps the moments here whose copy in the backup is damaged or has no picture: better this
        // iPhone's than none.
        let here = replacing
            ? existingMomentIDs().intersection(
                document.moments.filter { !$0.hasContent || $0.paths.contains(where: check.damaged.contains) }.map(\.id)
            )
            : existingMomentIDs()
        let projectsHere = replacing ? [] : existingProjectIDs()
        // A movie here whose soundtrack the backup can't bring: replacing would lose the only good copy.
        if replacing {
            let local = existingProjectIDs()
            if document.movies.contains(where: { local.contains($0.id) && $0.audioTracks.contains { check.damaged.contains($0.path) } }) {
                throw BackupArchive.Failure.unreadable
            }
        }
        var paths: [String: String] = [:]
        var stored: [String] = []
        // A file that can't come in (no space, unreadable): replacing then keeps what is here instead.
        var moveFailed = false
        func move(_ path: String) -> Bool {
            if paths[path] != nil { return true }
            guard let file = unpacked[path] else {
                moveFailed = true
                return false
            }
            let area: MediaStore.Area = path.hasPrefix(MediaStore.Area.derived.rawValue + "/") ? .derived : .originals
            guard let new = try? store.store(moving: file, in: area) else {
                moveFailed = true
                return false
            }
            paths[path] = new.relativePath
            stored.append(new.relativePath)
            return true
        }

        // Files first: nothing in the library changes until every file that should come in is here, so a
        // replacement that can't bring one in leaves the library untouched (no records to roll back).
        // A moment comes in whole or not at all: none of its files move unless all of them were unpacked.
        for record in document.moments where record.hasContent && !here.contains(record.id) && !record.paths.contains(where: check.damaged.contains) {
            if record.paths.allSatisfy({ unpacked[$0] != nil }) {
                for path in record.paths { _ = move(path) }
            } else {
                moveFailed = true
            }
        }
        for record in document.movies where !projectsHere.contains(record.id) {
            if let render = record.render, !check.damaged.contains(render.relativePath) { _ = move(render.relativePath) }
            for track in record.audioTracks where !check.damaged.contains(track.path) { _ = move(track.path) }
        }
        if replacing, moveFailed {
            for path in stored { try? store.remove(path) }
            throw BackupArchive.Failure.unreadable
        }
        var oldFiles: Set<String> = []
        var kept: [UUID: Moment] = [:]
        do {
            if replacing { (oldFiles, kept) = try removeEverything(keeping: here) }
        } catch {
            for path in stored { try? store.remove(path) }
            throw error
        }

        // P8.3: replacing restores every hidden day; adding brings one only for a day that had no moments here, so
        // a choice made on this iPhone stays.
        let daysHere = replacing ? [] : Set(((try? context.fetch(FetchDescriptor<Moment>())) ?? []).map(\.localDay))
        let rulesHere = replacing ? [] : Set(((try? context.fetch(FetchDescriptor<HiddenDay>())) ?? []).map(\.localDay))
        for day in Set(document.hiddenDays ?? []) where !daysHere.contains(day) && !rulesHere.contains(day) {
            context.insert(HiddenDay(localDay: day))
        }

        var wanted = 0
        var restored = 0
        var damagedFiles = 0
        var skipped: [Date] = []
        var moments: [UUID: Moment] = [:]
        // A record with no picture is no moment: not counted, not brought in.
        for record in document.moments where record.hasContent && !here.contains(record.id) {
            wanted += 1
            let damaged = record.paths.filter { check.damaged.contains($0) }
            damagedFiles += damaged.count
            // Its files came in above, all of them, or none did.
            guard damaged.isEmpty, record.paths.allSatisfy({ paths[$0] != nil }) else {
                skipped.append(record.capturedAt)
                continue
            }
            let moment = record.moment(paths: paths)
            context.insert(moment)
            moments[record.id] = moment
            restored += 1
        }
        let present = replacing ? moments.merging(kept) { new, _ in new } : try existingMoments(adding: moments)

        let collections = replacing ? [:] : Dictionary(((try? context.fetch(FetchDescriptor<MomentCollection>())) ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for record in document.collections {
            let collection = collections[record.id] ?? {
                let new = MomentCollection(id: record.id, title: record.title, sortOrder: record.sortOrder, createdAt: record.createdAt)
                new.coverMomentID = record.coverMomentID
                context.insert(new)
                return new
            }()
            var members = Set(collection.memberships.compactMap { $0.moment?.id })
            // Once each: a manifest listing a moment twice would give the collection two rows for it.
            for member in record.members where members.insert(member.momentID).inserted {
                guard let moment = present[member.momentID] else { continue }
                context.insert(CollectionMembership(collection: collection, moment: moment, position: member.position, addedAt: member.addedAt))
            }
        }

        for record in document.movies where !projectsHere.contains(record.id) {
            // A render or soundtrack that can't come back is damage too, even though the movie does.
            damagedFiles += record.paths.count(where: check.damaged.contains)
            let project = MovieProject(
                id: record.id, title: record.title, sourceRule: record.sourceRule,
                aspectRatio: MovieAspectRatio(rawValue: record.aspectRatio) ?? .portrait9x16,
                length: MovieLength(rawValue: record.length) ?? .short, createdAt: record.createdAt
            )
            project.style = record.style
            project.customLength = record.customLength
            project.fitRaw = record.fit
            project.showsDates = record.showsDates
            project.showsPlaces = record.showsPlaces
            project.showsTitle = record.showsTitle
            project.clipSoundLevel = record.clipSoundLevel
            project.voiceNoteLevel = record.voiceNoteLevel
            project.selectionSeed = record.selectionSeed
            project.updatedAt = record.updatedAt
            if var render = record.render, !check.damaged.contains(render.relativePath), move(render.relativePath), let path = paths[render.relativePath] {
                render.relativePath = path
                project.render = render
                project.statusRaw = record.status
            } else {
                project.statusRaw = MovieStatus.draft.rawValue
            }
            context.insert(project)
            for clip in record.clips {
                guard let moment = present[clip.momentID] else { continue }
                let new = MovieClip(project: project, moment: moment, position: clip.position)
                new.trimStart = clip.trimStart
                new.trimEnd = clip.trimEnd
                new.crop = clip.crop
                new.selfiePlacementRaw = clip.selfiePlacement
                new.transitionRaw = clip.transition
                new.clipAudioRaw = clip.clipAudio
                new.clipVolume = clip.clipVolume
                new.includesVoiceNote = clip.includesVoiceNote
                new.cameraLayoutRaw = clip.cameraLayout
                new.pipFrame = clip.pipFrame
                new.atmosphere = clip.atmosphere
                context.insert(new)
            }
            for card in record.textCards ?? [] {
                let new = MovieTextCard(id: card.id, project: project, position: card.position, text: card.text, duration: card.duration)
                new.lookRaw = card.look
                new.transitionRaw = card.transition
                new.atmosphere = card.atmosphere
                new.voiceNoteID = card.voiceNoteID
                context.insert(new)
            }
            for track in record.audioTracks {
                guard !check.damaged.contains(track.path), move(track.path), let path = paths[track.path] else { continue }
                let new = MovieAudioTrack(id: track.id, kind: AudioTrackKind(rawValue: track.kind) ?? .soundtrack, relativePath: path, startOffset: track.startOffset, gain: track.gain)
                new.name = track.name
                new.gainEnvelope = track.gainEnvelope
                new.project = project
                context.insert(new)
            }
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            for path in stored { try? store.remove(path) }
            throw error
        }
        for path in oldFiles {
            do { try store.remove(path) } catch { Self.logger.error("Removing a file failed: \(error.localizedDescription, privacy: .public)") }
            try? store.remove(LoopPreviews.path(for: path))
        }
        let manifest = BackupManifest(
            archiveID: document.archiveID, formatVersion: document.formatVersion, createdAt: document.createdAt,
            checksums: document.files.mapValues(\.sha256), entityCounts: Self.counts(document)
        )
        manifest.restoredAt = now()
        context.insert(manifest)
        try? context.save()
        return Outcome(
            restored: restored, wanted: wanted, damagedFiles: damagedFiles, alreadyHere: document.moments.count(where: \.hasContent) - wanted, skipped: skipped.sorted()
        )
    }

    // MARK: Private

    /// Everything goes before a backup replaces it: moments (Recently deleted too), collections, movies, and
    /// their files.
    /// Marks every record for deletion, unsaved; their files, to remove once the restore has saved.
    private func removeEverything(keeping: Set<UUID>) throws -> (files: Set<String>, kept: [UUID: Moment]) {
        // All read before anything is marked: a failed read leaves the library as it is.
        let all = try context.fetch(FetchDescriptor<Moment>())
        let kept = Dictionary(all.filter { keeping.contains($0.id) }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let moments = all.filter { !keeping.contains($0.id) }
        let projects = try context.fetch(FetchDescriptor<MovieProject>())
        let collections = try context.fetch(FetchDescriptor<MomentCollection>())
        let paths = moments.flatMap { $0.media.map(\.relativePath) + $0.voiceNotes.map(\.relativePath) }
            + projects.flatMap { $0.audioTracks.map(\.relativePath) + ($0.render.map { [$0.relativePath] } ?? []) }
        let hiddenDays = try context.fetch(FetchDescriptor<HiddenDay>())
        for project in projects { context.delete(project) }
        for collection in collections { context.delete(collection) }
        for day in hiddenDays { context.delete(day) }
        for moment in moments { context.delete(moment) }
        return (Set(paths), kept)
    }

    private func liveMoments() -> [Moment] {
        let moments = (try? context.fetch(FetchDescriptor<Moment>(predicate: #Predicate { $0.deletedAt == nil }, sortBy: [SortDescriptor(\.capturedAt)]))) ?? []
        return moments.filter { $0.status == .ready }
    }

    private func projects() -> [MovieProject] {
        (try? context.fetch(FetchDescriptor<MovieProject>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    private func existingMomentIDs() -> Set<UUID> {
        Set(((try? context.fetch(FetchDescriptor<Moment>())) ?? []).map(\.id))
    }

    private func existingProjectIDs() -> Set<UUID> {
        Set(projects().map(\.id))
    }

    private func existingMoments(adding new: [UUID: Moment]) throws -> [UUID: Moment] {
        var all = Dictionary(((try? context.fetch(FetchDescriptor<Moment>())) ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        all.merge(new) { _, new in new }
        return all
    }

    private func size(_ relativePath: String) -> Int64 {
        guard let url = try? store.url(for: relativePath) else { return 0 }
        return BackupArchive.size(url)
    }

    private static func counts(_ document: BackupDocument) -> [String: Int] {
        [
            "moments": document.moments.count, "collections": document.collections.count, "movieProjects": document.movies.count,
            "files": document.files.count,
        ]
    }
}
