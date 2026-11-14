import Core
import Foundation
import OSLog
import Persistence
import SwiftData

/// Movie projects and their rendered files. A project is the edit decisions (which moments, in what order,
/// shape, captions, sound); a render is one file made from it. Losing the file never loses the project.
@MainActor
struct MovieStore {
    let context: ModelContext
    let store: MediaStore
    var now: () -> Date = Date.init
    private let logger = Logger(subsystem: "MimoDays", category: "Movies")

    /// Projects not rendered yet, last edited first (F01's Drafts).
    func drafts() throws -> [MovieProject] {
        try projects().filter { $0.render == nil }.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Rendered movies, newest render first (F01's Movies).
    func movies() throws -> [MovieProject] {
        try projects().filter { $0.render != nil }.sorted { ($0.render?.renderedAt ?? .distantPast) > ($1.render?.renderedAt ?? .distantPast) }
    }

    /// A new draft of these moments, in this order.
    @discardableResult
    func create(
        title: String, source: MovieSourceRule, length: MovieLength, aspectRatio: MovieAspectRatio, fit: MovieFit,
        momentIDs: [UUID], seed: Int = 0
    ) throws -> MovieProject {
        let project = MovieProject(title: title, sourceRule: source, aspectRatio: aspectRatio, length: length, createdAt: now())
        project.fit = fit
        project.selectionSeed = seed
        context.insert(project)
        let moments = try self.moments(momentIDs)
        for (position, id) in momentIDs.enumerated() {
            guard let moment = moments[id] else { continue }
            context.insert(MovieClip(project: project, moment: moment, position: position))
        }
        try save()
        return project
    }

    /// A new draft with the same moments and edits; the render stays with the original.
    @discardableResult
    func duplicate(_ project: MovieProject) throws -> MovieProject {
        let copy = MovieProject(
            title: String(localized: "\(project.title) copy", bundle: .module, comment: "Title of a duplicated movie project"),
            sourceRule: project.sourceRule, aspectRatio: project.aspectRatio, length: project.length, createdAt: now()
        )
        copy.style = project.style
        copy.customLength = project.customLength
        copy.fit = project.fit
        copy.showsDates = project.showsDates
        copy.showsPlaces = project.showsPlaces
        copy.clipSoundLevel = project.clipSoundLevel
        copy.selectionSeed = project.selectionSeed
        context.insert(copy)
        for clip in project.orderedClips {
            guard let moment = clip.moment else { continue }
            let new = MovieClip(project: copy, moment: moment, position: clip.position)
            new.trimStart = clip.trimStart
            new.trimEnd = clip.trimEnd
            new.crop = clip.crop
            new.selfiePlacement = clip.selfiePlacement
            new.transition = clip.transition
            new.clipAudio = clip.clipAudio
            new.clipVolume = clip.clipVolume
            new.includesVoiceNote = clip.includesVoiceNote
            context.insert(new)
        }
        for track in project.audioTracks {
            // The person's audio file is shared: both projects point at it until the last one goes.
            let new = MovieAudioTrack(kind: track.kind, relativePath: track.relativePath, startOffset: track.startOffset, gain: track.gain)
            new.gainEnvelope = track.gainEnvelope
            new.project = copy
            context.insert(new)
        }
        try save()
        return copy
    }

    func rename(_ project: MovieProject, to title: String) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != project.title else { return }
        project.title = title
        project.updatedAt = now()
        try save()
    }

    /// Deletes the project and its rendered file (F15). Copies saved to Photos or Files are not ours to touch.
    func delete(_ project: MovieProject) throws {
        let render = project.render?.relativePath
        let audio = project.audioTracks.map(\.relativePath)
        context.delete(project)
        try save()
        if let render { removeFile(render) }
        let stillUsed = Set(try context.fetch(FetchDescriptor<MovieAudioTrack>()).map(\.relativePath))
        for path in audio where !stillUsed.contains(path) { removeFile(path) }
    }

    /// Keeps a finished render on its project; the one it replaces is deleted.
    func attach(_ render: MovieRender, to project: MovieProject) throws {
        let old = project.render?.relativePath
        project.render = render
        project.status = .rendered
        try save()
        if let old, old != render.relativePath { removeFile(old) }
    }

    /// Projects whose rendered file has gone become drafts again; nothing else about them changes.
    func forgetMissingRenders() throws {
        var changed = false
        for project in try projects() {
            guard let render = project.render, !store.fileExists(render.relativePath) else { continue }
            logger.notice("Rendered movie file is missing; the project stays as a draft")
            project.render = nil
            project.status = .draft
            changed = true
        }
        if changed { try save() }
    }

    /// The clips a movie is made of: in order, without moments deleted since (they're skipped, never padded).
    static func liveClips(of project: MovieProject) -> [MovieClip] {
        project.orderedClips.filter { $0.moment.map { $0.deletedAt == nil } ?? false }
    }

    private func projects() throws -> [MovieProject] {
        try context.fetch(FetchDescriptor<MovieProject>())
    }

    private func moments(_ ids: [UUID]) throws -> [UUID: Moment] {
        let list = Array(Set(ids))
        let found = try context.fetch(FetchDescriptor<Moment>(predicate: #Predicate { list.contains($0.id) && $0.deletedAt == nil }))
        return Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func save() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private func removeFile(_ relativePath: String) {
        do {
            try store.remove(relativePath)
        } catch {
            logger.error("Removing a movie file failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
