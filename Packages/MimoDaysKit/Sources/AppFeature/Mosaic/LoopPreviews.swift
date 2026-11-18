@preconcurrency import AVFoundation
import Core
import Foundation

/// Small copies of video moments' main streams, for the tiles that play on their own (Andrew, 2026-11-18): a tile is a
/// few hundred points wide, so decoding the full stream for each of eight or twelve tiles wastes the battery. A copy is
/// made the first time a tile asks for it, one at a time, into the store's cache (not backed up); a stream that can't be
/// copied plays as it is. Nobody waiting any more (the tile scrolled away) cancels its copy; the folder keeps to
/// `limit`, the least recently played going first.
actor LoopPreviews {
    static let shared = LoopPreviews()

    /// The copies' folder stays under this; one copy is a few megabytes.
    static let limit: Int64 = 400 << 20
    static let folder = "cache/loops"

    private var making: [String: Task<URL?, Never>] = [:]
    private var waiting: [String: Set<UUID>] = [:]
    /// Copies that failed, and when: tried again after `retryAfter`.
    private var failed: [String: Date] = [:]
    private let retryAfter: TimeInterval = 300
    private var last: Task<URL?, Never>?
    private var swept = false

    /// The small copy's place in the store for a stored video (`originals/ab/….mov`).
    static func path(for videoPath: String) -> String {
        let name = ((videoPath as NSString).lastPathComponent as NSString).deletingPathExtension
        return "\(folder)/\(name).mp4"
    }

    /// The small copy of `videoPath`, made now if there is none yet; nil when it can't be made, or the caller left.
    func preview(of videoPath: String, store: MediaStore) async -> URL? {
        let path = Self.path(for: videoPath)
        guard let destination = try? store.url(for: path), let source = try? store.url(for: videoPath) else { return nil }
        if !swept { sweep(store) }
        if FileManager.default.fileExists(atPath: destination.path) {
            // Played now: the last to go when the folder is trimmed.
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: destination.path)
            return destination
        }
        if let when = failed[path], Date().timeIntervalSince(when) < retryAfter { return nil }
        let task = making[path] ?? start(path, source: source, destination: destination, store: store)
        let caller = UUID()
        waiting[path, default: []].insert(caller)
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task { await self.leave(path, caller) }
        }
        leave(path, caller)
        return Task.isCancelled ? nil : result
    }

    /// Forgets a copy that doesn't play (damaged), so the tile plays the original and the next ask makes it again.
    func discard(_ videoPath: String, store: MediaStore) {
        try? store.remove(Self.path(for: videoPath))
    }

    private func start(_ path: String, source: URL, destination: URL, store: MediaStore) -> Task<URL?, Never> {
        // One copy at a time: several tiles appearing at once don't start several exports.
        let previous = last
        let task = Task<URL?, Never> {
            _ = await previous?.value
            guard !Task.isCancelled else { return nil }
            let result = await Self.make(source, destination)
            await self.finished(path, result, store: store)
            return result
        }
        making[path] = task
        last = task
        return task
    }

    private func leave(_ path: String, _ caller: UUID) {
        guard waiting[path]?.remove(caller) != nil, waiting[path]?.isEmpty == true else { return }
        waiting[path] = nil
        making[path]?.cancel()
        making[path] = nil
    }

    private func finished(_ path: String, _ result: URL?, store: MediaStore) {
        making[path] = nil
        if result == nil {
            // A cancelled copy isn't a failure; a real one waits before it is tried again.
            if waiting[path]?.isEmpty == false { failed[path] = Date() }
        } else {
            failed[path] = nil
            trim(store)
        }
    }

    /// The main stream's picture at 960 × 540 at most, without sound. Nothing is kept for a video deleted meanwhile.
    private static func make(_ source: URL, _ destination: URL) async -> URL? {
        let folder = destination.deletingLastPathComponent()
        let staging = folder.appendingPathComponent(".\(UUID().uuidString).partial.mp4")
        do {
            let duration = try await AVURLAsset(url: source).load(.duration)
            // The main stream's picture alone is the same as a selfie stream with no offset.
            let picture = try await VideoComposer.selfieStream(source, offset: 0, mainDuration: duration)
            guard let session = AVAssetExportSession(asset: picture, presetName: AVAssetExportPreset960x540) else { return nil }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try await session.export(to: staging, as: .mp4)
            guard !Task.isCancelled, FileManager.default.fileExists(atPath: source.path) else {
                try? FileManager.default.removeItem(at: staging)
                return nil
            }
            try FileManager.default.moveItem(at: staging, to: destination)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: staging)
            return nil
        }
    }

    /// Once per launch: half-written copies from a launch that ended mid-export go.
    private func sweep(_ store: MediaStore) {
        swept = true
        for url in files(store) where url.lastPathComponent.hasSuffix(".partial.mp4") {
            try? FileManager.default.removeItem(at: url)
        }
        trim(store)
    }

    /// The least recently played copies go until the folder is under `limit`.
    private func trim(_ store: MediaStore) {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        var copies = files(store).compactMap { url -> (url: URL, size: Int64, date: Date)? in
            guard let values = try? url.resourceValues(forKeys: keys), !url.lastPathComponent.hasPrefix(".") else { return nil }
            return (url, Int64(values.fileSize ?? 0), values.contentModificationDate ?? .distantPast)
        }
        var total = copies.reduce(Int64(0)) { $0 + $1.size }
        copies.sort { $0.date < $1.date }
        for copy in copies where total > Self.limit {
            try? FileManager.default.removeItem(at: copy.url)
            total -= copy.size
        }
    }

    private func files(_ store: MediaStore) -> [URL] {
        guard let folder = try? store.url(for: Self.folder) else { return [] }
        return (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
    }
}
