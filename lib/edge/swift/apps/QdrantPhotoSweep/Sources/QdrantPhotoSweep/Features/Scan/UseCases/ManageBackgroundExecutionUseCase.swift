import Foundation

struct ManageBackgroundExecutionUseCase: UseCase {
    let coordinator: ContinuousScanCoordinator

    @MainActor
    func execute(_ input: Void) async throws -> Void {
        coordinator.beginExtendedBackgroundExecution()
        BackgroundScanService.schedule(urgent: true)
    }
}
