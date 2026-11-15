@testable import AppFeature
@testable import Core
import DesignSystem
import Foundation
import Persistence
import SwiftData
import SwiftUI
import Testing
import TestSupport

/// The Memory Card (U20-U24) in the moment viewer, from moments saved off the simulated camera, pictures read before the snapshot.
@MainActor
@Suite(.tags(.snapshot))
struct ViewerSnapshotTests {
    private let container = try! TestStore.container()
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

    private func save(video: Bool, format: CaptureFormat = .portrait) async throws -> UUID {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        // 16:9 is recorded with the phone sideways.
        if format == .landscape { await engine.setCaptureHold(.landscapeLeft) }
        let media: CaptureResult.Media = video
            ? .video(try await engine.record(limit: .seconds(1)))
            : .photo(try await engine.capturePhoto(flash: false, silent: true))
        // Wed, Nov 11, 2026, 6:42 PM in Yerevan.
        var capture = CaptureResult(
            media: media, window: .init(),
            capturedAt: CaptureTime(instant: Date(timeIntervalSince1970: 1_794_422_520), timeZone: TimeZone(identifier: "Asia/Yerevan")!)
        )
        capture.format = format
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

    private func viewer(video: Bool, format: CaptureFormat = .portrait) async throws -> some View {
        let id = try await save(video: video, format: format)
        let model = MomentViewerModel(pager: MomentPager(ids: [id], start: id), library: library)
        await model.load(id)
        return NavigationStack { MomentViewer(model: model) }
    }

    /// U21.
    @Test func photo() async throws {
        assertScreenSnapshots(of: try await viewer(video: false), variants: [
            SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge),
            SnapshotVariant(.iPhone, .light, rightToLeft: true), SnapshotVariant(.iPad, .light),
        ])
    }

    /// U20, before it starts playing.
    @Test func video() async throws {
        assertScreenSnapshots(of: try await viewer(video: true), variants: [SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge)])
    }

    /// The card takes the moment's shape (Andrew, 2026-11-15): square, and wide with the window on its side.
    @Test func square() async throws {
        assertScreenSnapshots(of: try await viewer(video: false, format: .square), variants: [SnapshotVariant(.iPhone, .light)])
    }

    @Test func wide() async throws {
        assertScreenSnapshots(of: try await viewer(video: true, format: .landscape), variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPad, .light)])
    }

    /// A card on its own page, turned to `angle`.
    private func page(video: Bool, angle: Double, bare: Bool = false) async throws -> some View {
        let id = bare ? try await saveBare() : try await save(video: video)
        let model = MomentViewerModel(pager: MomentPager(ids: [id], start: id), library: library)
        await model.load(id)
        let moment = try #require(model.moments[id])
        return MemoryCardPage(model: model, moment: moment, isCurrent: false, screenWidth: 402, screenTop: 62, angle: angle, edit: {}, step: { _ in })
            .frame(width: 359)
            .padding(.top, 108)
            .padding(.bottom, 84)
            .frame(maxWidth: .infinity)
            .background(ColorToken.canvas.color)
    }

    /// A photo with nothing added: no caption, note, place or voice note.
    private func saveBare() async throws -> UUID {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let capture = CaptureResult(
            media: .photo(try await engine.capturePhoto(flash: false, silent: true)), window: .init(),
            capturedAt: CaptureTime(instant: Date(timeIntervalSince1970: 1_794_422_520), timeZone: TimeZone(identifier: "Asia/Yerevan")!)
        )
        let draft = MomentDraft(
            capture: capture, caption: "",
            window: SelfieWindowFrame(frame: CGRect(x: 266.7, y: 111.1, width: 112, height: 150), preview: CGSize(width: 402, height: 536)),
            promptID: nil
        )
        let saver = MomentSaver(context: container.mainContext, store: store, clock: clock, freeBytes: { nil })
        return try await saver.save(draft).id
    }

    /// U30, U34: the back.
    @Test func back() async throws {
        assertScreenSnapshots(of: try await page(video: true, angle: 180), variants: [
            SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge),
            SnapshotVariant(.iPhone, .light, rightToLeft: true),
        ])
    }

    /// U31: the back with only the basics, "+" links to add the rest.
    @Test func backBasics() async throws {
        assertScreenSnapshots(of: try await page(video: false, angle: 180, bare: true), variants: [SnapshotVariant(.iPhone, .light)])
    }

    /// U23: the cameras swapped, the main picture in the window.
    @Test func swapped() async throws {
        let id = try await save(video: false)
        let model = MomentViewerModel(pager: MomentPager(ids: [id], start: id), library: library)
        await model.load(id)
        let moment = try #require(model.moments[id])
        let card = MemoryCardGeometry.card(aspectRatio: moment.format.aspectRatio, in: CGSize(width: 359, height: 562))
        let front = MemoryCardFront(
            model: model, moment: moment, playback: nil, size: card,
            windowLayout: MemoryCardGeometry.windowLayout(format: .portrait, screenWidth: 402, topInset: 62),
            swapped: true, cornerOnRight: true, controlsShown: .constant(true),
            actions: MemoryCardActions(flip: {}, swap: nil, step: { _ in })
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorToken.canvas.color)
        assertScreenSnapshots(of: front, variants: [SnapshotVariant(.iPhone, .light)])
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
