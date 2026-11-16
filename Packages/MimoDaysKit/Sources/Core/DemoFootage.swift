import AVFoundation
import QuartzCore
import UIKit

/// Real clips in place of the simulated camera's drawn frames, for the website recordings (debug builds): the
/// previews loop a back and a front clip, a photo is the frame playing at the shutter, a recording the stretch
/// that played while it ran.
public struct DemoFootage: Sendable {
    public let folder: URL
    let back: URL
    let front: URL
    /// When the loops started; previews and captures read their place in the clip from here, so they agree.
    let start: Date

    /// Nil when the folder lacks either clip.
    public init?(folder: URL, back: String = "R02-dog", front: String = "F02-park", start: Date = .now) {
        guard let back = Self.clip(back, in: folder), let front = Self.clip(front, in: folder) else { return nil }
        self.folder = folder
        self.back = back
        self.front = front
        self.start = start
    }

    /// The file called `name` in `folder`, whatever its extension.
    public static func clip(_ name: String, in folder: URL) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.first { $0.deletingPathExtension().lastPathComponent == name }
    }

    /// `seconds` of `source` from `start` (moved back so they fit), as a new temporary file.
    public static func excerpt(of source: URL, from start: Double, seconds: Double) async throws -> URL {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        let length = min(seconds, duration)
        let from = max(0, min(start, duration - length))
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw CaptureError.recordingFailed
        }
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: from, preferredTimescale: 600), duration: CMTime(seconds: length, preferredTimescale: 600)
        )
        let url = try CaptureFiles.temporaryURL("mov")
        try await session.export(to: url, as: .mov)
        return url
    }

    func url(_ position: CameraPosition) -> URL { position == .back ? back : front }

    /// Seconds into a clip `duration` long that play at `date`.
    func offset(duration: Double, at date: Date = .now) -> Double {
        guard duration > 0 else { return 0 }
        return max(0, date.timeIntervalSince(start)).truncatingRemainder(dividingBy: duration)
    }

    func photo(_ position: CameraPosition) async throws -> URL {
        let asset = AVURLAsset(url: url(position))
        let duration = try await asset.load(.duration).seconds
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let (image, _) = try await generator.image(at: CMTime(seconds: offset(duration: duration), preferredTimescale: 600))
        guard let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.85) else { throw CaptureError.photoFailed }
        let file = try CaptureFiles.temporaryURL("jpg")
        try data.write(to: file, options: .atomic)
        return file
    }

    /// What played from `startedAt` for `seconds`.
    func clip(_ position: CameraPosition, from startedAt: Date, seconds: Double) async throws -> URL {
        let duration = try await AVURLAsset(url: url(position)).load(.duration).seconds
        return try await Self.excerpt(of: url(position), from: offset(duration: duration, at: startedAt), seconds: seconds)
    }

    /// A muted, endless loop of the clip, at the place it has reached.
    @MainActor
    func previewLayer(_ position: CameraPosition) -> CALayer {
        let item = AVPlayerItem(url: url(position))
        let player = AVQueuePlayer()
        player.isMuted = true
        let looper = AVPlayerLooper(player: player, templateItem: item)
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        layer.masksToBounds = true
        // The layer keeps the looper alive for as long as it is shown.
        layer.setValue(looper, forKey: "looper")
        let start = start
        Task {
            let duration = (try? await item.asset.load(.duration).seconds) ?? 0
            let seconds = max(0, Date.now.timeIntervalSince(start)).truncatingRemainder(dividingBy: max(duration, 1))
            await player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
            player.play()
        }
        return layer
    }
}
