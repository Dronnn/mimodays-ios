import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI

struct CollectionScreen: View {
    let id: UUID
    @Environment(\.mediaLibrary) private var library

    var body: some View {
        if let library { CollectionHost(model: CollectionModel(id: id, library: library)) }
    }
}

private struct CollectionHost: View {
    @State var model: CollectionModel
    var body: some View { CollectionView(model: model) }
}

/// M12: the cover, the name, how many moments and when, Add moments, then its moments oldest first.
/// ••• renames or deletes it; a long press takes one moment out. Make a movie joins with Movies (Phase 11).
struct CollectionView: View {
    let model: CollectionModel
    @Environment(\.dismiss) private var dismiss
    @State private var adds = false
    @State private var renames = false
    @State private var newTitle = ""
    @State private var confirmsDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Color(hex: 0x9C8573)
                    .overlay { if let cover = model.cover { Image(uiImage: cover).resizable().scaledToFill() } }
                    .frame(height: 190)
                    .clipShape(DayCardBlob())
                    .padding(.horizontal, 16)
                    .accessibilityHidden(true)
                Text(model.title)
                    .textStyle(.displayTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                subtitle
                    .textStyle(.rowCaption)
                    .foregroundStyle(ColorToken.textSecondary.color)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                Button { adds = true } label: {
                    Label { Text("Add moments", bundle: .module) } icon: { Icon.glyphPlus.image.resizable().frame(width: 18, height: 18) }
                }
                .buttonStyle(SoftButtonStyle())
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .accessibilityIdentifier("collection.add")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 4)], spacing: 4) {
                    ForEach(model.items) { item in
                        NavigationLink(value: MemoriesRoute.moment(MomentPager(ids: model.items.map(\.id), start: item.id))) {
                            MemoryTile(item: item, detail: model.details[item.id], image: model.images[item.id])
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) { model.remove(item.id) } label: {
                                Label { Text("Remove from collection", bundle: .module) } icon: { Icon.glyphClose.image }
                            }
                        }
                        .task { await model.load(item.id) }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .padding(.bottom, 24)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .navigationTitle(Text(model.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        newTitle = model.title
                        renames = true
                    } label: { Text("Rename", bundle: .module) }
                    Button(role: .destructive) { confirmsDelete = true } label: { Text("Delete collection", bundle: .module) }
                } label: {
                    Icon.glyphMore.image.foregroundStyle(ColorToken.textPrimary.color)
                }
                .accessibilityLabel(Text("More", bundle: .module))
                .accessibilityIdentifier("collection.more")
            }
        }
        .task {
            model.refresh()
            await model.loadCover()
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            model.refresh()
            Task { await model.loadCover() }
        }
        .onChange(of: model.exists) { if !model.exists { dismiss() } }
        .sheet(isPresented: $adds) {
            AddMomentsSheet(library: model.library, excluded: Set(model.items.map(\.id))) { model.add($0) }
        }
        .alert(Text("Rename collection", bundle: .module), isPresented: $renames) {
            TextField(text: $newTitle) { Text("Name", bundle: .module) }
            Button { model.rename(newTitle) } label: { Text("Save", bundle: .module) }
            Button(role: .cancel) {} label: { Text("Cancel", bundle: .module) }
        }
        .confirmationDialog(
            Text("Delete “\(model.title)”?", bundle: .module), isPresented: $confirmsDelete, titleVisibility: .visible
        ) {
            Button(role: .destructive) { model.delete() } label: { Text("Delete collection", bundle: .module) }
        } message: {
            Text("Its moments stay in Memories.", bundle: .module)
        }
    }

    /// "24 moments · Mar – Nov 2026".
    private var subtitle: Text {
        let count = Text("\(model.items.count) moments", bundle: .module)
        guard let span = model.span else { return count }
        let first = MemoriesView.dayDate(span.first)
        let last = MemoriesView.dayDate(span.last)
        let months = span.first / 100 == span.last / 100
            ? Text(first, format: Date.FormatStyle(timeZone: .gmt).month(.abbreviated).year())
            : Text(first..<last, format: Date.IntervalFormatStyle(timeZone: .gmt).month(.abbreviated).year())
        return Text("Collection detail: \(count) · \(months)", bundle: .module)
    }
}

/// Every moment not in the collection yet, newest first; tap to choose, then Add.
struct AddMomentsSheet: View {
    let library: MediaLibrary
    let excluded: Set<UUID>
    let onAdd: ([UUID]) -> Void
    @State private var items: [MemoryItem] = []
    @State private var images: [UUID: UIImage] = [:]
    @State private var chosen: [UUID] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 4)], spacing: 4) {
                    ForEach(items) { item in
                        Button { toggle(item.id) } label: {
                            MemoryTile(item: item, detail: nil, image: images[item.id])
                                .overlay(alignment: .bottomTrailing) { tick(chosen.contains(item.id)) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(chosen.contains(item.id) ? .isSelected : [])
                        .task { await load(item.id) }
                    }
                }
                .padding(16)
            }
            .background(ColorToken.surfaceSheet.color.ignoresSafeArea())
            .navigationTitle(Text("Add moments", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", bundle: .module) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onAdd(chosen)
                        dismiss()
                    } label: { Text("Add", bundle: .module) }
                    .disabled(chosen.isEmpty)
                    .accessibilityIdentifier("addMoments.add")
                }
            }
        }
        .tint(ColorToken.textLink.color)
        .task { fetch() }
    }

    private func tick(_ isOn: Bool) -> some View {
        ZStack {
            Circle().fill(isOn ? ColorToken.actionCoral.color : ColorToken.mediaScrim.color)
            Circle().strokeBorder(ColorToken.mediaFrame.color, lineWidth: 2)
            if isOn { Icon.glyphCheck.image.resizable().frame(width: 16, height: 16).foregroundStyle(ColorToken.mediaFrame.color) }
        }
        .frame(width: 26, height: 26)
        .padding(7)
        .accessibilityHidden(true)
    }

    private func toggle(_ id: UUID) {
        if let index = chosen.firstIndex(of: id) { chosen.remove(at: index) } else { chosen.append(id) }
    }

    private func fetch() {
        var descriptor = FetchDescriptor<Moment>(predicate: #Predicate { $0.deletedAt == nil }, sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        descriptor.propertiesToFetch = [\.id, \.localDay, \.capturedAt, \.timeZoneID, \.mediaTypeRaw, \.originRaw, \.isFavorite]
        items = ((try? library.context.fetch(descriptor)) ?? []).filter { !excluded.contains($0.id) }.map {
            MemoryItem(
                id: $0.id, localDay: $0.localDay, capturedAt: $0.capturedAt, timeZoneID: $0.timeZoneID,
                mediaType: $0.mediaType, origin: $0.origin, isFavorite: $0.isFavorite
            )
        }
    }

    private func load(_ id: UUID) async {
        guard images[id] == nil else { return }
        var descriptor = FetchDescriptor<Moment>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let path = (try? library.context.fetch(descriptor).first)?.media.first(where: { $0.role == .thumbnail })?.relativePath,
              let url = try? library.store.url(for: path),
              let image = try? await library.thumbnails.thumbnail(for: url, maxPixelSize: MemoriesModel.tilePixels) else { return }
        images[id] = UIImage(cgImage: image)
    }
}
