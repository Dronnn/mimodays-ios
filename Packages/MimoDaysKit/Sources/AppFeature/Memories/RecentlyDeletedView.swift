import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI

/// M15: what deleting does, a note when a movie draft uses them, Delete, Cancel.
struct DeleteConfirmationSheet: View {
    let count: Int
    /// Only for one moment: its words name what goes.
    let mediaType: MediaType?
    let movieDrafts: Int
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if count == 1 {
                    Text("Delete this moment?", bundle: .module)
                } else {
                    Text("Delete these \(count) moments?", bundle: .module)
                }
            }
            .textStyle(.largeSheetTitle)
            .foregroundStyle(ColorToken.textPrimary.color)
            .accessibilityAddTraits(.isHeader)
            Group {
                switch (count, mediaType) {
                case (1, .video?):
                    Text("The video, selfie window, note and voice note move to Recently deleted. You can bring them back within 30 days.", bundle: .module)
                case (1, _):
                    Text("The photo, selfie window, note and voice note move to Recently deleted. You can bring them back within 30 days.", bundle: .module)
                default:
                    Text("They move to Recently deleted with their notes and voice notes. You can bring them back within 30 days.", bundle: .module)
                }
            }
            .textStyle(.sheetBody)
            .foregroundStyle(ColorToken.textBody.color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 10)
            if movieDrafts > 0 {
                HStack(spacing: 10) {
                    Icon.glyphFilm.image.resizable().scaledToFit().frame(width: 18, height: 16).accessibilityHidden(true)
                    Group {
                        if count == 1 {
                            Text("Used in \(movieDrafts) movie drafts. It will be skipped there.", bundle: .module)
                        } else {
                            Text("Used in \(movieDrafts) movie drafts. They will be skipped there.", bundle: .module)
                        }
                    }
                    .textStyle(.rowCaption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(ColorToken.textPrimary.color)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FieldBlob().fill(ColorToken.accentPeach.color))
                .padding(.top, 16)
            }
            Button {
                onDelete()
                dismiss()
            } label: {
                count == 1 ? Text("Delete moment", bundle: .module) : Text("Delete \(count) moments", bundle: .module)
            }
            .buttonStyle(.destructive)
            .padding(.top, 22)
            .accessibilityIdentifier("delete.confirm")
            Button { dismiss() } label: { Text("Cancel", bundle: .module) }
                .buttonStyle(.text)
                .padding(.top, 6)
                .accessibilityIdentifier("delete.cancel")
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 8)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height = $0 }
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(ColorToken.surfaceSheet.color)
    }

    @State private var height: CGFloat = 340
}

/// One moment in Recently deleted.
struct DeletedItem: Equatable, Identifiable {
    var item: MemoryItem
    var deletedAt: Date
    var thumbnailPath: String?

    var id: UUID { item.id }
}

/// M16/M16b: moments waiting 30 days before they go, newest deletion first.
@MainActor
@Observable
final class RecentlyDeletedModel {
    private(set) var items: [DeletedItem] = []
    private(set) var images: [UUID: UIImage] = [:]
    let library: MediaLibrary
    private let clock: any DateProvider

    init(library: MediaLibrary, clock: any DateProvider = SystemDateProvider()) {
        self.library = library
        self.clock = clock
    }

    var now: Date { clock.now() }
    var store: DeletionStore { DeletionStore(context: library.context, store: library.store, now: { [clock] in clock.now() }) }

    func refresh() {
        let descriptor = FetchDescriptor<Moment>(predicate: #Predicate { $0.deletedAt != nil }, sortBy: [SortDescriptor(\.deletedAt, order: .reverse)])
        items = ((try? library.context.fetch(descriptor)) ?? []).map {
            DeletedItem(
                item: MemoryItem(
                    id: $0.id, localDay: $0.localDay, capturedAt: $0.capturedAt, timeZoneID: $0.timeZoneID,
                    mediaType: $0.mediaType, origin: $0.origin, isFavorite: $0.isFavorite
                ),
                deletedAt: $0.deletedAt ?? .now,
                thumbnailPath: $0.media.first { $0.role == .thumbnail }?.relativePath
            )
        }
    }

    func load(_ item: DeletedItem, pixels: Int = MemoriesModel.tilePixels) async {
        guard images[item.id] == nil, let path = item.thumbnailPath, let url = try? library.store.url(for: path),
              let image = try? await library.thumbnails.thumbnail(for: url, maxPixelSize: pixels) else { return }
        images[item.id] = UIImage(cgImage: image)
    }

    func daysLeft(_ item: DeletedItem) -> Int { DeletionStore.daysLeft(deletedAt: item.deletedAt, now: now) }

    func recover(_ ids: Set<UUID>) { try? store.recover(ids) }
    func deleteForever(_ ids: Set<UUID>) { try? store.deleteForever(ids) }
}

struct RecentlyDeletedScreen: View {
    @Environment(\.mediaLibrary) private var library
    var body: some View {
        if let library { RecentlyDeletedHost(model: RecentlyDeletedModel(library: library)) }
    }
}

private struct RecentlyDeletedHost: View {
    @State var model: RecentlyDeletedModel
    var body: some View { RecentlyDeletedView(model: model) }
}

/// M16: the grid with days left on each tile; Delete all and Recover all at the bottom.
struct RecentlyDeletedView: View {
    let model: RecentlyDeletedModel
    @State private var confirmsDeleteAll = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Recently deleted", bundle: .module)
                    .textStyle(.displayTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                Text("Moments are deleted for good after 30 days. They are not shown anywhere else in the app.", bundle: .module)
                    .textStyle(.rowCaption)
                    .foregroundStyle(ColorToken.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 4)], spacing: 4) {
                    ForEach(model.items) { item in
                        NavigationLink(value: MemoriesRoute.deletedMoment(item.id)) {
                            MemoryTile(item: item.item, detail: nil, image: model.images[item.id])
                                .overlay(alignment: .bottomLeading) { DaysLeftBadge(days: model.daysLeft(item)).padding(7) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("deleted.tile")
                        .task { await model.load(item) }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
            }
            .padding(.bottom, 24)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !model.items.isEmpty {
                HStack {
                    Button { confirmsDeleteAll = true } label: {
                        Text("Delete all", bundle: .module).textStyle(.rowTitle).foregroundStyle(ColorToken.textLink.color)
                    }
                    .accessibilityIdentifier("deleted.deleteAll")
                    Spacer()
                    Button { model.recover(Set(model.items.map(\.id))) } label: {
                        Text("Recover all", bundle: .module).textStyle(.rowTitle).foregroundStyle(ColorToken.textPrimary.color)
                    }
                    .accessibilityIdentifier("deleted.recoverAll")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .frame(minHeight: 56)
                .background {
                    ColorToken.canvas.color
                        .overlay(alignment: .top) { ColorToken.separator.color.frame(height: 1) }
                        .ignoresSafeArea()
                }
            }
        }
        .navigationTitle(Text("Recently deleted", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in model.refresh() }
        .confirmationDialog(
            Text("Delete \(model.items.count) moments for good?", bundle: .module), isPresented: $confirmsDeleteAll, titleVisibility: .visible
        ) {
            Button(role: .destructive) { model.deleteForever(Set(model.items.map(\.id))) } label: { Text("Delete all", bundle: .module) }
        } message: {
            Text("This can't be undone.", bundle: .module)
        }
    }
}

/// "⏱ 12 days" on a dark pill.
struct DaysLeftBadge: View {
    let days: Int

    var body: some View {
        HStack(spacing: 4) {
            Icon.glyphClock.image.resizable().frame(width: 12, height: 12)
            Text("\(days) days", bundle: .module).textStyle(.tileBadge)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Capsule().fill(ColorToken.mediaScrim.color))
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Removed in \(days) days", bundle: .module))
    }
}

struct DeletedMomentScreen: View {
    let id: UUID
    @Environment(\.mediaLibrary) private var library
    var body: some View {
        if let library { DeletedMomentHost(model: RecentlyDeletedModel(library: library), id: id) }
    }
}

private struct DeletedMomentHost: View {
    @State var model: RecentlyDeletedModel
    let id: UUID
    var body: some View { DeletedMomentView(model: model, id: id) }
}

/// M16b: the moment, how long ago it was deleted and how long it stays, Recover or Delete now.
struct DeletedMomentView: View {
    let model: RecentlyDeletedModel
    let id: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDelete = false

    var body: some View {
        ScrollView {
            if let item = model.items.first(where: { $0.id == id }) {
                VStack(spacing: 0) {
                    Color(hex: 0x9C8573)
                        .overlay { if let image = model.images[id] { Image(uiImage: image).resizable().scaledToFill() } }
                        .aspectRatio(386 / 440, contentMode: .fit)
                        .clipShape(ViewerPhotoBlob())
                        .overlay(alignment: .bottomLeading) { DaysLeftBadge(days: model.daysLeft(item)).padding(16) }
                        .accessibilityElement()
                        .accessibilityLabel(item.item.mediaType == .video ? Text("Video", bundle: .module) : Text("Photo", bundle: .module))
                        .padding(.horizontal, 8)
                        .task { await model.load(item, pixels: MomentViewerModel.photoPixels) }
                    HStack(alignment: .top, spacing: 12) {
                        Icon.glyphClock.image.resizable().frame(width: 20, height: 20).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            let ago = DeletionStore.daysAgo(deletedAt: item.deletedAt, now: model.now)
                            ago == 0 ? Text("Deleted today.", bundle: .module) : Text("Deleted \(ago) days ago.", bundle: .module)
                            Text("Will be removed in \(model.daysLeft(item)) days.", bundle: .module)
                        }
                        .textStyle(.rowCaption)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(FieldBlob().fill(ColorToken.surfaceCard.color))
                    .accessibilityElement(children: .combine)
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    Button {
                        model.recover([id])
                        dismiss()
                    } label: { Text("Recover", bundle: .module) }
                    .buttonStyle(.primary)
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                    .accessibilityIdentifier("deleted.recover")
                    Button { confirmsDelete = true } label: { Text("Delete now", bundle: .module) }
                        .buttonStyle(.text)
                        .padding(.top, 8)
                        .accessibilityIdentifier("deleted.deleteNow")
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task { model.refresh() }
        .confirmationDialog(Text("Delete this moment for good?", bundle: .module), isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button(role: .destructive) {
                model.deleteForever([id])
                dismiss()
            } label: { Text("Delete now", bundle: .module) }
        } message: {
            Text("This can't be undone.", bundle: .module)
        }
    }
}
