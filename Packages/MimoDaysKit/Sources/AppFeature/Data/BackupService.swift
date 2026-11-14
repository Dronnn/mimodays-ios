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
    func plan(includesRenders: Bool) -> (document: BackupDocument, files: [(path: String, url: URL)]) {
        var document = BackupDocument(createdAt: now())
        document.moments = liveMoments().map(BackupDocument.MomentRecord.init)
        document.collections = ((try? context.fetch(FetchDescriptor<MomentCollection>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? [])
            .map(BackupDocument.CollectionRecord.init)
        document.movies = projects().map { BackupDocument.MovieRecord($0, includesRender: includesRenders) }
        let paths = document.moments.flatMap(\.paths) + document.movies.flatMap(\.paths)
        var seen: Set<String> = []
        let files = paths.compactMap { path -> (path: String, url: URL)? in
            guard seen.insert(path).inserted, let url = try? store.url(for: path), FileManager.default.fileExists(atPath: url.path) else { return nil }
            return (path, url)
        }
        return (document, files)
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
        let last = backups.map(\.createdAt).max()
        let moments = liveMoments()
        guard let last else { return (nil, moments.count) }
        return (last, moments.count { $0.createdAt > last })
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
        var new: Int { moments - alreadyHere }
    }

    func summary(_ check: BackupArchive.Check) -> Summary {
        let here = existingMomentIDs()
        let document = check.document
        return Summary(
            createdAt: document.createdAt, moments: document.moments.count, collections: document.collections.count,
            projects: document.movies.count, alreadyHere: document.moments.count { here.contains($0.id) }, isClean: check.damaged.isEmpty
        )
    }

    /// The files a restore unpacks: those of the moments and projects it adds, left out the damaged ones.
    func files(for check: BackupArchive.Check, mode: Mode) -> Set<String> {
        let here = mode == .addMissing ? existingMomentIDs() : []
        let projectsHere = mode == .addMissing ? existingProjectIDs() : []
        let moments = check.document.moments.filter { !here.contains($0.id) }.flatMap(\.paths)
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
        if mode == .replaceEverything { try removeEverything() }
        let here = existingMomentIDs()
        var paths: [String: String] = [:]
        var stored: [String] = []
        func move(_ path: String) -> Bool {
            if paths[path] != nil { return true }
            guard let file = unpacked[path] else { return false }
            let area: MediaStore.Area = path.hasPrefix(MediaStore.Area.derived.rawValue + "/") ? .derived : .originals
            guard let new = try? store.store(moving: file, in: area) else { return false }
            paths[path] = new.relativePath
            stored.append(new.relativePath)
            return true
        }

        var wanted = 0
        var restored = 0
        var damagedFiles = 0
        var skipped: [Date] = []
        var moments: [UUID: Moment] = [:]
        for record in document.moments where !here.contains(record.id) {
            wanted += 1
            let damaged = record.paths.filter { check.damaged.contains($0) }
            damagedFiles += damaged.count
            guard damaged.isEmpty, record.paths.allSatisfy(move) else {
                skipped.append(record.capturedAt)
                continue
            }
            let moment = record.moment(paths: paths)
            context.insert(moment)
            moments[record.id] = moment
            restored += 1
        }
        let present = try existingMoments(adding: moments)

        let collections = Dictionary(((try? context.fetch(FetchDescriptor<MomentCollection>())) ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for record in document.collections {
            let collection = collections[record.id] ?? {
                let new = MomentCollection(id: record.id, title: record.title, sortOrder: record.sortOrder, createdAt: record.createdAt)
                new.coverMomentID = record.coverMomentID
                context.insert(new)
                return new
            }()
            let members = Set(collection.memberships.compactMap { $0.moment?.id })
            for member in record.members where !members.contains(member.momentID) {
                guard let moment = present[member.momentID] else { continue }
                context.insert(CollectionMembership(collection: collection, moment: moment, position: member.position, addedAt: member.addedAt))
            }
        }

        let projectsHere = existingProjectIDs()
        for record in document.movies where !projectsHere.contains(record.id) {
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
        let manifest = BackupManifest(
            archiveID: document.archiveID, formatVersion: document.formatVersion, createdAt: document.createdAt,
            checksums: document.files.mapValues(\.sha256), entityCounts: Self.counts(document)
        )
        manifest.restoredAt = now()
        context.insert(manifest)
        try? context.save()
        return Outcome(
            restored: restored, wanted: wanted, damagedFiles: damagedFiles, alreadyHere: document.moments.count - wanted, skipped: skipped.sorted()
        )
    }

    // MARK: Private

    /// Everything goes before a backup replaces it: moments (Recently deleted too), collections, movies, and
    /// their files.
    private func removeEverything() throws {
        let moments = (try? context.fetch(FetchDescriptor<Moment>())) ?? []
        let projects = (try? context.fetch(FetchDescriptor<MovieProject>())) ?? []
        let paths = moments.flatMap { $0.media.map(\.relativePath) + $0.voiceNotes.map(\.relativePath) }
            + projects.flatMap { $0.audioTracks.map(\.relativePath) + ($0.render.map { [$0.relativePath] } ?? []) }
        for project in projects { context.delete(project) }
        for collection in (try? context.fetch(FetchDescriptor<MomentCollection>())) ?? [] { context.delete(collection) }
        for moment in moments { context.delete(moment) }
        try context.save()
        for path in Set(paths) {
            do { try store.remove(path) } catch { Self.logger.error("Removing a file failed: \(error.localizedDescription, privacy: .public)") }
        }
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
