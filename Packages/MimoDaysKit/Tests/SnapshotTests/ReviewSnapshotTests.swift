@testable import AppFeature
@testable import Core
import DesignSystem
import Foundation
import Persistence
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

    @Test func photoWithANote() async throws {
        let model = try await review()
        defer { model.discard() }
        model.note = "Lena finally rode without training wheels. She shouted \"don't let go\" for the whole street"
        assertScreenSnapshots(of: screen(model), variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge)])
    }

    /// C08 with the keyboard's space left out (the keyboard doesn't render in snapshots).
    @Test func noteEditor() async throws {
        let model = try await review()
        defer { model.discard() }
        model.note = "Lena finally rode without training wheels. She shouted \"don't let go\" for the whole street"
        assertScreenSnapshots(of: NoteEditorView(model: model), variants: [
            SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge),
        ])
    }

    /// C10: a 12 s voice note with its words; the Voice note chip gives way to the card.
    @Test func photoWithAVoiceNote() async throws {
        let model = try await review()
        defer { model.discard() }
        let url = FileManager.default.temporaryDirectory.appending(path: "snapshot-voice-\(UUID().uuidString).m4a")
        try SimulatedVoiceRecorder.writeTone(to: url, seconds: 12)
        model.addVoice(at: url, recordedAt: time.instant)
        model.voice?.transcript = "She did it, she actually did it, look at her go, all the way to the corner"
        assertScreenSnapshots(of: screen(model), variants: [
            SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge),
        ])
    }

    /// C07 with the city filled in by itself, as in the design.
    @Test func photoWithAPlace() async throws {
        let model = try await review()
        defer { model.discard() }
        await model.locate()
        assertScreenSnapshots(of: screen(model), variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge)])
    }

    /// 7.6: a capture answering a surprise says so by its time (Penpot §H20).
    @Test func photoFromASurprise() async throws {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let capture = CaptureResult(media: .photo(try await engine.capturePhoto(flash: false, silent: true)), window: .init(), capturedAt: time)
        let model = ReviewModel(capture: capture, promptID: UUID())
        defer { model.discard() }
        await model.load()
        assertScreenSnapshots(of: screen(model), variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark)])
    }

    /// 7.6: every origin in both orders, as lists and the viewer will show them.
    @Test func originLabels() {
        let time = Text(verbatim: "8:05 AM")
        let rows = VStack(alignment: .leading, spacing: 16) {
            ForEach([MomentOrigin.randomPrompt, .manual, .imported], id: \.self) { origin in
                OriginLabel(origin: origin, time: time)
                OriginLabel(origin: origin, time: Text(verbatim: "Wed, Nov 11 · 6:42 PM"), order: .originFirst)
            }
        }
        .textStyle(.reviewMeta)
        .foregroundStyle(ColorToken.textBody.color)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ColorToken.canvas.color)
        assertScreenSnapshots(of: rows, variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge)])
    }

    /// C11: the current city chosen, places nearby and one used before.
    @Test func choosingAPlace() async throws {
        let recent = RecentPlace(place: ReviewPlace(label: "Grandma's house", latitude: 40.2, longitude: 44.49, precision: .city, source: .manual), uses: 4)
        let places = PlaceServices(location: SimulatedLocationProvider(), lookup: SimulatedPlaceLookup(), recents: { [recent] })
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let model = ReviewModel(capture: CaptureResult(media: .photo(try await engine.capturePhoto(flash: false, silent: true)), window: .init(), capturedAt: time), places: places)
        defer { model.discard() }
        await model.locate()
        await model.loadNearby()
        let screen = ZStack(alignment: .bottom) {
            Color.black.opacity(0.35).ignoresSafeArea()
            PlaceSheet(model: model, showsCurrent: true)
                .frame(maxWidth: .infinity)
                .background(ColorToken.surfaceSheet.color, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
                .ignoresSafeArea(edges: .bottom)
        }
        assertScreenSnapshots(of: screen, variants: [
            SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge),
        ])
    }

    /// C09 at 0:12 of 1:00, drawn as the sheet sits over review.
    @Test func recordingAVoiceNote() {
        // 12 s in on the recorder's clock, so the sheet's own ticks agree.
        let start = Date(timeIntervalSince1970: 0)
        var now = start
        let recorder = SimulatedVoiceRecorder(now: { now })
        let recording = VoiceRecording(recorder: recorder, url: URL(filePath: "/dev/null"), limit: ReviewModel.voiceLimit)
        #expect(recording.start())
        now = start + 12
        recording.elapsed = 12
        recording.levels = (0 ..< 11).map { Float(0.35 + 0.3 * sin(Double($0) * 1.3)) + 0.25 }
        let screen = ZStack(alignment: .bottom) {
            Color.black.opacity(0.35).ignoresSafeArea()
            VoiceRecordingSheet(recording: recording) { _ in }
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
                .background(ColorToken.surfaceSheet.color, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
                .ignoresSafeArea(edges: .bottom)
        }
        assertScreenSnapshots(of: screen, variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark)])
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

    /// C12 over the canvas, as it shows on Today.
    @Test func savedToast() {
        let screen = ZStack(alignment: .bottom) {
            ColorToken.canvas.color.ignoresSafeArea()
            SavedToast().padding(.bottom, 100)
        }
        assertScreenSnapshots(of: screen, variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark)])
    }
}
