import AVFoundation
@testable import Core
import Foundation
import Testing

/// P3.5: a smaller copy keeps the length, the turn, the sound and the timing, at the new size's width.
struct VideoTranscoderTests {
    /// A 1920×1080 clip turned to portrait, at a high bit rate, with a tone: what an older 1080p take looks like.
    static func takeLikeClip(seconds: Double = 2, withSound: Bool = true) async throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "TranscodeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let silent = folder.appending(path: "video.mov")
        let writer = try AVAssetWriter(outputURL: silent, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 1920, AVVideoHeightKey: 1080,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 20_000_000],
        ])
        // As the camera writes portrait: a quarter turn, shifted back into view by the frame's height.
        input.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 1920, kCVPixelBufferHeightKey as String: 1080,
        ])
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        let fps: Int32 = 30
        // Noise made once, shifted every frame, so the encoder needs the bit rate.
        let rowBytes = 1920 * 4
        let noise = (0..<(rowBytes * 1080 + 4096)).map { _ in UInt8.random(in: 0...255) }
        for frame in 0..<Int32(seconds * Double(fps)) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, try #require(adaptor.pixelBufferPool), &buffer)
            let pixels = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            if let base = CVPixelBufferGetBaseAddress(pixels) {
                let stride = CVPixelBufferGetBytesPerRow(pixels)
                let shift = Int(frame) * 97 % 4096
                noise.withUnsafeBytes { source in
                    for row in 0..<1080 {
                        (base + row * stride).copyMemory(from: source.baseAddress! + shift + row * rowBytes, byteCount: rowBytes)
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard withSound else { return silent }

        // A tone as AAC, then both in one movie.
        let tone = folder.appending(path: "tone.m4a")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let frames = AVAudioFrameCount(44_100 * seconds)
        let pcm = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        pcm.frameLength = frames
        for index in 0..<Int(frames) { pcm.floatChannelData?[0][index] = Float(sin(Double(index) * 2 * .pi * 440 / 44_100) * 0.3) }
        // The file is finished when it goes away.
        try {
            let file = try AVAudioFile(forWriting: tone, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1])
            try file.write(from: pcm)
        }()

        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: silent), audioAsset = AVURLAsset(url: tone)
        let videoTrack = try #require(try await videoAsset.loadTracks(withMediaType: .video).first)
        let audioTrack = try #require(try await audioAsset.loadTracks(withMediaType: .audio).first)
        let range = CMTimeRange(start: .zero, duration: try await videoAsset.load(.duration))
        let compositionVideo = try #require(composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
        try compositionVideo.insertTimeRange(range, of: videoTrack, at: .zero)
        compositionVideo.preferredTransform = try await videoTrack.load(.preferredTransform)
        let audioRange = CMTimeRange(start: .zero, duration: min(range.duration, try await audioAsset.load(.duration)))
        try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)?
            .insertTimeRange(audioRange, of: audioTrack, at: .zero)
        let movie = folder.appending(path: "take.mov")
        let export = try #require(AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough))
        try await export.export(to: movie, as: .mov)
        return movie
    }

    private static func bytes(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    @Test(arguments: [VideoSize.balanced, .compact])
    func aCopyIsSmallerAndStandsIn(_ size: VideoSize) async throws {
        let original = try await Self.takeLikeClip()
        let copy = original.deletingLastPathComponent().appending(path: "copy-\(size.rawValue).mov")
        try await AVVideoTranscoder().transcode(original, to: copy, size: size)
        #expect(Self.bytes(copy) < Self.bytes(original) / 2)
        #expect(await TranscodeCheck.matches(original: original, copy: copy, size: size))
        let track = try #require(try await AVURLAsset(url: copy).loadTracks(withMediaType: .video).first)
        let natural = try await track.load(.naturalSize)
        #expect(max(natural.width, natural.height) <= CGFloat(size.maxFormatWidth))
        let turn = try await track.load(.preferredTransform)
        #expect(abs(turn.b - 1) < 0.001 && abs(turn.c + 1) < 0.001, "Still turned to portrait")
        #expect(abs(turn.tx - natural.height) < 1, "The shift follows the smaller frame")
        #expect(!(try await AVURLAsset(url: copy).loadTracks(withMediaType: .audio)).isEmpty)
        try? FileManager.default.removeItem(at: original.deletingLastPathComponent())
    }

    @Test func aSilentTakeStaysSilent() async throws {
        let original = try await Self.takeLikeClip(seconds: 1, withSound: false)
        let copy = original.deletingLastPathComponent().appending(path: "copy.mov")
        try await AVVideoTranscoder().transcode(original, to: copy, size: .compact)
        #expect(await TranscodeCheck.matches(original: original, copy: copy, size: .compact))
        #expect(try await AVURLAsset(url: copy).loadTracks(withMediaType: .audio).isEmpty)
        try? FileManager.default.removeItem(at: original.deletingLastPathComponent())
    }

    /// High keeps what the camera made: nothing to make it smaller to.
    @Test func highIsNoTarget() async throws {
        let original = try await Self.takeLikeClip(seconds: 1, withSound: false)
        await #expect(throws: TranscodeError.noTargetBitRate) {
            try await AVVideoTranscoder().transcode(original, to: original.appendingPathExtension("copy"), size: .high)
        }
        try? FileManager.default.removeItem(at: original.deletingLastPathComponent())
    }

    /// A copy cut short, or one that lost its sound, never stands in.
    @Test func aDifferentCopyDoesNotStandIn() async throws {
        let long = try await Self.takeLikeClip(seconds: 2)
        let short = try await Self.takeLikeClip(seconds: 1)
        let silent = try await Self.takeLikeClip(seconds: 2, withSound: false)
        #expect(await !TranscodeCheck.matches(original: long, copy: short, size: .high))
        #expect(await !TranscodeCheck.matches(original: long, copy: silent, size: .high))
        // Still 1920 wide: too big for Compact.
        #expect(await !TranscodeCheck.matches(original: long, copy: long, size: .compact))
        for url in [long, short, silent] { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    }

    @Test func cancellingLeavesNoFile() async throws {
        let original = try await Self.takeLikeClip(seconds: 4, withSound: false)
        let copy = original.deletingLastPathComponent().appending(path: "copy.mov")
        let task = Task { try await AVVideoTranscoder().transcode(original, to: copy, size: .compact) }
        try await Task.sleep(for: .milliseconds(30))
        task.cancel()
        let result = await task.result
        if case .failure = result { #expect(!FileManager.default.fileExists(atPath: copy.path)) }
        try? FileManager.default.removeItem(at: original.deletingLastPathComponent())
    }
}
