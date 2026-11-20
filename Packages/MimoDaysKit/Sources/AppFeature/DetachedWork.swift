import Foundation

/// Runs `work` off the main actor, and cancelling the caller cancels it too: a plain detached task doesn't hear
/// its caller's cancellation, so its `Task.isCancelled` checks never fire and it runs to the end.
func detachedWork<T: Sendable>(priority: TaskPriority = .userInitiated, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
    let task = Task.detached(priority: priority, operation: work)
    return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
}

func detachedWork<T: Sendable>(priority: TaskPriority = .userInitiated, _ work: @escaping @Sendable () async -> T) async -> T {
    let task = Task.detached(priority: priority, operation: work)
    return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
}
