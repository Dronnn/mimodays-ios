import AVFoundation
import Core
import ImageIO

/// Never hand on empty or corrupt media (doc 01). The main file must be readable; an unreadable selfie file is
/// dropped and the moment kept without it. Everything of a rejected capture is deleted.
enum MediaCheck {
    static func checked(_ photo: CapturedPhoto) -> CapturedPhoto? {
        guard isReadableImage(photo.mainURL) else {
            remove([photo.mainURL, photo.selfieURL])
            return nil
        }
        var photo = photo
        if let selfie = photo.selfieURL, !isReadableImage(selfie) {
            remove([selfie])
            photo.selfieURL = nil
        }
        return photo
    }

    static func checked(_ video: CapturedVideo) async -> CapturedVideo? {
        guard await isPlayableVideo(video.mainURL) else {
            remove([video.mainURL, video.selfieURL])
            return nil
        }
        var video = video
        if let selfie = video.selfieURL, !(await isPlayableVideo(selfie)) {
            remove([selfie])
            video.selfieURL = nil
            video.selfieOffset = 0
        }
        return video
    }

    static func isReadableImage(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return false }
        return (properties[kCGImagePropertyPixelWidth] as? Int ?? 0) > 0 && (properties[kCGImagePropertyPixelHeight] as? Int ?? 0) > 0
    }

    static func isPlayableVideo(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let (playable, duration) = try? await asset.load(.isPlayable, .duration),
              let tracks = try? await asset.loadTracks(withMediaType: .video) else { return false }
        return playable && duration.seconds > 0 && !tracks.isEmpty
    }

    private static func remove(_ urls: [URL?]) {
        urls.compactMap(\.self).forEach { try? FileManager.default.removeItem(at: $0) }
    }
}
