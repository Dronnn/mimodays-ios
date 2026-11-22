import AVFoundation
import Synchronization
import os

/// P3.5: makes one camera stream again at a smaller video size.
public protocol VideoTranscoding: Sendable {
    /// Writes `source` at `size` to `destination`, keeping its length, timing, turn, sound and metadata.
    func transcode(_ source: URL, to destination: URL, size: VideoSize) async throws
}

public enum TranscodeError: Error, Equatable {
    case noTargetBitRate
    case noVideo
    case cannotWrite
    case failed
}

/// AVAssetReader into AVAssetWriter: HEVC where it can be written (H.264 otherwise) at the size's width and average bit
/// rate; sound as AAC at the original's channels and rate. Timestamps are copied as they are, so the selfie stream's
/// offset to the main one stays.
public struct AVVideoTranscoder: VideoTranscoding {
    private static let logger = Logger(subsystem: "MimoDays", category: "Storage")

    public init() {}

    public func transcode(_ source: URL, to destination: URL, size: VideoSize) async throws {
        guard let bitRate = size.averageBitRate else { throw TranscodeError.noTargetBitRate }
        let asset = AVURLAsset(url: source)
        guard let video = try await asset.loadTracks(withMediaType: .video).first else { throw TranscodeError.noVideo }
        let audio = try await asset.loadTracks(withMediaType: .audio).first
        let (natural, transform, frameRate) = try await video.load(.naturalSize, .preferredTransform, .nominalFrameRate)
        let scale = min(1, CGFloat(size.maxFormatWidth) / max(natural.width, natural.height, 1))
        func even(_ value: CGFloat) -> Int { max(Int((value * scale / 2).rounded()) * 2, 2) }

        let reader = try AVAssetReader(asset: asset)
        let videoOutput = AVAssetReaderTrackOutput(track: video, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw TranscodeError.failed }
        reader.add(videoOutput)

        try? FileManager.default.removeItem(at: destination)
        let writer = try AVAssetWriter(outputURL: destination, fileType: .mov)
        writer.metadata = try await asset.load(.metadata)
        var settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: even(natural.width),
            AVVideoHeightKey: even(natural.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoExpectedSourceFrameRateKey: frameRate > 0 ? Int(frameRate.rounded()) : 30,
            ],
        ]
        if !writer.canApply(outputSettings: settings, forMediaType: .video) { settings[AVVideoCodecKey] = AVVideoCodecType.h264 }
        guard writer.canApply(outputSettings: settings, forMediaType: .video) else { throw TranscodeError.cannotWrite }
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        // The turn's shift is in the original's pixels: it shrinks with the frame.
        videoInput.transform = CGAffineTransform(
            a: transform.a, b: transform.b, c: transform.c, d: transform.d,
            tx: transform.tx * CGFloat(even(natural.width)) / max(natural.width, 1),
            ty: transform.ty * CGFloat(even(natural.height)) / max(natural.height, 1)
        )
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { throw TranscodeError.cannotWrite }
        writer.add(videoInput)
        var channels = [Channel(output: videoOutput, input: videoInput, label: "video")]

        if let audio, let format = try await audio.load(.formatDescriptions).first,
           let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
            let audioOutput = AVAssetReaderTrackOutput(track: audio, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: max(Int(description.mChannelsPerFrame), 1),
                AVSampleRateKey: description.mSampleRate > 0 ? description.mSampleRate : 44_100,
                AVEncoderBitRateKey: 128_000,
            ]
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput.expectsMediaDataInRealTime = false
            if reader.canAdd(audioOutput), writer.canAdd(audioInput) {
                reader.add(audioOutput)
                writer.add(audioInput)
                channels.append(Channel(output: audioOutput, input: audioInput, label: "audio"))
            }
        }

        guard reader.startReading(), writer.startWriting() else {
            Self.logger.error("Transcode could not start: \(reader.error?.localizedDescription ?? writer.error?.localizedDescription ?? "?", privacy: .public)")
            throw TranscodeError.failed
        }
        writer.startSession(atSourceTime: .zero)
        let stop = Mutex(false)
        await withTaskCancellationHandler {
            await withTaskGroup(of: Void.self) { group in
                for channel in channels {
                    group.addTask { await channel.run(stopped: { stop.withLock { $0 } }) }
                }
            }
        } onCancel: {
            stop.withLock { $0 = true }
        }
        let cancelled = stop.withLock { $0 }
        if cancelled || reader.status == .failed {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: destination)
            if cancelled { throw CancellationError() }
            Self.logger.error("Transcode read failed: \(reader.error?.localizedDescription ?? "?", privacy: .public)")
            throw TranscodeError.failed
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            Self.logger.error("Transcode write failed: \(writer.error?.localizedDescription ?? "?", privacy: .public)")
            try? FileManager.default.removeItem(at: destination)
            throw TranscodeError.failed
        }
    }
}

/// One track from the reader into the writer, on its own queue.
private final class Channel: @unchecked Sendable {
    private let output: AVAssetReaderOutput
    private let input: AVAssetWriterInput
    private let queue: DispatchQueue
    /// Touched on `queue` only.
    private var isDone = false

    init(output: AVAssetReaderOutput, input: AVAssetWriterInput, label: String) {
        self.output = output
        self.input = input
        queue = DispatchQueue(label: "MimoDays.transcode.\(label)")
    }

    func run(stopped: @escaping @Sendable () -> Bool) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            input.requestMediaDataWhenReady(on: queue) { [self] in
                guard !isDone else { return }
                while input.isReadyForMoreMediaData {
                    guard !stopped(), let buffer = output.copyNextSampleBuffer(), input.append(buffer) else {
                        isDone = true
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }
                }
            }
        }
    }
}

/// P3.5: whether a smaller copy can stand in for its original: the same length, the same tracks, the same turn.
public enum TranscodeCheck {
    /// Frames line up within this.
    public static let durationTolerance = 0.15

    /// Turns compared without the float noise of a quarter turn; translations scale with the new width.
    static func same(_ first: CGAffineTransform, _ second: CGAffineTransform) -> Bool {
        [first.a - second.a, first.b - second.b, first.c - second.c, first.d - second.d].allSatisfy { abs($0) < 0.001 }
    }

    public static func matches(original: URL, copy: URL, size: VideoSize) async -> Bool {
        let (before, after) = (AVURLAsset(url: original), AVURLAsset(url: copy))
        guard let first = try? await before.load(.duration), let second = try? await after.load(.duration),
              abs(first.seconds - second.seconds) <= durationTolerance,
              let videoBefore = try? await before.loadTracks(withMediaType: .video),
              let videoAfter = try? await after.loadTracks(withMediaType: .video),
              videoBefore.count == videoAfter.count, let trackBefore = videoBefore.first, let trackAfter = videoAfter.first,
              let audioBefore = try? await before.loadTracks(withMediaType: .audio),
              let audioAfter = try? await after.loadTracks(withMediaType: .audio),
              audioBefore.isEmpty == audioAfter.isEmpty,
              let turnBefore = try? await trackBefore.load(.preferredTransform),
              let turnAfter = try? await trackAfter.load(.preferredTransform), same(turnBefore, turnAfter),
              let natural = try? await trackAfter.load(.naturalSize),
              max(natural.width, natural.height) <= CGFloat(size.maxFormatWidth)
        else { return false }
        return true
    }
}
