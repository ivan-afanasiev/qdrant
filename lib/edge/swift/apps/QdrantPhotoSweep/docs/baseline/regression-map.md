# Existing regression tests and rewrite disposition

Source: Tests/ScanLifecycleTests.swift; 13 Swift Testing tests in @Suite(.serialized), @MainActor. Production is tested with in-memory SwiftData and fake Photos/vector stores except the Vision smoke test. No live-library deletion is exercised.

Execution: all 13 passed on physical iPhone 17, iOS 27.0.1, through Xcode RunAllTests on 2026-11-12. [Recorded results](artifacts/test-results.json). The suite took 0.176 seconds according to its console; this is not application throughput or background-scheduling evidence.

| Existing test | Current invariant / limitation | Rewrite disposition | Target / requirement |
| --- | --- | --- | --- |
| visionFeaturePrintRunsWithSelectedComputeDevices | Real Vision returns finite nonempty floats from synthetic 224×224 image; does not force a background app state | Retain platform smoke test; add explicit execution-context coverage | SweepEmbeddingsTests; VEC-05, TEST-04 |
| coordinatorResumesTheSessionCreatedByItsPipeline | Explicit retry retains interrupted session ID and original failure; no automatic retry on activation | Port identity/recovery; revise retry behavior to finite automatic policy | SweepUseCasesTests; VEC-03, LIFE-02 |
| embeddingFailureStopsImmediatelyAndPreservesTheError | Missing model stops after one call, no completed session | Retain systemic-failure classification; add separate per-asset defer path | SweepUseCasesTests; VEC-03 |
| failedSearchIsRetriedEvenAfterVectorUpsert | Existing point does not imply completed detection | Split indexing and discovery journals/checkpoints; preserve replay invariant | SweepUseCasesTests/SweepPersistenceTests; LIFE-02 |
| cancellationInFinalBatchDoesNotMarkScanComplete | Final-batch cancellation remains retryable | Port to vectorization AND component publication boundaries | SweepUseCasesTests; LIFE-02, REV-03 |
| detectionDoesNotRequireUICallbackAndUsesConfiguredThreshold | Detection/checkpoint independent of optional UI callback; threshold captured | Retain independence; new revision-based discovery and scope tests | SweepUseCasesTests; ARC-04, VEC-06 |
| repeatedEdgesAreIdempotent | Reverse endpoints update same stored edge | Retain canonical edge/replay coverage under new schema | SweepPersistenceTests; REV-03, LIFE-02 |
| recoveryFindsScanningSessionsButNotUserCancelledSessions | Old scanning rows recover; old explicit cancellation excluded | Replace cancelled-session semantics with interrupted/manual-pause behavior | SweepPersistenceTests/SweepUseCasesTests; LIFE-03 |
| incrementalRangeIncludesPhotosAfterPreviousRangeEnd | Checks scannedAt-to-now interval; does not cover late imports/edited old photos | Replace timestamp-only assumption with content-revision reconciliation cases | SweepUseCasesTests; VEC-01, VEC-07 |
| foregroundWaitsForBackgroundCleanupAndBackgroundCannotOverlap | Exclusive execution and replacement wait for cleanup | Retain shared executor/shard invariant; discovery has distinct owner | SweepUseCasesTests/SweepCompositionTests; ARC-08, LIFE-04 |
| cancellationBeforePhotosContinuationInstallationResumesImmediately | Pre-install cancellation resumes with CancellationError | Preserve directly during Photos extraction | SweepPhotosTests; VEC-04 |
| photosCancellationCompletesContinuationOnlyOnce | Repeated cancellation/late callback resumes once | Preserve and extend late request-ID publication case | SweepPhotosTests; VEC-04 |
| explicitCancelPersistsCancellationBeforeReplacementStarts | Old UI Cancel stops worker, does not autoresume, permits replacement | Replace user-Cancel assertions with Pause/Resume/next-opening and internal replacement coverage | SweepUseCasesTests; LIFE-03 |

## Test-fixture caveats

- RecordingVectors returns no search matches; these tests do not prove actual grouping correctness, recall, date filtering or Qdrant SDK behavior.
- FixturePhotos.countAssets returns 1 regardless of configured count; fix when reusing fixtures.
- FixturePhotos.loadFullImage delegates to thumbnail loading, so it cannot detect accidental full-resolution requests.
- waitUntil polls with a real clock; use deterministic suspension gates/injected clocks in new tests.
- Current mock dependencies live in production source under DEBUG. Move test support out of the shipping dependency graph.
- One serialized main-actor suite cannot establish real background system scheduling or race freedom.

## Coverage to add in later steps

No current direct coverage was found for real shard contracts, lazy component completion (>10 matches), 2–3 buffer refill/exhaustion, stable cards, skip cycling, completed-group suppression, stale commit conflicts, deletion cleanup journals, cross-store reset, byte/statistics deduplication, incremental content edits, limited-access reconciliation, SafeDI lifetime identity, resource budgets, notifications or UI automation.

Map each new business unit to the canonical requirement IDs and the test matrix in REWRITE_PLAN.md §9. Keep the current suite until its useful behavior is replaced; do not copy obsolete product policies into the rewrite.
