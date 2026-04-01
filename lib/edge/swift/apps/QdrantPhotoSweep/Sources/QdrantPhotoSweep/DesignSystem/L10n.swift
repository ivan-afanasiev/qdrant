import SwiftUI

enum L10n {
    // MARK: - App

    static let appTitle: LocalizedStringKey = "Qdrant PhotoSweep"
    static let loading: LocalizedStringKey = "Loading..."

    // MARK: - Authorization

    static let photoAccessRequired: LocalizedStringKey = "Photo Access Required"
    static let openSettings: LocalizedStringKey = "Open Settings"

    // MARK: - Date Range Picker

    static let selectTimeRange: LocalizedStringKey = "Select Time Range"
    static let selectTimeRangeSubtitle: LocalizedStringKey = "Choose which photos to scan for duplicates"
    static let quickSelect: LocalizedStringKey = "Quick Select"
    static let customRange: LocalizedStringKey = "Custom Range"
    static let from: LocalizedStringKey = "From"
    static let to: LocalizedStringKey = "to"
    static let toLabel: LocalizedStringKey = "To"
    static let countingPhotos: LocalizedStringKey = "Counting photos..."
    static let startScanning: LocalizedStringKey = "Start Scanning"

    static func photosFound(_ count: Int) -> String {
        String(localized: "\(count) photos found")
    }

    // MARK: - Presets

    static let lastWeek: LocalizedStringKey = "Last Week"
    static let lastMonth: LocalizedStringKey = "Last Month"
    static let last3Months: LocalizedStringKey = "Last 3 Months"
    static let last6Months: LocalizedStringKey = "Last 6 Months"
    static let lastYear: LocalizedStringKey = "Last Year"
    static let allTime: LocalizedStringKey = "All Time"

    // MARK: - Scan

    static let scanning: LocalizedStringKey = "Scanning"
    static let preparingToScan: LocalizedStringKey = "Preparing to scan..."
    static let embeddingPhotos: LocalizedStringKey = "Embedding photos..."
    static let embeddingSubtitle: LocalizedStringKey = "Processing images and building vector database"
    static let cancel: LocalizedStringKey = "Cancel"
    static let scanComplete: LocalizedStringKey = "Scan Complete"
    static let findDuplicates: LocalizedStringKey = "Find Duplicates"
    static let scanFailed: LocalizedStringKey = "Scan Failed"
    static let scanCancelled: LocalizedStringKey = "Scan Cancelled"
    static let retry: LocalizedStringKey = "Retry"

    static func photosIndexed(_ count: Int) -> String {
        String(localized: "\(count) photos indexed")
    }

    // MARK: - Review

    static let reviewDuplicates: LocalizedStringKey = "Review Duplicates"
    static let noDuplicatesFound: LocalizedStringKey = "No Duplicates Found"
    static let libraryLooksClean: LocalizedStringKey = "Your photo library looks clean!"
    static let done: LocalizedStringKey = "Done"
    static let skip: LocalizedStringKey = "Skip"
    static let tapToKeepHint: LocalizedStringKey = "Tap a photo to keep it, others will be marked for deletion"
    static let readyToCleanUp: LocalizedStringKey = "Ready to Clean Up"
    static let groupsReviewed: LocalizedStringKey = "Groups reviewed"
    static let photosToDelete: LocalizedStringKey = "Photos to delete"
    static let photosToKeep: LocalizedStringKey = "Photos to keep"
    static let photosCleaned: LocalizedStringKey = "Photos cleaned"
    static let deletedPhotosNote: LocalizedStringKey = "Deleted photos will be moved to Recently Deleted"
    static let deletingPhotos: LocalizedStringKey = "Deleting photos..."
    static let allDone: LocalizedStringKey = "All Done!"
    static let finish: LocalizedStringKey = "Finish"
    static let error: LocalizedStringKey = "Error"
    static let unknownDate: LocalizedStringKey = "Unknown date"

    static func deleteNPhotos(_ count: Int) -> String {
        String(localized: "Delete \(count) Photos")
    }

    static func groupNofTotal(_ index: Int, _ total: Int) -> String {
        String(localized: "Group \(index) of \(total)")
    }

    static func similarPhotos(_ count: Int) -> String {
        String(localized: "\(count) similar photos")
    }

    // MARK: - Settings

    static let settings: LocalizedStringKey = "Settings"
    static let similarityThreshold: LocalizedStringKey = "Similarity Threshold"
    static let thresholdDescription: LocalizedStringKey = "Higher values find only very similar photos. Lower values find more potential duplicates."
    static let detection: LocalizedStringKey = "Detection"
    static let indexedPhotos: LocalizedStringKey = "Indexed Photos"
    static let clearDatabase: LocalizedStringKey = "Clear Database"
    static let clearing: LocalizedStringKey = "Clearing..."
    static let databaseCleared: LocalizedStringKey = "Database cleared"
    static let database: LocalizedStringKey = "Database"
    static let engine: LocalizedStringKey = "Engine"
    static let qdrantEdge: LocalizedStringKey = "Qdrant Edge"
    static let embeddings: LocalizedStringKey = "Embeddings"
    static let appleVision: LocalizedStringKey = "Apple Vision"
    static let dimensions: LocalizedStringKey = "Dimensions"
    static let about: LocalizedStringKey = "About"

    // MARK: - Errors

    static func authorizationError(_ detail: String) -> String {
        String(localized: "Authorization failed: \(detail)")
    }

    static func embeddingError(_ detail: String) -> String {
        String(localized: "Embedding failed: \(detail)")
    }

    static func vectorStoreError(_ detail: String) -> String {
        String(localized: "Vector store error: \(detail)")
    }

    static func photoLibraryError(_ detail: String) -> String {
        String(localized: "Photo library error: \(detail)")
    }

    static func deletionError(_ detail: String) -> String {
        String(localized: "Deletion failed: \(detail)")
    }

    static func unexpectedError(_ detail: String) -> String {
        String(localized: "Unexpected error: \(detail)")
    }

    static let photoAccessDenied = String(localized: "Photo library access was denied. Enable in Settings.")
    static let photoAccessRestricted = String(localized: "Photo library access is restricted on this device.")
    static let photoAccessNotDetermined = String(localized: "Photo library authorization was not determined.")
    static let photoAccessUnknown = String(localized: "Unknown photo library authorization status.")
}
