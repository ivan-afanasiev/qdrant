import SweepDomain
import SweepFeatureState

/// Onboarding operations, bound to use cases at composition time.
public struct OnboardingClient: Sendable {
    public var requestPhotoAccess: @Sendable () async -> PhotoAccessScope
    public var requestNotifications: @Sendable () async -> Bool
    /// Saves the choices and starts the first pass; false if saving failed.
    public var complete: @Sendable (DateScopePreset) async -> Bool

    public init(
        requestPhotoAccess: @escaping @Sendable () async -> PhotoAccessScope,
        requestNotifications: @escaping @Sendable () async -> Bool,
        complete: @escaping @Sendable (DateScopePreset) async -> Bool
    ) {
        self.requestPhotoAccess = requestPhotoAccess
        self.requestNotifications = requestNotifications
        self.complete = complete
    }
}

/// Welcome → photo access → notifications → date range → start.
public struct OnboardingFeature: Reducer {
    public enum Step: Equatable, Sendable {
        case welcome
        case photoAccess
        case notifications
        case dateRange
    }

    public struct State: Equatable, Sendable {
        public var step: Step = .welcome
        public var datePreset: DateScopePreset = .default
        public var isWorking = false
        /// Access was refused; the person must enable it in Settings.
        public var isAccessDenied = false
        public var didFailToComplete = false
        public var isCompleted = false

        public init() {}
    }

    public enum Action: Equatable, Sendable {
        case continueTapped
        case allowPhotosTapped
        case photoAccessResult(PhotoAccessScope)
        case allowNotificationsTapped
        case skipNotificationsTapped
        case notificationsResult(Bool)
        case datePresetSelected(DateScopePreset)
        case backTapped
        case startTapped
        case completionResult(Bool)
    }

    private let client: OnboardingClient

    public init(client: OnboardingClient) {
        self.client = client
    }

    public func reduce(into state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case .continueTapped:
            guard state.step == .welcome else { return .none }
            state.step = .photoAccess
            return .none

        case .allowPhotosTapped:
            guard state.step == .photoAccess, !state.isWorking else { return .none }
            state.isWorking = true
            return .run { [client] send in
                await send(.photoAccessResult(await client.requestPhotoAccess()))
            }

        case .photoAccessResult(let scope):
            state.isWorking = false
            // Limited access is enough to continue; review covers only the visible photos.
            state.isAccessDenied = scope == .none
            if scope != .none {
                state.step = .notifications
            }
            return .none

        case .allowNotificationsTapped:
            guard state.step == .notifications, !state.isWorking else { return .none }
            state.isWorking = true
            return .run { [client] send in
                await send(.notificationsResult(await client.requestNotifications()))
            }

        case .skipNotificationsTapped:
            guard state.step == .notifications else { return .none }
            state.step = .dateRange
            return .none

        case .notificationsResult:
            // Either answer continues; vectorization never depends on notifications.
            state.isWorking = false
            state.step = .dateRange
            return .none

        case .datePresetSelected(let preset):
            state.datePreset = preset
            return .none

        case .backTapped:
            guard !state.isWorking else { return .none }
            switch state.step {
            case .welcome: break
            case .photoAccess: state.step = .welcome
            case .notifications: state.step = .photoAccess
            case .dateRange: state.step = .notifications
            }
            return .none

        case .startTapped:
            guard state.step == .dateRange, !state.isWorking else { return .none }
            state.isWorking = true
            state.didFailToComplete = false
            let preset = state.datePreset
            return .run { [client] send in
                await send(.completionResult(await client.complete(preset)))
            }

        case .completionResult(let succeeded):
            state.isWorking = false
            state.isCompleted = succeeded
            state.didFailToComplete = !succeeded
            return .none
        }
    }
}
