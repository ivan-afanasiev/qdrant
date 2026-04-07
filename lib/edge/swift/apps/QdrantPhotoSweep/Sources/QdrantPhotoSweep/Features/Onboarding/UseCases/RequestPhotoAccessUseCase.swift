import Foundation
import Photos

struct RequestPhotoAccessUseCase: UseCase {
    func execute(_ input: Void) async throws -> OnboardingState.PermissionStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return .granted
        default:
            return .denied
        }
    }
}
