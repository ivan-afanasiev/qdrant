#if os(iOS)
import SwiftUI

public enum L10n {
    // MARK: - App

    public static let appTitle: LocalizedStringResource = LocalizedStringResource("app.title", bundle: .atURL(Bundle.module.bundleURL))
    public static let loading: LocalizedStringResource = LocalizedStringResource("app.loading", bundle: .atURL(Bundle.module.bundleURL))

    // MARK: - Authorization

    public static let photoAccessRequired: LocalizedStringResource = LocalizedStringResource("auth.photoAccessRequired", bundle: .atURL(Bundle.module.bundleURL))
    public static let openSettings: LocalizedStringResource = LocalizedStringResource("auth.openSettings", bundle: .atURL(Bundle.module.bundleURL))

    // MARK: - Date Range (shared)

    public static let customRange: LocalizedStringResource = LocalizedStringResource("dateRangePicker.customRange", bundle: .atURL(Bundle.module.bundleURL))
    public static let from: LocalizedStringResource = LocalizedStringResource("dateRangePicker.from", bundle: .atURL(Bundle.module.bundleURL))
    public static let to: LocalizedStringResource = LocalizedStringResource("dateRangePicker.to", bundle: .atURL(Bundle.module.bundleURL))
    public static let toLabel: LocalizedStringResource = LocalizedStringResource("dateRangePicker.toLabel", bundle: .atURL(Bundle.module.bundleURL))
    public static let startScanning: LocalizedStringResource = LocalizedStringResource("dateRangePicker.startScanning", bundle: .atURL(Bundle.module.bundleURL))

    // MARK: - Presets

    public static let lastWeek: LocalizedStringResource = LocalizedStringResource("preset.lastWeek", bundle: .atURL(Bundle.module.bundleURL))
    public static let lastMonth: LocalizedStringResource = LocalizedStringResource("preset.lastMonth", bundle: .atURL(Bundle.module.bundleURL))
    public static let last3Months: LocalizedStringResource = LocalizedStringResource("preset.last3Months", bundle: .atURL(Bundle.module.bundleURL))
    public static let last6Months: LocalizedStringResource = LocalizedStringResource("preset.last6Months", bundle: .atURL(Bundle.module.bundleURL))
    public static let lastYear: LocalizedStringResource = LocalizedStringResource("preset.lastYear", bundle: .atURL(Bundle.module.bundleURL))
    public static let allTime: LocalizedStringResource = LocalizedStringResource("preset.allTime", bundle: .atURL(Bundle.module.bundleURL))

    // MARK: - Scan

    public static let scanning: LocalizedStringResource = LocalizedStringResource("scan.title", bundle: .atURL(Bundle.module.bundleURL))
    public static let preparingToScan: LocalizedStringResource = LocalizedStringResource("scan.preparing", bundle: .atURL(Bundle.module.bundleURL))
    public static let embeddingPhotos: LocalizedStringResource = LocalizedStringResource("scan.embedding", bundle: .atURL(Bundle.module.bundleURL))
    public static let embeddingSubtitle: LocalizedStringResource = LocalizedStringResource("scan.embeddingSubtitle", bundle: .atURL(Bundle.module.bundleURL))
    public static let cancel: LocalizedStringResource = LocalizedStringResource("scan.cancel", bundle: .atURL(Bundle.module.bundleURL))
    public static let scanComplete: LocalizedStringResource = LocalizedStringResource("scan.complete", bundle: .atURL(Bundle.module.bundleURL))
    public static let findDuplicates: LocalizedStringResource = LocalizedStringResource("scan.findDuplicates", bundle: .atURL(Bundle.module.bundleURL))
    public static let scanResuming: LocalizedStringResource = LocalizedStringResource("scan.resuming", bundle: .atURL(Bundle.module.bundleURL))
    public static let retry: LocalizedStringResource = LocalizedStringResource("scan.retry", bundle: .atURL(Bundle.module.bundleURL))

    public static func photosIndexed(_ count: Int) -> String {
        String(localized: "scan.photosIndexed \(count)", bundle: .module)
    }

    // MARK: - Review

    public static let reviewDuplicates: LocalizedStringResource = LocalizedStringResource("review.title", bundle: .atURL(Bundle.module.bundleURL))
    public static let findingDuplicates: LocalizedStringResource = LocalizedStringResource("review.findingDuplicates", bundle: .atURL(Bundle.module.bundleURL))
    public static let findingDuplicatesSubtitle: LocalizedStringResource = LocalizedStringResource("review.findingDuplicatesSubtitle", bundle: .atURL(Bundle.module.bundleURL))
    public static let noDuplicatesFound: LocalizedStringResource = LocalizedStringResource("review.noDuplicatesFound", bundle: .atURL(Bundle.module.bundleURL))
    public static let libraryLooksClean: LocalizedStringResource = LocalizedStringResource("review.libraryLooksClean", bundle: .atURL(Bundle.module.bundleURL))
    public static let done: LocalizedStringResource = LocalizedStringResource("review.done", bundle: .atURL(Bundle.module.bundleURL))
    public static let skip: LocalizedStringResource = LocalizedStringResource("review.skip", bundle: .atURL(Bundle.module.bundleURL))
    public static let tapToKeepHint: LocalizedStringResource = LocalizedStringResource("review.tapToKeepHint", bundle: .atURL(Bundle.module.bundleURL))
    public static let readyToCleanUp: LocalizedStringResource = LocalizedStringResource("review.readyToCleanUp", bundle: .atURL(Bundle.module.bundleURL))
    public static let groupsReviewed: LocalizedStringResource = LocalizedStringResource("review.stats.groupsReviewed", bundle: .atURL(Bundle.module.bundleURL))
    public static let photosToDelete: LocalizedStringResource = LocalizedStringResource("review.stats.photosToDelete", bundle: .atURL(Bundle.module.bundleURL))
    public static let photosToKeep: LocalizedStringResource = LocalizedStringResource("review.stats.photosToKeep", bundle: .atURL(Bundle.module.bundleURL))
    public static let photosCleaned: LocalizedStringResource = LocalizedStringResource("review.stats.photosCleaned", bundle: .atURL(Bundle.module.bundleURL))
    public static let deletedPhotosNote: LocalizedStringResource = LocalizedStringResource("review.deletedPhotosNote", bundle: .atURL(Bundle.module.bundleURL))
    public static let deletingPhotos: LocalizedStringResource = LocalizedStringResource("review.deletingPhotos", bundle: .atURL(Bundle.module.bundleURL))
    public static let allDone: LocalizedStringResource = LocalizedStringResource("review.allDone", bundle: .atURL(Bundle.module.bundleURL))
    public static let allGroups: LocalizedStringResource = LocalizedStringResource("review.allGroups", bundle: .atURL(Bundle.module.bundleURL))
    public static let finish: LocalizedStringResource = LocalizedStringResource("review.finish", bundle: .atURL(Bundle.module.bundleURL))
    public static let error: LocalizedStringResource = LocalizedStringResource("review.error", bundle: .atURL(Bundle.module.bundleURL))
    public static let unknownDate: LocalizedStringResource = LocalizedStringResource("review.unknownDate", bundle: .atURL(Bundle.module.bundleURL))

    public static func deleteNPhotos(_ count: Int) -> String {
        String(localized: "review.deleteNPhotos \(count)", bundle: .module)
    }

    public static func groupNofTotal(_ index: Int, _ total: Int) -> String {
        String(localized: "review.groupNofTotal \(index) \(total)", bundle: .module)
    }

    public static func similarPhotos(_ count: Int) -> String {
        String(localized: "review.similarPhotos \(count)", bundle: .module)
    }

    // MARK: - Scan Progress (inline detection)

    public static let scanningWithInlineDetection: LocalizedStringResource = LocalizedStringResource("scan.inlineDetection.subtitle", bundle: .atURL(Bundle.module.bundleURL))
    public static let waitingForMoreGroups: LocalizedStringResource = LocalizedStringResource("scan.waitingForMoreGroups", bundle: .atURL(Bundle.module.bundleURL))
    public static let loadingGroup: LocalizedStringResource = LocalizedStringResource("scan.loadingGroup", bundle: .atURL(Bundle.module.bundleURL))

    public static func scanProgressStatus(_ processed: Int, _ total: Int) -> String {
        String(localized: "scan.progress.status \(processed) \(total)", bundle: .module)
    }

    public static func groupsFoundSoFar(_ count: Int) -> String {
        String(localized: "scan.progress.groupsFound \(count)", bundle: .module)
    }

    // MARK: - Onboarding

    public static let onboardingWelcomeSubtitle: LocalizedStringResource = LocalizedStringResource("onboarding.welcome.subtitle", bundle: .atURL(Bundle.module.bundleURL))
    public static let onboardingFeatureScanTitle: LocalizedStringResource = LocalizedStringResource("onboarding.feature.scan.title", bundle: .atURL(Bundle.module.bundleURL))
    public static let onboardingFeatureScanSubtitle: LocalizedStringResource = LocalizedStringResource("onboarding.feature.scan.subtitle", bundle: .atURL(Bundle.module.bundleURL))
    public static let onboardingFeatureVectorTitle: LocalizedStringResource = LocalizedStringResource("onboarding.feature.vector.title", bundle: .atURL(Bundle.module.bundleURL))
    public static let onboardingFeatureVectorSubtitle: LocalizedStringResource = LocalizedStringResource("onboarding.feature.vector.subtitle", bundle: .atURL(Bundle.module.bundleURL))
    public static let onboardingFeatureSwipeTitle: LocalizedStringResource = LocalizedStringResource("onboarding.feature.swipe.title", bundle: .atURL(Bundle.module.bundleURL))
    public static let onboardingFeatureSwipeSubtitle: LocalizedStringResource = LocalizedStringResource("onboarding.feature.swipe.subtitle", bundle: .atURL(Bundle.module.bundleURL))
    public static let onboardingPermissionTitle: LocalizedStringResource = LocalizedStringResource("onboarding.permission.title", bundle: .atURL(Bundle.module.bundleURL))
    public static let onboardingPermissionSubtitle: LocalizedStringResource = LocalizedStringResource("onboarding.permission.subtitle", bundle: .atURL(Bundle.module.bundleURL))
    public static let onboardingGrantAccess: LocalizedStringResource = LocalizedStringResource("onboarding.permission.grantAccess", bundle: .atURL(Bundle.module.bundleURL))
    public static let onboardingPermissionGranted: LocalizedStringResource = LocalizedStringResource("onboarding.permission.granted", bundle: .atURL(Bundle.module.bundleURL))
    public static let onboardingPermissionDenied: LocalizedStringResource = LocalizedStringResource("onboarding.permission.denied", bundle: .atURL(Bundle.module.bundleURL))
    public static let onboardingScanPeriodTitle: LocalizedStringResource = LocalizedStringResource("onboarding.scanPeriod.title", bundle: .atURL(Bundle.module.bundleURL))
    public static let onboardingScanPeriodSubtitle: LocalizedStringResource = LocalizedStringResource("onboarding.scanPeriod.subtitle", bundle: .atURL(Bundle.module.bundleURL))
    public static let onboardingNext: LocalizedStringResource = LocalizedStringResource("onboarding.next", bundle: .atURL(Bundle.module.bundleURL))
    public static let onboardingBack: LocalizedStringResource = LocalizedStringResource("onboarding.back", bundle: .atURL(Bundle.module.bundleURL))
    public static let onboardingGetStarted: LocalizedStringResource = LocalizedStringResource("onboarding.getStarted", bundle: .atURL(Bundle.module.bundleURL))

    // MARK: - Background

    public static let backgroundScanCompleteTitle = String(localized: "background.scan.completeTitle", bundle: .module)
    public static func backgroundScanCompleteBody(_ count: Int) -> String {
        String(localized: "background.scan.completeBody \(count)", bundle: .module)
    }

    // MARK: - Settings

    public static let settings: LocalizedStringResource = LocalizedStringResource("settings.title", bundle: .atURL(Bundle.module.bundleURL))
    public static let settingsScanPeriodHeader: LocalizedStringResource = LocalizedStringResource("settings.scanPeriod.header", bundle: .atURL(Bundle.module.bundleURL))
    public static let settingsScanPeriodFooter: LocalizedStringResource = LocalizedStringResource("settings.scanPeriod.footer", bundle: .atURL(Bundle.module.bundleURL))
    public static let settingsRescanButton: LocalizedStringResource = LocalizedStringResource("settings.scanPeriod.rescan", bundle: .atURL(Bundle.module.bundleURL))
    public static let similarityThreshold: LocalizedStringResource = LocalizedStringResource("settings.detection.similarityThreshold", bundle: .atURL(Bundle.module.bundleURL))
    public static let thresholdDescription: LocalizedStringResource = LocalizedStringResource("settings.detection.thresholdDescription", bundle: .atURL(Bundle.module.bundleURL))
    public static let detection: LocalizedStringResource = LocalizedStringResource("settings.detection.header", bundle: .atURL(Bundle.module.bundleURL))
    public static let indexedPhotos: LocalizedStringResource = LocalizedStringResource("settings.database.indexedPhotos", bundle: .atURL(Bundle.module.bundleURL))
    public static let clearDatabase: LocalizedStringResource = LocalizedStringResource("settings.database.clearDatabase", bundle: .atURL(Bundle.module.bundleURL))
    public static let clearing: LocalizedStringResource = LocalizedStringResource("settings.database.clearing", bundle: .atURL(Bundle.module.bundleURL))
    public static let databaseCleared: LocalizedStringResource = LocalizedStringResource("settings.database.cleared", bundle: .atURL(Bundle.module.bundleURL))
    public static let database: LocalizedStringResource = LocalizedStringResource("settings.database.header", bundle: .atURL(Bundle.module.bundleURL))
    public static let engine: LocalizedStringResource = LocalizedStringResource("settings.about.engine", bundle: .atURL(Bundle.module.bundleURL))
    public static let qdrantEdge: LocalizedStringResource = LocalizedStringResource("settings.about.qdrantEdge", bundle: .atURL(Bundle.module.bundleURL))
    public static let embeddings: LocalizedStringResource = LocalizedStringResource("settings.about.embeddings", bundle: .atURL(Bundle.module.bundleURL))
    public static let appleVision: LocalizedStringResource = LocalizedStringResource("settings.about.appleVision", bundle: .atURL(Bundle.module.bundleURL))
    public static let about: LocalizedStringResource = LocalizedStringResource("settings.about.header", bundle: .atURL(Bundle.module.bundleURL))

    // MARK: - Settings Statistics

    public static let settingsStatHeader: LocalizedStringResource = LocalizedStringResource("settings.stats.header", bundle: .atURL(Bundle.module.bundleURL))
    public static let settingsStatPhotosIndexed: LocalizedStringResource = LocalizedStringResource("settings.stats.photosIndexed", bundle: .atURL(Bundle.module.bundleURL))
    public static let settingsStatLastScan: LocalizedStringResource = LocalizedStringResource("settings.stats.lastScan", bundle: .atURL(Bundle.module.bundleURL))
    public static let settingsStatDuplicatesFound: LocalizedStringResource = LocalizedStringResource("settings.stats.duplicatesFound", bundle: .atURL(Bundle.module.bundleURL))
    public static let settingsStatPhotosDeleted: LocalizedStringResource = LocalizedStringResource("settings.stats.photosDeleted", bundle: .atURL(Bundle.module.bundleURL))

    // MARK: - Errors

    public static func authorizationError(_ detail: String) -> String {
        String(localized: "error.authorization \(detail)", bundle: .module)
    }

    public static func embeddingError(_ detail: String) -> String {
        String(localized: "error.embedding \(detail)", bundle: .module)
    }

    public static func vectorStoreError(_ detail: String) -> String {
        String(localized: "error.vectorStore \(detail)", bundle: .module)
    }

    public static func photoLibraryError(_ detail: String) -> String {
        String(localized: "error.photoLibrary \(detail)", bundle: .module)
    }

    public static func deletionError(_ detail: String) -> String {
        String(localized: "error.deletion \(detail)", bundle: .module)
    }

    public static func unexpectedError(_ detail: String) -> String {
        String(localized: "error.unexpected \(detail)", bundle: .module)
    }

    public static let photoAccessDenied = String(localized: "error.photoAccess.denied", bundle: .module)
    public static let photoAccessRestricted = String(localized: "error.photoAccess.restricted", bundle: .module)
    public static let photoAccessNotDetermined = String(localized: "error.photoAccess.notDetermined", bundle: .module)
    public static let photoAccessUnknown = String(localized: "error.photoAccess.unknown", bundle: .module)
}

#endif
