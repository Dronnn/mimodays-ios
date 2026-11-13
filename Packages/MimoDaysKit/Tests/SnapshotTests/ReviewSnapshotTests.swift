@testable import AppFeature
@testable import Core
import Foundation
import SnapshotTesting
import SwiftUI
import Testing
import TestSupport

/// C07 review and C13d with simulated captures, stills loaded before the snapshot.
@MainActor
@Suite(.tags(.snapshot))
struct ReviewSnapshotTests {
    /// Nov 11, 2026, 2:37 PM in the snapshot time zone.
    private let time = CaptureTime(instant: Date(timeIntervalSince1970: 1_794_407_820), timeZone: .gmt)

    private func review(video: Bool = false, interruption: CaptureInterruption? = nil, window: CameraSettings.SelfieWindow = .init()) async throws -> ReviewModel {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let media: CaptureResult.Media
        if video {
            var clip = try await engine.record(limit: .seconds(1))
            clip.interruption = interruption
            clip.duration = 6.2
            media = .video(clip)
        } else {
            media = .photo(try await engine.capturePhoto(flash: false, silent: true))
        }
        let model = ReviewModel(capture: CaptureResult(media: media, window: window, capturedAt: time))
        await model.load()
        return model
    }

    private func screen(_ model: ReviewModel) -> some View {
        ReviewView(model: model, onRetake: {}, onSave: {})
    }

    @Test func photo() async throws {
        let model = try await review()
        defer { model.discard() }
        assertScreenSnapshots(of: screen(model))
    }

    @Test func photoWithACaptionAndTheWindowMoved() async throws {
        let model = try await review(window: .init(corner: .bottomLeft, scale: .large))
        defer { model.discard() }
        model.caption = "Lena finally rode without training wheels"
        assertScreenSnapshots(of: screen(model), variants: [SnapshotVariant(.iPhone, .light)])
    }

    @Test func video() async throws {
        let model = try await review(video: true)
        defer { model.discard() }
        assertScreenSnapshots(of: screen(model), variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark)])
    }

    /// C13d: a call stopped the recording at 0:06.
    @Test func interruptedByACall() async throws {
        let model = try await review(video: true, interruption: .anotherApp)
        defer { model.discard() }
        assertScreenSnapshots(of: screen(model))
    }
}
