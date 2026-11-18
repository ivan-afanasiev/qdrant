import SweepDomain
import SweepFeatureState
import SweepUseCases

/// Settings operations, bound to use cases at composition time. Each returns false on failure.
public struct SettingsClient: Sendable {
    public var loadPreferences: @Sendable () async -> Preferences?
    public var loadStatistics: @Sendable () async -> LibraryStatistics?
    public var updateDateScope: @Sendable (DateScopePreset) async -> Bool
    public var updateSimilarity: @Sendable (SimilarityPreset) async -> Bool
    public var rescan: @Sendable () async -> Bool
    public var reset: @Sendable () async -> Bool

    public init(
        loadPreferences: @escaping @Sendable () async -> Preferences?,
        loadStatistics: @escaping @Sendable () async -> LibraryStatistics?,
        updateDateScope: @escaping @Sendable (DateScopePreset) async -> Bool,
        updateSimilarity: @escaping @Sendable (SimilarityPreset) async -> Bool,
        rescan: @escaping @Sendable () async -> Bool,
        reset: @escaping @Sendable () async -> Bool
    ) {
        self.loadPreferences = loadPreferences
        self.loadStatistics = loadStatistics
        self.updateDateScope = updateDateScope
        self.updateSimilarity = updateSimilarity
        self.rescan = rescan
        self.reset = reset
    }
}

public struct SettingsFeature: Reducer {
    public struct State: Equatable, Sendable {
        public var preferences: Preferences?
        public var statistics: LibraryStatistics?
        public var isWorking = false
        public var isConfirmingReset = false
        public var didFail = false
        /// Set after a successful rescan: the screen closes so the person sees progress and
        /// review again.
        public var isDismissRequested = false

        public init() {}
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case loaded(Preferences?, LibraryStatistics?)
        case datePresetSelected(DateScopePreset)
        case similaritySelected(SimilarityPreset)
        case rescanTapped
        case resetTapped
        case resetCancelled
        case resetConfirmed
        case operationFinished(Bool)
        case rescanFinished(Bool)
        case failureDismissed
    }

    private let client: SettingsClient

    public init(client: SettingsClient) {
        self.client = client
    }

    public func reduce(into state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case .onAppear:
            return load()

        case .loaded(let preferences, let statistics):
            state.preferences = preferences
            state.statistics = statistics
            return .none

        case .datePresetSelected(let preset):
            guard !state.isWorking, state.preferences?.datePreset != preset else { return .none }
            return run(&state) { [client] in await client.updateDateScope(preset) }

        case .similaritySelected(let preset):
            guard !state.isWorking, state.preferences?.similarity != preset else { return .none }
            return run(&state) { [client] in await client.updateSimilarity(preset) }

        case .rescanTapped:
            guard !state.isWorking else { return .none }
            state.isWorking = true
            state.didFail = false
            return .run { [client] send in
                await send(.rescanFinished(await client.rescan()))
            }

        case .rescanFinished(let succeeded):
            state.isWorking = false
            state.didFail = !succeeded
            state.isDismissRequested = succeeded
            return succeeded ? .none : load()

        case .resetTapped:
            guard !state.isWorking else { return .none }
            state.isConfirmingReset = true
            return .none

        case .resetCancelled:
            state.isConfirmingReset = false
            return .none

        case .resetConfirmed:
            guard state.isConfirmingReset, !state.isWorking else { return .none }
            state.isConfirmingReset = false
            return run(&state) { [client] in await client.reset() }

        case .operationFinished(let succeeded):
            state.isWorking = false
            state.didFail = !succeeded
            return load()

        case .failureDismissed:
            state.didFail = false
            return .none
        }
    }

    private func run(_ state: inout State, _ operation: @escaping @Sendable () async -> Bool) -> Effect<Action> {
        state.isWorking = true
        state.didFail = false
        return .run { send in
            await send(.operationFinished(await operation()))
        }
    }

    private func load() -> Effect<Action> {
        .run { [client] send in
            async let preferences = client.loadPreferences()
            async let statistics = client.loadStatistics()
            await send(.loaded(await preferences, await statistics))
        }
    }
}
