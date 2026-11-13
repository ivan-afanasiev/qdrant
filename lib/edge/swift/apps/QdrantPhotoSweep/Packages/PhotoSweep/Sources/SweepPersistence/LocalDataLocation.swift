import Foundation
import SwiftData
import SweepDomain

/// Versioned on-disk namespace for rewrite data, separate from every legacy location.
public struct LocalDataLocation: Equatable, Sendable {
    public static let namespaceVersion = 1

    public let root: URL

    /// - Parameter applicationSupport: the app's Application Support directory.
    public init(applicationSupport: URL) {
        root = applicationSupport.appending(path: "PhotoSweep/v\(Self.namespaceVersion)", directoryHint: .isDirectory)
    }

    public var metadataStoreURL: URL { root.appending(path: "metadata.store") }
    public var vectorIndexDirectory: URL { root.appending(path: "vectors", directoryHint: .isDirectory) }

    /// Creates the namespace directories if needed.
    public func prepare() throws(PersistenceError) {
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            throw .storeUnavailable("Cannot create \(root.path): \(error.localizedDescription)")
        }
    }
}

public enum MetadataStoreFactory {
    /// Opens (or creates) the versioned metadata store at `url`.
    public static func makeContainer(storeURL url: URL) throws(PersistenceError) -> ModelContainer {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let schema = Schema(versionedSchema: PhotoSweepSchemaV1.self)
            let configuration = ModelConfiguration(schema: schema, url: url)
            return try ModelContainer(for: schema, migrationPlan: PhotoSweepMigrationPlan.self, configurations: configuration)
        } catch {
            throw .storeUnavailable("Cannot open metadata store: \(error)")
        }
    }

    /// In-memory store for tests and previews.
    public static func makeInMemoryContainer() throws(PersistenceError) -> ModelContainer {
        do {
            let schema = Schema(versionedSchema: PhotoSweepSchemaV1.self)
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, migrationPlan: PhotoSweepMigrationPlan.self, configurations: configuration)
        } catch {
            throw .storeUnavailable("Cannot create in-memory metadata store: \(error)")
        }
    }
}
