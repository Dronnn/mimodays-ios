import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI

struct CollectionsScreen: View {
    @Environment(\.mediaLibrary) private var library

    var body: some View {
        if let library { CollectionsHost(model: CollectionsModel(library: library)) }
    }
}

private struct CollectionsHost: View {
    @State var model: CollectionsModel
    var body: some View { CollectionsView(model: model) }
}

/// M11: every collection as a stacked cover with its name and count; + makes a new one (M11b).
/// Recently deleted joins with 9.11.
struct CollectionsView: View {
    let model: CollectionsModel
    @State private var makesNew = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Collections", bundle: .module)
                    .textStyle(.displayTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                if model.collections.isEmpty, model.isLoaded {
                    empty.padding(.top, 88)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8, alignment: .top)], spacing: 6) {
                        ForEach(model.collections) { collection in
                            NavigationLink(value: MemoriesRoute.collection(collection.id)) {
                                CollectionCard(summary: collection, cover: model.covers[collection.id])
                            }
                            .buttonStyle(.plain)
                            .task(id: collection.coverPath) { await model.loadCover(collection) }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .padding(.bottom, 24)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .navigationTitle(Text("Collections", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { makesNew = true } label: {
                    Icon.glyphPlus.image.foregroundStyle(ColorToken.textPrimary.color)
                }
                .accessibilityLabel(Text("New collection", bundle: .module))
                .accessibilityIdentifier("collections.new")
            }
        }
        .task { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in model.refresh() }
        .sheet(isPresented: $makesNew) {
            NewCollectionSheet { model.create($0) }
        }
    }

    private var empty: some View {
        VStack(spacing: 0) {
            ExplainerArt(glyph: .glyphCollection)
            Text("No collections yet", bundle: .module)
                .textStyle(.emptyTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
                .padding(.top, 16)
                .accessibilityAddTraits(.isHeader)
            Text("Group moments that belong together, like a trip or someone's firsts.", bundle: .module)
                .textStyle(.body)
                .foregroundStyle(ColorToken.textBody.color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .padding(.horizontal, 34)
            Button { makesNew = true } label: { Text("New collection", bundle: .module) }
                .buttonStyle(.primary)
                .padding(.horizontal, 20)
                .padding(.top, 21)
                .accessibilityIdentifier("collections.create")
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }
}

/// `Collection / Card`: the cover on a tilted card behind it, the name and how many moments.
struct CollectionCard: View {
    let summary: CollectionSummary
    let cover: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ZStack {
                // The card behind peeks out at the top right, as in M11.
                DayCardBlob()
                    .fill(ColorToken.textSecondary.color.opacity(0.2))
                    .padding(9)
                    .rotationEffect(.degrees(8))
                    .offset(x: 10, y: -9)
                Color(hex: 0xC9B8AA)
                    .overlay { if let cover { Image(uiImage: cover).resizable().scaledToFill() } }
                    .clipShape(DayCardBlob())
                    .rotationEffect(.degrees(-1.5))
            }
            .aspectRatio(1, contentMode: .fit)
            .padding(.bottom, 12)
            .accessibilityHidden(true)
            Text(summary.title)
                .textStyle(.rowTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
                .lineLimit(2)
            Text("\(summary.count) moments", bundle: .module)
                .textStyle(.rowCaption)
                .foregroundStyle(ColorToken.textSecondary.color)
        }
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("collections.card")
    }
}

/// M11b: a name, what a collection is, Create.
struct NewCollectionSheet: View {
    let onCreate: (String) -> Void
    @State private var title = ""
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New collection", bundle: .module)
                .textStyle(.sheetTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 4)
            TextField(text: $title) {
                Text("Name", bundle: .module).foregroundStyle(ColorToken.textTertiary.color)
            }
            .textStyle(.searchQuery)
            .foregroundStyle(ColorToken.textPrimary.color)
            .tint(ColorToken.actionCoral.color)
            .focused($isFocused)
            .submitLabel(.done)
            .onSubmit(create)
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .background(FieldBlob().fill(ColorToken.surfaceCard.color))
            .padding(.top, 16)
            .accessibilityLabel(Text("Name", bundle: .module))
            .accessibilityIdentifier("collection.name")
            Text("A collection only groups moments. Removing a moment from it, or deleting the collection, never deletes the moment.", bundle: .module)
                .textStyle(.rowCaption)
                .foregroundStyle(ColorToken.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
                .padding(.top, 12)
            Button(action: create) { Text("Create", bundle: .module) }
                .buttonStyle(.primary)
                .disabled(trimmed.isEmpty)
                .opacity(trimmed.isEmpty ? 0.5 : 1)
                .padding(.top, 28)
                .accessibilityIdentifier("collection.create")
        }
        .padding(.horizontal, 16)
        .padding(.top, 28)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(ColorToken.surfaceSheet.color)
        .onAppear { isFocused = true }
    }

    private var trimmed: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func create() {
        guard !trimmed.isEmpty else { return }
        onCreate(trimmed)
        dismiss()
    }
}

/// Edit moment's Collections (M07): tick the collections it belongs in, or make a new one. Kept on Save.
struct CollectionPickerSheet: View {
    let library: MediaLibrary
    @Binding var selection: Set<UUID>
    @State private var collections: [MomentCollection] = []
    @State private var makesNew = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Collections", bundle: .module)
                    .textStyle(.sheetTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button { dismiss() } label: {
                    Text("Done", bundle: .module)
                        .textStyle(.editorDone)
                        .foregroundStyle(ColorToken.textLink.color)
                        .frame(minHeight: Size.minimumTapTarget)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("collections.done")
            }
            .padding(.horizontal, 4)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(collections) { collection in
                        let isOn = selection.contains(collection.id)
                        Button {
                            if isOn { selection.remove(collection.id) } else { selection.insert(collection.id) }
                        } label: {
                            HStack(spacing: 14) {
                                Text(collection.title)
                                    .textStyle(.rowTitle)
                                    .foregroundStyle(ColorToken.textPrimary.color)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if isOn {
                                    Icon.glyphCheck.image.frame(width: 24, height: 24).foregroundStyle(ColorToken.textLink.color)
                                }
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 52)
                            .overlay(alignment: .bottom) { ColorToken.separator.color.frame(height: 1).padding(.leading, 16) }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                        .accessibilityIdentifier("collections.pick")
                    }
                    Button { makesNew = true } label: {
                        HStack(spacing: 10) {
                            Icon.glyphPlus.image.resizable().frame(width: 20, height: 20)
                            Text("New collection", bundle: .module).textStyle(.rowTitle)
                        }
                        .foregroundStyle(ColorToken.textLink.color)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("collections.newFromPicker")
                }
                .background(ColorToken.surfaceCard.color, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(ColorToken.surfaceSheet.color)
        .task { fetch() }
        .sheet(isPresented: $makesNew) {
            NewCollectionSheet { title in
                // The collection exists from now on; the moment joins it when the edit is saved.
                if let id = try? CollectionStore(context: library.context).create(title) {
                    selection.insert(id)
                    fetch()
                }
            }
        }
    }

    private func fetch() {
        collections = (try? library.context.fetch(FetchDescriptor<MomentCollection>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
    }
}
