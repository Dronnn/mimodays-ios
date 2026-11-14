import DesignSystem
import Persistence
import SwiftUI

/// `Editor / Timeline`: every clip as a 62×84 tile; the chosen one ringed in coral between apricot trim handles,
/// the playhead over the clip playing. Tap to choose, long-press and drag to move.
struct MovieTimeline: View {
    let model: MovieEditorModel
    /// The trim handles open Trim.
    let trim: () -> Void

    static let tile = CGSize(width: 62, height: 84)
    static let spacing: CGFloat = 4

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal) {
                HStack(spacing: Self.spacing) {
                    ForEach(Array(model.clips.enumerated()), id: \.element.persistentModelID) { index, clip in
                        tile(clip, index: index)
                            .id(index)
                    }
                }
                .padding(.horizontal, 16)
                // The playhead's knob stands 4 pt above the strip.
                .padding(.top, 14)
                .padding(.bottom, 10)
            }
            .scrollIndicators(.hidden)
            .onChange(of: model.selected) { _, index in
                withAnimation(.snappy) { reader.scrollTo(index, anchor: .center) }
            }
        }
        .frame(height: 108)
    }

    private func tile(_ clip: MovieClip, index: Int) -> some View {
        let isSelected = index == model.selected
        let id = clip.moment?.id
        return Color(hex: 0xC9B8AA)
            .overlay {
                if let id, let image = model.tiles.images[id] { Image(uiImage: image).filling() }
            }
            .frame(width: Self.tile.width, height: Self.tile.height)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay { if isSelected { selection } }
            .overlay(alignment: .topLeading) { playhead(index) }
            .contentShape(Rectangle())
            .onTapGesture { model.select(index) }
            .draggable(String(index)) {
                Color(hex: 0xC9B8AA)
                    .overlay { if let id, let image = model.tiles.images[id] { Image(uiImage: image).filling() } }
                    .frame(width: Self.tile.width, height: Self.tile.height)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .dropDestination(for: String.self) { items, _ in
                guard let source = items.first.flatMap(Int.init) else { return false }
                model.move(from: source, to: index)
                return true
            }
            .task(id: id) { if let id { await model.tiles.load(id) } }
            .accessibilityElement()
            .accessibilityLabel(label(index))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { model.select(index) }
            .accessibilityAction(named: Text("Move earlier", bundle: .module)) { model.move(from: index, to: index - 1) }
            .accessibilityAction(named: Text("Move later", bundle: .module)) { model.move(from: index, to: index + 1) }
            .accessibilityIdentifier("editor.clip")
    }

    /// The coral ring 3 pt outside the tile, and the apricot handles on its sides.
    private var selection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(ColorToken.actionCoral.color, lineWidth: 3)
                .padding(-3)
            HStack {
                handle.offset(x: -6)
                Spacer()
                handle.offset(x: 6)
            }
            .padding(.vertical, -3)
        }
        .onTapGesture(perform: trim)
    }

    private var handle: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color(hex: 0xF2A93B))
            .frame(width: 10)
            .overlay { Capsule().fill(ColorToken.surfaceCard.color).frame(width: 2, height: 22) }
    }

    /// The coral line and knob over the clip that's playing, as far into it as the movie is.
    @ViewBuilder
    private func playhead(_ index: Int) -> some View {
        if let playhead = model.playhead, playhead.index == index {
            ZStack(alignment: .top) {
                Capsule().fill(ColorToken.actionCoral.color).frame(width: 3, height: 104)
                Circle().fill(ColorToken.actionCoral.color).frame(width: 11, height: 11).offset(y: -4)
            }
            .offset(x: Self.tile.width * playhead.fraction - 1.5, y: -10)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func label(_ index: Int) -> Text {
        Text("Clip \(index + 1) of \(model.clips.count)", bundle: .module)
    }
}
