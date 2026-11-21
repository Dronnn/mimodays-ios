import AVFoundation
import DesignSystem
import SwiftUI

/// P8.6: "LIVE" over a Live Photo's tile or card; said as "Live Photo".
struct LiveBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .strokeBorder(.white, style: StrokeStyle(lineWidth: 1.4, dash: [1.6, 1.4]))
                .frame(width: 11, height: 11)
            Text(verbatim: "LIVE")
                .textStyle(.tileBadge)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(Capsule().fill(ColorToken.mediaScrim.color))
        .accessibilityElement()
        .accessibilityLabel(Text("Live Photo", bundle: .module))
    }
}

/// EE06: on a Live Photo's card the still shows first; Play Live Photo plays its motion once with its sound, Stop
/// Live Photo (or the end, another card, the back) brings the still back. Motion that's gone says so in its place.
struct LivePhotoPlayback: View {
    /// The motion file; nil when it's gone.
    let url: URL?
    let isCurrent: Bool
    @State private var player: AVPlayer?
    @State private var ended: (any NSObjectProtocol)?

    var body: some View {
        ZStack {
            if let player {
                PlayerLayerView(player: player)
                    .clipShape(MemoryCardOutline())
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            if url == nil {
                Text("Motion unavailable", bundle: .module)
                    .textStyle(.rowCaption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .background(Capsule().fill(ColorToken.mediaScrim.color))
                    .accessibilityIdentifier("card.livePhotoUnavailable")
            } else {
                button
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            LiveBadge().padding(.top, 22).padding(.leading, 22)
        }
        .environment(\.layoutDirection, .leftToRight)
        .onChange(of: isCurrent) { _, current in if !current { stop() } }
        .onDisappear { stop() }
    }

    private var button: some View {
        Button { player == nil ? play() : stop() } label: {
            VStack(spacing: 8) {
                (player == nil ? Icon.glyphPlay : .glyphPause).image
                    .resizable()
                    .frame(width: 26, height: 26)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(.white))
                    .padding(10)
                    .background(Circle().fill(ColorToken.mediaScrim.color))
                Group {
                    if player == nil { Text("Play Live Photo", bundle: .module) } else { Text("Stop Live Photo", bundle: .module) }
                }
                .textStyle(.rowCaption)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            }
            .opacity(player == nil ? 1 : 0.85)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(player == nil ? [] : .isSelected)
        .accessibilityIdentifier("card.livePhotoPlay")
    }

    private func play() {
        guard let url else { return }
        let player = AVPlayer(url: url)
        ended = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: player.currentItem, queue: .main
        ) { _ in MainActor.assumeIsolated { stop() } }
        self.player = player
        player.play()
    }

    private func stop() {
        player?.pause()
        player = nil
        if let ended { NotificationCenter.default.removeObserver(ended) }
        ended = nil
    }
}

/// A small hand-cut chip button (EE05's Try again, Import as still, Skip, Keep motion).
struct ChipButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textStyle(.rowCaption)
            .fontWeight(.semibold)
            .foregroundStyle(ColorToken.textPrimary.color)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(ReviewChipBlob().fill(ColorToken.surfaceChip.color))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
            .contentShape(Rectangle())
    }
}
