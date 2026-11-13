import AVFoundation
import Foundation
import ImageIO
import SwiftData
import Testing
import TestSupport

@Model
final class ProbeRecord {
    var title: String
    init(title: String) { self.title = title }
}

struct InfrastructureTests {
    @Test func inMemoryContainerStartsEmptyEachTime() throws {
        let first = ModelContext(try makeInMemoryContainer(for: [ProbeRecord.self]))
        first.insert(ProbeRecord(title: "Lake walk"))
        try first.save()
        #expect(try first.fetchCount(FetchDescriptor<ProbeRecord>()) == 1)

        let second = ModelContext(try makeInMemoryContainer(for: [ProbeRecord.self]))
        #expect(try second.fetchCount(FetchDescriptor<ProbeRecord>()) == 0)
    }

    @Test func temporaryDirectoryIsRemovedWhenReleased() throws {
        var directory: TemporaryDirectory? = try TemporaryDirectory()
        let url = try #require(directory).url
        let copy = try Fixture.backPhoto.copy(to: url)
        #expect(FileManager.default.fileExists(atPath: copy.path))
        directory = nil
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test(arguments: [(Fixture.backPhoto, 900, 1200), (Fixture.frontPhoto, 360, 480)])
    func photoFixturesDecode(fixture: Fixture, width: Int, height: Int) throws {
        let source = try #require(CGImageSourceCreateWithURL(fixture.url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == width)
        #expect(image.height == height)
    }

    @Test(arguments: [Fixture.clip, Fixture.voiceNote])
    func timedFixturesLastTwoSeconds(fixture: Fixture) async throws {
        let duration = try await AVURLAsset(url: fixture.url).load(.duration)
        #expect(abs(duration.seconds - 2) < 0.1)
    }
}
