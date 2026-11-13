@preconcurrency import AVFoundation
import Core
import CoreImage

/// What a saved video needs besides its files to be played back composed, also after a relaunch.
struct VideoTiming: Codable, Equatable, Sendable {
    var duration: TimeInterval
    /// How much later the selfie stream started than the main one (negative: earlier).
    var selfieOffset: TimeInterval
    var hasAudio: Bool
    var mainPosition: CameraPosition
    /// Where the selfie window was when recording started; nil without a selfie stream.
    var window: SelfieWindowFrame?
}

/// Plays (and later exports) the two streams as one: the main video with the selfie video in the signature
/// window, offset by the recorded start difference, main audio only.
enum VideoComposer {
    enum Failure: Error {
        case noVideo
        case compositionFailed
    }

    struct Composed: @unchecked Sendable {
        let asset: AVComposition
        let videoComposition: AVVideoComposition?

        @MainActor func playerItem() -> AVPlayerItem {
            let item = AVPlayerItem(asset: asset)
            item.videoComposition = videoComposition
            return item
        }
    }

    static func compose(mainURL: URL, selfieURL: URL?, timing: VideoTiming) async throws -> Composed {
        let composition = AVMutableComposition()
        let main = AVURLAsset(url: mainURL)
        guard let mainVideo = try await main.loadTracks(withMediaType: .video).first else { throw Failure.noVideo }
        let range = CMTimeRange(start: .zero, duration: try await main.load(.duration))
        guard let mainTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw Failure.compositionFailed
        }
        try mainTrack.insertTimeRange(range, of: mainVideo, at: .zero)
        let mainTransform = try await mainVideo.load(.preferredTransform)
        mainTrack.preferredTransform = mainTransform

        if timing.hasAudio, let audio = try await main.loadTracks(withMediaType: .audio).first,
           let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try audioTrack.insertTimeRange(range, of: audio, at: .zero)
        }

        guard let selfieURL, let window = timing.window else {
            return Composed(asset: composition, videoComposition: nil)
        }
        let selfie = AVURLAsset(url: selfieURL)
        guard let selfieVideo = try await selfie.loadTracks(withMediaType: .video).first,
              let selfieTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw Failure.noVideo
        }
        let selfieRange = try await selfieVideo.load(.timeRange)
        if let (source, start) = placement(selfie: selfieRange.duration, offset: timing.selfieOffset, main: range.duration) {
            try selfieTrack.insertTimeRange(source, of: selfieVideo, at: start)
        }

        let naturalSize = try await mainVideo.load(.naturalSize)
        let upright = naturalSize.applying(mainTransform)
        let renderSize = CGSize(width: abs(upright.width), height: abs(upright.height))
        let instruction = SelfieWindowInstruction(
            timeRange: range, mainTrackID: mainTrack.trackID, selfieTrackID: selfieTrack.trackID,
            mainOrientation: .init(mainTransform), selfieOrientation: .init(try await selfieVideo.load(.preferredTransform)),
            art: SelfieWindowArt(window: window, canvas: renderSize)
        )
        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = SelfieWindowCompositor.self
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [instruction]
        return Composed(asset: composition, videoComposition: videoComposition)
    }

    /// Which part of the selfie stream goes where on the main timeline: a later start is inserted later,
    /// an earlier one is trimmed; nothing runs past the main stream.
    static func placement(selfie: CMTime, offset: TimeInterval, main: CMTime) -> (source: CMTimeRange, at: CMTime)? {
        let shift = CMTime(seconds: offset, preferredTimescale: 600)
        let sourceStart = shift < .zero ? CMTimeMultiply(shift, multiplier: -1) : .zero
        let at = shift < .zero ? .zero : shift
        let length = CMTimeMinimum(CMTimeSubtract(selfie, sourceStart), CMTimeSubtract(main, at))
        guard length > .zero else { return nil }
        return (CMTimeRange(start: sourceStart, duration: length), at)
    }
}

/// Frames come in sensor orientation with the turn in the track transform; Core Image needs it as an orientation.
extension CGImagePropertyOrientation {
    init(_ transform: CGAffineTransform) {
        switch (transform.a.rounded(), transform.b.rounded(), transform.c.rounded(), transform.d.rounded()) {
        case (0, 1, -1, 0): self = .right
        case (0, -1, 1, 0): self = .left
        case (-1, 0, 0, -1): self = .down
        case (-1, 0, 0, 1): self = .upMirrored
        case (1, 0, 0, -1): self = .downMirrored
        case (0, 1, 1, 0): self = .leftMirrored
        case (0, -1, -1, 0): self = .rightMirrored
        default: self = .up
        }
    }
}

final class SelfieWindowInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let mainTrackID: CMPersistentTrackID
    let selfieTrackID: CMPersistentTrackID
    let mainOrientation: CGImagePropertyOrientation
    let selfieOrientation: CGImagePropertyOrientation
    let art: SelfieWindowArt

    init(
        timeRange: CMTimeRange, mainTrackID: CMPersistentTrackID, selfieTrackID: CMPersistentTrackID,
        mainOrientation: CGImagePropertyOrientation, selfieOrientation: CGImagePropertyOrientation, art: SelfieWindowArt
    ) {
        self.timeRange = timeRange
        self.mainTrackID = mainTrackID
        self.selfieTrackID = selfieTrackID
        self.mainOrientation = mainOrientation
        self.selfieOrientation = selfieOrientation
        self.art = art
        requiredSourceTrackIDs = [NSNumber(value: mainTrackID), NSNumber(value: selfieTrackID)]
    }
}

/// Draws each frame with `SelfieWindowArt`, the same pipeline as the composed photo.
final class SelfieWindowCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false])

    let sourcePixelBufferAttributes: [String: any Sendable]? = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]

    func renderContextChanged(_: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? SelfieWindowInstruction,
              let mainBuffer = request.sourceFrame(byTrackID: instruction.mainTrackID),
              let output = request.renderContext.newPixelBuffer() else {
            request.finish(with: VideoComposer.Failure.compositionFailed)
            return
        }
        let main = Self.upright(mainBuffer, instruction.mainOrientation)
        let selfie = request.sourceFrame(byTrackID: instruction.selfieTrackID).map { Self.upright($0, instruction.selfieOrientation) }
        let frame = instruction.art.compose(main: main, selfie: selfie)
        context.render(frame, to: output, bounds: CGRect(origin: .zero, size: instruction.art.canvas), colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        request.finish(withComposedVideoFrame: output)
    }

    private static func upright(_ buffer: CVPixelBuffer, _ orientation: CGImagePropertyOrientation) -> CIImage {
        let image = CIImage(cvPixelBuffer: buffer).oriented(orientation)
        return image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    }
}
