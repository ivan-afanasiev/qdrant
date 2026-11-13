# Step 4 — Domain and state contracts (2026-11-13)

Step 4 of REWRITE_PLAN.md §10: separate vectorization/discovery models, native reducers/effects, policies and fakes. Exit: deterministic tests cover the agreed gates, retries, pause, buffer and review semantics. Everything here is pure or in-memory; persistence (step 5), the live vectorization pipeline (step 6) and discovery/deletion use cases (step 7) are not started. The legacy engine remains the running app.

## Delivered

| Target | Contents |
| --- | --- |
| SweepDomain | Typed IDs and monotonic revisions (`AssetID`, `GroupID`, `OperationID`, `VectorizationPassID`, `DiscoveryRevision`, `IndexGeneration`, `MembershipRevision`), `IDGenerating`; inclusive `DateRange.contains`; `EmbeddingCompatibility` + `VectorReusePolicy`; `VectorizationFailure` classification, finite `RetryPolicy`, `Sleeper`; `VectorizationPass`, `VectorizationStatus`, `InitialPassGate`; `PausePolicy`; `SimilarityThreshold`, resumable paged `ComponentExpansion`; `DiscoveryStatus`, `DiscoveryUpdate`, `ReviewBufferPolicy`, `DiscoveryPolicy`; `ReviewGroupSnapshot`, `KeepSelectionPolicy`, `ReviewCommitPolicy`, `ReviewQueue` |
| SweepFeatureState | `Reducer`, `Effect` (run/cancel/merge, effect IDs, `cancelInFlight`), `Send` that drops actions from cancelled effects, `@MainActor @Observable Store` |
| SweepUseCases | `RetryRunner` executing `RetryPolicy` with an injected `Sleeper` |
| SweepLibraryFeature | `LibraryFeature` reducer: status observation, Pause/Resume/Retry, no Cancel; `VectorizationControls` binding point |
| SweepReviewFeature | `ReviewFeature` reducer: card loading, keep selection, explicit delete-all, Skip, commit outcomes, revision retirement; `ReviewClient` binding point |
| SweepTestSupport | `FakePhotoLibrary` (records thumbnail vs full-resolution requests), `FakeVectorStore` (cosine search, paging, failure injection), `FakeEmbeddingProvider`, `RecordingSleeper`, `SequentialIDGenerator`, `AsyncGate` |

No views, SafeDI annotations or use-case bindings were added for the new reducers; the step 3 `LibraryStore` DI stub is unchanged.

## Exit-criteria coverage

| Area | Rule IDs | Tests |
| --- | --- | --- |
| Initial gate | VEC-02 | `InitialPassGateTests`, `VectorizationPassTests` — blocked during pass, opens with deferred count, incremental passes never reopen/close, obsolete pass ignored, scope change/rescan closes |
| Retries | VEC-03 | `RetryPolicyTests`, `RetryRunnerTests` — finite asset retries then deferral, infrastructure failures stop the pass instead of deferring, immediate stop for authorization/incompatibility, capped backoff, cancellation during backoff |
| Pause | LIFE-03 | `PausePolicyTests`, `LibraryFeatureTests` — manual pause blocks automatic/background triggers, activation/Resume/Retry clear it, no optimistic state, view disappearance cancels only the subscription |
| Buffer/discovery | REV-01–REV-03 | `DiscoveryStatusPolicyTests`, `ComponentExpansionTests` — background suspension, capacity 2–3, empty buffer ≠ exhaustion, A–B–C chains, inclusive threshold, >10 matches, 5,000-link chain, scope on both sides, paging/resume |
| Review semantics | REV-05, REV-07, REV-08 | `KeepSelectionPolicyTests`, `ReviewCommitPolicyTests`, `ReviewQueueTests`, `ReviewFeature*Tests` — no default selection, empty selection never deletes, delete-all/keep-all, declined deletion keeps card, conflicts refresh, skip persistence failure keeps card, deferred ordering/cycling without duplicates, stale results ignored, revision retirement with in-flight commit reconciliation |
| Vector reuse | VEC-05 | `VectorReusePolicyTests` — uncommitted points, edits, model revision/preprocessing changes, stale generation |
| State infrastructure | ARC-03, ARC-04 | `StoreTests` — synchronous reduction, effect feedback, cancel-in-flight, cancellation drops stale sends, merge |

## Confirmed decisions

These choices were not spelled out in the plan; the owner confirmed all eight as implemented on 2026-11-13. Items 2–4, 6 and 7 are also recorded in the agent rules.

1. **Feature targets depend on SweepDomain** for value types (`VectorizationStatus`, `ReviewGroupSnapshot`, IDs). Plan §4, project-map and the boundary script are updated; features still cannot import adapters, Photos, SwiftData or QdrantEdge.
2. **Similarity threshold is inclusive** (`score >= threshold`), values limited to 0…1.
3. **Date scope is inclusive at both ends**, matching the Photos predicate; assets without a creation date are outside every scope.
4. **Transient infrastructure failures** count against the systemic attempt limit and stop the pass; only `assetUnavailable` failures lead to per-photo deferral.
5. **Default retry parameters** (3 asset attempts, 3 systemic attempts, 1 s base, 30 s cap) and **default buffer capacity 3** are placeholders pending device measurement.
6. **Explicit Retry also clears a manual pause.** An **interrupted** pass offers no control because it resumes automatically.
7. **Deferred (skipped) groups do not count toward the ready buffer**; they are offered only after discovery is exhausted.
8. **A threshold/rescan revision retires the open card** unless a commit is in flight; the in-flight outcome is reconciled first, then the card is retired.

## Not in this step

Completed-group suppression and merge/split lineage (REV-06/REV-07 identity) need persisted membership history and move to steps 5/7. No persistence formats or `Codable` conformances are defined yet. Statistics, notifications, the background executor and the vectorization lifecycle state machine belong to steps 5–8.

## Validation results

Environment: Xcode 27.2 (27B52), Apple Swift 6.4.2.

| Check | Result |
| --- | --- |
| `swift build --build-tests` (macOS) | No errors or warnings |
| `swift test` (macOS) | 113/113 pass — Domain 61, Review 20, TestSupport 11, Store 6, RetryRunner 6, Library 5 (parameterized cases counted once), Composition 3, Qdrant 1 |
| Async suites repeated 25× (`Store`, `Review`, `Library`, `RetryRunner`, determinism helpers) | 0 failed runs |
| `xcodebuild test -scheme PhotoSweep`, iPhone 17 iOS 26.5 simulator | 117/118 pass; only `VisionEmbeddingTests` fails with the known simulator "espresso context" error (step 3) |
| Xcode BuildProject (app + tests) | Succeeds |
| `python3 Scripts/check-module-boundaries.py` | PASS — 15 boundaries, 11 test targets |

During validation a stale SwiftPM build cache produced spurious `libtool`/`codesign` failures; `swift package clean` resolved them.
