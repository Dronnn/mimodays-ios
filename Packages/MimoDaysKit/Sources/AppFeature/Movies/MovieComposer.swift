@preconcurrency import AVFoundation
import Core
import CoreImage
import DesignSystem
import os
import Persistence
import UIKit

/// A movie plan as one playable, exportable asset (11.7): clips back to back on one timeline, every frame drawn
/// by `MovieCompositor` - the picture fitted to the movie's shape, the selfie window placed on the movie's frame,
/// the caption and title, fades. Clip sound, voice notes and music at the project's levels.
enum MovieComposer {
    enum Failure: Error {
        case empty
        case compositionFailed
    }

    struct Composed: @unchecked Sendable {
        let asset: AVComposition
        let videoComposition: AVVideoComposition
        let audioMix: AVAudioMix

        @MainActor func playerItem() -> AVPlayerItem {
            let item = AVPlayerItem(asset: asset)
            item.videoComposition = videoComposition
            item.audioMix = audioMix
            return item
        }
    }

    /// A fade dips through black: this long out of one clip, this long into the next.
    static let fadeSeconds = 0.4
    /// The title shows this long, then fades.
    static let titleSeconds = 2.5
    static let musicFadeSeconds = 1.5
    /// The caption's bottom edge above the frame's, in phone points.
    static let captionBottom: CGFloat = 24
    private static let timescale: CMTimeScale = 600

    static func compose(_ plan: MoviePlan, renderSize: CGSize) async throws -> Composed {
        guard !plan.clips.isEmpty else { throw Failure.empty }
        let composition = AVMutableComposition()
        guard let mainTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let selfieTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let soundTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              let voiceTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw Failure.compositionFailed }

        // Photos run on a blank clip stretched to their length: a track that is only empty edits doesn't export,
        // and an empty stretch at the end doesn't count towards the movie's length.
        let fillerAsset = AVURLAsset(url: try await filler())
        guard let filler = try await fillerAsset.loadTracks(withMediaType: .video).first else { throw Failure.compositionFailed }
        let fillerRange = try await filler.load(.timeRange)

        var instructions: [MovieClipInstruction] = []
        var cursor = CMTime.zero
        for (index, clip) in plan.clips.enumerated() {
            let length = time(clip.duration)
            let range = CMTimeRange(start: cursor, duration: length)
            var video: MovieClipInstruction.Video?
            switch clip.media {
            case .photo:
                // The compositor draws the still; the blank clip's frames are never read.
                try mainTrack.insertTimeRange(fillerRange, of: filler, at: cursor)
                mainTrack.scaleTimeRange(CMTimeRange(start: cursor, duration: fillerRange.duration), toDuration: length)
            case let .video(start, selfieOffset, hasAudio):
                let asset = AVURLAsset(url: clip.mainURL)
                guard let source = try await asset.loadTracks(withMediaType: .video).first else { throw Failure.compositionFailed }
                let sourceRange = CMTimeRange(start: time(start), duration: length)
                // The file's length can run a frame past its video; that last bit is stretched over, not left black.
                let picture = sourceRange.intersection(try await source.load(.timeRange))
                guard picture.duration > .zero else { throw Failure.compositionFailed }
                try mainTrack.insertTimeRange(picture, of: source, at: cursor)
                if picture.duration != length {
                    mainTrack.scaleTimeRange(CMTimeRange(start: cursor, duration: picture.duration), toDuration: length)
                }
                var selfieOrientation = CGImagePropertyOrientation.up
                var selfieTrackID: CMPersistentTrackID?
                // Each asset stays in a local: a track holds its asset weakly, and inserting from a track whose
                // asset has gone fails (-12780).
                let selfieAsset = clip.selfieURL.map { AVURLAsset(url: $0) }
                if let selfieAsset, let selfie = try await selfieAsset.loadTracks(withMediaType: .video).first,
                   let (part, at) = selfiePart(
                       mainStart: start, length: clip.duration, offset: selfieOffset, selfieLength: try await selfie.load(.timeRange).duration.seconds
                   ) {
                    try selfieTrack.insertTimeRange(part, of: selfie, at: cursor + at)
                    selfieOrientation = .init(try await selfie.load(.preferredTransform))
                    selfieTrackID = selfieTrack.trackID
                }
                if hasAudio, clip.soundOn, let audio = try await asset.loadTracks(withMediaType: .audio).first {
                    let available = try await audio.load(.timeRange)
                    let part = sourceRange.intersection(available)
                    if part.duration > .zero { try soundTrack.insertTimeRange(part, of: audio, at: cursor + (part.start - sourceRange.start)) }
                }
                video = .init(
                    mainTrackID: mainTrack.trackID, selfieTrackID: selfieTrackID,
                    mainOrientation: .init(try await source.load(.preferredTransform)), selfieOrientation: selfieOrientation
                )
            }
            let voiceAsset = clip.voiceURL.map { AVURLAsset(url: $0) }
            if let voiceAsset, let voice = try await voiceAsset.loadTracks(withMediaType: .audio).first {
                // A note longer than its clip stops with it.
                let available = try await voice.load(.timeRange)
                try voiceTrack.insertTimeRange(CMTimeRange(start: available.start, duration: CMTimeMinimum(available.duration, length)), of: voice, at: cursor)
            }
            let next = plan.clips.indices.contains(index + 1) ? plan.clips[index + 1] : nil
            instructions.append(MovieClipInstruction(
                timeRange: range, clip: clip, index: index, video: video, canvas: renderSize, fit: plan.fit,
                fadeIn: index > 0 && clip.transition == .fade, fadeOut: next?.transition == .fade, title: index == 0 ? plan.title : nil
            ))
            cursor = cursor + length
        }
        // F09's music: from the start, as long as the movie or the song, fading in and out.
        let musicAsset = plan.music.map { AVURLAsset(url: $0.url) }
        var musicRamp: CMTimeRange?
        if let musicAsset, let song = try await musicAsset.loadTracks(withMediaType: .audio).first,
           let musicTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let available = try await song.load(.timeRange)
            let played = CMTimeRange(start: available.start, duration: CMTimeMinimum(available.duration, cursor))
            try musicTrack.insertTimeRange(played, of: song, at: .zero)
            musicRamp = CMTimeRange(start: .zero, duration: played.duration)
        }
        // Tracks nothing was put in would make players and exporters stumble.
        for track in [selfieTrack, soundTrack, voiceTrack] where track.segments.allSatisfy(\.isEmpty) {
            composition.removeTrack(track)
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = MovieCompositor.self
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = instructions

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = composition.tracks(withMediaType: .audio).map { track in
            let parameters = AVMutableAudioMixInputParameters(track: track)
            switch track.trackID {
            case soundTrack.trackID: parameters.setVolume(Float(plan.clipSoundLevel), at: .zero)
            case voiceTrack.trackID: parameters.setVolume(Float(plan.voiceNoteLevel), at: .zero)
            default:
                guard let ramp = musicRamp, let gain = plan.music?.gain else { break }
                let fade = CMTimeMinimum(time(musicFadeSeconds), CMTimeMultiplyByFloat64(ramp.duration, multiplier: 0.5))
                parameters.setVolumeRamp(fromStartVolume: 0, toEndVolume: Float(gain), timeRange: CMTimeRange(start: .zero, duration: fade))
                parameters.setVolumeRamp(fromStartVolume: Float(gain), toEndVolume: 0, timeRange: CMTimeRange(start: ramp.end - fade, duration: fade))
            }
            return parameters
        }
        return Composed(asset: composition, videoComposition: videoComposition, audioMix: audioMix)
    }

    /// A one-second black 16x16 clip, written once per launch.
    private static func filler() async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "MovieFiller-1.mov")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let scratch = FileManager.default.temporaryDirectory.appending(path: "MovieFiller-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: scratch, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 16, AVVideoHeightKey: 16])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 16, kCVPixelBufferHeightKey as String: 16,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? Failure.compositionFailed }
        writer.startSession(atSourceTime: .zero)
        for second in 0..<2 {
            guard let pool = adaptor.pixelBufferPool else { throw Failure.compositionFailed }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw Failure.compositionFailed }
            CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer), 0, CVPixelBufferGetDataSize(buffer))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(second), timescale: 2))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: 1, timescale: 1))
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? Failure.compositionFailed }
        // Another movie may have written it meanwhile; either copy is the same.
        if (try? FileManager.default.moveItem(at: scratch, to: url)) == nil { try? FileManager.default.removeItem(at: scratch) }
        return url
    }

    private static func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: timescale)
    }

    /// The part of the selfie stream that plays with `length` seconds of the main stream from `mainStart`, and
    /// how far into the clip it begins. Selfie second s is main second s + offset.
    static func selfiePart(mainStart: Double, length: Double, offset: Double, selfieLength: Double) -> (CMTimeRange, CMTime)? {
        let from = max(mainStart - offset, 0)
        let to = min(mainStart + length - offset, selfieLength)
        guard to > from else { return nil }
        return (CMTimeRange(start: time(from), end: time(to)), time(from + offset - mainStart))
    }

    // MARK: Layout

    /// Where the picture goes on the movie frame (top-left origin): Fill covers it and crops, Show all fits inside.
    static func pictureRect(source: CGSize, canvas: CGSize, fit: MovieFit) -> CGRect {
        guard source.width > 0, source.height > 0 else { return CGRect(origin: .zero, size: canvas) }
        let scale = fit == .fill
            ? max(canvas.width / source.width, canvas.height / source.height)
            : min(canvas.width / source.width, canvas.height / source.height)
        let size = CGSize(width: source.width * scale, height: source.height * scale)
        return CGRect(x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2, width: size.width, height: size.height)
    }

    /// The camera's window: 112 pt on a 402 pt wide screen.
    static let defaultWindowScale = SelfieWindowLayout.frame.width / 402
    /// Space between the window or the caption and the frame's edge, as a share of its short side.
    static let marginScale = 20.0 / 402

    /// The selfie window on the movie frame (top-left origin), the same share of the short side as on the camera.
    /// Recorded: where it was on the picture, kept inside the frame. Nil when hidden.
    static func windowRect(window: PiPLayout?, placement: MovieSelfiePlacement?, picture: CGRect, canvas: CGSize) -> CGRect? {
        if placement == .hidden { return nil }
        let short = min(canvas.width, canvas.height)
        let width = CGFloat(window?.scale ?? defaultWindowScale) * short
        let size = CGSize(width: width, height: width * SelfieWindowLayout.frame.height / SelfieWindowLayout.frame.width)
        let margin = short * marginScale
        let maxX = canvas.width - margin - size.width
        let maxY = canvas.height - margin - size.height
        let origin: CGPoint = switch placement {
        case .topRight: CGPoint(x: maxX, y: margin)
        case .topLeft: CGPoint(x: margin, y: margin)
        // F07 offers one bottom spot; bottom left is the caption's.
        case .bottom: CGPoint(x: maxX, y: maxY)
        case .hidden, nil:
            CGPoint(
                x: min(max(picture.minX + CGFloat(window?.centerX ?? 1) * picture.width - size.width / 2, margin), maxX),
                y: min(max(picture.minY + CGFloat(window?.centerY ?? 0) * picture.height - size.height / 2, margin), maxY)
            )
        }
        return CGRect(origin: origin, size: size)
    }
}

/// One clip's stretch of the timeline and everything the compositor needs to draw it.
final class MovieClipInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    struct Video {
        let mainTrackID: CMPersistentTrackID
        /// Nil when this clip's selfie isn't on the timeline.
        let selfieTrackID: CMPersistentTrackID?
        let mainOrientation: CGImagePropertyOrientation
        let selfieOrientation: CGImagePropertyOrientation
    }

    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let clip: MoviePlan.Clip
    let index: Int
    let video: Video?
    let canvas: CGSize
    let fit: MovieFit
    let fadeIn: Bool
    let fadeOut: Bool
    /// The movie's title, on the first clip only.
    let title: String?

    init(
        timeRange: CMTimeRange, clip: MoviePlan.Clip, index: Int, video: Video?, canvas: CGSize, fit: MovieFit,
        fadeIn: Bool, fadeOut: Bool, title: String? = nil
    ) {
        self.title = title
        self.timeRange = timeRange
        self.clip = clip
        self.index = index
        self.video = video
        self.canvas = canvas
        self.fit = fit
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
        requiredSourceTrackIDs = video.map { video in [video.mainTrackID, video.selfieTrackID].compactMap { $0 }.map { NSNumber(value: $0) } }
    }

    /// 0 (black) to 1 at `seconds` into the clip.
    func opacity(at seconds: Double) -> Double {
        let length = timeRange.duration.seconds
        var value = 1.0
        if fadeIn { value = min(value, seconds / MovieComposer.fadeSeconds) }
        if fadeOut { value = min(value, (length - seconds) / MovieComposer.fadeSeconds) }
        return min(max(value, 0), 1)
    }
}

/// Draws every movie frame. What a clip needs beyond its video frames - its photos, window art, caption - is made
/// on its first frame and kept only while it plays, so a long movie never holds them all.
final class MovieCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private struct Look {
        let index: Int
        var picture: CIImage?
        var selfie: CIImage?
        var window: (art: SelfieWindowArt, box: CGRect)??
        let caption: CIImage?
        var title: CIImage?
    }

    private let context = CIContext(options: [.cacheIntermediates: false])
    private let current = OSAllocatedUnfairLock<Look?>(initialState: nil)

    let sourcePixelBufferAttributes: [String: any Sendable]? = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]

    func renderContextChanged(_: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? MovieClipInstruction,
              let output = request.renderContext.newPixelBuffer() else {
            request.finish(with: MovieComposer.Failure.compositionFailed)
            return
        }
        let canvas = instruction.canvas
        let bounds = CGRect(origin: .zero, size: canvas)
        var look = look(for: instruction)
        let seconds = (request.compositionTime - instruction.timeRange.start).seconds

        var picture: CIImage?
        var selfie: CIImage?
        if let video = instruction.video {
            picture = request.sourceFrame(byTrackID: video.mainTrackID).map { Self.upright($0, video.mainOrientation) }
            selfie = video.selfieTrackID.flatMap { request.sourceFrame(byTrackID: $0) }.map { Self.upright($0, video.selfieOrientation) }
        } else {
            picture = look.picture
            selfie = look.selfie
        }

        var frame = CIImage(color: .black).cropped(to: bounds)
        if let picture {
            let rect = MovieComposer.pictureRect(source: picture.extent.size, canvas: canvas, fit: instruction.fit)
            // Photos drift in a little over their seconds, so a still doesn't sit dead (doc 01).
            let zoom = instruction.video == nil ? 1 + 0.04 * seconds / max(instruction.timeRange.duration.seconds, 0.1) : 1
            let placed = picture
                .transformed(by: CGAffineTransform(scaleX: rect.width / picture.extent.width * zoom, y: rect.height / picture.extent.height * zoom))
            let x = rect.midX - placed.extent.width / 2
            let y = canvas.height - rect.midY - placed.extent.height / 2
            frame = placed.transformed(by: CGAffineTransform(translationX: x - placed.extent.minX, y: y - placed.extent.minY))
                .composited(over: frame)
                .cropped(to: bounds)
            if look.window == nil {
                look.window = Self.window(for: instruction, picture: rect)
                current.withLock { [look] in $0 = look }
            }
            if let selfie, let window = look.window ?? nil {
                frame = Self.place(window.art, box: window.box, selfie: selfie, over: frame, canvas: canvas)
            }
        }
        if let caption = look.caption { frame = caption.composited(over: frame) }
        if let title = look.title {
            let shown = min(MovieComposer.titleSeconds, instruction.timeRange.duration.seconds)
            let alpha = min(max((shown - seconds) / MovieComposer.fadeSeconds, 0), 1)
            if alpha > 0 {
                frame = title.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)]).composited(over: frame)
            }
        }
        let opacity = instruction.opacity(at: seconds)
        if opacity < 1 {
            let o = CGFloat(opacity)
            frame = frame.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: o, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: o, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: o, w: 0),
            ])
        }
        context.render(frame.cropped(to: bounds), to: output, bounds: bounds, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        request.finish(withComposedVideoFrame: output)
    }

    /// The clip's look, made on its first frame.
    private func look(for instruction: MovieClipInstruction) -> Look {
        if let look = current.withLock({ $0 }), look.index == instruction.index { return look }
        let clip = instruction.clip
        let canvas = instruction.canvas
        var look = Look(index: instruction.index, caption: clip.caption.flatMap { Self.caption($0, canvas: canvas) })
        look.title = instruction.title.flatMap { Self.title($0, canvas: canvas) }
        if instruction.video == nil {
            // Enough pixels for Fill on any shape and the drift.
            let pixels = Int(max(canvas.width, canvas.height) * 1.5)
            look.picture = ImageDecoding.thumbnailNow(clip.mainURL, maxPixelSize: pixels).map { CIImage(cgImage: $0) }
            look.selfie = clip.selfieURL.flatMap { ImageDecoding.thumbnailNow($0, maxPixelSize: 800) }.map { CIImage(cgImage: $0) }
        }
        current.withLock { [look] in $0 = look }
        return look
    }

    /// The signature window drawn in a box around it, not over the whole frame.
    private static func window(for instruction: MovieClipInstruction, picture: CGRect) -> (art: SelfieWindowArt, box: CGRect)? {
        guard instruction.clip.selfieURL != nil,
              let rect = MovieComposer.windowRect(
                  window: instruction.clip.window, placement: instruction.clip.placement, picture: picture, canvas: instruction.canvas
              ) else { return nil }
        let pad = max(rect.width, rect.height) * 0.4
        let box = rect.insetBy(dx: -pad, dy: -pad).intersection(CGRect(origin: .zero, size: instruction.canvas)).integral
        let art = SelfieWindowArt(window: SelfieWindowFrame(frame: rect.offsetBy(dx: -box.minX, dy: -box.minY), preview: box.size), canvas: box.size)
        return (art, box)
    }

    private static func place(_ art: SelfieWindowArt, box: CGRect, selfie: CIImage, over frame: CIImage, canvas: CGSize) -> CIImage {
        // Core Image counts from the bottom.
        let flipped = CGRect(x: box.minX, y: canvas.height - box.maxY, width: box.width, height: box.height)
        let local = frame.cropped(to: flipped).transformed(by: CGAffineTransform(translationX: -flipped.minX, y: -flipped.minY))
        return art.compose(main: local, selfie: selfie)
            .transformed(by: CGAffineTransform(translationX: flipped.minX, y: flipped.minY))
            .composited(over: frame)
    }

    /// F08/F10 `Editor / Caption`: Patrick Hand 16 in cream on a plum pill at 55%, bottom left - drawn at the
    /// phone's scale (402 pt across the short side).
    private static func caption(_ text: String, canvas: CGSize) -> CIImage? {
        let unit = min(canvas.width, canvas.height) / 402
        let font = TextStyle.dayCaption.ctFont(pointSize: 16 * unit) as UIFont
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: cream])
        let margin = 16 * unit
        let padding = 14 * unit
        let height = 30 * unit
        let textSize = attributed.boundingRect(
            with: CGSize(width: canvas.width - margin * 2 - padding * 2, height: height), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil
        ).size
        let size = CGSize(width: ceil(textSize.width + padding * 2), height: ceil(height))
        let image = renderer(size).image { _ in
            plum.withAlphaComponent(0.55).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2).fill()
            attributed.draw(
                with: CGRect(x: padding, y: (size.height - textSize.height) / 2, width: size.width - padding * 2, height: textSize.height),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil
            )
        }
        guard let cgImage = image.cgImage else { return nil }
        return CIImage(cgImage: cgImage).transformed(by: CGAffineTransform(translationX: margin, y: MovieComposer.captionBottom * unit))
    }

    /// F08 "Title at the start": the movie's name in Fraunces over the first clip, centred, with a soft shadow.
    private static func title(_ text: String, canvas: CGSize) -> CIImage? {
        let unit = min(canvas.width, canvas.height) / 402
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.5)
        shadow.shadowBlurRadius = 12 * unit
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributed = NSAttributedString(string: text, attributes: [
            .font: TextStyle.displayTitle.ctFont(pointSize: 40 * unit) as UIFont, .foregroundColor: cream, .shadow: shadow, .paragraphStyle: paragraph,
        ])
        let width = canvas.width - 48 * unit
        let bounds = attributed.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil)
        let pad = shadow.shadowBlurRadius * 2
        let size = CGSize(width: ceil(width + pad * 2), height: ceil(bounds.height + pad * 2))
        let image = renderer(size).image { _ in
            attributed.draw(with: CGRect(x: pad, y: pad, width: width, height: bounds.height), options: [.usesLineFragmentOrigin], context: nil)
        }
        guard let cgImage = image.cgImage else { return nil }
        return CIImage(cgImage: cgImage)
            .transformed(by: CGAffineTransform(translationX: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2))
    }

    private static let cream = UIColor(red: 0xFB / 255, green: 0xF6 / 255, blue: 0xEF / 255, alpha: 1)
    private static let plum = UIColor(red: 0x2A / 255, green: 0x1B / 255, blue: 0x21 / 255, alpha: 1)

    private static func renderer(_ size: CGSize) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format)
    }

    private static func upright(_ buffer: CVPixelBuffer, _ orientation: CGImagePropertyOrientation) -> CIImage {
        let image = CIImage(cvPixelBuffer: buffer).oriented(orientation)
        return image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    }
}
