# Step 7 — Lazy discovery and card review (2026-11-14)

Step 7 of REWRITE_PLAN.md §10: component expansion → 2–3-group buffer → selection/skip → recoverable deletion/refill. Exit: scoped chain semantics, incremental arrivals, suppression and failure recovery pass; grid is removed.

As agreed: the rewrite review flow has no grid (legacy grid code goes with the legacy engine at cutover), seeds are newest photos first, and the flow is complete and tested but not wired into the running app until the screens exist (step 9).

## Delivered

| Target | Contents |
| --- | --- |
| SweepDomain | `VectorStoring.searchPage` (paged, thresholded, date-filtered) and `vector(id:)`; `VectorSearchFilter`, `VectorPayload` (asset + creation time); `PhotoLibraryProviding.accessScope()` / `assets(withIdentifiers:)`; `AdapterError.deletionDeclined`; `DiscoveryRepository`, `ComponentOutcome`, `DeletionRepository`; atomic `WorkflowStateRepository.modifyWorkflowState` |
| SweepQdrant | Exact paged search with payload range filter, inclusive threshold, vector retrieval |
| SweepPhotos | Access scope, lookup by identifier, declined deletion mapped from `PHPhotosError.userCancelled` |
| SweepPersistence | Per-asset `examinedRevision` and seed keys; newest-first `nextSeed`; `pendingGroups(containing:)`; one-save `completeComponent` (discard / publish with lineage / merge) and `finishDeletion` |
| SweepUseCases | `DiscoveryExecutor`; `LoadNextReviewGroup`, `SkipGroup`, `CommitReviewDecision`, `FinishConfirmedDeletion`, `ReconcileDeletion`, `LoadReviewImage`; deletion reconciliation in `RecoverPendingOperations`; vectorization payload now carries creation time |
| SweepReviewFeature | `ReviewClient.live(...)` binding the step 4 card reducer to these use cases |

### Discovery

Foreground only, after the initial gate. Each round restores an interrupted component or takes the newest eligible photo not yet examined in this revision. It then expands the full chain through paged Qdrant searches restricted to the date range, checkpointing after every query, and records the outcome in one save:
- single photo, or overlap with a reviewed group: discarded (suppressed)
- overlap with exactly one pending group: merged, keeping its ID and bumping its revision
- otherwise: a new group, absorbing any pending groups it joins, with lineage

It stops when the buffer is full, when no eligible photo remains (exhausted), or when the app moves to the background (suspended). Threshold change or rescan (`beginNewRevision`) retires the current groups, order and deferrals and starts again from the newest photo using the existing vectors.

### Review and deletion

The next card is fresh groups in discovery order; skipped groups come back only after exhaustion. Groups with a deletion in progress are hidden. Commit re-checks the membership revision and that every photo is accessible, and returns a conflict otherwise.

Keep-all completes the review. Deleting follows journal intent → Photos → confirmed outcome → remove vectors → one save that removes assets, completes the group, counts the statistics once and closes the journal. If the user declines in Photos, the journal is closed, the card stays and nothing is counted. A failed or interrupted deletion is reconciled: a photo counts as deleted only if it is missing while the app has **full** access. Limited access leaves the entry open and the group hidden, and Photos is never asked to delete again during recovery.

## SDK findings (REV-04)

- **Qdrant Edge `scoreThreshold` is exclusive** (score > threshold), confirmed by probe; the domain rule is inclusive. The adapter passes `threshold.nextDown`, which returns exactly the scores ≥ threshold, with no client filtering that could shorten pages.
- **Paging uses `offset` with exact search** so pages neither skip nor repeat points. Verified with 37 matches in pages of 10 on a real shard. Exact search scans every point per query; its cost at 100,000+ photos is unmeasured (step 10).
- **The date filter** is a payload `RangeFloat` on `created`; points without a creation time never match.
- **Stored vectors** are read with `retrieve(withVector:)` (JSON array).

## Exit-criteria coverage

| Criterion | Tests (`SweepDiscoveryReviewTests` 28, `DiscoveryStoreTests` 8, `QdrantNeighborhoodTests` 4) |
| --- | --- |
| Scoped chain semantics | A–B–C chain without A–C match; newest seed first; 25-photo group across pages of 4; out-of-scope and undated photos neither join nor bridge; gate respected |
| Buffer | stops at capacity without examining everything; refills after each review until true exhaustion; background suspends, foreground resumes; interrupted component resumes from checkpoint |
| Incremental arrivals | new photos after exhaustion form groups; a new match merges into the pending group with the same ID; a new photo joining two groups produces one group with lineage |
| Suppression | a new match for a reviewed group never resurfaces it |
| Review | skipped group returns only after the rest; keep-all; delete selected; explicit delete-all; declined deletion; stale card → conflict; photo removed outside the app → conflict; full resolution only for preview; reducer drives the real use cases |
| Failure recovery | crash before the Photos call; crash after Photos deleted but before confirmation; limited access never proves deletion; crash after confirmation finishes cleanup once without deleting again; failed call that still deleted; vector cleanup failure hidden until recovery |

## Confirmed decisions

The owner confirmed all seven choices on 2026-11-14.

1. **Seed order is tracked with an "examined in revision" mark per photo**, not a position cursor, so photos added later are still discovered newest-first.
2. **A component touching exactly one pending group grows that group** (same ID, new revision; an open card then gets a conflict and refreshes). Touching several creates a new group that retires them, with lineage.
3. **Suppression discards the whole component** if any photo belongs to a group reviewed in this revision, as the step 5 decision stated.
4. **Splits are not recomputed**: when a pending group's photo is edited or removed, the group is not re-split. Commit-time validation reports the conflict.
5. **The storage estimate is recorded only when every deleted photo's size is known.** The Photos adapter does not provide sizes yet (as before), so estimates stay "unknown" rather than downloading originals.
6. **If cleanup fails after Photos deleted**, the commit reports a failure, the card is hidden and cleanup finishes at the next launch's recovery.
7. **For a partially completed deletion, only confirmed-missing photos are counted**, and the size estimate is dropped unless all of them are missing.

## Not validated

The real Photos deletion prompt and the declined-error mapping need a device (TEST-05). Exact-search cost at scale is unmeasured. A launch-time hookup that runs recovery with deletion reconciliation belongs to the app wiring step.

## Validation results

Environment: Xcode 27.2 (27B52), Apple Swift 6.4.2.

| Check | Result |
| --- | --- |
| `swift build --build-tests` (macOS) | No errors or warnings |
| `swift test` (macOS) | 219/219 pass, 0 CoreData errors |
| `SweepDiscoveryReviewTests` and `SweepVectorizationTests` repeated 30× each | 0 failed runs |
| `xcodebuild test -scheme PhotoSweep`, iPhone 17 iOS 26.5 simulator, run twice | All suites pass; Vision skipped on simulator; 0 CoreData errors |
| Xcode BuildProject (app + tests) | Succeeds |
| `python3 Scripts/check-module-boundaries.py` | PASS — 15 boundaries, 14 test targets |

The first simulator run exposed a timing-dependent step 6 test (`libraryChangesTriggerIncrementalPassWithoutClosingGate`): its helper polled with a bounded number of yields. It now waits deterministically on the fake library's fetch count, and the helper was removed.
