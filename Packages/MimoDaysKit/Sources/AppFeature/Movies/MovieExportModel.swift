@preconcurrency import AVFoundation
import Core
import Foundation
import OSLog
import Persistence
import SwiftData
import UIKit
import UserNotifications

/// F11-F14: the quality and what the file says about where and when, then the render with its progress,
/// and what came of it. The finished file becomes the project's render (the old one goes).
@MainActor
@Observable
final class MovieExportModel {
    enum Phase: Equatable {
        case options
        /// `progress` 0...1; `remaining` seconds, once there's enough to guess from.
        case rendering(progress: Double, remaining: Double?)
        case ready(MovieRender)
        case failed(Failure)
    }

    enum Failure: Equatable {
        /// Not enough room; `needed` more bytes would do.
        case space(needed: Int64)
        case other
    }

    let project: MovieProject
    var resolution: MovieResolution = .p1080
    /// F11's Privacy: the day the movie starts, and the exact place, in the file's details. Off: nothing.
    var dateInFile = true
    var placeInFile = false
    private(set) var phase: Phase = .options
    private(set) var plan: MoviePlan
    private let library: MediaLibrary
    private let clock: any DateProvider
    private let freeSpace: () -> Int64?
    private var task: Task<Void, Never>?
    private var background = UIBackgroundTaskIdentifier.invalid
    private let logger = Logger(subsystem: "MimoDays", category: "Movies")

    /// Starts with the quality and place set in Settings (S06); a movie made before keeps its own quality.
    init(
        project: MovieProject, library: MediaLibrary, defaults: MovieDefaults = MovieDefaults(),
        clock: any DateProvider = SystemDateProvider(), freeSpace: @escaping () -> Int64? = MovieExportModel.deviceFreeSpace
    ) {
        self.project = project
        self.library = library
        self.clock = clock
        self.freeSpace = freeSpace
        plan = MoviePlan(project, store: library.store)
        resolution = project.render?.resolution ?? defaults.resolution
        placeInFile = defaults.exactPlaceInFiles
    }

    private var store: MovieStore { MovieStore(context: library.context, store: library.store, now: { [clock] in clock.now() }) }

    // MARK: Estimates

    /// Bits a second the encoder spends at each quality; "About 95 MB" for a 1:04 movie at 1080p.
    static func bitrate(_ resolution: MovieResolution) -> Double {
        switch resolution {
        case .p720: 5_600_000
        case .p1080: 11_900_000
        case .p2160: 45_000_000
        }
    }

    func estimatedBytes(_ resolution: MovieResolution) -> Int64 {
        Int64(plan.duration * Self.bitrate(resolution) / 8)
    }

    var available: Int64? { freeSpace() }

    nonisolated static func deviceFreeSpace() -> Int64? {
        let values = try? URL.homeDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    // MARK: Render

    func start() {
        let needed = estimatedBytes(resolution)
        if let free = freeSpace(), free < needed + needed / 5 {
            phase = .failed(.space(needed: needed + needed / 5 - free))
            return
        }
        phase = .rendering(progress: 0, remaining: nil)
        let started = clock.now()
        task = Task { [weak self] in
            guard let self else { return }
            let id = UIApplication.shared.beginBackgroundTask(withName: "Movie export") { [weak self] in
                MainActor.assumeIsolated { self?.backgroundTimeRanOut() }
            }
            background = id
            // Only its own: after a cancel and a new start, `background` is the new export's.
            defer { if background == id { endBackgroundTask() } }
            do {
                let render = try await render(started: started)
                try store.attach(render, to: project)
                phase = .ready(render)
                notifyIfAway()
            } catch {
                // A cancel has already said where to go: back to the options, or F14 when time ran out.
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                logger.error("Exporting the movie failed: \(error.localizedDescription, privacy: .public)")
                phase = .failed(.other)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        phase = .options
        endBackgroundTask()
    }

    /// iOS gives an app in the background a few minutes. When they run out, the render stops, the draft stays as it
    /// was and F14 offers to try again; left running, iOS would end the app.
    private func backgroundTimeRanOut() {
        task?.cancel()
        task = nil
        phase = .failed(.other)
        endBackgroundTask()
    }

    private func endBackgroundTask() {
        guard background != .invalid else { return }
        UIApplication.shared.endBackgroundTask(background)
        background = .invalid
    }

    /// F14's smaller option: the same movie at 720p.
    func retryAt720() {
        resolution = .p720
        start()
    }

    func waitForRender() async { await task?.value }

    private func render(started: Date) async throws -> MovieRender {
        let plan = await MoviePlan(project, store: library.store).leavingOutUnreadable()
        self.plan = plan
        let composed = try await MovieComposer.compose(plan, renderSize: plan.aspectRatio.renderSize(resolution))
        guard let session = AVAssetExportSession(asset: composed.asset, presetName: Self.preset(resolution)) else {
            throw MovieComposer.Failure.compositionFailed
        }
        session.videoComposition = composed.videoComposition
        session.audioMix = composed.audioMix
        session.metadata = metadata(plan)
        session.shouldOptimizeForNetworkUse = true
        let output = FileManager.default.temporaryDirectory.appending(path: "Movie-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: output) }
        let progress = Task { [weak self] in
            for await state in session.states(updateInterval: 0.25) {
                guard case let .exporting(progress) = state else { continue }
                self?.progressed(progress.fractionCompleted, since: started)
            }
        }
        defer { progress.cancel() }
        try await session.export(to: output, as: .mp4)
        try Task.checkCancellation()
        let file = try library.store.store(copyOf: output, in: .derived, fileExtension: "mp4")
        return MovieRender(
            relativePath: file.relativePath, renderedAt: clock.now(), duration: plan.duration, resolution: resolution,
            byteCount: file.byteCount
        )
    }

    private func progressed(_ fraction: Double, since started: Date) {
        guard case .rendering = phase else { return }
        let elapsed = clock.now().timeIntervalSince(started)
        let remaining = fraction > 0.05 ? elapsed / fraction * (1 - fraction) : nil
        phase = .rendering(progress: fraction, remaining: remaining)
    }

    static func preset(_ resolution: MovieResolution) -> String {
        switch resolution {
        case .p720: AVAssetExportPreset1280x720
        case .p1080: AVAssetExportPreset1920x1080
        case .p2160: AVAssetExportPreset3840x2160
        }
    }

    /// Only what F11 allows: the day the first clip was taken, the place of the first clip that has one.
    private func metadata(_ plan: MoviePlan) -> [AVMetadataItem] {
        var items: [AVMetadataItem] = []
        let moments = MovieStore.liveClips(of: project).compactMap(\.moment)
        if dateInFile, let first = moments.first {
            let item = AVMutableMetadataItem()
            item.identifier = .commonIdentifierCreationDate
            item.value = first.capturedAt.ISO8601Format() as NSString
            items.append(item)
        }
        let places = moments.lazy.compactMap { moment -> (Double, Double)? in
            guard let latitude = moment.location?.latitude, let longitude = moment.location?.longitude else { return nil }
            return (latitude, longitude)
        }
        if placeInFile, let (latitude, longitude) = places.first {
            let item = AVMutableMetadataItem()
            item.identifier = .quickTimeMetadataLocationISO6709
            item.value = Self.iso6709(latitude: latitude, longitude: longitude) as NSString
            items.append(item)
        }
        return items
    }

    /// "+37.8044-122.2712/".
    nonisolated static func iso6709(latitude: Double, longitude: Double) -> String {
        String(format: "%+08.4f%+09.4f/", latitude, longitude)
    }

    /// "We'll let you know when it's ready" (F12): a notice when the person has left the app.
    private func notifyIfAway() {
        guard UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = String(appLocalized: "Your movie is ready", bundle: .module)
        content.body = project.title
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "movie-\(project.id)", content: content, trigger: nil))
    }
}
