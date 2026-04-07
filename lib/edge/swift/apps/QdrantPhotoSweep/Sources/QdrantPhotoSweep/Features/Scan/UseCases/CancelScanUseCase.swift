import Foundation

struct CancelScanUseCase: UseCase {
    let coordinator: ContinuousScanCoordinator

    @MainActor
    func execute(_ input: Void) async throws -> Void {
        coordinator.cancel()
    }
}
