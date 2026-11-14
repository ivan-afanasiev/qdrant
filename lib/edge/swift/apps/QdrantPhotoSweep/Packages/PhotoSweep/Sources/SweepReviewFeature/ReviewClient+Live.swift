import SweepDomain
import SweepUseCases

extension ReviewClient {
    /// Binds the card reducer to the discovery owner and review use cases.
    public static func live(
        discovery: DiscoveryExecutor,
        loadNext: LoadNextReviewGroup,
        skip: SkipGroup,
        commit: CommitReviewDecision,
        ids: any IDGenerating
    ) -> ReviewClient {
        ReviewClient(
            observeDiscovery: { discovery.updates() },
            // A load failure shows no card; the next discovery update retries.
            loadNextGroup: { try? await loadNext.execute() },
            skip: { await skip.execute($0) },
            commit: { await commit.execute($0, $1, $2) },
            makeOperationID: { OperationID(ids.makeUUID()) }
        )
    }
}
