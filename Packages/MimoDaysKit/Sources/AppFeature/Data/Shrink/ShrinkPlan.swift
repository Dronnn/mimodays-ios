import Core
import Foundation
import Persistence
import SwiftData

/// P3.5 (Penpot §V3 X04): which videos "Make smaller" takes, and what it frees.
enum ShrinkSelection: Codable, Equatable, Hashable, Sendable {
    case olderThan30Days
    case olderThanAYear
    case all
    /// X04b, and one moment from its Memory Card.
    case chosen(Set<UUID>)
}

/// One video moment's camera streams that are bigger than the new size needs.
struct ShrinkCandidate: Equatable, Sendable, Identifiable {
    struct Stream: Equatable, Sendable {
        var mediaID: UUID
        var relativePath: String
        var checksum: String
        var byteCount: Int64
        var duration: Double
        var pixelWidth: Int
        var pixelHeight: Int
    }

    var id: UUID
    var capturedAt: Date
    var streams: [Stream]

    var bytes: Int64 { streams.reduce(0) { $0 + $1.byteCount } }

    func estimatedBytes(at size: VideoSize) -> Int64 {
        streams.reduce(0) { $0 + ShrinkPolicy.estimatedBytes($1, at: size) }
    }
}

enum ShrinkPolicy {
    /// Sound stays at about this.
    static let audioBitRate = 128_000
    /// A stream within a quarter of the new bit rate isn't worth making again.
    static let margin = 1.25

    static func bitRate(_ stream: ShrinkCandidate.Stream) -> Double {
        stream.duration > 0 ? Double(stream.byteCount) * 8 / stream.duration : 0
    }

    /// Wider than the size allows, or well over its bit rate. High has no bit rate to shrink to.
    static func needsShrinking(_ stream: ShrinkCandidate.Stream, to size: VideoSize) -> Bool {
        guard let target = size.averageBitRate, stream.duration > 0, stream.byteCount > 0 else { return false }
        let wider = max(stream.pixelWidth, stream.pixelHeight) > Int(size.maxFormatWidth)
        return wider || bitRate(stream) > Double(target + audioBitRate) * margin
    }

    /// What the stream should take at the new size; never more than it takes now.
    static func estimatedBytes(_ stream: ShrinkCandidate.Stream, at size: VideoSize) -> Int64 {
        guard needsShrinking(stream, to: size), let target = size.averageBitRate else { return stream.byteCount }
        let estimate = Int64(stream.duration * Double(target + audioBitRate) / 8)
        return min(estimate, stream.byteCount)
    }

    /// The day before which a moment counts as older; nil for All and Choose…
    static func cutoff(_ selection: ShrinkSelection, now: Date, calendar: Calendar) -> Date? {
        switch selection {
        case .olderThan30Days: calendar.date(byAdding: .day, value: -30, to: now)
        case .olderThanAYear: calendar.date(byAdding: .year, value: -1, to: now)
        case .all, .chosen: nil
        }
    }

    /// The saved video moments (not in Recently Deleted) with at least one camera stream to make smaller, oldest first.
    @MainActor
    static func candidates(
        _ selection: ShrinkSelection, size: VideoSize, in context: ModelContext, now: Date = .now, calendar: Calendar = .current
    ) throws -> [ShrinkCandidate] {
        let video = MediaType.video.rawValue
        var descriptor = FetchDescriptor<Moment>(
            predicate: #Predicate { $0.mediaTypeRaw == video && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.capturedAt)]
        )
        if let cutoff = cutoff(selection, now: now, calendar: calendar) {
            descriptor.predicate = #Predicate { $0.mediaTypeRaw == video && $0.deletedAt == nil && $0.capturedAt < cutoff }
        }
        let chosen: Set<UUID>? = if case let .chosen(ids) = selection { ids } else { nil }
        return try context.fetch(descriptor).compactMap { moment in
            if let chosen, !chosen.contains(moment.id) { return nil }
            guard moment.status == .ready else { return nil }
            let streams = cameraStreams(of: moment).filter { needsShrinking($0, to: size) }
            return streams.isEmpty ? nil : ShrinkCandidate(id: moment.id, capturedAt: moment.capturedAt, streams: streams)
        }
    }

    /// Both cameras' videos, whatever their size (X04b lists every video with its size).
    @MainActor
    static func cameraStreams(of moment: Moment) -> [ShrinkCandidate.Stream] {
        moment.media
            .filter { ($0.role == .rearSource || $0.role == .frontSource) && ($0.duration ?? 0) > 0 }
            .sorted { $0.role == .rearSource && $1.role != .rearSource }
            .map {
                ShrinkCandidate.Stream(
                    mediaID: $0.id, relativePath: $0.relativePath, checksum: $0.checksum, byteCount: $0.byteCount,
                    duration: $0.duration ?? 0, pixelWidth: $0.pixelWidth, pixelHeight: $0.pixelHeight
                )
            }
    }
}
