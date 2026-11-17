import SweepDomain
import SweepFeatureState

/// App-owned vectorization operations the library screen may observe and control.
/// Bound to the vectorization use cases at composition time.
public struct VectorizationControls: Sendable {
    public var observeStatus: @Sendable () -> AsyncStream<VectorizationStatus>
    public var pause: @Sendable () async -> Void
    public var resume: @Sendable () async -> Void
    public var retry: @Sendable () async -> Void

    public init(
        observeStatus: @escaping @Sendable () -> AsyncStream<VectorizationStatus>,
        pause: @escaping @Sendable () async -> Void,
        resume: @escaping @Sendable () async -> Void,
        retry: @escaping @Sendable () async -> Void
    ) {
        self.observeStatus = observeStatus
        self.pause = pause
        self.resume = resume
        self.retry = retry
    }
}

/// Vectorization progress with Pause/Resume/Retry. There is no Cancel control.
public struct LibraryFeature: Reducer {
    public enum Control: Equatable, Sendable {
        case pause
        case resume
        case retry
    }

    public struct State: Equatable, Sendable {
        public var status: VectorizationStatus
        public var isObserving: Bool

        public init(status: VectorizationStatus = .idle, isObserving: Bool = false) {
            self.status = status
            self.isObserving = isObserving
        }

        /// The single control offered for the current status. An interrupted pass
        /// resumes automatically on activation, so it offers none.
        public var control: Control? {
            switch status {
            case .preparing, .running: .pause
            case .pausedByUser: .resume
            case .failed: .retry
            case .idle, .interrupted, .completed: nil
            }
        }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        /// Cancels only the status subscription, never app-owned vectorization.
        case onDisappear
        case statusChanged(VectorizationStatus)
        case controlTapped(Control)
    }

    static let observationID = EffectID("library.observeStatus")

    private let controls: VectorizationControls

    public init(controls: VectorizationControls) {
        self.controls = controls
    }

    public func reduce(into state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case .onAppear:
            state.isObserving = true
            return .run(id: Self.observationID, cancelInFlight: true) { [controls] send in
                for await status in controls.observeStatus() {
                    await send(.statusChanged(status))
                }
            }

        case .onDisappear:
            state.isObserving = false
            return .cancel(Self.observationID)

        case .statusChanged(let status):
            state.status = status
            return .none

        case .controlTapped(let control):
            // Ignore taps on a control the current status no longer offers.
            guard control == state.control else { return .none }
            let operation = switch control {
            case .pause: controls.pause
            case .resume: controls.resume
            case .retry: controls.retry
            }
            // The resulting status arrives through the observation, not optimistically.
            return .run { _ in await operation() }
        }
    }
}
