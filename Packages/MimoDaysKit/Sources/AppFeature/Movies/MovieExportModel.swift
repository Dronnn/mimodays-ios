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
        /// P8.13: handed to iOS, waiting for its turn.
        case waiting
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
    private(set) var task: Task<Void, Never>?
    private var background = UIBackgroundTaskIdentifier.invalid
    /// P8.13: iOS 26 keeps the export going after MimoDays is left.
    private let continuation: (any ContinuedExportScheduler)?
    private var continued: (any ContinuedExportTask)?
    /// iOS took this export on: F12 offers Back to Movies.
    private(set) var runsInBackground = false
    /// iOS turned it down: "Keep MimoDays open to finish this export."
    private(set) var foregroundOnly = false
    /// P8.13: the export's `ExportJob` row, so a relaunch knows one was cut short.
    private(set) var job: ExportJob?
    private let logger = Logger(subsystem: "MimoDays", category: "Movies")

    /// Starts with the quality and place set in Settings (S06); a movie made before keeps its own quality.
    init(
        project: MovieProject, library: MediaLibrary, defaults: MovieDefaults = MovieDefaults(),
        clock: any DateProvider = SystemDateProvider(), freeSpace: @escaping () -> Int64? = MovieExportModel.deviceFreeSpace,
        continuation: (any ContinuedExportScheduler)? = nil
    ) {
        self.project = project
        self.library = library
        self.clock = clock
        self.freeSpace = freeSpace
        self.continuation = continuation
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

    /// F11's "You can leave MimoDays while the movie is being made."
    var canLeave: Bool { continuation?.isAvailable == true }

    /// Waiting for iOS or rendering: another export has to wait, and nothing may take its files.
    var isBusy: Bool {
        switch phase {
        case .waiting, .rendering: true
        default: false
        }
    }

    /// Notes where the export is; a new start begins a new row.
    private func record(_ state: ExportState) {
        let context = library.context
        if job == nil || job?.state.isOver == true {
            let row = ExportJob(kind: .movie, sourceIDs: [project.id], destination: .files, createdAt: clock.now())
            context.insert(row)
            job = row
        }
        guard let job else { return }
        job.state = state
        if state == .finished { job.progress = 1 }
        if state.isOver { job.finishedAt = clock.now() }
        try? context.save()
    }

    /// Jobs a quit or a crash cut short (doc: P8.13): stopped, never finished without their file.
    static func reconcileJobs(in context: ModelContext, now: Date) {
        let movie = ExportKind.movie.rawValue
        let queued = ExportState.queued.rawValue
        let running = ExportState.running.rawValue
        let open = (try? context.fetch(FetchDescriptor<ExportJob>(
            predicate: #Predicate { $0.kindRaw == movie && ($0.stateRaw == queued || $0.stateRaw == running) }
        ))) ?? []
        guard !open.isEmpty else { return }
        for job in open {
            job.state = .failed
            job.errorMessage = "interrupted"
            job.finishedAt = now
        }
        try? context.save()
    }

    func start() {
        // Two taps before the options make way: one render, or Cancel would stop only the second.
        if case .rendering = phase { return }
        if phase == .waiting { return }
        let needed = estimatedBytes(resolution)
        if let free = freeSpace(), free < needed + needed / 5 {
            phase = .failed(.space(needed: needed + needed / 5 - free))
            return
        }
        runsInBackground = false
        foregroundOnly = false
        if let continuation, continuation.isAvailable {
            phase = .waiting
            record(.queued)
            let accepted = continuation.submit(title: String(appLocalized: "Exporting a movie", bundle: .module)) { [weak self] task in
                guard let self else { return task.finish(success: false) }
                runContinued(task)
            }
            if accepted {
                runsInBackground = true
                return
            }
            foregroundOnly = true
        }
        runInForeground()
    }

    /// iOS's turn came: the same render, its progress shown by iOS too.
    private func runContinued(_ handed: any ContinuedExportTask) {
        // Cancelled while it waited.
        guard phase == .waiting, runsInBackground else { return handed.finish(success: false) }
        continued = handed
        handed.stopped = { [weak self, weak handed] in
            guard let self, let handed, continued === handed else { return }
            stoppedByIOS()
        }
        phase = .rendering(progress: 0, remaining: nil)
        record(.running)
        let started = clock.now()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let render = try await render(started: started)
                guard !Task.isCancelled else {
                    try? library.store.remove(render.relativePath)
                    return
                }
                try store.attach(render, to: project)
                phase = .ready(render)
                record(.finished)
                handed.finish(success: true)
                notifyIfAway()
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                logger.error("Exporting the movie failed: \(error.localizedDescription, privacy: .public)")
                phase = .failed(.other)
                record(.failed)
                handed.finish(success: false)
            }
            if continued === handed { continued = nil }
        }
    }

    /// The system's Cancel, or iOS needed the time back: the render stops, the draft stays, F14 offers to try again.
    private func stoppedByIOS() {
        task?.cancel()
        task = nil
        continued?.finish(success: false)
        continued = nil
        phase = .failed(.other)
        record(.failed)
    }

    private func runInForeground() {
        phase = .rendering(progress: 0, remaining: nil)
        record(.running)
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
                // Cancelled while the file was being stored: it isn't kept.
                guard !Task.isCancelled else {
                    try? library.store.remove(render.relativePath)
                    return
                }
                try store.attach(render, to: project)
                phase = .ready(render)
                record(.finished)
                notifyIfAway()
            } catch {
                // A cancel has already said where to go: back to the options, or F14 when time ran out.
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                logger.error("Exporting the movie failed: \(error.localizedDescription, privacy: .public)")
                phase = .failed(.other)
                record(.failed)
            }
        }
    }

    func cancel() {
        let wasBusy = isBusy
        task?.cancel()
        task = nil
        phase = .options
        if wasBusy { record(.cancelled) }
        continued?.finish(success: false)
        continued = nil
        runsInBackground = false
        endBackgroundTask()
    }

    /// iOS gives an app in the background a few minutes. When they run out, the render stops, the draft stays as it
    /// was and F14 offers to try again; left running, iOS would end the app.
    private func backgroundTimeRanOut() {
        task?.cancel()
        task = nil
        phase = .failed(.other)
        record(.failed)
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
        continued?.report(fraction)
        job?.progress = fraction
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
        // The clips the movie really shows: one that couldn't be read is left out of its place and day too.
        let shown = Set(plan.clips.map(\.momentID))
        let moments = MovieStore.liveClips(of: project).compactMap(\.moment).filter { shown.contains($0.id) }
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
