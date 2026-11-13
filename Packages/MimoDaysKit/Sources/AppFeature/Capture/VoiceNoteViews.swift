import Core
import DesignSystem
import SwiftUI

/// C09 while it records: up to a minute, one bar per 1/54 of it. It stops on a tap, at the limit, when the sheet is
/// swiped away, or when something interrupts (a call); what was recorded is kept every time.
@MainActor
@Observable
final class VoiceRecording: Identifiable {
    static let bars = 54

    let url: URL
    let limit: TimeInterval
    let startedAt = Date()
    var elapsed: TimeInterval = 0
    /// One level (0...1) per bar recorded so far, the loudest moment in it.
    var levels: [Float] = []
    private(set) var isFinished = false
    private let recorder: any VoiceRecorder

    init(recorder: any VoiceRecorder, url: URL, limit: TimeInterval) {
        self.recorder = recorder
        self.url = url
        self.limit = limit
    }

    /// False when the microphone can't start.
    func start() -> Bool {
        (try? recorder.start(to: url, limit: limit)) != nil
    }

    /// Follows the recorder until it stops.
    func run() async {
        while !isFinished, !Task.isCancelled {
            tick()
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    func tick() {
        guard !isFinished else { return }
        elapsed = recorder.elapsed
        let bar = min(Self.bars, Int(elapsed / limit * Double(Self.bars)) + 1)
        while levels.count < bar { levels.append(0) }
        levels[bar - 1] = max(levels[bar - 1], recorder.level)
        if !recorder.isRecording { finish() }
    }

    func finish() {
        guard !isFinished else { return }
        recorder.stop()
        elapsed = recorder.elapsed
        isFinished = true
    }
}

/// `Sheet / Voice note` (C09): title, the minute as bars (coral so far), "0:12 / 1:00", the coral stop button.
struct VoiceRecordingSheet: View {
    let recording: VoiceRecording
    /// Once, when the sheet goes away for any reason.
    let onFinish: (VoiceRecording) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var height: CGFloat = 293

    var body: some View {
        VStack(spacing: 0) {
            Text("Voice note", bundle: .module)
                .textStyle(.sheetTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
            WaveformBars(
                levels: recording.levels, count: VoiceRecording.bars, filled: recording.levels.count,
                minHeight: 6, maxHeight: 47, rest: ColorToken.textPrimary.color.opacity(0.28)
            )
            .frame(height: 48)
            .padding(.horizontal, 42)
            .padding(.top, 29)
            .accessibilityHidden(true)
            Text(verbatim: "\(Self.clock(recording.elapsed)) / \(Self.clock(recording.limit))")
                .textStyle(.voiceTimer)
                .monospacedDigit()
                .foregroundStyle(ColorToken.textPrimary.color)
                .padding(.top, 22)
                .accessibilityHidden(true)
            Button {
                dismiss()
            } label: {
                RoundedRectangle(cornerRadius: 6)
                    .fill(ColorToken.textOnCoral.color)
                    .frame(width: 24, height: 24)
                    .frame(width: 80, height: 80)
                    .background(Circle().fill(ColorToken.actionCoral.color).shadow(color: ColorToken.textLink.color.opacity(0.3), radius: 6, y: 4))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            .accessibilityLabel(Text("Stop recording", bundle: .module))
            .accessibilityValue(Text("\(Self.spoken(recording.elapsed)) of \(Self.spoken(recording.limit))", bundle: .module))
            .accessibilityIdentifier("voice.stop")
            Text("Tap to stop", bundle: .module)
                .textStyle(.voiceHint)
                .foregroundStyle(ColorToken.textBody.color)
                .padding(.top, 10)
                .accessibilityHidden(true)
        }
        .padding(.top, 24)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height = $0 }
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(ColorToken.surfaceSheet.color)
        .task {
            await recording.run()
            dismiss()
        }
        .onDisappear {
            recording.finish()
            onFinish(recording)
        }
    }

    /// "0:12".
    static func clock(_ seconds: TimeInterval) -> String {
        Duration.seconds(Int(seconds.rounded(.down))).formatted(.time(pattern: .minuteSecond))
    }

    /// "12 seconds", "1 minute".
    static func spoken(_ seconds: TimeInterval) -> String {
        Duration.seconds(Int(seconds.rounded(.down))).formatted(.units(allowed: [.minutes, .seconds], width: .wide))
    }
}

/// `Review / Voice card` (C10): play, the waveform (coral as it plays), length, remove; the transcript under it.
struct VoiceNoteCard: View {
    let model: ReviewModel
    let voice: ReviewVoiceNote

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                playButton
                TimelineView(.animation(paused: !model.playsVoice)) { _ in
                    WaveformBars(
                        levels: model.voiceLevels, count: ReviewModel.voiceBars,
                        filled: Int(model.voiceProgress * Double(ReviewModel.voiceBars)),
                        minHeight: 4, maxHeight: 22, rest: ColorToken.textPrimary.color
                    )
                }
                .frame(height: 22)
                .padding(.leading, 12)
                .accessibilityHidden(true)
                Text(verbatim: VoiceRecordingSheet.clock(voice.duration.rounded()))
                    .textStyle(.reviewChip)
                    .monospacedDigit()
                    .foregroundStyle(ColorToken.textBody.color)
                    .padding(.leading, 7)
                    .accessibilityHidden(true)
                Button { model.removeVoice() } label: {
                    Icon.glyphTrash.image
                        .frame(width: 24, height: 24)
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .frame(width: Size.minimumTapTarget, height: Size.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, -10)
                .accessibilityLabel(Text("Remove voice note", bundle: .module))
                .accessibilityIdentifier("review.voice.remove")
            }
            .padding(.top, 14)
            if let transcript = voice.transcript {
                Text("Transcript in quotes: \(transcript)", bundle: .module)
                    .textStyle(.reviewField)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .lineLimit(1)
                    .padding(.leading, 2)
                    .padding(.top, 12)
                    .accessibilityIdentifier("review.voice.transcript")
                Text("Transcribed on this iPhone", bundle: .module)
                    .textStyle(.voiceCredit)
                    .foregroundStyle(ColorToken.textTertiary.color)
                    .padding(.leading, 2)
                    .padding(.top, 10)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.bottom, voice.transcript == nil ? 14 : 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            VoiceCardBlob()
                .fill(ColorToken.surfaceCard.color)
                .shadow(color: CameraPalette.chipText.opacity(0.08), radius: 2, y: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review.voice")
    }

    /// 36 pt coral disc; a play triangle, or two bars while it plays.
    private var playButton: some View {
        Button { model.toggleVoice() } label: {
            Group {
                if model.playsVoice {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1.5).frame(width: 3.5, height: 12)
                        RoundedRectangle(cornerRadius: 1.5).frame(width: 3.5, height: 12)
                    }
                } else {
                    Icon.glyphPlay.image.frame(width: 20, height: 20)
                }
            }
            .foregroundStyle(ColorToken.textOnCoral.color)
            .frame(width: 36, height: 36)
            .background(Circle().fill(ColorToken.actionCoral.color))
            .frame(width: Size.minimumTapTarget, height: Size.minimumTapTarget)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -4)
        .accessibilityLabel(model.playsVoice ? Text("Pause voice note", bundle: .module) : Text("Play voice note", bundle: .module))
        .accessibilityValue(Text(verbatim: VoiceRecordingSheet.spoken(voice.duration.rounded())))
        .accessibilityIdentifier("review.voice.play")
    }
}

/// 3 pt rounded bars spread evenly across the width; the first `filled` in coral. Bars past `levels` stay flat.
struct WaveformBars: View {
    let levels: [Float]
    let count: Int
    let filled: Int
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let rest: Color

    var body: some View {
        let accent = ColorToken.actionCoral.color
        Canvas { context, size in
            let step = size.width / CGFloat(count)
            for index in 0 ..< count {
                let level = index < levels.count ? CGFloat(levels[index]) : 0
                let height = minHeight + level * (maxHeight - minHeight)
                let bar = CGRect(x: CGFloat(index) * step + (step - 3) / 2, y: (size.height - height) / 2, width: 3, height: height)
                context.fill(Path(roundedRect: bar, cornerRadius: 1.5), with: .color(index < filled ? accent : rest))
            }
        }
    }
}
