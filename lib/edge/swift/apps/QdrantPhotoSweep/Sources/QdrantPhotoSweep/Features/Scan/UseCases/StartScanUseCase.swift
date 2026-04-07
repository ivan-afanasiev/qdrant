import Foundation

struct StartScanInput: Sendable {
    let dateRange: DateRange
    let resumeSessionId: UUID?
}

struct StartScanUseCase: UseCase {
    let coordinator: ContinuousScanCoordinator
    let deps: Dependencies

    @MainActor
    func execute(_ input: StartScanInput) async throws -> Void {
        guard !coordinator.isActive else { return }
        coordinator.startPipeline(
            dateRange: input.dateRange,
            resumeSessionId: input.resumeSessionId,
            deps: deps
        )
    }
}
