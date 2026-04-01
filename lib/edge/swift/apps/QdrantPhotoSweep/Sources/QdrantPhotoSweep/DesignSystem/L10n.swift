import SwiftUI

enum L10n {
    // MARK: - App

    static let appTitle: LocalizedStringKey = "app.title"
    static let loading: LocalizedStringKey = "app.loading"

    // MARK: - Authorization

    static let photoAccessRequired: LocalizedStringKey = "auth.photoAccessRequired"
    static let openSettings: LocalizedStringKey = "auth.openSettings"

    // MARK: - Date Range Picker

    static let selectTimeRange: LocalizedStringKey = "dateRangePicker.selectTimeRange"
    static let selectTimeRangeSubtitle: LocalizedStringKey = "dateRangePicker.selectTimeRangeSubtitle"
    static let quickSelect: LocalizedStringKey = "dateRangePicker.quickSelect"
    static let customRange: LocalizedStringKey = "dateRangePicker.customRange"
    static let from: LocalizedStringKey = "dateRangePicker.from"
    static let to: LocalizedStringKey = "dateRangePicker.to"
    static let toLabel: LocalizedStringKey = "dateRangePicker.toLabel"
    static let countingPhotos: LocalizedStringKey = "dateRangePicker.countingPhotos"
    static let startScanning: LocalizedStringKey = "dateRangePicker.startScanning"

    static func photosFound(_ count: Int) -> String {
        String(localized: "dateRangePicker.photosFound \(count)")
    }

    // MARK: - Presets

    static let lastWeek: LocalizedStringKey = "preset.lastWeek"
    static let lastMonth: LocalizedStringKey = "preset.lastMonth"
    static let last3Months: LocalizedStringKey = "preset.last3Months"
    static let last6Months: LocalizedStringKey = "preset.last6Months"
    static let lastYear: LocalizedStringKey = "preset.lastYear"
    static let allTime: LocalizedStringKey = "preset.allTime"

    // MARK: - Scan

    static let scanning: LocalizedStringKey = "scan.title"
    static let preparingToScan: LocalizedStringKey = "scan.preparing"
    static let embeddingPhotos: LocalizedStringKey = "scan.embedding"
    static let embeddingSubtitle: LocalizedStringKey = "scan.embeddingSubtitle"
    static let cancel: LocalizedStringKey = "scan.cancel"
    static let scanComplete: LocalizedStringKey = "scan.complete"
    static let findDuplicates: LocalizedStringKey = "scan.findDuplicates"
    static let scanFailed: LocalizedStringKey = "scan.failed"
    static let scanCancelled: LocalizedStringKey = "scan.cancelled"
    static let retry: LocalizedStringKey = "scan.retry"

    static func photosIndexed(_ count: Int) -> String {
        String(localized: "scan.photosIndexed \(count)")
    }

    // MARK: - Review

    static let reviewDuplicates: LocalizedStringKey = "review.title"
    static let noDuplicatesFound: LocalizedStringKey = "review.noDuplicatesFound"
    static let libraryLooksClean: LocalizedStringKey = "review.libraryLooksClean"
    static let done: LocalizedStringKey = "review.done"
    static let skip: LocalizedStringKey = "review.skip"
    static let tapToKeepHint: LocalizedStringKey = "review.tapToKeepHint"
    static let readyToCleanUp: LocalizedStringKey = "review.readyToCleanUp"
    static let groupsReviewed: LocalizedStringKey = "review.stats.groupsReviewed"
    static let photosToDelete: LocalizedStringKey = "review.stats.photosToDelete"
    static let photosToKeep: LocalizedStringKey = "review.stats.photosToKeep"
    static let photosCleaned: LocalizedStringKey = "review.stats.photosCleaned"
    static let deletedPhotosNote: LocalizedStringKey = "review.deletedPhotosNote"
    static let deletingPhotos: LocalizedStringKey = "review.deletingPhotos"
    static let allDone: LocalizedStringKey = "review.allDone"
    static let finish: LocalizedStringKey = "review.finish"
    static let error: LocalizedStringKey = "review.error"
    static let unknownDate: LocalizedStringKey = "review.unknownDate"

    static func deleteNPhotos(_ count: Int) -> String {
        String(localized: "review.deleteNPhotos \(count)")
    }

    static func groupNofTotal(_ index: Int, _ total: Int) -> String {
        String(localized: "review.groupNofTotal \(index) \(total)")
    }

    static func similarPhotos(_ count: Int) -> String {
        String(localized: "review.similarPhotos \(count)")
    }

    // MARK: - Settings

    static let settings: LocalizedStringKey = "settings.title"
    static let similarityThreshold: LocalizedStringKey = "settings.detection.similarityThreshold"
    static let thresholdDescription: LocalizedStringKey = "settings.detection.thresholdDescription"
    static let detection: LocalizedStringKey = "settings.detection.header"
    static let indexedPhotos: LocalizedStringKey = "settings.database.indexedPhotos"
    static let clearDatabase: LocalizedStringKey = "settings.database.clearDatabase"
    static let clearing: LocalizedStringKey = "settings.database.clearing"
    static let databaseCleared: LocalizedStringKey = "settings.database.cleared"
    static let database: LocalizedStringKey = "settings.database.header"
    static let engine: LocalizedStringKey = "settings.about.engine"
    static let qdrantEdge: LocalizedStringKey = "settings.about.qdrantEdge"
    static let embeddings: LocalizedStringKey = "settings.about.embeddings"
    static let appleVision: LocalizedStringKey = "settings.about.appleVision"
    static let about: LocalizedStringKey = "settings.about.header"

    // MARK: - Errors

    static func authorizationError(_ detail: String) -> String {
        String(localized: "error.authorization \(detail)")
    }

    static func embeddingError(_ detail: String) -> String {
        String(localized: "error.embedding \(detail)")
    }

    static func vectorStoreError(_ detail: String) -> String {
        String(localized: "error.vectorStore \(detail)")
    }

    static func photoLibraryError(_ detail: String) -> String {
        String(localized: "error.photoLibrary \(detail)")
    }

    static func deletionError(_ detail: String) -> String {
        String(localized: "error.deletion \(detail)")
    }

    static func unexpectedError(_ detail: String) -> String {
        String(localized: "error.unexpected \(detail)")
    }

    static let photoAccessDenied = String(localized: "error.photoAccess.denied")
    static let photoAccessRestricted = String(localized: "error.photoAccess.restricted")
    static let photoAccessNotDetermined = String(localized: "error.photoAccess.notDetermined")
    static let photoAccessUnknown = String(localized: "error.photoAccess.unknown")
}
