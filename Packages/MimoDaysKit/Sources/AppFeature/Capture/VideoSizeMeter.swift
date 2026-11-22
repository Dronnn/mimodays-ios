import Core
import DesignSystem
import Foundation
import SwiftUI

/// P3.4 (Penpot §V3 X07): "the MB a minute under the picker is measured on this phone, not guessed". Each video
/// taken adds its size and length to its video size and camera count; the picker shows the average once there is
/// enough of it. Device preferences, like the camera settings.
@MainActor
final class VideoSizeMeter {
    /// A minute's worth at one video size, with one or both cameras.
    struct Rate: Equatable {
        var megabytesPerMinute: Int
        var bothCameras: Bool
    }

    private struct Tally: Codable {
        var bytes: Int64 = 0
        var seconds: Double = 0
    }

    private static let key = "videoSizeMeasures"
    /// Shorter than this in all, and the average says too little.
    static let enoughSeconds: Double = 8
    private let defaults: UserDefaults?
    private var memory: [String: Tally] = [:]

    /// `nil` keeps the measures in memory only (UI tests, previews).
    init(defaults: UserDefaults?) {
        self.defaults = defaults
    }

    func record(_ size: VideoSize, streams: Int, bytes: Int64, seconds: TimeInterval) {
        guard bytes > 0, seconds > 0, streams > 0 else { return }
        var all = tallies
        var tally = all[Self.slot(size, streams: streams)] ?? Tally()
        tally.bytes += bytes
        tally.seconds += seconds
        all[Self.slot(size, streams: streams)] = tally
        tallies = all
    }

    /// Both cameras when measured, as most videos are taken; else one camera; nil before enough is known.
    func rate(for size: VideoSize) -> Rate? {
        for streams in [2, 1] {
            guard let tally = tallies[Self.slot(size, streams: streams)], tally.seconds >= Self.enoughSeconds else { continue }
            let perMinute = Double(tally.bytes) / tally.seconds * 60 / 1_000_000
            return Rate(megabytesPerMinute: max(Int(perMinute.rounded()), 1), bothCameras: streams == 2)
        }
        return nil
    }

    /// Seconds of video measured at a size, with any number of cameras.
    func measuredSeconds(_ size: VideoSize) -> TimeInterval {
        [1, 2].reduce(0) { $0 + (tallies[Self.slot(size, streams: $1)]?.seconds ?? 0) }
    }

    func rates() -> [VideoSize: Rate] {
        Dictionary(uniqueKeysWithValues: VideoSize.allCases.compactMap { size in rate(for: size).map { (size, $0) } })
    }

    private static func slot(_ size: VideoSize, streams: Int) -> String { "\(size.rawValue)-\(streams)" }

    private var tallies: [String: Tally] {
        get {
            guard let defaults else { return memory }
            return defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([String: Tally].self, from: $0) } ?? [:]
        }
        set {
            guard let defaults else {
                memory = newValue
                return
            }
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Self.key)
        }
    }
}

/// X01/X02: the size picker and the line under it.
struct VideoSizePicker: View {
    @Binding var size: VideoSize
    let rates: [VideoSize: VideoSizeMeter.Rate]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SegmentedControl(selection: $size, options: VideoSize.allCases) { $0.label }
                .accessibilityIdentifier("cameraSettings.videoSize")
            caption
                .textStyle(.rowCaption)
                .foregroundStyle(ColorToken.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    private var caption: Text {
        let same = Text("Both cameras always record at the same size.", bundle: .module, comment: "Under the video size picker (P3.4)")
        guard let rate = rates[size] else { return same }
        let measured = rate.bothCameras
            ? Text("About \(rate.megabytesPerMinute) MB a minute with both cameras.", bundle: .module, comment: "Under the video size picker (P3.4): measured on this phone from earlier videos at this size")
            : Text("About \(rate.megabytesPerMinute) MB a minute with one camera.", bundle: .module, comment: "Under the video size picker (P3.4): measured on this phone from earlier videos at this size")
        return Text("\(measured) \(same)", bundle: .module, comment: "Under the video size picker: the measured size a minute, then that both cameras record at the same size")
    }
}
