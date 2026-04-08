import Foundation

enum ScanFeature {
    struct UseCases: @unchecked Sendable {
        let loadInitialState: LoadInitialStateUseCase
        let startScan: StartScanUseCase
        let cancelScan: CancelScanUseCase
        let manageBackground: ManageBackgroundExecutionUseCase
    }
}

@Observable
@MainActor
final class ScanState {
    enum Status: Equatable {
        case idle
        case scanning(processed: Int, total: Int)
        case completed(indexed: Int)
        case failed(AppError)
        case cancelled
    }

    enum Action {
        case didStartScan(total: Int)
        case didResumeScan(processed: Int, total: Int)
        case batchCompleted(count: Int)
        case didFinishScan(indexed: Int)
        case didFail(AppError)
        case didTapCancel
    }

    private(set) var status: Status = .idle

    var processedCount: Int {
        switch status {
        case .scanning(let processed, _): processed
        case .completed(let indexed): indexed
        default: 0
        }
    }

    var totalCount: Int {
        switch status {
        case .scanning(_, let total): total
        default: 0
        }
    }

    var progress: Double {
        switch status {
        case .scanning(let processed, let total) where total > 0:
            Double(processed) / Double(total)
        case .completed:
            1.0
        default:
            0
        }
    }

    func reduce(_ action: Action) {
        switch action {
        case .didStartScan(let total):
            status = .scanning(processed: 0, total: total)

        case .didResumeScan(let processed, let total):
            status = .scanning(processed: processed, total: total)

        case .batchCompleted(let count):
            switch status {
            case .scanning(let current, let total):
                status = .scanning(processed: current + count, total: total)
            default:
                break
            }

        case .didFinishScan(let indexed):
            status = .completed(indexed: indexed)

        case .didFail(let error):
            status = .failed(error)

        case .didTapCancel:
            status = .cancelled
        }
    }
}
