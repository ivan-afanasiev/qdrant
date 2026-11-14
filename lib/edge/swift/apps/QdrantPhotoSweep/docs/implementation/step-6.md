# Step 6 — Foreground vectorization (2026-11-14)

Step 6 of REWRITE_PLAN.md §10: authorization → reconciliation → thumbnails → Vision → Qdrant → durable pass completion/deferred outcomes. Exit: cache reuse, automatic triggers, Pause/Resume/Retry and initial review gate pass end to end.

The pipeline is complete and tested end to end against the real SwiftData store, but it is **not wired into the running app**. The legacy engine is still active and the rewrite has no screens until step 9; running both would double Photos/Vision work and heat. Composition and app wiring land with the presentation step.

## Delivered

| Target | Contents |
| --- | --- |
| SweepDomain | `PhotoAsset.modificationDate` and `contentRevision`; contracts `PhotoLibraryChangeObserving`, `EmbeddingModelDescribing` (`EmbeddingModelDescriptor`), `VectorStoreProviding`; `WorkflowState.indexCompatibility`; `SimilarityThreshold.standard` (0.92, as before) |
| SweepPhotos | `PhotoLibraryChangeMonitor` (PHPhotoLibrary observer, registered on first subscription, bursts coalesced); modification date mapped from `PHAsset` |
| SweepEmbeddings | `VisionEmbeddingService.modelDescriptor()`: model, `VNGenerateImageFeaturePrintRequest.currentRevision`, dimensions probed once with a synthetic image |
| SweepQdrant | `QdrantStoreProvider`: single shard owner, one directory per index generation (`g<n>`), old generations removable |
| SweepPersistence | Workflow state stores the index compatibility (schema v1 extended in place; not yet shipped) |
| SweepUseCases | `VectorizationExecutor` (app-owned actor), `ReconcilePhotoLibrary`, `VectorizePhoto`, `StatusBroadcast`, `VectorizationConfiguration` |
| SweepTestSupport | `FakeVectorStoreProvider`, `FakePhotoLibraryChanges`; `FakeEmbeddingProvider` describes and can change its model |

### Executor behavior

- **Triggers** go through `PausePolicy`. App activation, Resume and Retry clear a manual pause; automatic foreground and background triggers are blocked by it. A trigger during a pass queues one follow-up pass, so photos added mid-pass are picked up. Library change notifications trigger automatic foreground passes.
- **Pass:** request authorization → describe the model → switch generation if compatibility changed → open the generation's store → reconcile (register identity and content revision) → resume the checkpointed pass for the same scope, or start a new one containing only photos without a reusable vector → per photo: 224 px fast thumbnail → Vision → classify failures and retry with `RetryRunner` → per batch: record deferrals, then `VectorWriteTransaction` → on completion, open the initial gate (initial passes only) and finish the pass.
- **Gate:** a pass is initial while the gate is closed, otherwise incremental. Incremental passes never close it; a model change closes it and rebuilds the index in a new generation.
- **Pause / interrupt:** both stop at the next photo boundary. Everything committed before that point is kept. Pause persists the manual pause; interruption does not.
- **Failures:** a photo that cannot be loaded or embedded is retried, then deferred. Ten deferrals in a row stop the pass as systemic. Authorization loss, store or model failures and write failures stop the pass and offer Retry. A photo that vanished from the library mid-pass is deferred.
- **Status** is broadcast to any number of observers; cancelling an observer never affects the pass.

## Exit-criteria coverage (`SweepVectorizationTests`, 19 tests)

| Criterion | Tests |
| --- | --- |
| Cache reuse | relaunch re-embeds nothing; edited photo re-embedded; model change rebuilds in a new generation and removes the old shard |
| Automatic triggers | library change → incremental pass with gate kept open; trigger during a pass queues a follow-up; observer cancellation doesn't stop work |
| Pause/Resume/Retry | pause checkpoints mid-pass and blocks automatic/background triggers; pause survives relaunch until app activation; resume continues from checkpoint; system interruption is not a manual pause; relaunch resumes the same pass; systemic failure stops with finite retries and Retry succeeds; Retry ignored when nothing failed |
| Initial review gate | gate closed during the initial pass; opens on completion with deferred count; unavailable photos deferred after retries; deferral breaker; denied access fails without deferring photos |
| Thumbnails only | no full-resolution requests during processing; 224×224 thumbnail requested |

## Confirmed decisions

The owner confirmed all eight choices on 2026-11-14.

1. **Not wired into the app** until the presentation step (see above).
2. **Per-photo embedding errors defer the photo**; a run of 10 consecutive deferrals stops the pass as systemic. Up to 9 photos may be marked unavailable before the breaker trips.
3. **Photos missing from the library during a pass are deferred, not removed**; telling inaccessible from deleted is part of reconciliation work in step 7.
4. **Content revision is the Photos modification date**; photos without one are treated as never edited.
5. **Default scope "all time" is stored as distant past … distant future**, so it does not end at install time.
6. **Processing is sequential** (one photo at a time, batches of 16). Concurrency and thermal work budgets (`EvaluateWorkBudget`) wait for device measurements.
7. **On a model change the old index is removed when the new generation starts**, so review is unavailable until the rebuild finishes.
8. **Retry is also offered after an interruption**, in addition to failures.

## Not validated

The Photos change monitor, the Vision model probe and the Qdrant provider driven by the executor have not run on a device or simulator end to end; Vision cannot run on simulators. Background triggers (`backgroundContinuation`, `backgroundScheduled`) are honored by the pause policy but no background adapter calls them yet (step 8).

## Validation results

Environment: Xcode 27.2 (27B52), Apple Swift 6.4.2.

| Check | Result |
| --- | --- |
| `swift build --build-tests` (macOS) | No errors or warnings |
| `swift test` (macOS) | 176/176 pass |
| `SweepVectorizationTests` repeated 30× | 0 failed runs |
| `xcodebuild test -scheme PhotoSweep`, iPhone 17 iOS 26.5 simulator | All suites pass; Vision skipped on simulator; 0 CoreData errors |
| `QdrantStoreProviderTests` (real Qdrant, macOS and simulator) | Generations isolated, old generations removed, dimension mismatch rejected |
| Xcode BuildProject (app + tests) | Succeeds |
| `python3 Scripts/check-module-boundaries.py` | PASS — 15 boundaries, 13 test targets |
