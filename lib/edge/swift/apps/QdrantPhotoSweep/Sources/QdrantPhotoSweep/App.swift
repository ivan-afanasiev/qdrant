import SweepComposition
import SwiftUI

/// Which engine runs. The rewrite is the default; Debug builds can select the legacy engine
/// with the launch argument `-PhotoSweepLegacyEngine YES` until cutover. Never both.
enum EngineSelection {
    case rewrite
    case legacy

    static var current: EngineSelection {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "PhotoSweepLegacyEngine") {
            return .legacy
        }
        #endif
        return .rewrite
    }
}

@main
struct QdrantPhotoSweepApp: App {
    /// Created once, outside body reconstruction. Exactly one of the two is non-nil.
    private let rewrite: PhotoSweepComposition?
    private let legacy: LegacyEngine?

    init() {
        switch EngineSelection.current {
        case .rewrite:
            let composition = PhotoSweepComposition()
            // Background launch handlers must be registered before launch finishes.
            composition.registerBackgroundHandlers()
            rewrite = composition
            legacy = nil
        case .legacy:
            rewrite = nil
            legacy = LegacyEngine()
        }
    }

    var body: some Scene {
        WindowGroup {
            if let rewrite {
                PhotoSweepRootView(composition: rewrite)
            } else if let legacy {
                LegacyRootView(engine: legacy)
            }
        }
    }
}
