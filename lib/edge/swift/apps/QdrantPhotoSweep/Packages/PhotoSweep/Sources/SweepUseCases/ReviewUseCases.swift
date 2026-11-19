import CoreGraphics
import Foundation
import SweepDomain

/// Called after the review queue changed, normally to refill the discovery buffer.
public typealias QueueChangeHandler = @Sendable () async -> Void

// MARK: - Loading

/// Next card: fresh groups in discovery order; skipped groups only after discovery is
/// exhausted. Groups with a deletion in progress are never shown again.
public struct LoadNextReviewGroup: Sendable {
    private let review: any ReviewRepository
    private let progress: any DiscoveryProgressRepository
    private let workflow: any WorkflowStateRepository
    private let journal: any OperationJournal

    public init(
        review: any ReviewRepository,
        progress: any DiscoveryProgressRepository,
        workflow: any WorkflowStateRepository,
        journal: any OperationJournal
    ) {
        self.review = review
        self.progress = progress
        self.workflow = workflow
        self.journal = journal
    }

    public func execute() async throws(PersistenceError) -> ReviewGroupSnapshot? {
        guard let state = try await workflow.loadWorkflowState() else { return nil }
        let revision = state.discoveryRevision
        var queue = try await review.reviewQueue(for: revision)
        let exhausted = try await progress.discoveryProgress(for: revision)?.isSeedCursorExhausted ?? false
        let deleting = Set(try await journal.openJournalEntries().compactMap { entry -> GroupID? in
            if case .deletion(let group, _, _, _) = entry.kind { return group }
            return nil
        })
        for group in deleting {
            queue.complete(group)
        }
        guard let id = queue.current(isDiscoveryExhausted: exhausted) else { return nil }
        return try await review.group(id)
    }
}

/// Review images: a thumbnail shown first, then the original for presented cards and the preview.
/// Vectorization never uses this; it loads thumbnails only.
public struct LoadReviewImage: Sendable {
    private let library: any PhotoLibraryProviding

    public init(library: any PhotoLibraryProviding) {
        self.library = library
    }

    /// Accessible photos among `assets`, for card details such as the creation date.
    public func details(_ assets: [AssetID]) async -> [AssetID: PhotoAsset] {
        let photos = (try? await library.assets(withIdentifiers: assets.map(\.rawValue))) ?? []
        return Dictionary(photos.map { (AssetID($0.localIdentifier), $0) }, uniquingKeysWith: { first, _ in first })
    }

    public func thumbnail(_ asset: AssetID, pixels: Int) async throws(AdapterError) -> CGImage {
        try await library.loadThumbnail(for: try await photo(asset), size: CGSize(width: pixels, height: pixels))
    }

    /// High quality at screen size, for review cards; the original stays for the preview.
    public func display(_ asset: AssetID, maxPixels: Int) async throws(AdapterError) -> CGImage {
        try await library.loadDisplayImage(for: try await photo(asset), maxPixels: maxPixels)
    }

    public func original(_ asset: AssetID) async throws(AdapterError) -> CGImage {
        try await library.loadFullImage(for: try await photo(asset))
    }

    private func photo(_ asset: AssetID) async throws(AdapterError) -> PhotoAsset {
        guard let photo = try await library.assets(withIdentifiers: [asset.rawValue]).first else {
            throw .photoLibrary("Photo \(asset) is not available")
        }
        return photo
    }
}

// MARK: - Skip

public struct SkipGroup: Sendable {
    private let review: any ReviewRepository
    private let onQueueChanged: QueueChangeHandler

    public init(review: any ReviewRepository, onQueueChanged: @escaping QueueChangeHandler) {
        self.review = review
        self.onQueueChanged = onQueueChanged
    }

    /// Persists the deferral before the card may advance.
    public func execute(_ snapshot: ReviewGroupSnapshot) async -> SkipOutcome {
        do {
            try await review.deferGroup(snapshot.id)
        } catch {
            return .failed(String(describing: error))
        }
        await onQueueChanged()
        return .persisted
    }
}

// MARK: - Deletion

/// Cleanup after Photos confirmed a deletion. Safe to repeat; never deletes from Photos.
public struct FinishConfirmedDeletion: Sendable {
    private let assets: any AssetRepository
    private let vectorStores: any VectorStoreProviding
    private let workflow: any WorkflowStateRepository
    private let deletion: any DeletionRepository

    public init(
        assets: any AssetRepository,
        vectorStores: any VectorStoreProviding,
        workflow: any WorkflowStateRepository,
        deletion: any DeletionRepository
    ) {
        self.assets = assets
        self.vectorStores = vectorStores
        self.workflow = workflow
        self.deletion = deletion
    }

    public func execute(_ operation: OperationID, deleted: [AssetID], estimatedBytes: Int64?) async throws(LocalDataError) {
        let state: WorkflowState?
        let records: [AssetID: AssetRecord]
        do {
            state = try await workflow.loadWorkflowState()
            records = try await assets.assets(deleted)
        } catch {
            throw .persistence(error)
        }
        if let state, let compatibility = state.indexCompatibility, !records.isEmpty {
            do {
                let store = try await vectorStores.store(for: state.indexGeneration, dimensions: compatibility.dimensions)
                try await store.delete(ids: records.values.map(\.pointID.storeKey))
            } catch {
                // The journal stays open; recovery repeats the cleanup.
                throw .vectorStore(error)
            }
        }
        do {
            try await deletion.finishDeletion(operation, deleted: deleted, estimatedBytes: estimatedBytes, revision: state?.discoveryRevision ?? DiscoveryRevision(0))
        } catch {
            throw .persistence(error)
        }
    }
}

/// Decides what an interrupted or failed deletion actually did. A photo counts as deleted
/// only if it is missing while the app has full library access.
public struct ReconcileDeletion: Sendable {
    public enum Result: Equatable, Sendable {
        /// Cleanup ran for the photos confirmed missing.
        case finished(deleted: [AssetID])
        /// Every photo still exists; the entry was closed and nothing was counted.
        case notDeleted
        /// Cannot tell (limited or no access); the entry stays open.
        case uncertain
    }

    private let library: any PhotoLibraryProviding
    private let journal: any OperationJournal
    private let finisher: FinishConfirmedDeletion

    public init(library: any PhotoLibraryProviding, journal: any OperationJournal, finisher: FinishConfirmedDeletion) {
        self.library = library
        self.journal = journal
        self.finisher = finisher
    }

    public func execute(_ entry: JournalEntry) async throws(LocalDataError) -> Result {
        guard case .deletion(_, _, let intended, let estimatedBytes) = entry.kind else { return .uncertain }
        return try await execute(entry.id, intended: intended, estimatedBytes: estimatedBytes, isConfirmed: entry.phase == .externalConfirmed)
    }

    public func execute(_ operation: OperationID, intended: [AssetID], estimatedBytes: Int64?, isConfirmed: Bool) async throws(LocalDataError) -> Result {
        if isConfirmed {
            try await finisher.execute(operation, deleted: intended, estimatedBytes: estimatedBytes)
            return .finished(deleted: intended)
        }
        guard await library.accessScope() == .full else { return .uncertain }
        let present: Set<String>
        do {
            present = Set(try await library.assets(withIdentifiers: intended.map(\.rawValue)).map(\.localIdentifier))
        } catch {
            return .uncertain
        }
        let missing = intended.filter { !present.contains($0.rawValue) }
        do {
            if missing.isEmpty {
                try await journal.closeJournalEntry(operation)
                return .notDeleted
            }
            try await journal.confirmExternalDeletion(operation)
        } catch {
            throw .persistence(error)
        }
        // Only the confirmed-missing photos are counted; the size estimate covers the whole
        // request, so it is kept only when everything was deleted.
        let bytes = missing.count == intended.count ? estimatedBytes : nil
        try await finisher.execute(operation, deleted: missing, estimatedBytes: bytes)
        return .finished(deleted: missing)
    }
}

/// Commits a validated card decision. Keep-all completes the review; a deletion is
/// journaled before Photos is asked, and cleanup runs only after Photos confirms.
public struct CommitReviewDecision: Sendable {
    private let review: any ReviewRepository
    private let journal: any OperationJournal
    private let library: any PhotoLibraryProviding
    private let reconcile: ReconcileDeletion
    private let finisher: FinishConfirmedDeletion
    private let onQueueChanged: QueueChangeHandler

    public init(
        review: any ReviewRepository,
        journal: any OperationJournal,
        library: any PhotoLibraryProviding,
        finisher: FinishConfirmedDeletion,
        onQueueChanged: @escaping QueueChangeHandler
    ) {
        self.review = review
        self.journal = journal
        self.library = library
        self.finisher = finisher
        self.reconcile = ReconcileDeletion(library: library, journal: journal, finisher: finisher)
        self.onQueueChanged = onQueueChanged
    }

    public func execute(_ snapshot: ReviewGroupSnapshot, _ decision: ReviewDecision, _ operation: OperationID) async -> ReviewCommitOutcome {
        // 1. The card must still describe the current group and every photo must be accessible.
        let available: [PhotoAsset]
        do {
            let current = try await review.group(snapshot.id)
            available = try await library.assets(withIdentifiers: snapshot.members.map(\.rawValue))
            let present = Set(available.map { AssetID($0.localIdentifier) })
            try ReviewCommitPolicy.validateCurrent(snapshot, currentRevision: current?.revision, unavailable: Set(snapshot.members).subtracting(present))
        } catch let error as ReviewError {
            if case .conflict = error {
                await onQueueChanged()
                return .conflict
            }
            return .failed(String(describing: error))
        } catch {
            return .failed(String(describing: error))
        }

        switch decision {
        case .keepAll:
            do {
                try await review.completeGroup(snapshot.id, operation: operation)
            } catch {
                return .failed(String(describing: error))
            }
            await onQueueChanged()
            return .completed

        case .delete(_, let delete):
            let toDelete = snapshot.members.filter { delete.contains($0) }
            let sizes = available.filter { delete.contains(AssetID($0.localIdentifier)) }.map(\.fileSize)
            let estimatedBytes: Int64? = sizes.contains(nil) ? nil : sizes.compactMap { $0 }.reduce(0, +)

            // 2. Durable intent before Photos is touched.
            do {
                try await journal.beginDeletion(operation, group: snapshot.id, revision: snapshot.revision, assets: toDelete, estimatedBytes: estimatedBytes)
            } catch {
                return .failed(String(describing: error))
            }
            // 3. Ask Photos.
            do throws(AdapterError) {
                try await library.deleteAssets(toDelete.map(\.rawValue))
            } catch .deletionDeclined {
                try? await journal.closeJournalEntry(operation)
                return .deletionDeclined
            } catch {
                return await reconcileFailure(operation, toDelete: toDelete, estimatedBytes: estimatedBytes, error: error)
            }
            // 4–5. Record the confirmed outcome, then clean up and count once.
            do {
                try await journal.confirmExternalDeletion(operation)
                try await finisher.execute(operation, deleted: toDelete, estimatedBytes: estimatedBytes)
            } catch {
                // Photos already deleted; the open entry hides the card and recovery finishes cleanup.
                await onQueueChanged()
                return .failed("Photos were deleted; cleanup will finish later (\(error))")
            }
            await onQueueChanged()
            return .completed
        }
    }

    /// A failed request may still have deleted some photos; never assume either way.
    private func reconcileFailure(_ operation: OperationID, toDelete: [AssetID], estimatedBytes: Int64?, error: AdapterError) async -> ReviewCommitOutcome {
        switch try? await reconcile.execute(operation, intended: toDelete, estimatedBytes: estimatedBytes, isConfirmed: false) {
        case .finished:
            await onQueueChanged()
            return .completed
        case .notDeleted:
            return .failed("Photos could not be deleted (\(error))")
        case .uncertain, nil:
            return .failed("Deletion result is unknown and will be checked again (\(error))")
        }
    }
}

/// A bounded decorative sample from the current pass, never a similarity result.
public struct LoadProgressThumbnails: Sendable {
    private let passes: any VectorizationPassRepository
    private let images: LoadReviewImage

    public init(passes: any VectorizationPassRepository, library: any PhotoLibraryProviding) {
        self.passes = passes
        self.images = LoadReviewImage(library: library)
    }

    public func execute() async -> [CGImage] {
        guard !Task.isCancelled, let pass = try? await passes.activePass() else { return [] }
        let candidates = Array(pass.outcomes.keys.prefix(8))
        var result: [CGImage] = []
        for asset in candidates {
            guard !Task.isCancelled else { return [] }
            if let image = try? await images.thumbnail(asset, pixels: 160) {
                result.append(image)
            }
        }
        return Task.isCancelled ? [] : result
    }
}
