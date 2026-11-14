import Core
import DesignSystem
import SwiftUI

/// Screens only Memories opens; they share its moments and tiles.
enum MemoriesTabRoute: Hashable {
    /// M10.
    case favorites
}

/// M10/M10e: every favourite, newest first, in the timeline's tiles. Taking the heart off in the viewer takes it
/// off here too. Select works as in M13.
struct FavoritesView: View {
    let model: MemoriesModel
    /// The moments ticked while selecting; nil when not selecting.
    @State private var selection: Set<UUID>?

    init(model: MemoriesModel, selection: Set<UUID>? = nil) {
        self.model = model
        _selection = State(initialValue: selection)
    }

    var body: some View {
        let favorites = model.favorites
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Favorites", bundle: .module)
                    .textStyle(.displayTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                if favorites.isEmpty, model.isLoaded {
                    empty
                        .padding(.top, 88)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 4)], spacing: 4) {
                        ForEach(favorites) { item in
                            Group {
                                if selection != nil {
                                    SelectableTile(selection: $selection, id: item.id) {
                                        MemoryTile(item: item, detail: model.details[item.id], image: model.images[item.id], leavesRoomForMark: true)
                                    }
                                } else {
                                    NavigationLink(value: MemoriesRoute.moment(MomentPager(ids: favorites.map(\.id), start: item.id))) {
                                        MemoryTile(item: item, detail: model.details[item.id], image: model.images[item.id])
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .task { await model.load(item.id) }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                }
            }
            .padding(.bottom, 24)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .navigationTitle(Text("Favorites", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        // The big title in the page says it; the bar keeps only the way back.
        .toolbar(removing: .title)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(selection == nil ? .automatic : .hidden, for: .navigationBar)
        .toolbar {
            if !favorites.isEmpty, selection == nil {
                ToolbarItem(placement: .topBarTrailing) { SelectButton(selection: $selection, id: "favorites.select") }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if selection != nil { SelectBar(selection: $selection, all: favorites.map(\.id)) }
        }
        .memoriesSelectActions(model: model, selection: $selection)
    }

    /// M10e.
    private var empty: some View {
        VStack(spacing: 0) {
            ExplainerArt(glyph: .explainerHeart)
            Text("No favorites yet", bundle: .module)
                .textStyle(.emptyTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
                .padding(.top, 16)
                .accessibilityAddTraits(.isHeader)
            Text("Tap the heart on any moment to keep it here.", bundle: .module)
                .textStyle(.emptyBody)
                .foregroundStyle(ColorToken.textBody.color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .padding(.horizontal, 34)
        }
        .frame(maxWidth: .infinity)
    }
}
