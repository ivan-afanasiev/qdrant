import SweepDomain
import SweepFeatureState

/// Review operations the card screen depends on. Bound to the review use cases at composition time.
public struct ReviewClient: Sendable {
    public var observeDiscovery: @Sendable () -> AsyncStream<DiscoveryUpdate>
    public var loadNextGroup: @Sendable () async -> ReviewGroupSnapshot?
    /// Persists the deferral; the card advances only after `.persisted`.
    public var skip: @Sendable (ReviewGroupSnapshot) async -> SkipOutcome
    /// Runs the recoverable commit/deletion workflow for a validated decision.
    public var commit: @Sendable (ReviewGroupSnapshot, ReviewDecision, OperationID) async -> ReviewCommitOutcome
    public var makeOperationID: @Sendable () -> OperationID

    public init(
        observeDiscovery: @escaping @Sendable () -> AsyncStream<DiscoveryUpdate>,
        loadNextGroup: @escaping @Sendable () async -> ReviewGroupSnapshot?,
        skip: @escaping @Sendable (ReviewGroupSnapshot) async -> SkipOutcome,
        commit: @escaping @Sendable (ReviewGroupSnapshot, ReviewDecision, OperationID) async -> ReviewCommitOutcome,
        makeOperationID: @escaping @Sendable () -> OperationID
    ) {
        self.observeDiscovery = observeDiscovery
        self.loadNextGroup = loadNextGroup
        self.skip = skip
        self.commit = commit
        self.makeOperationID = makeOperationID
    }
}

/// Card review: one group at a time, keep selection, Skip, explicit delete-all.
public struct ReviewFeature: Reducer {
    public struct Card: Equatable, Sendable {
        /// Fixed while the card is open; external changes surface as a conflict on commit.
        public let snapshot: ReviewGroupSnapshot
        public var keep: Set<AssetID>

        public init(snapshot: ReviewGroupSnapshot, keep: Set<AssetID> = []) {
            self.snapshot = snapshot
            self.keep = keep
        }
    }

    public enum Pending: Equatable, Sendable {
        case commit(OperationID)
        case skip(GroupID)
    }

    public enum Notice: Equatable, Sendable {
        case emptySelection
        case conflictRefreshed
        case deletionDeclined
        case commitFailed(String)
        case skipFailed(String)
    }

    public struct State: Equatable, Sendable {
        public var card: Card?
        public var discovery: DiscoveryUpdate?
        public var pending: Pending?
        public var isLoading: Bool
        public var notice: Notice?

        public init(
            card: Card? = nil,
            discovery: DiscoveryUpdate? = nil,
            pending: Pending? = nil,
            isLoading: Bool = false,
            notice: Notice? = nil
        ) {
            self.card = card
            self.discovery = discovery
            self.pending = pending
            self.isLoading = isLoading
            self.notice = notice
        }

        /// True when the open card belongs to an older discovery revision.
        var isCardObsolete: Bool {
            guard let card, let discovery else { return false }
            return card.snapshot.discoveryRevision < discovery.revision
        }

        var isCommitPending: Bool {
            if case .commit = pending { return true }
            return false
        }

        /// Loading is useful only while discovery can provide groups.
        var canLoad: Bool {
            switch discovery?.status {
            case .searching, .bufferReady, .exhausted: true
            case .waitingForInitialPass, .suspended, .failed, nil: false
            }
        }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case onDisappear
        case discoveryUpdated(DiscoveryUpdate)
        case groupLoaded(ReviewGroupSnapshot?)
        case keepToggled(AssetID)
        case commitTapped
        /// Keeps every photo: completes the review without deleting anything.
        case keepAllTapped
        case deleteAllTapped
        case skipTapped
        case commitFinished(OperationID, ReviewCommitOutcome)
        case skipFinished(GroupID, SkipOutcome)
        case noticeDismissed
    }

    static let observationID = EffectID("review.observeDiscovery")
    static let loadID = EffectID("review.loadNextGroup")

    private let client: ReviewClient

    public init(client: ReviewClient) {
        self.client = client
    }

    public func reduce(into state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case .onAppear:
            return .run(id: Self.observationID, cancelInFlight: true) { [client] send in
                for await update in client.observeDiscovery() {
                    await send(.discoveryUpdated(update))
                }
            }

        case .onDisappear:
            // In-flight commits and skips keep running so external outcomes still reconcile.
            state.isLoading = false
            return .merge(.cancel(Self.observationID), .cancel(Self.loadID))

        case .discoveryUpdated(let update):
            if let current = state.discovery, update.revision < current.revision {
                return .none
            }
            state.discovery = update
            if state.isCardObsolete, !state.isCommitPending {
                // Threshold change or rescan retired this card; a pending skip result becomes stale.
                // A pending commit keeps the card until its outcome reconciles.
                state.card = nil
                state.pending = nil
            }
            return loadIfNeeded(&state)

        case .groupLoaded(let snapshot):
            state.isLoading = false
            // Never replace an open card: its snapshot and selection stay stable.
            guard state.card == nil, let snapshot else { return .none }
            if let discovery = state.discovery, snapshot.discoveryRevision < discovery.revision {
                return .none
            }
            state.card = Card(snapshot: snapshot)
            return .none

        case .keepToggled(let asset):
            guard state.pending == nil, var card = state.card,
                  card.snapshot.members.contains(asset) else { return .none }
            if card.keep.contains(asset) {
                card.keep.remove(asset)
            } else {
                card.keep.insert(asset)
            }
            state.card = card
            return .none

        case .commitTapped:
            guard let card = state.card else { return .none }
            return commit(.keep(card.keep), state: &state)

        case .keepAllTapped:
            guard let card = state.card else { return .none }
            return commit(.keep(Set(card.snapshot.members)), state: &state)

        case .deleteAllTapped:
            return commit(.deleteAll, state: &state)

        case .skipTapped:
            guard state.pending == nil, let card = state.card else { return .none }
            let snapshot = card.snapshot
            state.pending = .skip(snapshot.id)
            return .run { [client] send in
                let outcome = await client.skip(snapshot)
                await send(.skipFinished(snapshot.id, outcome))
            }

        case .commitFinished(let operation, let outcome):
            guard state.pending == .commit(operation) else { return .none }
            state.pending = nil
            switch outcome {
            case .completed:
                state.card = nil
            case .conflict:
                state.card = nil
                state.notice = .conflictRefreshed
            case .deletionDeclined:
                state.notice = .deletionDeclined
            case .failed(let message):
                state.notice = .commitFailed(message)
            }
            if state.isCardObsolete {
                state.card = nil
            }
            return loadIfNeeded(&state)

        case .skipFinished(let group, let outcome):
            guard state.pending == .skip(group) else { return .none }
            state.pending = nil
            switch outcome {
            case .persisted:
                state.card = nil
                return loadIfNeeded(&state)
            case .failed(let message):
                state.notice = .skipFailed(message)
                return .none
            }

        case .noticeDismissed:
            state.notice = nil
            return .none
        }
    }

    private func commit(_ intent: ReviewCommitIntent, state: inout State) -> Effect<Action> {
        guard state.pending == nil, let card = state.card else { return .none }
        let decision: ReviewDecision
        do {
            decision = try KeepSelectionPolicy.validate(intent, for: card.snapshot)
        } catch .emptySelection {
            state.notice = .emptySelection
            return .none
        } catch {
            state.notice = .conflictRefreshed
            return .none
        }
        let operation = client.makeOperationID()
        let snapshot = card.snapshot
        state.pending = .commit(operation)
        return .run { [client] send in
            let outcome = await client.commit(snapshot, decision, operation)
            await send(.commitFinished(operation, outcome))
        }
    }

    private func loadIfNeeded(_ state: inout State) -> Effect<Action> {
        guard state.card == nil, !state.isLoading, state.canLoad else { return .none }
        state.isLoading = true
        return .run(id: Self.loadID, cancelInFlight: true) { [client] send in
            let snapshot = await client.loadNextGroup()
            await send(.groupLoaded(snapshot))
        }
    }
}
