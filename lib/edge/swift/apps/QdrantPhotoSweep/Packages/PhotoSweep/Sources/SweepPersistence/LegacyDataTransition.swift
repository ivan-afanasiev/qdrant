import Foundation
import SweepDomain

/// One-time clean start for the rewrite: retires the legacy index, metadata store and
/// preferences without migrating them. Library photos are never touched.
///
/// Idempotent and restartable: items are removed first and the namespace marker is written
/// last, so an interrupted run simply repeats. Run it only after the legacy engine has been
/// removed; running it alongside the legacy app would delete that app's live data.
public struct LegacyDataTransition {
    public struct Inventory: Equatable, Sendable {
        public let files: [URL]
        public let defaultsKeys: [String]

        public init(files: [URL], defaultsKeys: [String]) {
            self.files = files
            self.defaultsKeys = defaultsKeys
        }

        /// Everything the pre-rewrite app stored, per the step 2 baseline inventory.
        public static func legacyApp(documents: URL, applicationSupport: URL) -> Inventory {
            Inventory(
                files: [
                    documents.appending(path: "qdrant-edge", directoryHint: .isDirectory),
                    documents.appending(path: "qdrant-edge-dims"),
                    applicationSupport.appending(path: "default.store"),
                    applicationSupport.appending(path: "default.store-shm"),
                    applicationSupport.appending(path: "default.store-wal"),
                ],
                defaultsKeys: [
                    "hasCompletedOnboarding", "similarityThreshold", "scanPreset",
                    "customRangeStart", "customRangeEnd", "isCustomRange",
                ]
            )
        }
    }

    public enum Outcome: Equatable, Sendable {
        case alreadyCurrent
        /// Paths that existed and were removed in this run.
        case retired(removed: [URL])
    }

    public static let markerKey = "photoSweep.localDataNamespace"

    private let inventory: Inventory
    private let defaults: UserDefaults
    private let namespaceVersion: Int

    public init(inventory: Inventory, defaults: UserDefaults, namespaceVersion: Int = LocalDataLocation.namespaceVersion) {
        self.inventory = inventory
        self.defaults = defaults
        self.namespaceVersion = namespaceVersion
    }

    public var isCurrent: Bool {
        defaults.integer(forKey: Self.markerKey) >= namespaceVersion
    }

    public func run() throws(PersistenceError) -> Outcome {
        guard !isCurrent else { return .alreadyCurrent }
        var removed: [URL] = []
        for url in inventory.files where FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                throw .storeUnavailable("Cannot remove legacy item \(url.lastPathComponent): \(error.localizedDescription)")
            }
            removed.append(url)
        }
        for key in inventory.defaultsKeys {
            defaults.removeObject(forKey: key)
        }
        defaults.set(namespaceVersion, forKey: Self.markerKey)
        return .retired(removed: removed)
    }
}
