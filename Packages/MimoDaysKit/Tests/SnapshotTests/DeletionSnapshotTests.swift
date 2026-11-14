@testable import AppFeature
@testable import Core
import DesignSystem
import Foundation
import Persistence
import SwiftData
import SwiftUI
import Testing
import TestSupport

/// Delete (M15), Recently deleted (M16) and one deleted moment (M16b).
@MainActor
@Suite(.tags(.snapshot))
struct DeletionSnapshotTests {
    private let container = try! MimoDaysStore.makeContainer(inMemory: true)
    private let store: MediaStore
    private static let now = Date(timeIntervalSince1970: 1_794_422_520)

    /// The view's `.task` can still run after a test returns; its store must outlive the test.
    private static var stores: [ModelContainer] = []

    init() throws {
        store = try MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "DeletionSnapshots-\(UUID().uuidString)"))
        Self.stores.append(container)
    }

    private var library: MediaLibrary { MediaLibrary(context: container.mainContext, store: store, thumbnails: ThumbnailPipeline()) }

    /// Moments deleted 2, 5, 9… days ago.
    private func deleted(_ count: Int) async throws -> RecentlyDeletedModel {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let saver = MomentSaver(context: container.mainContext, store: store, clock: TestDateProvider(), freeBytes: { nil })
        for index in 0..<count {
            let capture = CaptureResult(
                media: .photo(try await engine.capturePhoto(flash: false, silent: true)), window: .init(),
                capturedAt: CaptureTime(instant: Self.now.addingTimeInterval(-Double(index + 20) * 86_400), timeZone: .gmt)
            )
            let draft = MomentDraft(
                capture: capture, caption: "",
                window: SelfieWindowFrame(frame: CGRect(x: 266.7, y: 111.1, width: 112, height: 150), preview: CGSize(width: 402, height: 536)),
                promptID: nil
            )
            let id = try await saver.save(draft).id
            let deletedAt = Self.now.addingTimeInterval(-Double(2 + index * 3) * 86_400 - 3_600)
            try DeletionStore(context: container.mainContext, store: store, now: { deletedAt }).moveToRecentlyDeleted([id])
        }
        let model = RecentlyDeletedModel(library: library, clock: TestDateProvider(Self.now))
        model.refresh()
        for item in model.items { await model.load(item) }
        return model
    }

    /// M15, for a photo used in two movie drafts.
    @Test func sheet() {
        assertScreenSnapshots(
            of: DeleteConfirmationSheet(count: 1, mediaType: .photo, movieDrafts: 2) {}.background(ColorToken.surfaceSheet.color.ignoresSafeArea()),
            variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge)]
        )
    }

    @Test func sheetForSeveral() {
        assertScreenSnapshots(
            of: DeleteConfirmationSheet(count: 4, mediaType: nil, movieDrafts: 0) {}.background(ColorToken.surfaceSheet.color.ignoresSafeArea()),
            variants: [SnapshotVariant(.iPhone, .light)]
        )
    }

    /// M16.
    @Test func recentlyDeleted() async throws {
        let model = try await deleted(7)
        assertScreenSnapshots(of: NavigationStack { RecentlyDeletedView(model: model) }, variants: [
            SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge),
            SnapshotVariant(.iPhone, .light, rightToLeft: true),
        ])
    }

    /// M16b.
    @Test func deletedMoment() async throws {
        let model = try await deleted(1)
        let id = try #require(model.items.first?.id)
        await model.load(model.items[0], pixels: MomentViewerModel.photoPixels)
        assertScreenSnapshots(of: NavigationStack { DeletedMomentView(model: model, id: id) }, variants: [
            SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge),
        ])
    }
}
