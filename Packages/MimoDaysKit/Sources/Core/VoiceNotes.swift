import AVFoundation
import Speech

/// Records a voice note: AAC in an .m4a, mono. Kept apart from a clip's own sound (doc 01 §Voice).
@MainActor
public protocol VoiceRecorder: AnyObject {
    /// Starts a new recording at `url`; it stops by itself at `limit` seconds.
    func start(to url: URL, limit: TimeInterval) throws
    /// Seconds recorded so far; keeps the last value once stopped.
    var elapsed: TimeInterval { get }
    /// The input level right now, 0...1.
    var level: Float { get }
    /// False once stopped: by `stop()`, at the limit, or by an interruption such as a call.
    var isRecording: Bool { get }
    /// Ends the recording and closes the file.
    func stop()
}

public enum VoiceRecorderError: Error {
    case couldNotStart
}

@MainActor
public final class AVVoiceRecorder: VoiceRecorder {
    private var recorder: AVAudioRecorder?
    private var lastElapsed: TimeInterval = 0

    public init() {}

    public func start(to url: URL, limit: TimeInterval) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
        let recorder = try AVAudioRecorder(url: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ])
        recorder.isMeteringEnabled = true
        guard recorder.record(forDuration: limit) else { throw VoiceRecorderError.couldNotStart }
        self.recorder = recorder
        lastElapsed = 0
    }

    public var elapsed: TimeInterval {
        if let recorder, recorder.isRecording { lastElapsed = recorder.currentTime }
        return lastElapsed
    }

    public var level: Float {
        guard let recorder, recorder.isRecording else { return 0 }
        recorder.updateMeters()
        // -50 dB and below reads as silence.
        return max(0, min(1, (recorder.averagePower(forChannel: 0) + 50) / 50))
    }

    public var isRecording: Bool { recorder?.isRecording ?? false }

    public func stop() {
        guard let recorder else { return }
        _ = elapsed
        recorder.stop()
        self.recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Previews, tests and the simulator: a soft tone as long as the "recording" ran.
@MainActor
public final class SimulatedVoiceRecorder: VoiceRecorder {
    private let now: () -> Date
    private var startedAt: Date?
    private var url: URL?
    private var limit: TimeInterval = 0
    private var stoppedAt: TimeInterval?

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    public func start(to url: URL, limit: TimeInterval) throws {
        self.url = url
        self.limit = limit
        startedAt = now()
        stoppedAt = nil
    }

    public var elapsed: TimeInterval {
        if let stoppedAt { return stoppedAt }
        guard let startedAt else { return 0 }
        return min(limit, now().timeIntervalSince(startedAt))
    }

    public var level: Float {
        isRecording ? Float(0.45 + 0.35 * sin(elapsed * 7)) : 0
    }

    public var isRecording: Bool { startedAt != nil && stoppedAt == nil && elapsed < limit }

    public func stop() {
        guard let url, stoppedAt == nil else { return }
        let seconds = max(0.5, elapsed)
        stoppedAt = seconds
        try? Self.writeTone(to: url, seconds: seconds)
    }

    static func writeTone(to url: URL, seconds: TimeInterval) throws {
        let rate = 16_000.0
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
        ])
        let frames = AVAudioFrameCount(seconds * rate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames),
              let samples = buffer.floatChannelData?[0] else { return }
        for frame in 0 ..< Int(frames) {
            let time = Double(frame) / rate
            samples[frame] = Float(0.2 * sin(2 * .pi * 220 * time) * (0.5 + 0.5 * sin(time * 7)))
        }
        buffer.frameLength = frames
        try file.write(from: buffer)
    }
}

// MARK: Transcription

/// Words from a voice note, worked out on this iPhone; the audio never leaves it.
public protocol VoiceTranscriber: Sendable {
    /// Asks iOS for the on-device speech model if it isn't there yet (a one-time download), without waiting.
    func prepare() async
    /// Nil when it can't: before iOS 26, an unsupported language, the model not ready yet, or no words heard.
    func transcribe(_ url: URL) async -> String?
}

/// SpeechTranscriber, iOS 26 and later (Andrew, 2026-11-13: older systems get no transcript).
public struct OnDeviceTranscriber: VoiceTranscriber {
    private let locale: Locale

    public init(locale: Locale = .current) {
        self.locale = locale
    }

    public func prepare() async {
        guard #available(iOS 26, *), let transcriber = await Self.transcriber(for: locale) else { return }
        _ = try? await AssetInventory.assetInstallationRequest(supporting: [transcriber])?.downloadAndInstall()
    }

    public func transcribe(_ url: URL) async -> String? {
        guard #available(iOS 26, *), let transcriber = await Self.transcriber(for: locale),
              await AssetInventory.status(forModules: [transcriber]) == .installed,
              let file = try? AVAudioFile(forReading: url) else { return nil }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let words = Task { try await transcriber.results.reduce(into: "") { $0 += String($1.text.characters) } }
        do {
            if let end = try await analyzer.analyzeSequence(from: file) {
                try await analyzer.finalizeAndFinish(through: end)
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } catch {
            await analyzer.cancelAndFinishNow()
        }
        let text = (try? await words.value)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    @available(iOS 26, *)
    private static func transcriber(for locale: Locale) async -> SpeechTranscriber? {
        guard SpeechTranscriber.isAvailable, let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else { return nil }
        return SpeechTranscriber(locale: supported, preset: .transcription)
    }
}

public struct SimulatedTranscriber: VoiceTranscriber {
    private let text: String?

    public init(text: String? = "Look, the first snow on the balcony") {
        self.text = text
    }

    public func prepare() async {}

    public func transcribe(_: URL) async -> String? { text }
}

// MARK: Waveform

public enum VoiceWaveform {
    /// Length in seconds and `bars` peak levels (0...1, loudest = 1) across the file, for drawing.
    public static func read(_ url: URL, bars: Int) -> (duration: TimeInterval, levels: [Float])? {
        guard bars > 0, let file = try? AVAudioFile(forReading: url), file.length > 0 else { return nil }
        let format = file.processingFormat
        let perBar = max(1, AVAudioFrameCount(file.length) / AVAudioFrameCount(bars))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: perBar) else { return nil }
        var levels: [Float] = []
        while levels.count < bars, (try? file.read(into: buffer, frameCount: perBar)) != nil, buffer.frameLength > 0,
              let samples = buffer.floatChannelData?[0] {
            var sum: Float = 0
            for index in 0 ..< Int(buffer.frameLength) { sum += samples[index] * samples[index] }
            levels.append((sum / Float(buffer.frameLength)).squareRoot())
        }
        let loudest = levels.max() ?? 0
        if loudest > 0 { levels = levels.map { $0 / loudest } }
        return (Double(file.length) / format.sampleRate, levels)
    }
}
