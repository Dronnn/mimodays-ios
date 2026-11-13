import Core
import CoreGraphics
import Foundation
import ImageIO
import Testing
import TestSupport

struct ThumbnailPipelineTests {
    @Test func photoIsDownsampledKeepingAspect() async throws {
        let image = try await ThumbnailPipeline().thumbnail(for: Fixture.backPhoto.url, maxPixelSize: 200)
        #expect(max(image.width, image.height) == 200)
        #expect(image.width * 4 == image.height * 3) // 900x1200 is 3:4
    }

    @Test func videoGivesAPosterFrame() async throws {
        let image = try await ThumbnailPipeline().thumbnail(for: Fixture.clip.url, maxPixelSize: 160)
        #expect(max(image.width, image.height) <= 160)
        #expect(image.height > image.width) // 360x480 portrait
    }

    @Test func repeatedRequestsComeFromCache() async throws {
        let pipeline = ThumbnailPipeline()
        _ = try await pipeline.thumbnail(for: Fixture.frontPhoto.url, maxPixelSize: 120)
        _ = try await pipeline.thumbnail(for: Fixture.frontPhoto.url, maxPixelSize: 120)
        #expect(await pipeline.renderCount == 1)
        _ = try await pipeline.thumbnail(for: Fixture.frontPhoto.url, maxPixelSize: 240)
        #expect(await pipeline.renderCount == 2)
    }

    @Test func oldestEntryIsEvictedAtCapacity() async throws {
        let pipeline = ThumbnailPipeline(capacity: 1)
        _ = try await pipeline.thumbnail(for: Fixture.frontPhoto.url, maxPixelSize: 100)
        _ = try await pipeline.thumbnail(for: Fixture.backPhoto.url, maxPixelSize: 100)
        _ = try await pipeline.thumbnail(for: Fixture.frontPhoto.url, maxPixelSize: 100)
        #expect(await pipeline.renderCount == 3)
    }

    @Test func unreadableFileThrows() async throws {
        let directory = try TemporaryDirectory()
        let bogus = directory.url.appendingPathComponent("broken.jpg")
        try Data("not an image".utf8).write(to: bogus)
        await #expect(throws: ThumbnailError.unreadable("broken.jpg")) {
            try await ThumbnailPipeline().thumbnail(for: bogus, maxPixelSize: 100)
        }
    }

    @Test func thumbnailFileLandsInDerivedArea() async throws {
        let directory = try TemporaryDirectory()
        let store = try MediaStore(root: directory.url)
        let stored = try await ThumbnailPipeline().storeThumbnail(for: Fixture.backPhoto.url, maxPixelSize: 300, in: store)
        #expect(stored.relativePath.hasPrefix("derived/"))
        let source = try #require(CGImageSourceCreateWithURL(try store.url(for: stored.relativePath) as CFURL, nil))
        let size = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(size[kCGImagePropertyPixelHeight] as? Int == 300)
    }
}
