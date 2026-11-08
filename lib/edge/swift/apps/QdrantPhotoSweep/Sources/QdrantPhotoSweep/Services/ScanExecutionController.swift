import Foundation

/// Serializes entire scan lifetimes, including cancellation cleanup.
/// Foreground requests can replace background work; background requests never replace a scan.
@MainActor
final class ScanExecutionController {
    static let shared = ScanExecutionController()

    private var activeId: UUID?
    private var activeTask: Task<ScanOutcome, Never>?
    var isRunning: Bool { activeTask != nil }

    func run(
        replacingCurrent: Bool,
        operation: @escaping @MainActor () async -> ScanOutcome
    ) async -> ScanOutcome? {
        while let previous = activeTask {
            guard replacingCurrent, !Task.isCancelled else { return nil }
            let previousId = activeId
            previous.cancel()
            _ = await previous.value
            if activeId == previousId {
                activeId = nil
                activeTask = nil
            }
        }
        guard !Task.isCancelled else { return nil }
        let id = UUID()
        let task = Task { await operation() }
        activeId = id
        activeTask = task
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if activeId == id {
            activeId = nil
            activeTask = nil
        }
        return result
    }
}
