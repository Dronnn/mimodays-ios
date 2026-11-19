@preconcurrency import AVFoundation
import DesignSystem
import SwiftUI

/// F10 from the editor: the movie as it stands, big; Edit goes back, Export goes on.
struct MoviePreviewView: View {
    let model: MovieEditorModel
    let export: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        MovieWatchView(player: model.player, close: { dismiss() }) {
            HStack(spacing: 12) {
                Button { dismiss() } label: { Text("Edit", bundle: .module) }
                    .buttonStyle(GlassButtonStyle())
                    .accessibilityIdentifier("preview.edit")
                Button(action: export) { Text("Export", bundle: .module) }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("preview.export")
            }
            .padding(.horizontal, 20)
        }
        .onAppear { model.player.play() }
        .onDisappear { model.caughtUp() }
    }
}

extension MovieEditorModel {
    /// The preview played the same player; the editor picks up where it stopped.
    func caughtUp() {
        pause()
        seek(to: player.currentTime().seconds.isFinite ? player.currentTime().seconds : time)
    }
}

/// F10's frame: the movie fitted to the screen on plum, × top left, the scrubber with its times, play or pause,
/// and whatever buttons go at the bottom. Also plays a rendered movie (F15).
struct MovieWatchView<Actions: View>: View {
    let player: AVPlayer
    let close: () -> Void
    @ViewBuilder let actions: Actions
    @State private var time = 0.0
    @State private var length = 0.0
    @State private var isPlaying = false
    @State private var scrubbing = false
    @State private var observer: Any?

    var body: some View {
        ZStack {
            Color(hex: 0x2A1B21).ignoresSafeArea()
            MoviePlayerSurface(player: player)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            LinearGradient(colors: [.clear, Color(hex: 0x2A1B21).opacity(0.7)], startPoint: .center, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack(spacing: 0) {
                HStack {
                    Button(action: close) {
                        Icon.glyphClose.image
                            .resizable()
                            .frame(width: 24, height: 24)
                            .foregroundStyle(ColorToken.mediaFrame.color)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color(hex: 0x2A1B21).opacity(0.42)))
                            .frame(width: Size.minimumTapTarget, height: Size.minimumTapTarget)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Close", bundle: .module))
                    .accessibilityIdentifier("preview.close")
                    .padding(.leading, 14)
                    Spacer()
                }
                .padding(.top, 4)
                Spacer()
                scrubber
                    .padding(.horizontal, 16)
                Button(action: toggle) {
                    (isPlaying ? Icon.glyphPause : Icon.glyphPlay).image
                        .resizable()
                        .frame(width: 36, height: 36)
                        .foregroundStyle(ColorToken.mediaFrame.color)
                        .frame(width: Size.minimumTapTarget, height: Size.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? Text("Pause", bundle: .module) : Text("Play", bundle: .module))
                .accessibilityIdentifier("preview.play")
                .padding(.top, 8)
                actions
                    .padding(.top, 20)
                    .padding(.bottom, 14)
            }
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden(false)
        .onAppear(perform: observe)
        .onDisappear {
            if let observer { player.removeTimeObserver(observer) }
            observer = nil
        }
    }

    /// `Scrub`: a cream line on a faint track with a knob; the time so far and the whole length under it.
    private var scrubber: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let fraction = length > 0 ? min(max(time / length, 0), 1) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(ColorToken.mediaFrame.color.opacity(0.3)).frame(height: 4)
                    Capsule().fill(ColorToken.mediaFrame.color).frame(width: width * fraction, height: 4)
                    Circle().fill(ColorToken.mediaFrame.color).frame(width: 16, height: 16).offset(x: width * fraction - 8)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            scrubbing = true
                            time = min(max(drag.location.x / width, 0), 1) * length
                            player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                        }
                        .onEnded { _ in scrubbing = false }
                )
            }
            // Touched across 44 pt; laid out in 16.
            .frame(height: 44)
            .padding(.vertical, -14)
            .accessibilityElement()
            .accessibilityLabel(Text("Position", bundle: .module))
            .accessibilityValue(Text(MovieEditorView.clock(time)))
            .accessibilityAdjustableAction { direction in
                time = min(max(time + (direction == .increment ? 5 : -5), 0), length)
                player.seek(to: CMTime(seconds: time, preferredTimescale: 600))
            }
            HStack {
                Text(MovieEditorView.clock(time))
                Spacer()
                Text(MovieEditorView.clock(length))
            }
            .textStyle(.scrubTime)
            .monospacedDigit()
            .foregroundStyle(ColorToken.mediaFrame.color)
            .accessibilityHidden(true)
        }
        // Left to right in every language, so the fill, the knob, a touch and the times under them agree.
        .environment(\.layoutDirection, .leftToRight)
    }

    private func toggle() {
        if isPlaying {
            player.pause()
        } else {
            if length > 0, time >= length - 0.05 { player.seek(to: .zero) }
            player.play()
        }
    }

    private func observe() {
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [player] now in
            MainActor.assumeIsolated {
                if !scrubbing, now.seconds.isFinite { time = now.seconds }
                isPlaying = player.rate != 0
                if let duration = player.currentItem?.duration.seconds, duration.isFinite { length = duration }
            }
        }
    }
}

/// `Button / Glass`: cream words on a faint cream hand-cut shape, over a movie.
struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textStyle(.buttonPrimary)
            .foregroundStyle(ColorToken.mediaFrame.color)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background { ColorToken.mediaFrame.color.opacity(0.2).mask { Icon.shapeButton.image.resizable() } }
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }
}
