import BackgroundTasks
import Foundation
import Observation
import Persistence
import SwiftUI

/// P8.13: a movie export iOS keeps running after MimoDays is left, with the system's progress and Cancel
/// (iOS 26 continued processing). Without it, the export runs while MimoDays is open, as before.
@MainActor
protocol ContinuedExportScheduler: AnyObject {
    /// iOS can take exports on (iOS 26 and the app set up for it).
    var isAvailable: Bool { get }
    /// Hands one export to iOS. False when iOS turns it down: then it runs in the foreground only. `run` comes once
    /// iOS starts it, at once or after another app's work.
    func submit(title: String, run: @escaping @MainActor (any ContinuedExportTask) -> Void) -> Bool
    /// The export submitted last, cancelled while it still waits for iOS: its request and progress go.
    func cancelWaiting()
}

extension ContinuedExportScheduler {
    func cancelWaiting() {}
}

/// The running export as iOS sees it.
@MainActor
protocol ContinuedExportTask: AnyObject {
    /// 0...1, for the system's progress.
    func report(_ fraction: Double)
    /// iOS (or the person, from the system's progress) stopped it.
    var stopped: (@MainActor () -> Void)? { get set }
    func finish(success: Bool)
}

/// The real one: `BGContinuedProcessingTask`, identifiers under `com.mrmaier.MimoDays.export.*` in the app's
/// `BGTaskSchedulerPermittedIdentifiers`.
@available(iOS 26, *)
@MainActor
final class SystemContinuedExport: ContinuedExportScheduler {
    static let prefix = "com.mrmaier.MimoDays.export"

    var isAvailable: Bool {
        let permitted = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
        return permitted.contains("\(Self.prefix).*")
    }

    /// The request submitted last.
    private var submitted: String?

    func cancelWaiting() {
        guard let submitted else { return }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: submitted)
        self.submitted = nil
    }

    func submit(title: String, run: @escaping @MainActor (any ContinuedExportTask) -> Void) -> Bool {
        let identifier = "\(Self.prefix).\(UUID().uuidString)"
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            guard let task = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            MainActor.assumeIsolated { run(Handle(task)) }
        }
        guard registered else { return false }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: "")
        // Waits its turn rather than failing when iOS is busy ("Waiting to export…").
        request.strategy = .queue
        do {
            try BGTaskScheduler.shared.submit(request)
            submitted = identifier
            return true
        } catch {
            return false
        }
    }

    private final class Handle: ContinuedExportTask {
        let task: BGContinuedProcessingTask
        var stopped: (@MainActor () -> Void)?
        private var finished = false

        init(_ task: BGContinuedProcessingTask) {
            self.task = task
            task.progress.totalUnitCount = 1000
            task.expirationHandler = { [weak self] in
                Task { @MainActor in self?.stopped?() }
            }
        }

        func report(_ fraction: Double) {
            task.progress.completedUnitCount = Int64((min(max(fraction, 0), 1) * 1000).rounded())
        }

        func finish(success: Bool) {
            guard !finished else { return }
            finished = true
            task.setTaskCompleted(success: success)
        }
    }
}

extension ExportState {
    var isOver: Bool { self == .finished || self == .failed || self == .cancelled }
}

/// P8.13: one movie export at a time, kept while its screen is closed (Back to Movies) so it can be reopened.
@MainActor
@Observable
final class MovieExportCenter {
    private(set) var active: MovieExportModel?
    /// iOS 26's continued processing, handed to every export model.
    let continuation: (any ContinuedExportScheduler)?

    init(continuation: (any ContinuedExportScheduler)? = nil) {
        self.continuation = continuation
    }

    /// The export screen's model for `project`: the one under way for it, or a new one. Nil while another movie is
    /// exporting: Movies offers View export for that one instead.
    func model(for project: MovieProject, make: () -> MovieExportModel) -> MovieExportModel? {
        if let active, active.isBusy {
            return active.project.id == project.id ? active : nil
        }
        if let active, active.project.id == project.id { return active }
        let model = make()
        active = model
        return model
    }

    /// Delete all, Replace everything and deleting the movie wait for this: its files are in use.
    var isExporting: Bool { active?.isBusy == true }

    /// JJ03: Movies' View export row - the export under way, or one that finished or stopped while its screen was
    /// closed. A cancel isn't news: no row.
    var row: MovieExportModel? {
        guard let active else { return nil }
        switch active.phase {
        case .waiting, .rendering, .ready, .stopped, .failed: return active
        case .options, .canceled: return nil
        }
    }

    /// Its screen closed: an export that isn't under way is done with (seen, canceled or never started).
    func release(_ model: MovieExportModel) {
        guard active === model, !model.isBusy else { return }
        active = nil
    }
}

extension View {
    /// P8.13: Delete all, Replace everything and deleting the exporting movie wait until the export is canceled.
    func exportInUseAlert(_ isPresented: Binding<Bool>) -> some View {
        alert(Text("A movie is being exported", bundle: .module, comment: "P8.13: an action needs files the running export uses"), isPresented: isPresented) {
            Button(role: .cancel) {} label: { Text("OK", bundle: .module) }
        } message: {
            Text("Cancel the export first: it uses these files.", bundle: .module, comment: "P8.13: under A movie is being exported")
        }
    }
}
