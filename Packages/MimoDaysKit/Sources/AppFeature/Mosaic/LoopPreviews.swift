@preconcurrency import AVFoundation
import Core
import Foundation

/// Small copies of video moments' main streams, for the tiles that play on their own (Andrew, 2026-11-18): a tile is a
/// few hundred points wide, so decoding the full stream for each of eight or twelve tiles wastes the battery. A copy is
/// made the first time a tile asks for it, one at a time, into the store's cache (purgeable, not backed up); a stream
/// that can't be copied plays as it is.
actor LoopPreviews {
    static let shared = LoopPreviews()

    private var making: [String: Task<URL?, Never>] = [:]
    private var failed: Set<String> = []
    private var last: Task<URL?, Never>?

    /// The small copy's place in the store for a stored video (`originals/ab/….mov`).
    static func path(for videoPath: String) -> String {
        let name = ((videoPath as NSString).lastPathComponent as NSString).deletingPathExtension
        return "cache/loops/\(name).mp4"
    }

    /// The small copy of `videoPath`, made now if there is none yet; nil when it can't be made.
    func preview(of videoPath: String, store: MediaStore) async -> URL? {
        let path = Self.path(for: videoPath)
        guard !failed.contains(path), let destination = try? store.url(for: path), let source = try? store.url(for: videoPath) else { return nil }
        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        if let task = making[path] { return await task.value }
        // One copy at a time: several tiles appearing at once don't start several exports.
        let previous = last
        let task = Task<URL?, Never> {
            _ = await previous?.value
            return await Self.make(source, destination)
        }
        making[path] = task
        last = task
        let result = await task.value
        making[path] = nil
        if result == nil { failed.insert(path) }
        return result
    }

    /// The main stream's picture at 960 × 540 at most, without sound.
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
            try FileManager.default.moveItem(at: staging, to: destination)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: staging)
            return nil
        }
    }
}
