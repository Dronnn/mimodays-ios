@preconcurrency import AVFoundation
@testable import AppFeature
@testable import Core
import CoreGraphics
import Foundation
import Testing

struct VideoComposerTests {
    private let window = SelfieWindowFrame(frame: CGRect(x: 266.7, y: 111.1, width: 112, height: 150), preview: CGSize(width: 402, height: 700))

    private func seconds(_ value: Double) -> CMTime { CMTime(seconds: value, preferredTimescale: 600) }

    @Test func aLaterSelfieStartsLater() throws {
        let (source, at) = try #require(VideoComposer.placement(selfie: seconds(10), offset: 0.04, main: seconds(10)))
        #expect(at == seconds(0.04))
        #expect(source.start == .zero)
        #expect(source.duration == seconds(9.96))
    }

    @Test func anEarlierSelfieIsTrimmed() throws {
        let (source, at) = try #require(VideoComposer.placement(selfie: seconds(10.05), offset: -0.05, main: seconds(10)))
        #expect(at == .zero)
        #expect(source.start == seconds(0.05))
        #expect(source.duration == seconds(10))
    }

    @Test func nothingRunsPastTheMainStream() throws {
        let (source, _) = try #require(VideoComposer.placement(selfie: seconds(12), offset: 0, main: seconds(10)))
        #expect(source.duration == seconds(10))
        #expect(VideoComposer.placement(selfie: seconds(1), offset: 11, main: seconds(10)) == nil)
    }

    @Test func trackTransformsBecomeOrientations() {
        #expect(CGImagePropertyOrientation(.identity) == .up)
        #expect(CGImagePropertyOrientation(CGAffineTransform(rotationAngle: .pi / 2)) == .right)
        #expect(CGImagePropertyOrientation(CGAffineTransform(rotationAngle: -.pi / 2)) == .left)
        #expect(CGImagePropertyOrientation(CGAffineTransform(scaleX: -1, y: 1)) == .upMirrored)
    }

    /// A recorded clip plays composed, and again from the saved timing alone (as after a relaunch).
    @Test func recordedClipPlaysComposedAndAgainFromSavedTiming() async throws {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let video = try await engine.record(limit: .seconds(1))
        defer { [video.mainURL, video.selfieURL].compactMap(\.self).forEach { try? FileManager.default.removeItem(at: $0) } }
        let timing = VideoTiming(
            duration: video.duration, selfieOffset: video.selfieOffset, hasAudio: video.hasAudio,
            mainPosition: video.mainPosition, window: window
        )

        let saved = try JSONEncoder().encode(timing)
        let restored = try JSONDecoder().decode(VideoTiming.self, from: saved)
        #expect(restored == timing)

        for timing in [timing, restored] {
            let composed = try await VideoComposer.compose(mainURL: video.mainURL, selfieURL: video.selfieURL, timing: timing)
            let duration = try await composed.asset.load(.duration).seconds
            #expect(abs(duration - video.duration) < 0.2)
            let videoComposition = try #require(composed.videoComposition)
            #expect(videoComposition.renderSize == CGSize(width: 450, height: 600))

            let generator = AVAssetImageGenerator(asset: composed.asset)
            generator.videoComposition = videoComposition
            let (frame, _) = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600))
            let pixel = try color(of: frame)
            let (rect, _) = PhotoComposer.placement(of: window, in: CGSize(width: 450, height: 600))
            // Warm rear gradient outside the window, mint selfie inside it.
            let outside = pixel(5, 590)
            let inside = pixel(Int(rect.midX), Int(rect.midY))
            #expect(outside.r > outside.g)
            #expect(inside.g > inside.r)
        }
    }

    @Test func withoutASelfieThereIsNoCompositor() async throws {
        let engine = SimulatedCaptureEngine(multiCam: false)
        _ = await engine.start()
        let video = try await engine.record(limit: .seconds(1))
        defer { try? FileManager.default.removeItem(at: video.mainURL) }
        let timing = VideoTiming(duration: video.duration, selfieOffset: 0, hasAudio: false, mainPosition: .back, window: nil)
        let composed = try await VideoComposer.compose(mainURL: video.mainURL, selfieURL: nil, timing: timing)
        #expect(composed.videoComposition == nil)
        #expect(try await composed.asset.loadTracks(withMediaType: .video).count == 1)
    }

    private func color(of image: CGImage) throws -> (Int, Int) -> (r: Int, g: Int, b: Int) {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data
        return { x, y in
            let i = (y * width + x) * 4
            return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
        }
    }
}
