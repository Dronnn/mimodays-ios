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

    private func save(
        video: Bool, format: CaptureFormat = .portrait,
        note: String = "Lena caught a flake on her glove and wouldn't come in until it melted."
    ) async throws -> UUID {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        // 16:9 is recorded with the phone sideways.
        if format == .landscape { await engine.setCaptureHold(.landscapeLeft) }
        let media: CaptureResult.Media = video
            ? .video(try await engine.record(limit: .seconds(1)))
            : .photo(try await engine.capturePhoto(flash: .off, silent: true))
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
        draft.note = note
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

    @Test func photoOnDuo() async throws {
        assertScreenSnapshots(of: try await viewer(video: false).onDuo(), variants: SnapshotVariant.duo)
    }

    /// U20, before it starts playing.
    @Test func video() async throws {
        assertScreenSnapshots(of: try await viewer(video: true), variants: [
            SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge),
        ])
    }

    /// The card takes the moment's shape (Andrew, 2026-11-15): square, and wide with the window on its side.
    @Test func square() async throws {
        assertScreenSnapshots(of: try await viewer(video: false, format: .square), variants: [SnapshotVariant(.iPhone, .light)])
    }

    @Test func wide() async throws {
        assertScreenSnapshots(of: try await viewer(video: true, format: .landscape), variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPad, .light)])
    }

    /// The test matrix's other cells: a square video and a wide photo.
    @Test func squareVideo() async throws {
        assertScreenSnapshots(of: try await viewer(video: true, format: .square), variants: [SnapshotVariant(.iPhone, .light)])
    }

    @Test func widePhoto() async throws {
        assertScreenSnapshots(of: try await viewer(video: false, format: .landscape), variants: [SnapshotVariant(.iPhone, .light)])
    }

    /// The back of a square and of a wide card.
    @Test func backSquareAndWide() async throws {
        assertScreenSnapshots(of: try await page(video: true, format: .square, angle: 180), variants: [SnapshotVariant(.iPhone, .light)], testName: "backSquare")
        assertScreenSnapshots(of: try await page(video: false, format: .landscape, angle: 180), variants: [SnapshotVariant(.iPhone, .light)], testName: "backWide")
    }

    /// Swapped on a square video and a wide one: the main stream in the window, on its side on the wide card.
    @Test func swappedSquareAndWide() async throws {
        assertScreenSnapshots(of: try await front(video: true, format: .square, swapped: true), variants: [SnapshotVariant(.iPhone, .light)], testName: "swappedSquare")
        assertScreenSnapshots(of: try await front(video: true, format: .landscape, swapped: true), variants: [SnapshotVariant(.iPhone, .light)], testName: "swappedWide")
    }

    /// A card on its own page, turned to `angle`.
    private func page(video: Bool, format: CaptureFormat = .portrait, angle: Double, bare: Bool = false, note: String? = nil) async throws -> some View {
        let id = bare ? try await saveBare() : try await save(video: video, format: format, note: note ?? "Lena caught a flake on her glove and wouldn't come in until it melted.")
        let model = MomentViewerModel(pager: MomentPager(ids: [id], start: id), library: library)
        await model.load(id)
        let moment = try #require(model.moments[id])
        return MemoryCardPage(model: model, moment: moment, isCurrent: false, screenWidth: 402, angle: angle, edit: {}, step: { _ in })
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
            media: .photo(try await engine.capturePhoto(flash: .off, silent: true)), window: .init(),
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

    /// A note longer than the back: it scrolls, the live window after the last line.
    @Test func backLongNote() async throws {
        let note = String(repeating: "Lena caught a flake on her glove and wouldn't come in until it melted. Then another, and another. ", count: 6)
        assertScreenSnapshots(of: try await page(video: false, angle: 180, note: note), variants: [
            SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge),
        ])
    }

    /// P8.3 (BB02): the back says the moment is hidden from memories, or hidden with its day.
    @Test func backHidden() async throws {
        let id = try await save(video: false)
        let context = container.mainContext
        let moment = try #require(try context.fetch(FetchDescriptor<Moment>(predicate: #Predicate { $0.id == id })).first)
        try MemoryVisibility.setHidden(true, moment, in: context)
        assertScreenSnapshots(of: try await hiddenPage(id), variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge)])
        try MemoryVisibility.setHidden(false, moment, in: context)
        try MemoryVisibility.setDayHidden(true, moment.localDay, in: context)
        assertScreenSnapshots(of: try await hiddenPage(id), variants: [SnapshotVariant(.iPhone, .light)], testName: "backHiddenWithItsDay")
    }

    private func hiddenPage(_ id: UUID) async throws -> some View {
        let model = MomentViewerModel(pager: MomentPager(ids: [id], start: id), library: library)
        await model.load(id)
        let moment = try #require(model.moments[id])
        return MemoryCardPage(model: model, moment: moment, isCurrent: false, screenWidth: 402, angle: 180, edit: {}, step: { _ in })
            .frame(width: 359)
            .padding(.top, 108)
            .padding(.bottom, 84)
            .frame(maxWidth: .infinity)
            .background(ColorToken.canvas.color)
    }

    /// U31: the back with only the basics, "+" links to add the rest.
    @Test func backBasics() async throws {
        assertScreenSnapshots(of: try await page(video: false, angle: 180, bare: true), variants: [SnapshotVariant(.iPhone, .light)])
    }

    /// A card front on its own: `swapped`, part way through a swap, or with the window held `dragged`.
    private func front(
        video: Bool = false, format: CaptureFormat = .portrait, swapped: Bool = false, swapProgress: Double? = nil, dragged: CGSize? = nil
    ) async throws -> some View {
        let id = try await save(video: video, format: format)
        let model = MomentViewerModel(pager: MomentPager(ids: [id], start: id), library: library)
        await model.load(id)
        let moment = try #require(model.moments[id])
        let card = MemoryCardGeometry.card(aspectRatio: moment.format.aspectRatio, in: CGSize(width: 359, height: 562))
        let layout = MemoryCardGeometry.windowLayout(format: format, screenWidth: 402)
        let saved = try #require(moment.video?.layout ?? moment.photo?.layout)
        return MemoryCardFront(
            pictures: MemoryCardFront.Pictures(main: model.image(moment.mainPath), selfie: model.image(moment.selfiePath), isVideo: video),
            playback: nil, size: card,
            window: MemoryCardFront.Window(
                layout: layout, placement: layout.placement(nearest: saved), rotation: saved.rotation, id: "viewer.selfieWindow",
                move: { _ in }, swap: {}
            ),
            swapped: swapped, cornerOnRight: true, controlsShown: .constant(true),
            actions: MemoryCardActions(flip: {}, swap: nil, step: { _ in }),
            heldDrag: dragged, swapProgress: swapProgress
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorToken.canvas.color)
    }

    /// U23: the cameras swapped, the main picture in the window.
    @Test func swapped() async throws {
        assertScreenSnapshots(of: try await front(swapped: true), variants: [SnapshotVariant(.iPhone, .light)])
    }

    /// U22: half way through the swap, the selfie growing into the card as the main picture shrinks into the window.
    @Test func swapping() async throws {
        assertScreenSnapshots(of: try await front(swapProgress: 0.5), variants: [SnapshotVariant(.iPhone, .light)])
    }

    /// U24: the window dragged down and left, the four corners showing, the one it would land on in coral.
    @Test func dragging() async throws {
        assertScreenSnapshots(of: try await front(dragged: CGSize(width: -200, height: 250)), variants: [
            SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark),
        ])
    }

    /// U41: opened from a place on the Map, the second of three there.
    @Test func fromTheMap() async throws {
        let ids = [try await save(video: false), try await save(video: false), try await save(video: false)]
        let model = MomentViewerModel(pager: MomentPager(ids: ids, start: ids[1], origin: .place("Kentron")), library: library)
        for id in ids { await model.load(id) }
        assertScreenSnapshots(of: NavigationStack { MomentViewer(model: model) }, variants: [SnapshotVariant(.iPhone, .light)])
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
