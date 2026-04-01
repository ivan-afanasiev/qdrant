import Foundation

@Observable
final class SettingsState {
    enum Status: Equatable {
        case idle(pointCount: Int)
        case clearing
        case cleared
        case failed(AppError)
    }

    enum Action {
        case didLoadInfo(pointCount: Int)
        case didTapClearDatabase
        case didFinishClearing
        case didFail(AppError)
    }

    var status: Status = .idle(pointCount: 0)
    var similarityThreshold: Float = 0.92

    func reduce(_ action: Action) {
        switch action {
        case .didLoadInfo(let count):
            status = .idle(pointCount: count)
        case .didTapClearDatabase:
            status = .clearing
        case .didFinishClearing:
            status = .cleared
        case .didFail(let error):
            status = .failed(error)
        }
    }
}
