import Foundation

enum HomeFeature {
    struct UseCases: Sendable {
        let loadHomeData: LoadHomeDataUseCase
    }
}

@Observable
@MainActor
final class HomeState {
    struct Stats: Equatable {
        var totalPhotosIndexed: Int = 0
        var lastScanDate: Date?
        var duplicateGroupsFound: Int = 0
        var photosDeleted: Int = 0
    }

    enum Action {
        case didLoadData(LoadHomeDataOutput)
    }

    var stats = Stats()
    var interruptedSession: ScanSessionDTO?
    var newPhotoCount: Int = 0
    var lastSession: ScanSessionDTO?
    var pendingGroupCount: Int = 0

    func reduce(_ action: Action) {
        switch action {
        case .didLoadData(let output):
            stats = output.stats
            interruptedSession = output.interruptedSession
            newPhotoCount = output.newPhotoCount
            lastSession = output.lastSession
            pendingGroupCount = output.pendingGroupCount
        }
    }
}

extension Dependencies {
    var homeUseCases: HomeFeature.UseCases {
        HomeFeature.UseCases(
            loadHomeData: LoadHomeDataUseCase(
                scanStore: scanStore,
                photoLibrary: photoLibrary
            )
        )
    }
}
