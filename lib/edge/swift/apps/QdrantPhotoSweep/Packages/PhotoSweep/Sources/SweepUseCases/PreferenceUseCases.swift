import Foundation
import SweepDomain

public struct Preferences: Equatable, Sendable {
    public let datePreset: DateScopePreset
    public let similarity: SimilarityPreset
    public let isOnboardingCompleted: Bool

    public init(datePreset: DateScopePreset, similarity: SimilarityPreset, isOnboardingCompleted: Bool) {
        self.datePreset = datePreset
        self.similarity = similarity
        self.isOnboardingCompleted = isOnboardingCompleted
    }

    public static let defaults = Preferences(datePreset: .default, similarity: .default, isOnboardingCompleted: false)
}

/// LoadPreferences: defaults before the first save.
public struct LoadPreferences: Sendable {
    private let workflow: any WorkflowStateRepository

    public init(workflow: any WorkflowStateRepository) {
        self.workflow = workflow
    }

    public func execute() async throws(PersistenceError) -> Preferences {
        guard let state = try await workflow.loadWorkflowState() else { return .defaults }
        return Preferences(
            datePreset: state.datePreset,
            similarity: SimilarityPreset(threshold: state.threshold) ?? .default,
            isOnboardingCompleted: state.isOnboardingCompleted
        )
    }
}

/// RequestPhotoAccess: shows the system prompt if needed and reports the resulting scope.
public struct RequestPhotoAccess: Sendable {
    private let library: any PhotoLibraryProviding

    public init(library: any PhotoLibraryProviding) {
        self.library = library
    }

    public func execute() async -> PhotoAccessScope {
        try? await library.requestAuthorization()
        return await library.accessScope()
    }
}

/// Asks for permission to announce "photos ready for review".
public struct RequestNotificationPermission: Sendable {
    private let notifier: any ReviewReadyNotifying

    public init(notifier: any ReviewReadyNotifying) {
        self.notifier = notifier
    }

    public func execute() async -> Bool {
        await notifier.requestPermission()
    }
}

/// Saves the onboarding choices and starts the first pass. Starting is the person's
/// action, so it may continue in the background with continued processing.
public struct CompleteOnboarding: Sendable {
    private let workflow: any WorkflowStateRepository
    private let lifecycle: AppLifecycleCoordinator
    private let observeLibrary: @Sendable () async -> Void
    private let now: @Sendable () -> Date

    public init(
        workflow: any WorkflowStateRepository,
        lifecycle: AppLifecycleCoordinator,
        observeLibrary: @escaping @Sendable () async -> Void,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.workflow = workflow
        self.lifecycle = lifecycle
        self.observeLibrary = observeLibrary
        self.now = now
    }

    public func execute(datePreset: DateScopePreset) async throws(PersistenceError) {
        let today = now()
        let updated = try await workflow.modifyWorkflowState { state in
            state.datePreset = datePreset
            state.scope = datePreset.range(endingAt: today)
            state.isOnboardingCompleted = true
        }
        if updated == nil {
            var initial = WorkflowState.initial(datePreset: datePreset, now: today)
            initial.isOnboardingCompleted = true
            try await workflow.saveWorkflowState(initial)
        }
        await observeLibrary()
        await lifecycle.userRequestedVectorization(.userResume)
    }
}

/// UpdateDateScope: retires discovery for the old scope and starts a scoped initial pass
/// that reuses compatible vectors.
public struct UpdateDateScope: Sendable {
    private let workflow: any WorkflowStateRepository
    private let discovery: DiscoveryExecutor
    private let lifecycle: AppLifecycleCoordinator
    private let now: @Sendable () -> Date

    public init(
        workflow: any WorkflowStateRepository,
        discovery: DiscoveryExecutor,
        lifecycle: AppLifecycleCoordinator,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.workflow = workflow
        self.discovery = discovery
        self.lifecycle = lifecycle
        self.now = now
    }

    public func execute(_ preset: DateScopePreset) async throws(PersistenceError) {
        let today = now()
        try await workflow.modifyWorkflowState { state in
            state.datePreset = preset
            state.scope = preset.range(endingAt: today)
            // The new scope needs its own completed initial pass before review.
            state.gate = InitialPassGate()
        }
        try await discovery.beginNewRevision()
        await lifecycle.userRequestedRestart(.userResume)
    }
}

/// UpdateSimilarityThreshold: takes effect immediately with a new discovery revision;
/// vectors are reused, review order and skips reset.
public struct UpdateSimilarityThreshold: Sendable {
    private let workflow: any WorkflowStateRepository
    private let discovery: DiscoveryExecutor

    public init(workflow: any WorkflowStateRepository, discovery: DiscoveryExecutor) {
        self.workflow = workflow
        self.discovery = discovery
    }

    public func execute(_ preset: SimilarityPreset) async throws(PersistenceError) {
        let threshold = preset.threshold
        try await workflow.modifyWorkflowState { $0.threshold = threshold }
        try await discovery.beginNewRevision()
    }
}

/// RescanLibrary: reconciles the scope, vectorizes new or changed photos, then discovers
/// again with fresh review order. Compatible vectors are reused.
public struct RescanLibrary: Sendable {
    private let workflow: any WorkflowStateRepository
    private let discovery: DiscoveryExecutor
    private let lifecycle: AppLifecycleCoordinator

    public init(workflow: any WorkflowStateRepository, discovery: DiscoveryExecutor, lifecycle: AppLifecycleCoordinator) {
        self.workflow = workflow
        self.discovery = discovery
        self.lifecycle = lifecycle
    }

    public func execute() async throws(PersistenceError) {
        try await workflow.modifyWorkflowState { $0.gate = InitialPassGate() }
        try await discovery.beginNewRevision()
        await lifecycle.userRequestedRestart(.userResume)
    }
}

/// LoadStatistics.
public struct LoadStatistics: Sendable {
    private let statistics: any StatisticsRepository

    public init(statistics: any StatisticsRepository) {
        self.statistics = statistics
    }

    public func execute() async throws(PersistenceError) -> LibraryStatistics {
        try await statistics.statistics()
    }
}
