import SwiftData
import SwiftUI

@Observable
final class AppSettings {
    static let defaultSimilarityThreshold: Float = 0.92

    private let defaults = UserDefaults.standard

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    var similarityThreshold: Float {
        didSet { defaults.set(similarityThreshold, forKey: "similarityThreshold") }
    }

    var scanPreset: DatePreset? {
        didSet {
            defaults.set(scanPreset?.rawValue, forKey: "scanPreset")
            if scanPreset != nil { isCustomRange = false }
        }
    }

    var customRangeStart: Date {
        didSet { defaults.set(customRangeStart, forKey: "customRangeStart") }
    }

    var customRangeEnd: Date {
        didSet { defaults.set(customRangeEnd, forKey: "customRangeEnd") }
    }

    var isCustomRange: Bool {
        didSet { defaults.set(isCustomRange, forKey: "isCustomRange") }
    }

    var currentDateRange: DateRange {
        switch isCustomRange {
        case true:
            DateRange(start: customRangeStart, end: customRangeEnd)
        case false:
            scanPreset?.dateRange ?? DatePreset.allTime.dateRange
        }
    }

    /// Bumped by Settings to signal ScanView should start a new scan with the current range.
    var rescanRequestId = UUID()

    func requestRescan() {
        rescanRequestId = UUID()
    }

    init() {
        let storedThreshold = defaults.float(forKey: "similarityThreshold")
        self.similarityThreshold = storedThreshold > 0 ? storedThreshold : Self.defaultSimilarityThreshold
        self.hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        self.scanPreset = defaults.string(forKey: "scanPreset").flatMap(DatePreset.init(rawValue:)) ?? .allTime
        self.customRangeStart = (defaults.object(forKey: "customRangeStart") as? Date) ?? Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
        self.customRangeEnd = (defaults.object(forKey: "customRangeEnd") as? Date) ?? .now
        self.isCustomRange = defaults.bool(forKey: "isCustomRange")
    }
}

// MARK: - DependencyProviding Protocol

protocol DependencyProviding {
    var vectorStore: any VectorStoring { get }
    var embeddingService: any EmbeddingProviding { get }
    var photoLibrary: any PhotoLibraryProviding { get }
    var scanStore: any ScanSessionStoring { get }
    var settings: AppSettings { get }
}

// MARK: - Live Implementation

final class AppDependencies: DependencyProviding {
    let vectorStore: any VectorStoring
    let embeddingService: any EmbeddingProviding
    let photoLibrary: any PhotoLibraryProviding
    let scanStore: any ScanSessionStoring
    let settings: AppSettings

    init(
        vectorStore: any VectorStoring,
        embeddingService: any EmbeddingProviding,
        photoLibrary: any PhotoLibraryProviding,
        scanStore: any ScanSessionStoring,
        settings: AppSettings
    ) {
        self.vectorStore = vectorStore
        self.embeddingService = embeddingService
        self.photoLibrary = photoLibrary
        self.scanStore = scanStore
        self.settings = settings
    }

    @MainActor
    static func forBackground(modelContainer: ModelContainer) async -> AppDependencies {
        let photoLibrary = PhotoLibraryService()
        let embeddingService = VisionEmbeddingService()

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let shardDir = documentsPath.appendingPathComponent("qdrant-edge")
        let vectorStore = QdrantVectorStore(path: shardDir.path, dimensions: 0)
        await vectorStore.restoreDimensionsFromDisk()

        let scanStore = SwiftDataScanStore(modelContainer: modelContainer)
        let settings = AppSettings()

        return AppDependencies(
            vectorStore: vectorStore,
            embeddingService: embeddingService,
            photoLibrary: photoLibrary,
            scanStore: scanStore,
            settings: settings
        )
    }
}

// MARK: - SwiftUI Environment

private struct DependencyContainerKey: EnvironmentKey {
    static let defaultValue: (any DependencyProviding)? = nil
}

extension EnvironmentValues {
    var dependencies: (any DependencyProviding)? {
        get { self[DependencyContainerKey.self] }
        set { self[DependencyContainerKey.self] = newValue }
    }
}
