import Foundation

enum SettingsFeature {
    struct UseCases: Sendable {
        let clearDatabase: ClearDatabaseUseCase
        let loadDatabaseInfo: LoadDatabaseInfoUseCase
        let loadStats: LoadStatsUseCase
    }
}

@Observable
@MainActor
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

extension DependencyProviding {
    var settingsUseCases: SettingsFeature.UseCases {
        SettingsFeature.UseCases(
            clearDatabase: ClearDatabaseUseCase(vectorStore: vectorStore),
            loadDatabaseInfo: LoadDatabaseInfoUseCase(vectorStore: vectorStore),
            loadStats: LoadStatsUseCase(scanStore: scanStore)
        )
    }
}
