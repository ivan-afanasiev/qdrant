import Foundation
import Testing
import SweepDomain
import SweepPersistence
import SweepTestSupport
import SweepUseCases

/// Forwards to the real store but fails the metadata commit, like a crash at that boundary.
private struct FailingCommitJournal: VectorWriteJournaling {
    let base: SwiftDataMetadataStore

    func beginVectorWrite(_ operation: OperationID, intents: [VectorWriteIntent]) async throws(PersistenceError) {
        try await base.beginVectorWrite(operation, intents: intents)
    }

    func commitVectorWrite(_ operation: OperationID, pass: VectorizationPassID?) async throws(PersistenceError) {
        throw .saveFailed("injected")
    }

    func abandonVectorWrite(_ operation: OperationID) async throws(PersistenceError) {
        try await base.abandonVectorWrite(operation)
    }
}

@Suite struct AssetRegistrationTests {
    @Test func assetsSurviveReopenWithStablePointIDs() async throws {
        let file = try TemporaryStore()
        let first = try await file.open().register([discovered("a"), discovered("b")])
        #expect(Set(first.map(\.pointID)).count == 2)
        #expect(first.allSatisfy { $0.state == .pending })

        let reopened = try await file.open().assets([AssetID("a"), AssetID("b")])
        #expect(reopened[AssetID("a")] == first[0])
        #expect(reopened[AssetID("b")] == first[1])
    }

    @Test func pointIDsNeverCollideEvenWhenGeneratorRepeats() async throws {
        let file = try TemporaryStore()
        let a = try await file.open(ids: SequentialIDGenerator()).register([discovered("a")])
        // A fresh generator proposes the same first UUID again; the store must skip it.
        let b = try await file.open(ids: SequentialIDGenerator()).register([discovered("b")])
        #expect(a[0].pointID != b[0].pointID)
    }

    @Test func editedContentReturnsVectorizedAssetToPending() async throws {
        let file = try TemporaryStore()
        let store = try file.open()
        let records = try await store.register([discovered("a")])
        try await VectorWriteTransaction(journal: store, vectorStore: FakeVectorStore(), ids: SequentialIDGenerator(startingAt: 500))
            .write(items(for: records), pass: nil)
        #expect(try await store.assets([AssetID("a")])[AssetID("a")]?.storedVector != nil)

        let edited = try await store.register([discovered("a", revision: "r2")])
        #expect(edited[0].state == .pending)
        #expect(edited[0].storedVector == nil)
        #expect(edited[0].pointID == records[0].pointID)
    }

    @Test func removedAssetsAreGone() async throws {
        let store = try TemporaryStore().open()
        _ = try await store.register([discovered("a"), discovered("b")])
        try await store.removeAssets([AssetID("a")])
        #expect(try await store.assets([AssetID("a"), AssetID("b")]).keys.sorted() == [AssetID("b")])
    }
}

@Suite struct VectorWriteRecoveryTests {
    @Test func transactionCommitsVectorsMetadataAndPassTogether() async throws {
        let file = try TemporaryStore()
        let store = try file.open()
        let vectors = FakeVectorStore()
        let records = try await store.register([discovered("a"), discovered("b")])
        let pass = VectorizationPass(id: passID(1), kind: .initial, scope: scope, workSet: records.map(\.id))
        try await store.beginPass(pass)

        try await VectorWriteTransaction(journal: store, vectorStore: vectors, ids: SequentialIDGenerator(startingAt: 500))
            .write(items(for: records), pass: pass.id)

        let reopened = try file.open()
        #expect(try await vectors.count() == 2)
        #expect(try await reopened.openJournalEntries().isEmpty)
        let stored = try await reopened.assets(records.map(\.id))
        #expect(stored.values.allSatisfy { $0.storedVector == StoredVector(
            assetID: $0.id, contentRevision: AssetContentRevision("r1"), compatibility: compatibility, generation: generation, isCommitted: true
        ) })
        #expect(try await reopened.activePass()?.isComplete == true)
    }

    @Test func crashAfterIntentBeforeUpsertRollsBack() async throws {
        let file = try TemporaryStore()
        let vectors = FakeVectorStore()
        let records = try await file.open().register([discovered("a")])
        try await file.open().beginVectorWrite(operation(1), intents: records.map(intent(for:)))

        let relaunched = try file.open()
        let report = try await recovery(store: relaunched, vectors: vectors).execute()
        #expect(report.rolledBackVectorWrites == [operation(1)])
        #expect(try await relaunched.openJournalEntries().isEmpty)
        #expect(try await relaunched.assets([AssetID("a")])[AssetID("a")]?.state == .pending)
    }

    @Test func pointWrittenWithoutMetadataCommitIsNotTreatedAsSuccess() async throws {
        let file = try TemporaryStore()
        let vectors = FakeVectorStore()
        let records = try await file.open().register([discovered("a")])
        // Crash between the vector store write and the metadata commit.
        try await file.open().beginVectorWrite(operation(1), intents: records.map(intent(for:)))
        try await vectors.upsert(points: [VectorPoint(id: records[0].pointID.storeKey, vector: [1, 0, 0], payloadJson: "{}")])

        let relaunched = try file.open()
        let report = try await recovery(store: relaunched, vectors: vectors).execute()
        #expect(report.rolledBackVectorWrites == [operation(1)])
        #expect(try await vectors.count() == 0)
        #expect(try await relaunched.assets([AssetID("a")])[AssetID("a")]?.state == .pending)
    }

    @Test func crashAfterCommitNeedsNoRecovery() async throws {
        let file = try TemporaryStore()
        let vectors = FakeVectorStore()
        let store = try file.open()
        let records = try await store.register([discovered("a")])
        try await VectorWriteTransaction(journal: store, vectorStore: vectors, ids: SequentialIDGenerator(startingAt: 500))
            .write(items(for: records), pass: nil)

        let relaunched = try file.open()
        #expect(try await recovery(store: relaunched, vectors: vectors).execute() == RecoveryReport())
        #expect(try await vectors.count() == 1)
        #expect(try await relaunched.assets([AssetID("a")])[AssetID("a")]?.storedVector != nil)
    }

    @Test func recoveryIsIdempotent() async throws {
        let file = try TemporaryStore()
        let vectors = FakeVectorStore()
        let records = try await file.open().register([discovered("a")])
        try await file.open().beginVectorWrite(operation(1), intents: records.map(intent(for:)))

        let relaunched = try file.open()
        _ = try await recovery(store: relaunched, vectors: vectors).execute()
        #expect(try await recovery(store: try file.open(), vectors: vectors).execute() == RecoveryReport())
    }

    @Test func vectorStoreFailureRollsBackImmediately() async throws {
        let store = try TemporaryStore().open()
        let vectors = FakeVectorStore()
        await vectors.setFailure(.vectorStore("busy"))
        let records = try await store.register([discovered("a")])
        await #expect(throws: VectorWriteError.vectorStore(.vectorStore("busy"))) {
            try await VectorWriteTransaction(journal: store, vectorStore: vectors, ids: SequentialIDGenerator(startingAt: 500))
                .write(items(for: records), pass: nil)
        }
        #expect(try await store.openJournalEntries().isEmpty)
        #expect(try await store.assets([AssetID("a")])[AssetID("a")]?.state == .pending)
        guard case .transient = VectorWriteError.vectorStore(.vectorStore("busy")).failure else {
            Issue.record("A vector store failure must classify as transient infrastructure, not asset unavailability")
            return
        }
    }

    @Test func failedCommitLeavesEntryForRecovery() async throws {
        let file = try TemporaryStore()
        let store = try file.open()
        let vectors = FakeVectorStore()
        let records = try await store.register([discovered("a")])
        await #expect(throws: VectorWriteError.commitFailed(.saveFailed("injected"))) {
            try await VectorWriteTransaction(journal: FailingCommitJournal(base: store), vectorStore: vectors, ids: SequentialIDGenerator(startingAt: 500))
                .write(items(for: records), pass: nil)
        }
        #expect(try await store.openJournalEntries().count == 1)
        #expect(try await vectors.count() == 1)

        let report = try await recovery(store: try file.open(), vectors: vectors).execute()
        #expect(report.rolledBackVectorWrites.count == 1)
        #expect(try await vectors.count() == 0)
    }

    @Test func assetEditedDuringWriteStaysPending() async throws {
        let store = try TemporaryStore().open()
        let records = try await store.register([discovered("a")])
        try await store.beginVectorWrite(operation(1), intents: records.map(intent(for:)))
        _ = try await store.register([discovered("a", revision: "r2")])
        try await store.commitVectorWrite(operation(1), pass: nil)
        #expect(try await store.assets([AssetID("a")])[AssetID("a")]?.state == .pending)
    }
}
