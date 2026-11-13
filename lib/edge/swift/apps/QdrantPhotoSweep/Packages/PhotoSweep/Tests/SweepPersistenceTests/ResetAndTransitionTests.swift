import Foundation
import Testing
import SweepDomain
import SweepPersistence
import SweepTestSupport
import SweepUseCases

@Suite struct ResetLocalDataTests {
    /// A store with vectors, a pass, a group, statistics and an open deletion.
    func populated(_ file: TemporaryStore, vectors: FakeVectorStore) async throws -> SwiftDataMetadataStore {
        let store = try file.open()
        try await store.saveWorkflowState(try workflow(revision: 3, generation: 2, paused: true))
        let records = try await store.register([discovered("a"), discovered("b")])
        try await store.beginPass(VectorizationPass(id: passID(1), kind: .initial, scope: scope, workSet: records.map(\.id)))
        try await VectorWriteTransaction(journal: store, vectorStore: vectors, ids: SequentialIDGenerator(startingAt: 500))
            .write(items(for: records), pass: passID(1))
        try await store.publishGroup(snapshot(1, discovery: 3, members: ["a", "b"]), derivedFrom: [], progress: DiscoveryProgress(revision: DiscoveryRevision(3)))
        try await store.recordDeletion(operation(70), photoCount: 1, estimatedBytes: 100, revision: DiscoveryRevision(3))
        try await store.beginDeletion(operation(80), group: groupID(1), revision: MembershipRevision(1), assets: [AssetID("b")], estimatedBytes: nil)
        return store
    }

    func expectReset(_ store: SwiftDataMetadataStore, vectors: FakeVectorStore) async throws {
        #expect(try await vectors.count() == 0)
        #expect(try await store.assets([AssetID("a"), AssetID("b")]).isEmpty)
        #expect(try await store.activePass() == nil)
        #expect(try await store.group(groupID(1)) == nil)
        #expect(try await store.discoveryProgress(for: DiscoveryRevision(3)) == nil)

        let state = try #require(try await store.loadWorkflowState())
        #expect(state.scope == scope)
        #expect(state.threshold == (try threshold(0.9)))
        #expect(state.pause == .none)
        #expect(!state.gate.isOpen)
        #expect(state.discoveryRevision > DiscoveryRevision(3))
        #expect(state.indexGeneration > IndexGeneration(2))

        // The started deletion must remain recoverable; confirmed history is kept.
        let entries = try await store.openJournalEntries()
        #expect(entries.map(\.id) == [operation(80)])
        #expect(try await store.statistics().deletedPhotos == 1)
    }

    @Test func resetClearsIndexAndMetadataButKeepsRecoverableDeletion() async throws {
        let file = try TemporaryStore()
        let vectors = FakeVectorStore()
        let store = try await populated(file, vectors: vectors)
        try await ResetLocalData(resetting: store, workflow: store, vectorStore: vectors, ids: SequentialIDGenerator(startingAt: 900)).execute()
        try await expectReset(try file.open(), vectors: vectors)
    }

    @Test func interruptedResetResumesOnRelaunch() async throws {
        let file = try TemporaryStore()
        let vectors = FakeVectorStore()
        let store = try await populated(file, vectors: vectors)
        // Crash right after the reset intent was journaled.
        try await store.beginReset(operation(90))

        let relaunched = try file.open()
        let report = try await recovery(store: relaunched, vectors: vectors).execute()
        #expect(report.resumedResets == [operation(90)])
        #expect(report.pendingDeletions == [operation(80)])
        try await expectReset(relaunched, vectors: vectors)
    }

    @Test func resetInterruptedAfterClearingVectorsResumes() async throws {
        let file = try TemporaryStore()
        let vectors = FakeVectorStore()
        let store = try await populated(file, vectors: vectors)
        try await store.beginReset(operation(90))
        try await vectors.delete(ids: try await vectors.scroll(offset: nil, limit: 100).records.map(\.id))

        let relaunched = try file.open()
        _ = try await recovery(store: relaunched, vectors: vectors).execute()
        try await expectReset(relaunched, vectors: vectors)
    }

    @Test func resetWithoutSavedWorkflowState() async throws {
        let store = try TemporaryStore().open()
        let vectors = FakeVectorStore()
        _ = try await store.register([discovered("a")])
        try await ResetLocalData(resetting: store, workflow: store, vectorStore: vectors, ids: SequentialIDGenerator(startingAt: 900)).execute()
        #expect(try await store.loadWorkflowState() == nil)
        #expect(try await store.assets([AssetID("a")]).isEmpty)
    }

    @Test func vectorStoreFailureLeavesResetResumable() async throws {
        let file = try TemporaryStore()
        let vectors = FakeVectorStore()
        let store = try await populated(file, vectors: vectors)
        await vectors.setFailure(.vectorStore("busy"))
        await #expect(throws: LocalDataError.vectorStore(.vectorStore("busy"))) {
            try await ResetLocalData(resetting: store, workflow: store, vectorStore: vectors, ids: SequentialIDGenerator(startingAt: 900)).execute()
        }
        await vectors.setFailure(nil)
        let report = try await recovery(store: try file.open(), vectors: vectors).execute()
        #expect(report.resumedResets.count == 1)
        try await expectReset(try file.open(), vectors: vectors)
    }

    @Test func resetNeverTouchesLibraryPhotos() async throws {
        // ResetLocalData has no photo library dependency at all; this records that the
        // library fake stays untouched while a full reset runs next to it.
        let library = FakePhotoLibrary(assets: [PhotoAsset(id: "p", localIdentifier: "p", creationDate: nil, pixelWidth: 1, pixelHeight: 1, fileSize: nil)])
        let file = try TemporaryStore()
        let vectors = FakeVectorStore()
        let store = try await populated(file, vectors: vectors)
        try await ResetLocalData(resetting: store, workflow: store, vectorStore: vectors, ids: SequentialIDGenerator(startingAt: 900)).execute()
        #expect(await library.deletedIdentifiers.isEmpty)
        #expect(await library.assets.count == 1)
    }
}

@Suite struct LocalDataLocationTests {
    @Test func namespaceIsVersionedAndSeparateFromLegacyStore() throws {
        let support = URL(filePath: "/tmp/support", directoryHint: .isDirectory)
        let location = LocalDataLocation(applicationSupport: support)
        #expect(location.root.path.hasSuffix("PhotoSweep/v1"))
        #expect(location.metadataStoreURL.lastPathComponent == "metadata.store")
        #expect(location.vectorIndexDirectory.path.hasSuffix("PhotoSweep/v1/vectors"))
        let legacy = LegacyDataTransition.Inventory.legacyApp(documents: support, applicationSupport: support)
        #expect(!legacy.files.contains { $0.path.hasPrefix(location.root.path) })
    }

    @Test func storeOpensInsidePreparedNamespace() async throws {
        let file = try TemporaryStore()
        let location = LocalDataLocation(applicationSupport: file.directory)
        try location.prepare()
        let store = SwiftDataMetadataStore(container: try MetadataStoreFactory.makeContainer(storeURL: location.metadataStoreURL))
        try await store.saveWorkflowState(try workflow())
        #expect(FileManager.default.fileExists(atPath: location.metadataStoreURL.path))
    }
}

@Suite struct LegacyDataTransitionTests {
    final class Sandbox {
        let root: URL
        let documents: URL
        let support: URL
        let suiteName = "PhotoSweepTests.\(UUID().uuidString)"
        let defaults: UserDefaults

        init() throws {
            root = FileManager.default.temporaryDirectory.appending(path: "LegacyTransition-\(UUID().uuidString)", directoryHint: .isDirectory)
            documents = root.appending(path: "Documents", directoryHint: .isDirectory)
            support = root.appending(path: "Application Support", directoryHint: .isDirectory)
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: documents.appending(path: "qdrant-edge/segments", directoryHint: .isDirectory), withIntermediateDirectories: true)
            try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
            try Data("768".utf8).write(to: documents.appending(path: "qdrant-edge-dims"))
            for name in ["default.store", "default.store-shm", "default.store-wal"] {
                try Data().write(to: support.appending(path: name))
            }
            // Unrelated user and rewrite files must survive.
            try Data("keep".utf8).write(to: documents.appending(path: "notes.txt"))
            let namespace = LocalDataLocation(applicationSupport: support)
            try namespace.prepare()
            try Data().write(to: namespace.metadataStoreURL)
            guard let defaults = UserDefaults(suiteName: suiteName) else { throw SandboxError.noDefaults }
            self.defaults = defaults
            for key in ["hasCompletedOnboarding", "similarityThreshold", "scanPreset", "unrelatedKey"] {
                defaults.set(true, forKey: key)
            }
        }

        deinit {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        var transition: LegacyDataTransition {
            LegacyDataTransition(inventory: .legacyApp(documents: documents, applicationSupport: support), defaults: defaults)
        }

        func exists(_ url: URL) -> Bool {
            FileManager.default.fileExists(atPath: url.path)
        }
    }

    enum SandboxError: Error {
        case noDefaults
    }

    @Test func retiresLegacyDataOnlyOnce() throws {
        let sandbox = try Sandbox()
        guard case .retired(let removed) = try sandbox.transition.run() else {
            Issue.record("Expected legacy data to be retired")
            return
        }
        #expect(removed.count == 5)
        #expect(!sandbox.exists(sandbox.documents.appending(path: "qdrant-edge")))
        #expect(!sandbox.exists(sandbox.support.appending(path: "default.store")))
        #expect(sandbox.defaults.object(forKey: "hasCompletedOnboarding") == nil)
        #expect(sandbox.defaults.object(forKey: "similarityThreshold") == nil)
        #expect(sandbox.transition.isCurrent)

        #expect(try sandbox.transition.run() == .alreadyCurrent)
    }

    @Test func keepsRewriteNamespaceAndUnrelatedData() throws {
        let sandbox = try Sandbox()
        _ = try sandbox.transition.run()
        #expect(sandbox.exists(LocalDataLocation(applicationSupport: sandbox.support).metadataStoreURL))
        #expect(sandbox.exists(sandbox.documents.appending(path: "notes.txt")))
        #expect(sandbox.defaults.bool(forKey: "unrelatedKey"))
    }

    @Test func interruptedTransitionCompletesOnRerun() throws {
        let sandbox = try Sandbox()
        // Simulate a crash after some items were removed but before the marker was written.
        try FileManager.default.removeItem(at: sandbox.documents.appending(path: "qdrant-edge"))
        try FileManager.default.removeItem(at: sandbox.support.appending(path: "default.store"))
        guard case .retired(let removed) = try sandbox.transition.run() else {
            Issue.record("Expected the remaining legacy data to be retired")
            return
        }
        #expect(removed.count == 3)
        #expect(sandbox.transition.isCurrent)
    }

    @Test func freshInstallOnlyWritesMarker() throws {
        let sandbox = try Sandbox()
        try FileManager.default.removeItem(at: sandbox.documents.appending(path: "qdrant-edge"))
        try FileManager.default.removeItem(at: sandbox.documents.appending(path: "qdrant-edge-dims"))
        for name in ["default.store", "default.store-shm", "default.store-wal"] {
            try FileManager.default.removeItem(at: sandbox.support.appending(path: name))
        }
        #expect(try sandbox.transition.run() == .retired(removed: []))
        #expect(sandbox.transition.isCurrent)
    }
}
