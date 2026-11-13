@testable import AppFeature
import Core
import CoreGraphics
import Foundation
import ImageIO
import Testing

struct PhotoComposerTests {
    /// iPhone preview 402 × 700 with the default window (frame 112 × 150 at 266.7, 111.1).
    private let window = SelfieWindowFrame(frame: CGRect(x: 266.7, y: 111.1, width: 112, height: 150), preview: CGSize(width: 402, height: 700))

    @Test func theWindowKeepsItsPlaceInTheVisiblePartOfTheFullPhoto() {
        // A 3:4 photo is wider than the preview: the preview shows its middle 689 px.
        let (rect, scale) = PhotoComposer.placement(of: window, in: CGSize(width: 900, height: 1200))
        #expect(abs(scale - 1200.0 / 700) < 0.0001)
        let hiddenSide = (900 - 402 * scale) / 2
        #expect(abs(rect.minX - (hiddenSide + 266.7 * scale)) < 0.01)
        #expect(abs(rect.minY - 111.1 * scale) < 0.01)
        #expect(abs(rect.width - 112 * scale) < 0.01)
        // Right edge as far from the visible edge as on screen.
        #expect(abs((900 - hiddenSide) - rect.maxX - 23.3 * scale) < 0.01)
    }

    @Test func composesTheSelfieInACreamFrameOverTheWholePhoto() throws {
        let main = solid(width: 900, height: 1200, rgb: (200, 40, 40))
        let selfie = solid(width: 360, height: 480, rgb: (40, 40, 200))
        let composed = PhotoComposer.compose(main: main, selfie: selfie, window: window)
        #expect(composed.width == 900 && composed.height == 1200)
        let (rect, scale) = PhotoComposer.placement(of: window, in: CGSize(width: 900, height: 1200))
        let pixels = try rgba(composed)
        #expect(pixels(10, 10).isClose(to: (200, 40, 40)))
        #expect(pixels(Int(rect.midX), Int(rect.midY)).isClose(to: (40, 40, 200)))
        #expect(pixels(Int(rect.midX), Int(rect.minY + 2 * scale)).isClose(to: (0xFB, 0xF6, 0xEF)))
    }

    @MainActor
    @Test func theShutterDeliversSourcesAndTheComposite() async throws {
        var results: [CaptureResult] = []
        let model = CameraModel(
            engine: SimulatedCaptureEngine(), store: InMemoryCameraSettingsStore(), isSurprise: false,
            microphoneStatus: { .granted }, onCapture: { results.append($0) }
        )
        await model.start()
        model.selfieWindowFrame = window
        await model.shutter()
        guard case let .photo(photo, _, composedURL) = try #require(results.first) else { Issue.record("not a photo"); return }
        #expect(photo.selfieURL != nil)
        let url = try #require(composedURL)
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 900)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 1200)
        results.first?.discardFiles()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor
    @Test func noSelfieMeansNoComposite() async throws {
        var results: [CaptureResult] = []
        let model = CameraModel(
            engine: SimulatedCaptureEngine(), store: InMemoryCameraSettingsStore(), isSurprise: false,
            microphoneStatus: { .granted }, onCapture: { results.append($0) }
        )
        await model.start()
        model.selfieWindowFrame = window
        model.toggleSelfie()
        await model.shutter()
        guard case let .photo(photo, _, composedURL) = try #require(results.first) else { Issue.record("not a photo"); return }
        #expect(photo.selfieURL == nil)
        #expect(composedURL == nil)
        results.first?.discardFiles()
    }

    // MARK: Helpers

    private func solid(width: Int, height: Int, rgb: (Int, Int, Int)) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: CGFloat(rgb.0) / 255, green: CGFloat(rgb.1) / 255, blue: CGFloat(rgb.2) / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// Pixel reader with a top-left origin.
    private func rgba(_ image: CGImage) throws -> (Int, Int) -> Pixel {
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
            return Pixel(r: Int(pixels[i]), g: Int(pixels[i + 1]), b: Int(pixels[i + 2]))
        }
    }

    struct Pixel {
        let r: Int, g: Int, b: Int
        func isClose(to rgb: (Int, Int, Int)) -> Bool {
            abs(r - rgb.0) <= 8 && abs(g - rgb.1) <= 8 && abs(b - rgb.2) <= 8
        }
    }
}
