import Foundation

enum InitialAction: Sendable {
    case resumeScan(dateRange: DateRange, sessionId: UUID)
    case reviewPending
    case startNewScan(dateRange: DateRange)
}

struct LoadInitialStateUseCase: UseCase {
    let scanStore: any ScanSessionStoring
    let settings: AppSettings

    func execute(_ input: Void) async throws -> InitialAction {
        if let interrupted = try await scanStore.latestInterruptedSession() {
            let range = DateRange(start: interrupted.rangeStart, end: interrupted.rangeEnd)
            return .resumeScan(dateRange: range, sessionId: interrupted.id)
        }

        let pendingCount = try await scanStore.pendingGroupCount()
        if pendingCount > 0 {
            return .reviewPending
        }

        return .startNewScan(dateRange: settings.currentDateRange)
    }
}
