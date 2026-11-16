import SweepDomain

public enum LocalDataError: Error, Equatable, Sendable {
    case persistence(PersistenceError)
    case vectorStore(AdapterError)
}

// MARK: - Vector writes

public struct VectorWriteItem: Sendable {
    public let intent: VectorWriteIntent
    public let vector: [Float]
    public let payloadJson: String

    public init(intent: VectorWriteIntent, vector: [Float], payloadJson: String) {
        self.intent = intent
        self.vector = vector
        self.payloadJson = payloadJson
    }
}

public enum VectorWriteError: Error, Equatable, Sendable {
    /// The intent could not be journaled; nothing was written.
    case journal(PersistenceError)
    /// The vector store rejected the write; written points were rolled back.
    case vectorStore(AdapterError)
    /// Points may exist without committed metadata; `RecoverPendingOperations` rolls them back.
    case commitFailed(PersistenceError)

    /// Classification for `RetryPolicy`: none of these is the asset's fault.
    public var failure: VectorizationFailure {
        switch self {
        case .journal(let error), .commitFailed(let error): .systemic(String(describing: error))
        case .vectorStore(let error): .transient(String(describing: error))
        }
    }
}

/// Journal intent → vector store upsert → metadata commit that closes the journal.
/// A crash at any boundary leaves an open entry that recovery rolls back, so success
/// is never inferred from point existence alone.
public struct VectorWriteTransaction: Sendable {
    private let journal: any VectorWriteJournaling
    private let vectorStore: any VectorStoring
    private let ids: any IDGenerating

    public init(journal: any VectorWriteJournaling, vectorStore: any VectorStoring, ids: any IDGenerating) {
        self.journal = journal
        self.vectorStore = vectorStore
        self.ids = ids
    }

    @discardableResult
    public func write(_ items: [VectorWriteItem], pass: VectorizationPassID?) async throws(VectorWriteError) -> OperationID {
        let operation = OperationID(ids.makeUUID())
        do {
            try await journal.beginVectorWrite(operation, intents: items.map(\.intent))
        } catch {
            throw .journal(error)
        }
        do {
            try await vectorStore.upsert(points: items.map {
                VectorPoint(id: $0.intent.pointID.storeKey, vector: $0.vector, payloadJson: $0.payloadJson)
            })
        } catch {
            // Best-effort rollback; if it fails, the open entry is rolled back during recovery.
            try? await vectorStore.delete(ids: items.map(\.intent.pointID.storeKey))
            try? await journal.abandonVectorWrite(operation)
            throw .vectorStore(error)
        }
        do {
            try await journal.commitVectorWrite(operation, pass: pass)
        } catch {
            throw .commitFailed(error)
        }
        return operation
    }
}

// MARK: - Reset

/// Restartable reset of the vector index and all local metadata. Library photos are never
/// touched; open deletion journals are preserved so started deletions still reconcile.
///
/// Precondition: the caller has stopped vectorization and discovery mutations and
/// invalidated their effects before calling `execute()`.
public struct ResetLocalData: Sendable {
    private let resetting: any LocalDataResetting
    private let workflow: any WorkflowStateRepository
    private let vectorStore: any VectorStoring
    private let ids: any IDGenerating
    private let pageSize: Int

    public init(
        resetting: any LocalDataResetting,
        workflow: any WorkflowStateRepository,
        vectorStore: any VectorStoring,
        ids: any IDGenerating,
        pageSize: Int = 500
    ) {
        self.resetting = resetting
        self.workflow = workflow
        self.vectorStore = vectorStore
        self.ids = ids
        self.pageSize = pageSize
    }

    @discardableResult
    public func execute() async throws(LocalDataError) -> OperationID {
        let operation = OperationID(ids.makeUUID())
        do {
            try await resetting.beginReset(operation)
        } catch {
            throw .persistence(error)
        }
        try await resume(operation)
        return operation
    }

    /// Continues a reset whose journal entry is still open. Safe to repeat.
    public func resume(_ operation: OperationID) async throws(LocalDataError) {
        try await clearVectorStore()
        do {
            let current = try await workflow.loadWorkflowState()
            try await resetting.clearMetadataForReset(keeping: current?.afterReset())
            try await resetting.finishReset(operation)
        } catch {
            throw .persistence(error)
        }
    }

    private func clearVectorStore() async throws(LocalDataError) {
        var previousPage: [String] = []
        while true {
            let page: ScrollPage
            do {
                page = try await vectorStore.scroll(offset: nil, limit: pageSize)
            } catch {
                throw .vectorStore(error)
            }
            let pointIDs = page.records.map(\.id)
            guard !pointIDs.isEmpty else { return }
            guard pointIDs != previousPage else {
                throw .vectorStore(.vectorStore("Vector store did not delete points during reset"))
            }
            do {
                try await vectorStore.delete(ids: pointIDs)
            } catch {
                throw .vectorStore(error)
            }
            previousPage = pointIDs
        }
    }
}

// MARK: - Recovery

public struct RecoveryReport: Equatable, Sendable {
    public var rolledBackVectorWrites: [OperationID] = []
    public var resumedResets: [OperationID] = []
    /// Deletions whose cleanup ran (Photos had confirmed, or photos were missing with full access).
    public var finishedDeletions: [OperationID] = []
    /// Deletions that turned out not to have happened; their entries were closed.
    public var abandonedDeletions: [OperationID] = []
    /// Deletions that cannot be proven either way yet (for example with limited access).
    public var pendingDeletions: [OperationID] = []

    public init() {}
}

/// Run at bootstrap before any new work: finishes interrupted resets, rolls back vector
/// writes whose metadata never committed, and reports open deletions.
public struct RecoverPendingOperations: Sendable {
    private let journal: any OperationJournal
    private let vectorWrites: any VectorWriteJournaling
    private let vectorStore: any VectorStoring
    private let reset: ResetLocalData
    private let deletions: ReconcileDeletion?

    /// - Parameter deletions: reconciles open deletions; without it they are only reported.
    public init(
        journal: any OperationJournal,
        vectorWrites: any VectorWriteJournaling,
        vectorStore: any VectorStoring,
        reset: ResetLocalData,
        deletions: ReconcileDeletion? = nil
    ) {
        self.journal = journal
        self.vectorWrites = vectorWrites
        self.vectorStore = vectorStore
        self.reset = reset
        self.deletions = deletions
    }

    public func execute() async throws(LocalDataError) -> RecoveryReport {
        var report = RecoveryReport()
        // An interrupted reset supersedes every other pending local operation except deletions.
        for entry in try await openEntries() where entry.kind == .reset {
            try await reset.resume(entry.id)
            report.resumedResets.append(entry.id)
        }
        for entry in try await openEntries() {
            switch entry.kind {
            case .vectorWrite(let intents):
                do {
                    try await vectorStore.delete(ids: intents.map(\.pointID.storeKey))
                } catch {
                    throw .vectorStore(error)
                }
                do {
                    try await vectorWrites.abandonVectorWrite(entry.id)
                } catch {
                    throw .persistence(error)
                }
                report.rolledBackVectorWrites.append(entry.id)
            case .deletion:
                switch try await deletions?.execute(entry) {
                case .finished: report.finishedDeletions.append(entry.id)
                case .notDeleted: report.abandonedDeletions.append(entry.id)
                case .uncertain, nil: report.pendingDeletions.append(entry.id)
                }
            case .reset:
                break
            }
        }
        return report
    }

    private func openEntries() async throws(LocalDataError) -> [JournalEntry] {
        do {
            return try await journal.openJournalEntries()
        } catch {
            throw .persistence(error)
        }
    }
}

/// Vector store for when no vector was ever written (no index compatibility yet):
/// nothing to roll back or clear.
public struct EmptyVectorStore: VectorStoring {
    public init() {}
    public func exists(id: String) async throws(AdapterError) -> Bool { false }
    public func upsert(points: [VectorPoint]) async throws(AdapterError) {}
    public func search(vector: [Float], limit: Int, threshold: Float) async throws(AdapterError) -> [ScoredResult] { [] }
    public func searchPage(vector: [Float], threshold: Float, filter: VectorSearchFilter?, offset: Int, limit: Int) async throws(AdapterError) -> [ScoredResult] { [] }
    public func vector(id: String) async throws(AdapterError) -> [Float]? { nil }
    public func scroll(offset: String?, limit: Int) async throws(AdapterError) -> ScrollPage { ScrollPage(records: [], nextOffset: nil) }
    public func delete(ids: [String]) async throws(AdapterError) {}
    public func count() async throws(AdapterError) -> Int { 0 }
    public func close() async {}
}

/// ResetLocalData from Settings: stops work, clears the index and local metadata (keeping
/// preferences, statistics and recoverable deletions), then starts a fresh initial pass.
/// Library photos are never touched.
public struct ResetAppData: Sendable {
    private let workflow: any WorkflowStateRepository
    private let resetting: any LocalDataResetting
    private let vectorStores: any VectorStoreProviding
    private let vectorization: VectorizationExecutor
    private let discovery: DiscoveryExecutor
    private let lifecycle: AppLifecycleCoordinator
    private let ids: any IDGenerating

    public init(
        workflow: any WorkflowStateRepository,
        resetting: any LocalDataResetting,
        vectorStores: any VectorStoreProviding,
        vectorization: VectorizationExecutor,
        discovery: DiscoveryExecutor,
        lifecycle: AppLifecycleCoordinator,
        ids: any IDGenerating
    ) {
        self.workflow = workflow
        self.resetting = resetting
        self.vectorStores = vectorStores
        self.vectorization = vectorization
        self.discovery = discovery
        self.lifecycle = lifecycle
        self.ids = ids
    }

    public func execute() async throws(LocalDataError) {
        // Stop mutations first; interruption is not a manual pause.
        await vectorization.interrupt()
        await discovery.stop()
        let vectorStore: any VectorStoring
        do {
            if let state = try await workflow.loadWorkflowState(), let compatibility = state.indexCompatibility {
                vectorStore = try await vectorStores.store(for: state.indexGeneration, dimensions: compatibility.dimensions)
            } else {
                vectorStore = EmptyVectorStore()
            }
        } catch let error as PersistenceError {
            throw .persistence(error)
        } catch let error as AdapterError {
            throw .vectorStore(error)
        } catch {
            throw .persistence(.storeUnavailable(String(describing: error)))
        }
        try await ResetLocalData(resetting: resetting, workflow: workflow, vectorStore: vectorStore, ids: ids).execute()
        await discovery.requestRefill()
        await lifecycle.userRequestedVectorization(.userResume)
    }
}
