import SweepComposition
import SwiftUI

@main
struct QdrantPhotoSweepApp: App {
    /// Created once, outside body reconstruction.
    private let composition: PhotoSweepComposition

    init() {
        let composition = PhotoSweepComposition()
        // Background launch handlers must be registered before launch finishes.
        composition.registerBackgroundHandlers()
        self.composition = composition
    }

    var body: some Scene {
        WindowGroup {
            PhotoSweepRootView(composition: composition)
        }
    }
}
