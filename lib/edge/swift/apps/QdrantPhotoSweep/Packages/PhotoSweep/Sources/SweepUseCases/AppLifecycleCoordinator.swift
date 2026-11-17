import Foundation
import SweepDomain

/// Routes app lifecycle events and system execution windows into the single app-owned
/// vectorization executor and the foreground-only discovery executor.
///
/// - Foreground: activation clears a manual pause, resumes vectorization and refills discovery.
/// - Background: discovery is suspended at its checkpoint; vectorization continues only inside
///   a granted window (continued processing for user actions, a short grace window, or an
///   iOS-scheduled processing window). Every window is finished exactly once.
public actor AppLifecycleCoordinator {
    public struct Dependencies: Sendable {
        public let vectorization: VectorizationExecutor
        public let discovery: DiscoveryExecutor
        public let scheduler: any BackgroundExecutionScheduling
        public let notifier: any ReviewReadyNotifying
        public let workflow: any WorkflowStateRepository
        /// Whether automatic work (activation, scheduled and grace windows) may start. False
        /// until onboarding is completed: before the person chooses a date range, a pass would
        /// reconcile the whole library and hold the metadata store that onboarding saves to.
        public let isAutomaticWorkAllowed: @Sendable () async -> Bool

        public init(
            vectorization: VectorizationExecutor,
            discovery: DiscoveryExecutor,
            scheduler: any BackgroundExecutionScheduling,
            notifier: any ReviewReadyNotifying,
            workflow: any WorkflowStateRepository,
            isAutomaticWorkAllowed: @escaping @Sendable () async -> Bool = { true }
        ) {
            self.vectorization = vectorization
            self.discovery = discovery
            self.scheduler = scheduler
            self.notifier = notifier
            self.workflow = workflow
            self.isAutomaticWorkAllowed = isAutomaticWorkAllowed
        }
    }

    private struct ActiveWindow {
        let window: any ExecutionWindow
        let progressTask: Task<Void, Never>
    }

    private let dependencies: Dependencies
    private var presence: AppPresence = .foreground
    private var windows: [ObjectIdentifier: ActiveWindow] = [:]
    /// Passes already being announced in this process; guards against overlapping windows
    /// racing between the persisted check and the persisted record.
    private var announcedPasses: Set<VectorizationPassID> = []
    private var completionObserver: Task<Void, Never>?
    /// Vectorized count of the running pass at the last mid-pass discovery refill.
    private var lastRefillVectorizedCount = 0

    public init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    public var activeWindowCount: Int { windows.count }

    // MARK: - Lifecycle events

    /// HandleAppActivation: the next app opening clears a manual pause.
    public func appDidBecomeActive() async {
        observeVectorizationCompletions()
        presence = .foreground
        // The grace window is no longer needed once the app is visible again.
        for active in windows.values where active.window.kind == .grace {
            finish(active.window, success: true)
        }
        if await dependencies.isAutomaticWorkAllowed() {
            await dependencies.vectorization.handle(.appActivation)
        }
        await dependencies.discovery.setPresence(.foreground)
    }

    /// HandleBackgroundEntry: discovery stops; vectorization keeps going only in a granted window.
    public func appDidEnterBackground() async {
        observeVectorizationCompletions()
        presence = .background
        await dependencies.discovery.setPresence(.background)
        let hasContinuation = windows.values.contains { $0.window.kind == .continued }
        if VectorizationProgress.isWorking(dependencies.vectorization.status), !hasContinuation,
           let grace = await dependencies.scheduler.beginGraceWindow() {
            Task { await self.run(grace) }
        }
        await scheduleUnlessPaused()
    }

    /// Explicit user actions (first start, Resume, Retry, Rescan) start vectorization and ask
    /// for continued processing so it can keep running in the background.
    @discardableResult
    public func userRequestedVectorization(_ trigger: VectorizationTrigger) async -> VectorizationTriggerOutcome {
        observeVectorizationCompletions()
        let outcome = await dependencies.vectorization.handle(trigger)
        switch outcome {
        case .started, .queued:
            // A rejection only means no background continuation; foreground work continues.
            _ = await dependencies.scheduler.requestContinuedProcessing()
        case .blockedByManualPause, .failed:
            break
        }
        return outcome
    }

    // MARK: - Execution windows

    /// Runs vectorization for a system-granted window until the pass ends or the window expires.
    public func run(_ window: any ExecutionWindow) async {
        observeVectorizationCompletions()
        let id = ObjectIdentifier(window)
        guard windows[id] == nil else { return }
        // Continued windows only follow a person's action, which onboarding itself performs.
        if window.kind != .continued, !(await dependencies.isAutomaticWorkAllowed()) {
            window.finish(success: true)
            return
        }
        let vectorization = dependencies.vectorization
        let progressTask = Task {
            for await status in vectorization.statusUpdates() {
                switch status {
                case .running(let progress):
                    window.reportProgress(progress)
                case .preparing(let done, let total) where total > 0:
                    // Reading the library can take minutes; a moving Live Activity keeps
                    // iOS from treating the task as stalled.
                    window.reportProgress(VectorizationProgress(total: total, vectorized: done, deferred: 0))
                default:
                    break
                }
            }
        }
        windows[id] = ActiveWindow(window: window, progressTask: progressTask)
        window.onExpiration { [weak self] in
            Task { await self?.expire(window) }
        }

        let trigger: VectorizationTrigger? = switch window.kind {
        case .continued: .backgroundContinuation
        case .scheduled: .backgroundScheduled
        case .grace: nil
        }
        if let trigger {
            switch await vectorization.handle(trigger) {
            case .blockedByManualPause:
                finish(window, success: true)
                return
            case .failed:
                finish(window, success: false)
                return
            case .started, .queued:
                break
            }
        }

        await vectorization.waitUntilIdle()
        guard windows[id] != nil else { return }
        let completed: Bool
        if case .completed = vectorization.status {
            completed = true
        } else {
            completed = false
        }
        if completed, presence == .background {
            await notifyReviewReadyIfNeeded()
        }
        finish(window, success: completed)
        if !completed, presence == .background {
            await scheduleUnlessPaused()
        }
    }

    /// HandleExecutionExpiration. A continued window's expiration is treated as the person
    /// cancelling it (the system does not distinguish the two), i.e. a manual pause.
    private func expire(_ window: any ExecutionWindow) async {
        guard let active = windows[ObjectIdentifier(window)] else { return }
        // The window is gone; stop reporting before waiting for the safe stop below.
        active.progressTask.cancel()
        let othersKeepRunning = windows.keys.contains { $0 != ObjectIdentifier(window) }
        if window.kind == .continued {
            await dependencies.vectorization.pause()
        } else if !othersKeepRunning {
            await dependencies.vectorization.interrupt()
        }
        finish(window, success: false)
        if window.kind != .continued {
            await scheduleUnlessPaused()
        }
    }

    /// Finishes a window exactly once and stops its progress reporting.
    private func finish(_ window: any ExecutionWindow, success: Bool) {
        guard let active = windows.removeValue(forKey: ObjectIdentifier(window)) else { return }
        active.progressTask.cancel()
        window.finish(success: success)
    }

    // MARK: - Discovery refill

    /// Newly committed vectors (including the pass that opens the initial gate) become
    /// eligible for discovery, which only refills while the app is in the foreground.
    /// Refills happen after every committed batch, not only when a pass ends: otherwise a
    /// long pass (new photos, retried deferrals) leaves discovery exhausted until it finishes.
    private func observeVectorizationCompletions() {
        guard completionObserver == nil else { return }
        let updates = dependencies.vectorization.statusUpdates()
        completionObserver = Task { [weak self] in
            for await status in updates {
                switch status {
                case .completed:
                    await self?.vectorizationCompleted()
                case .running(let progress):
                    await self?.vectorizationCommitted(progress)
                default:
                    break
                }
            }
        }
    }

    private func vectorizationCompleted() async {
        lastRefillVectorizedCount = 0
        guard presence == .foreground else { return }
        await dependencies.discovery.requestRefill()
    }

    /// Requests a refill when a batch added vectors since the last refill in this pass.
    private func vectorizationCommitted(_ progress: VectorizationProgress) async {
        if progress.vectorized < lastRefillVectorizedCount {
            // A new pass started; its counts restart from zero.
            lastRefillVectorizedCount = 0
        }
        guard progress.vectorized > lastRefillVectorizedCount, presence == .foreground else { return }
        lastRefillVectorizedCount = progress.vectorized
        await dependencies.discovery.requestRefill()
    }

    // MARK: - Scheduling and notifications

    /// ScheduleVectorization: asks iOS for a later window unless the person paused.
    private func scheduleUnlessPaused() async {
        guard await dependencies.isAutomaticWorkAllowed() else { return }
        let pause = (try? await dependencies.workflow.loadWorkflowState())?.pause ?? .none
        guard !pause.isPausedByUser else { return }
        await dependencies.scheduler.scheduleProcessing()
    }

    /// NotifyReviewReady: once per completed background pass that processed photos and left
    /// review available. The pass is recorded before posting, so it is never announced twice.
    private func notifyReviewReadyIfNeeded() async {
        guard let pass = dependencies.vectorization.lastCompletedPass, pass.didWork,
              !announcedPasses.contains(pass.id) else { return }
        // Claimed before any suspension, so a concurrent window cannot announce it too.
        announcedPasses.insert(pass.id)
        guard let state = try? await dependencies.workflow.loadWorkflowState(),
              state.gate.isOpen, state.notifiedPassID != pass.id,
              await dependencies.notifier.permission() == .authorized else { return }
        let passID = pass.id
        guard (try? await dependencies.workflow.modifyWorkflowState({ $0.notifiedPassID = passID })) != nil else { return }
        try? await dependencies.notifier.postReviewReady(unavailableCount: pass.progress.deferred)
    }
}
