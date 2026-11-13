import Testing
import SweepDomain
import SweepTestSupport
import SweepUseCases

/// Returns scripted failures in order, then succeeds with the attempt number.
private actor ScriptedOperation {
    private var failures: [VectorizationFailure]
    private(set) var attempts = 0

    init(failures: [VectorizationFailure]) {
        self.failures = failures
    }

    func attempt() throws(VectorizationFailure) -> Int {
        attempts += 1
        guard failures.isEmpty else { throw failures.removeFirst() }
        return attempts
    }
}

@Suite struct RetryRunnerTests {
    let policy = RetryPolicy(maxAssetAttempts: 3, maxSystemicAttempts: 2, baseDelay: .seconds(1), maxDelay: .seconds(10))

    @Test func successOnFirstAttemptNeverSleeps() async throws {
        let sleeper = RecordingSleeper()
        let operation = ScriptedOperation(failures: [])
        let outcome = try await RetryRunner(policy: policy, sleeper: sleeper).run { () async throws(VectorizationFailure) -> Int in
            try await operation.attempt()
        }
        #expect(outcome == .succeeded(1, attempts: 1))
        #expect(await sleeper.sleeps.isEmpty)
    }

    @Test func temporaryUnavailabilityRecoversAndPreservesProgress() async throws {
        let sleeper = RecordingSleeper()
        let operation = ScriptedOperation(failures: [.assetUnavailable("iCloud"), .assetUnavailable("iCloud")])
        let outcome = try await RetryRunner(policy: policy, sleeper: sleeper).run { () async throws(VectorizationFailure) -> Int in
            try await operation.attempt()
        }
        #expect(outcome == .succeeded(3, attempts: 3))
        #expect(await sleeper.sleeps == [.seconds(1), .seconds(2)])
    }

    @Test func persistentlyUnavailableAssetIsDeferredAfterFiniteAttempts() async throws {
        let sleeper = RecordingSleeper()
        let operation = ScriptedOperation(failures: Array(repeating: .assetUnavailable("gone"), count: 10))
        let outcome = try await RetryRunner(policy: policy, sleeper: sleeper).run { () async throws(VectorizationFailure) -> Int in
            try await operation.attempt()
        }
        #expect(outcome == .deferred(.unavailable("gone"), attempts: 3))
        #expect(await operation.attempts == 3)
        #expect(await sleeper.sleeps.count == 2)
    }

    @Test func systemicFailureStopsPassWithoutDeferringAsset() async throws {
        let sleeper = RecordingSleeper()
        let operation = ScriptedOperation(failures: Array(repeating: .systemic("store"), count: 10))
        let outcome = try await RetryRunner(policy: policy, sleeper: sleeper).run { () async throws(VectorizationFailure) -> Int in
            try await operation.attempt()
        }
        #expect(outcome == .stopped(.systemic("store"), attempts: 2))
        #expect(await sleeper.sleeps == [.seconds(1)])
    }

    @Test func authorizationLossStopsWithoutRetrying() async throws {
        let sleeper = RecordingSleeper()
        let operation = ScriptedOperation(failures: [.authorization])
        let outcome = try await RetryRunner(policy: policy, sleeper: sleeper).run { () async throws(VectorizationFailure) -> Int in
            try await operation.attempt()
        }
        #expect(outcome == .stopped(.authorization, attempts: 1))
        #expect(await sleeper.sleeps.isEmpty)
    }

    @Test func cancellationDuringBackoffStopsFurtherAttempts() async throws {
        let gate = AsyncGate()
        let operation = ScriptedOperation(failures: Array(repeating: .assetUnavailable("slow"), count: 10))
        let runner = RetryRunner(policy: policy, sleeper: RecordingSleeper())
        let task = Task {
            try await runner.run { () async throws(VectorizationFailure) -> Int in
                await gate.wait()
                return try await operation.attempt()
            }
        }
        await gate.waitForWaiters(1)
        task.cancel()
        await gate.open()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(await operation.attempts == 1)
    }
}
