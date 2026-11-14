import DesignSystem
import Persistence
import SwiftUI

/// M13's top bar while selecting: Cancel, "N selected", Select all (Deselect all once everything is ticked).
/// Memories, Favorites and Recently deleted share it.
struct SelectBar: View {
    @Binding var selection: Set<UUID>?
    /// Every moment the screen shows, in order.
    let all: [UUID]

    var body: some View {
        let chosen = selection ?? []
        let isAll = !all.isEmpty && chosen.count == all.count
        ZStack {
            Group {
                if chosen.isEmpty {
                    Text("Select moments", bundle: .module)
                } else {
                    Text("\(chosen.count) selected", bundle: .module)
                }
            }
            .textStyle(.editorTitle)
            .foregroundStyle(ColorToken.textPrimary.color)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("select.count")
            HStack {
                Button { selection = nil } label: {
                    Text("Cancel", bundle: .module).textStyle(.editorCancel).foregroundStyle(ColorToken.textPrimary.color)
                }
                .accessibilityIdentifier("select.cancel")
                Spacer()
                Button { selection = isAll ? [] : Set(all) } label: {
                    (isAll ? Text("Deselect all", bundle: .module) : Text("Select all", bundle: .module))
                        .textStyle(.editorDone).foregroundStyle(ColorToken.textLink.color)
                }
                .accessibilityIdentifier("select.all")
            }
            .buttonStyle(.plain)
            .frame(minHeight: Size.minimumTapTarget)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
        .background(ColorToken.canvas.color.ignoresSafeArea())
    }
}

/// "Select" in coral, which starts selecting (M01, M10, M16).
struct SelectButton: View {
    @Binding var selection: Set<UUID>?
    let id: String

    var body: some View {
        Button { selection = [] } label: {
            Text("Select", bundle: .module)
                .textStyle(.control)
                .foregroundStyle(ColorToken.textLink.color)
                .frame(minHeight: Size.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/// A selectable tile: the tile with M13's circle; a tap ticks it.
struct SelectableTile<Tile: View>: View {
    @Binding var selection: Set<UUID>?
    let id: UUID
    @ViewBuilder let tile: () -> Tile

    var body: some View {
        let isOn = selection?.contains(id) == true
        Button {
            guard var chosen = selection else { return }
            if chosen.remove(id) == nil { chosen.insert(id) }
            selection = chosen
        } label: {
            tile().overlay { SelectionMark(isOn: isOn) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The bar under a selection: a hairline on top, the screen's own actions, dimmed until something is ticked.
struct SelectActionsBar<Actions: View>: View {
    var isEnabled = true
    let inset: CGFloat
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack { actions() }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.4)
            .padding(.horizontal, inset)
            .frame(minHeight: 56)
            .background {
                ColorToken.canvas.color
                    .overlay(alignment: .top) { ColorToken.separator.color.frame(height: 1) }
                    .ignoresSafeArea()
            }
    }
}

extension View {
    /// M13's Collect, Movie and Delete under a selection of moments, with their sheets (Memories, Favorites).
    func memoriesSelectActions(model: MemoriesModel, selection: Binding<Set<UUID>?>) -> some View {
        modifier(MemoriesSelectActions(model: model, selection: selection))
    }
}

private struct MemoriesSelectActions: ViewModifier {
    let model: MemoriesModel
    @Binding var selection: Set<UUID>?
    @Environment(AppRouter.self) private var router
    @State private var confirmsDelete = false
    @State private var collects = false
    @State private var collections: Set<UUID> = []

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let chosen = selection {
                    // Both wait for a tick.
                    SelectActionsBar(isEnabled: !chosen.isEmpty, inset: 28) {
                        Button { collects = true } label: { action(.glyphCollection, Text("Collect", bundle: .module)) }
                            .accessibilityIdentifier("select.collect")
                        Spacer()
                        Button {
                            router.open(.newMovie(MovieSourceRule(kind: .selection, momentIDs: Array(chosen))))
                            selection = nil
                        } label: { action(.glyphFilm, Text("Movie", bundle: .module)) }
                            .accessibilityIdentifier("select.movie")
                        Spacer()
                        Button { confirmsDelete = true } label: { action(.glyphTrash, Text("Delete", bundle: .module)) }
                            .accessibilityIdentifier("select.delete")
                    }
                }
            }
            .sheet(isPresented: $confirmsDelete) {
                let chosen = selection ?? []
                DeleteConfirmationSheet(
                    count: chosen.count, mediaType: model.mediaType(of: chosen), movieDrafts: model.movieDrafts(using: chosen)
                ) {
                    if model.delete(chosen) { selection = nil }
                }
            }
            .sheet(isPresented: $collects, onDismiss: {
                guard let chosen = selection, !collections.isEmpty else { return }
                model.collect(chosen, into: collections)
                collections = []
                selection = nil
            }) {
                CollectionPickerSheet(library: model.library, selection: $collections)
            }
    }

    private func action(_ icon: Icon, _ title: Text) -> some View {
        VStack(spacing: 2) {
            icon.image.resizable().scaledToFit().frame(width: 24, height: 24).accessibilityHidden(true)
            title.textStyle(.tileBadge)
        }
        .foregroundStyle(ColorToken.textPrimary.color)
        .frame(minWidth: Size.minimumTapTarget, minHeight: Size.minimumTapTarget)
        .contentShape(Rectangle())
    }
}
