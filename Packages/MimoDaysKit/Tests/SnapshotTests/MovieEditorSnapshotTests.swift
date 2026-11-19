@testable import AppFeature
@testable import Core
import DesignSystem
import Foundation
import Persistence
import SwiftData
import SwiftUI
import Testing
import TestSupport

/// The movie editor F06-F09 and U50-U54 (the stage's player doesn't draw offscreen), the export F11-F14 and the movie page F15.
@MainActor
@Suite(.tags(.snapshot))
struct MovieEditorSnapshotTests {
    private let container = try! TestStore.container()
    private let store: MediaStore
    private static var stores: [ModelContainer] = []

    init() throws {
        store = try MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "MovieEditorSnapshots-\(UUID().uuidString)"))
        Self.stores.append(container)
    }

    private var context: ModelContext { container.mainContext }
    private var library: MediaLibrary { MediaLibrary(context: context, store: store, thumbnails: ThumbnailPipeline()) }

    /// October 2026: `count` moments a day apart from Wed, Oct 7, at Oakland; `voice` of them with a voice note.
    private func project(_ count: Int = 8) async throws -> MovieProject {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let saver = MomentSaver(context: context, store: store, clock: TestDateProvider(), freeBytes: { nil })
        var ids: [UUID] = []
        for index in 0..<count {
            let instant = Date(timeIntervalSince1970: 1_791_374_400 + Double(index - 2) * 86_400) // Oct 7, 2026 noon UTC at index 2
            let capture = CaptureResult(
                media: .photo(try await engine.capturePhoto(flash: .off, silent: true)), window: .init(),
                capturedAt: CaptureTime(instant: instant, timeZone: .gmt)
            )
            let draft = MomentDraft(
                capture: capture, caption: "",
                window: SelfieWindowFrame(frame: CGRect(x: 266.7, y: 111.1, width: 112, height: 150), preview: CGSize(width: 402, height: 536)),
                promptID: nil,
                place: ReviewPlace(label: "Oakland", latitude: 37.80, longitude: -122.27, precision: .exact, source: .manual)
            )
            ids.append(try await saver.save(draft).id)
        }
        return try MovieStore(context: context, store: store).create(
            title: "October 2026", source: MovieSourceRule(kind: .selection, momentIDs: ids), length: .quick,
            aspectRatio: .portrait9x16, fit: .fill, momentIDs: ids
        )
    }

    private func editor(_ tool: MovieEditorModel.Tool) async throws -> MovieEditorModel {
        let model = MovieEditorModel(project: try await project(), library: library)
        model.tool = tool
        model.select(2)
        for clip in model.clips { if let id = clip.moment?.id { await model.tiles.load(id) } }
        return model
    }

    private func page(_ view: some View) -> some View {
        NavigationStack { view }.environment(AppRouter()).environment(\.mediaLibrary, library)
    }

    private let variants = [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge)]

    /// F06.
    @Test func clips() async throws {
        let model = try await editor(.clips)
        assertScreenSnapshots(of: page(MovieEditorView(model: model, export: {})), variants: variants)
    }

    @Test func clipsOnDuo() async throws {
        let model = try await editor(.clips)
        assertScreenSnapshots(of: page(MovieEditorView(model: model, export: {})).onDuo(), variants: SnapshotVariant.duo)
    }

    /// X04: on iPad the tools and their panel are on the right of the stage and timeline.
    @Test func clipsOnIPad() async throws {
        let model = try await editor(.clips)
        assertScreenSnapshots(
            of: page(MovieEditorView(model: model, export: {})),
            variants: [SnapshotVariant(.iPadLandscape, .light), SnapshotVariant(.iPad, .light)]
        )
    }

    /// F07.
    @Test func shape() async throws {
        let model = try await editor(.shape)
        model.setPlacement(.topRight)
        assertScreenSnapshots(of: page(MovieEditorView(model: model, export: {})), variants: [SnapshotVariant(.iPhone, .light)])
    }

    /// F08.
    @Test func captions() async throws {
        let model = try await editor(.text)
        assertScreenSnapshots(of: page(MovieEditorView(model: model, export: {})), variants: [SnapshotVariant(.iPhone, .light)])
    }

    /// F09.
    @Test func audio() async throws {
        let model = try await editor(.audio)
        assertScreenSnapshots(of: page(MovieEditorView(model: model, export: {})), variants: [SnapshotVariant(.iPhone, .light)])
    }

    /// F09 with the person's voice recorded over the movie: named as theirs, with its level.
    @Test func audioWithVoice() async throws {
        let model = try await editor(.audio)
        let recorded = try CaptureFiles.temporaryURL("m4a")
        try SimulatedVoiceRecorder.writeTone(to: recorded, seconds: 2)
        model.addVoiceover(at: recorded)
        assertScreenSnapshots(of: page(MovieEditorView(model: model, export: {})), variants: [SnapshotVariant(.iPhone, .light)])
    }

    /// U50: a text card first, an Atmosphere dot, a muted clip; the playhead in the lead shows U54's badge.
    @Test func timeline() async throws {
        let model = try await editor(.clips)
        model.addCard()
        model.setTransition(.atmosphere, at: 2)
        model.select(3)
        model.setClipSound(false)
        model.select(2)
        model.seek(to: model.starts[2] + 0.3)
        assertScreenSnapshots(of: page(MovieEditorView(model: model, export: {})), variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark)])
    }

    private func sheet(_ view: some View) -> some View {
        page(view.background(ColorToken.canvas.color.ignoresSafeArea()))
    }

    /// U51.
    @Test func cardSheet() async throws {
        let model = try await editor(.text)
        model.addCard()
        model.setCardText("The long way home", of: try #require(model.selectedCard))
        assertScreenSnapshots(of: sheet(CardSheet(model: model)), variants: variants)
    }

    /// U52.
    @Test func clipSheet() async throws {
        let model = try await editor(.clips)
        model.setCameraLayout(.sideBySide)
        assertScreenSnapshots(of: sheet(ClipSheet(model: model)), variants: variants)
    }

    /// U53.
    @Test func transitionSheet() async throws {
        let model = try await editor(.clips)
        model.setTransition(.atmosphere, at: 2)
        assertScreenSnapshots(of: sheet(TransitionSheet(model: model, index: 2)), variants: variants)
    }

    /// F11.
    @Test func exportOptions() async throws {
        let model = MovieExportModel(project: try await project(), library: library, freeSpace: { 12_000_000_000 })
        // On the canvas, as MovieExportView puts it.
        assertScreenSnapshots(of: page(MovieExportOptions(model: model, cover: nil).background(ColorToken.canvas.color.ignoresSafeArea())), variants: variants)
    }

    /// F12.
    @Test func rendering() {
        assertScreenSnapshots(
            of: page(MovieRendering(progress: 0.42, remaining: 20, cover: nil, cancel: {}).background(ColorToken.canvas.color.ignoresSafeArea())),
            variants: [SnapshotVariant(.iPhone, .light)]
        )
    }

    /// F13.
    @Test func ready() {
        let render = MovieRender(relativePath: "derived/x.mp4", renderedAt: .now, duration: 64, resolution: .p1080, byteCount: 95_000_000)
        assertScreenSnapshots(
            of: page(MovieReady(title: "October 2026", render: render, url: URL(filePath: "/tmp/x.mp4"), cover: nil, done: {})
                .background(ColorToken.canvas.color.ignoresSafeArea())),
            variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark)]
        )
    }

    /// F14.
    @Test func failed() async throws {
        let model = MovieExportModel(project: try await project(), library: library, freeSpace: { 1000 })
        model.start()
        assertScreenSnapshots(
            of: page(MovieExportFailed(model: model, failure: .space(needed: 95_000_000), backToEditor: {})
                .background(ColorToken.canvas.color.ignoresSafeArea())),
            variants: [SnapshotVariant(.iPhone, .light)]
        )
    }

    /// F15.
    @Test func movie() async throws {
        let project = try await project()
        project.title = "September 2026"
        project.render = MovieRender(
            relativePath: "derived/x.mp4", renderedAt: Date(timeIntervalSince1970: 1_790_856_000), duration: 62, resolution: .p1080, byteCount: 1
        )
        let tiles = MemoriesModel(context: context, store: store, thumbnails: ThumbnailPipeline())
        if let id = MovieStore.liveClips(of: project).first?.moment?.id { await tiles.load(id) }
        assertScreenSnapshots(of: page(MoviePageView(project: project, library: library, tiles: tiles)), variants: variants)
    }
}
