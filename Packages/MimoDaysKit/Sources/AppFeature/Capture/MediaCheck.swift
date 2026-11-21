import AVFoundation
import Core
import ImageIO
import OSLog
import UniformTypeIdentifiers

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
        if video.hasAudio { await logSoundStart(video.mainURL) }
        var video = video
        // After a swap the main file is the other camera's: its own length, not the one the engine reported.
        if let duration = try? await AVURLAsset(url: video.mainURL).load(.duration).seconds, duration > 0 { video.duration = duration }
        if let selfie = video.selfieURL, !(await isPlayableVideo(selfie)) {
            remove([selfie])
            video.selfieURL = nil
            video.selfieOffset = 0
        }
        return video
    }

    /// Its size, a small picture that decodes, and for a JPEG its end marker: ImageIO tells the size of a cut-off one
    /// and draws its missing part grey.
    static func isReadableImage(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              CGImageSourceGetType(source) as String? != UTType.jpeg.identifier || endsJPEG(url),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              (properties[kCGImagePropertyPixelWidth] as? Int ?? 0) > 0, (properties[kCGImagePropertyPixelHeight] as? Int ?? 0) > 0
        else { return false }
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 64] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options) != nil
    }

    private static func endsJPEG(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size >= 2 else { return false }
        try? handle.seek(toOffset: size - 2)
        return (try? handle.read(upToCount: 2)) == Data([0xFF, 0xD9])
    }

    /// Playable, with a length, and its first picture decodes.
    static func isPlayableVideo(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let (playable, duration) = try? await asset.load(.isPlayable, .duration), playable, duration.seconds > 0,
              let track = try? await asset.loadTracks(withMediaType: .video).first,
              let reader = try? AVAssetReader(asset: asset) else { return false }
        // Decoded, not passed through: a sample table can list frames that don't decode.
        let output = AVAssetReaderTrackOutput(
            track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        )
        guard reader.canAdd(output) else { return false }
        reader.add(output)
        defer { reader.cancelReading() }
        guard reader.startReading() else { return false }
        while let sample = output.copyNextSampleBuffer() {
            if CMSampleBufferGetImageBuffer(sample) != nil { return true }
        }
        return false
    }

    private static let logger = Logger(subsystem: "MimoDays", category: "Camera")

    /// How long after the picture the sound begins in a recording: the device check reads it in Console.
    private static func logSoundStart(_ url: URL) async {
        let asset = AVURLAsset(url: url)
        guard let picture = try? await asset.loadTracks(withMediaType: .video).first,
              let sound = try? await asset.loadTracks(withMediaType: .audio).first,
              let pictureRange = try? await picture.load(.timeRange), let soundRange = try? await sound.load(.timeRange)
        else {
            logger.error("Recording has no sound track")
            return
        }
        let late = (soundRange.start - pictureRange.start).seconds
        logger.info("Sound begins \(Int(late * 1000), privacy: .public) ms after the picture, lasts \(soundRange.duration.seconds, privacy: .public) of \(pictureRange.duration.seconds, privacy: .public) s")
    }

    private static func remove(_ urls: [URL?]) {
        urls.compactMap(\.self).forEach { try? FileManager.default.removeItem(at: $0) }
    }
}
