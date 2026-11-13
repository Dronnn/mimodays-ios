import Core
import Foundation
import Persistence
import os

/// A capture in review with what was added so far. Written on every change, so if iOS closes the app mid-review
/// the next launch reopens review with it (Andrew, 2026-11-13).
struct ReviewDraft: Codable, Equatable {
    var capture: CaptureResult
    var caption = ""
    var note = ""
    var window: CameraSettings.SelfieWindow
    var promptID: UUID?
    var voice: ReviewVoiceNote?
    var place: ReviewPlace?
    /// A place or "No place" was picked, so a late location fix doesn't fill it in.
    var placeWasChosen = false
}

/// C09/C10: a voice note recorded in review, kept apart from the clip's own sound.
struct ReviewVoiceNote: Codable, Equatable {
    var url: URL
    var duration: TimeInterval
    var recordedAt: Date
    /// Worked out on this iPhone (iOS 26 and later); nil until it is done, or when it can't be.
    var transcript: String?
}

/// One pending review on disk: the capture's files and `draft.json`, in Application Support (tmp can be purged
/// while the app isn't running), excluded from device backups. Cleared after a save or a retake.
struct ReviewDraftStore: Sendable {
    let root: URL
    private static let draftName = "draft.json"

    init(root: URL) {
        self.root = root
    }

    /// Moves the capture's files in (a rename on the same volume) and returns it pointing at them.
    func adopt(_ capture: CaptureResult) throws -> CaptureResult {
        try prepare()
        var moved = capture
        try moved.mapFiles { url in
            let destination = root.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
        return moved
    }

    /// Where a new voice note is recorded, next to the capture.
    func newVoiceURL() throws -> URL {
        try prepare()
        return root.appending(path: "voice-\(UUID().uuidString).m4a")
    }

    func save(_ draft: ReviewDraft) {
        do {
            try prepare()
            try JSONEncoder().encode(draft).write(to: root.appending(path: Self.draftName), options: .atomic)
        } catch {
            Logger(subsystem: "MimoDays", category: "Review").error("Keeping the review draft failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// The pending draft with its files where they are now (the app's container path changes between installs).
    /// Nil when there is none or its main file is gone.
    func load() -> ReviewDraft? {
        guard let data = try? Data(contentsOf: root.appending(path: Self.draftName)),
              var draft = try? JSONDecoder().decode(ReviewDraft.self, from: data) else { return nil }
        try? draft.capture.mapFiles { root.appending(path: $0.lastPathComponent) }
        if let selfie = draft.capture.selfieURL, !FileManager.default.fileExists(atPath: selfie.path) {
            draft.capture.dropSelfie()
        }
        if let voice = draft.voice {
            let url = root.appending(path: voice.url.lastPathComponent)
            draft.voice = FileManager.default.fileExists(atPath: url.path) ? ReviewVoiceNote(
                url: url, duration: voice.duration, recordedAt: voice.recordedAt, transcript: voice.transcript
            ) : nil
        }
        return FileManager.default.fileExists(atPath: draft.capture.mainURL.path) ? draft : nil
    }

    /// Removes the draft and every file with it.
    func clear() {
        try? FileManager.default.removeItem(at: root)
    }

    private func prepare() throws {
        guard !FileManager.default.fileExists(atPath: root.path) else { return }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var url = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}

extension CaptureResult {
    mutating func mapFiles(_ transform: (URL) throws -> URL) throws {
        switch media {
        case var .photo(photo):
            photo.mainURL = try transform(photo.mainURL)
            photo.selfieURL = try photo.selfieURL.map(transform)
            media = .photo(photo)
        case var .video(video):
            video.mainURL = try transform(video.mainURL)
            video.selfieURL = try video.selfieURL.map(transform)
            media = .video(video)
        }
    }

    mutating func dropSelfie() {
        switch media {
        case var .photo(photo):
            photo.selfieURL = nil
            media = .photo(photo)
        case var .video(video):
            video.selfieURL = nil
            video.selfieOffset = 0
            media = .video(video)
        }
        window = nil
    }
}
