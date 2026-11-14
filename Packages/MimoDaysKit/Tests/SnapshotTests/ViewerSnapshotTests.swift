@testable import AppFeature
@testable import Core
import DesignSystem
import Foundation
import Persistence
import SwiftData
import SwiftUI
import Testing
import TestSupport

/// The moment viewer (M05 photo, M06 video), from moments saved off the simulated camera, pictures read before the snapshot.
@MainActor
@Suite(.tags(.snapshot))
struct ViewerSnapshotTests {
    private let container = try! MimoDaysStore.makeContainer(inMemory: true)
    private let root = FileManager.default.temporaryDirectory.appending(path: "ViewerSnapshots-\(UUID().uuidString)")
    private let store: MediaStore
    private let clock = TestDateProvider()

    /// The view's `.task` can still run after a test returns; its store must outlive the test.
    private static var stores: [ModelContainer] = []

    init() throws {
        store = try MediaStore(root: root)
        Self.stores.append(container)
    }

    private var library: MediaLibrary { MediaLibrary(context: container.mainContext, store: store, thumbnails: ThumbnailPipeline()) }

    private func save(video: Bool) async throws -> UUID {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let media: CaptureResult.Media = video
            ? .video(try await engine.record(limit: .seconds(1)))
            : .photo(try await engine.capturePhoto(flash: false, silent: true))
        // Wed, Nov 11, 2026, 6:42 PM in Yerevan.
        let capture = CaptureResult(
            media: media, window: .init(),
            capturedAt: CaptureTime(instant: Date(timeIntervalSince1970: 1_794_422_520), timeZone: TimeZone(identifier: "Asia/Yerevan")!)
        )
        var draft = MomentDraft(
            capture: capture, caption: "First snow on the balcony",
            window: SelfieWindowFrame(frame: CGRect(x: 266.7, y: 111.1, width: 112, height: 150), preview: CGSize(width: 402, height: 536)),
            promptID: nil,
            place: ReviewPlace(label: "Yerevan", latitude: 40.18, longitude: 44.51, precision: .city, source: .gps)
        )
        draft.note = "Lena caught a flake on her glove and wouldn't come in until it melted."
        let url = root.appending(path: "voice-\(UUID().uuidString).m4a")
        try SimulatedVoiceRecorder.writeTone(to: url, seconds: 12)
        draft.voice = ReviewVoiceNote(url: url, duration: 12, recordedAt: .now, transcript: nil)
        let saver = MomentSaver(context: container.mainContext, store: store, clock: clock, freeBytes: { nil })
        return try await saver.save(draft).id
    }

    private func viewer(video: Bool) async throws -> some View {
        let id = try await save(video: video)
        let model = MomentViewerModel(pager: MomentPager(ids: [id], start: id), library: library)
        await model.load(id)
        return NavigationStack { MomentViewer(model: model) }
    }

    /// M05.
    @Test func photo() async throws {
        assertScreenSnapshots(of: try await viewer(video: false), variants: [
            SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge),
            SnapshotVariant(.iPhone, .light, rightToLeft: true), SnapshotVariant(.iPad, .light),
        ])
    }

    /// M06, before it starts playing.
    @Test func video() async throws {
        assertScreenSnapshots(of: try await viewer(video: true), variants: [SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge)])
    }

    /// M07.
    @Test func edit() async throws {
        let id = try await save(video: false)
        let model = try #require(EditMomentModel(id: id, library: library, voice: .simulated, places: .simulated))
        await model.loadThumbnail()
        // The saved caption wraps right at a word in the multi-line field at AX3, and machines disagree on
        // which side of it: a shorter one keeps the snapshot about the screen.
        model.caption = "First snow"
        assertScreenSnapshots(of: EditMomentView(model: model), variants: [
            SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge),
            SnapshotVariant(.iPhone, .light, rightToLeft: true),
        ])
    }
}
