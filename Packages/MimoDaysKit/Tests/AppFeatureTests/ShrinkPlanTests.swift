@testable import AppFeature
import Core
import Foundation
import Persistence
import SwiftData
import Testing

/// P3.5 X04: which videos Make smaller takes, and what it frees.
@MainActor
struct ShrinkPlanTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()
    private let now = Date(timeIntervalSince1970: 1_795_000_000)

    /// 30 s at 1920×1080 and `megabitsPerSecond`, with a selfie stream at the same rate when `selfie`.
    @discardableResult
    private func video(
        daysAgo: Int, megabitsPerSecond: Double = 16, width: Int = 1920, selfie: Bool = true, type: MediaType = .video,
        in context: ModelContext
    ) -> Moment {
        let date = now.addingTimeInterval(TimeInterval(-daysAgo * 86_400))
        let moment = Moment(captured: CaptureTime(instant: date, timeZone: calendar.timeZone), origin: .manual, mediaType: type, createdAt: date)
        context.insert(moment)
        let bytes = Int64(megabitsPerSecond * 1_000_000 / 8 * 30)
        let roles: [MediaRole] = selfie ? [.rearSource, .frontSource] : [.rearSource]
        for role in roles {
            moment.media.append(MomentMedia(
                role: role, relativePath: "originals/\(UUID().uuidString).mov", uniformType: "com.apple.quicktime-movie",
                pixelWidth: width, pixelHeight: width * 9 / 16, checksum: "c", byteCount: bytes, duration: 30
            ))
        }
        moment.media.append(MomentMedia(role: .thumbnail, relativePath: "derived/t.jpg", uniformType: "public.jpeg", pixelWidth: 40, pixelHeight: 30, checksum: "t", byteCount: 1))
        return moment
    }

    private func candidates(_ selection: ShrinkSelection, _ context: ModelContext, size: VideoSize = .compact) throws -> [ShrinkCandidate] {
        try ShrinkPolicy.candidates(selection, size: size, in: context, now: now, calendar: calendar)
    }

    @Test func olderThanPicksByAge() throws {
        let container = try MimoDaysStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let recent = video(daysAgo: 3, in: context)
        let month = video(daysAgo: 45, in: context)
        let years = video(daysAgo: 800, in: context)
        #expect(try candidates(.olderThan30Days, context).map(\.id) == [years.id, month.id])
        #expect(try candidates(.olderThanAYear, context).map(\.id) == [years.id])
        #expect(try candidates(.all, context).map(\.id) == [years.id, month.id, recent.id])
        #expect(try candidates(.chosen([recent.id]), context).map(\.id) == [recent.id])
    }

    /// Photos, text, Recently Deleted and videos already that small are left alone; so is anything for High.
    @Test func onlyVideosBiggerThanTheSize() throws {
        let container = try MimoDaysStore.makeContainer(inMemory: true)
        let context = container.mainContext
        video(daysAgo: 40, type: .photo, in: context)
        video(daysAgo: 40, megabitsPerSecond: 2, width: 1280, in: context)
        video(daysAgo: 40, in: context).deletedAt = now
        let big = video(daysAgo: 40, in: context)
        #expect(try candidates(.all, context).map(\.id) == [big.id])
        #expect(try candidates(.all, context, size: .high).isEmpty)
    }

    /// A 720p stream at a high bit rate still gets smaller for Compact; a 1080p one at Balanced's rate does for Compact
    /// by width, not for Balanced.
    @Test func widthOrBitRate() {
        let stream = { (rate: Double, width: Int) in
            ShrinkCandidate.Stream(
                mediaID: UUID(), relativePath: "a", checksum: "c", byteCount: Int64(rate * 1_000_000 / 8 * 10),
                duration: 10, pixelWidth: width, pixelHeight: width * 9 / 16
            )
        }
        #expect(ShrinkPolicy.needsShrinking(stream(12, 1280), to: .compact))
        #expect(!ShrinkPolicy.needsShrinking(stream(2.5, 1280), to: .compact))
        #expect(ShrinkPolicy.needsShrinking(stream(6, 1920), to: .compact))
        #expect(!ShrinkPolicy.needsShrinking(stream(6, 1920), to: .balanced))
    }

    /// X04's "now", "after" and "frees": both streams count, and nothing grows.
    @Test func whatItFrees() throws {
        let container = try MimoDaysStore.makeContainer(inMemory: true)
        let context = container.mainContext
        video(daysAgo: 40, megabitsPerSecond: 16, in: context)
        let candidate = try #require(try candidates(.all, context).first)
        #expect(candidate.streams.count == 2)
        #expect(candidate.bytes == 2 * 60_000_000)
        // 2.5 Mbit/s of video and 128 kbit/s of sound for 30 s, twice.
        #expect(candidate.estimatedBytes(at: .compact) == 2 * Int64(30 * Double(2_500_000 + 128_000) / 8))
        #expect(candidate.estimatedBytes(at: .high) == candidate.bytes)
    }
}
