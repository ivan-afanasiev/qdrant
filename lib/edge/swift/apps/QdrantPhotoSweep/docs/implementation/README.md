# Rewrite log

What each step of `REWRITE_PLAN.md` §10 delivered, the decisions that shaped it, and the lessons worth keeping. Architecture is described in `ARCHITECTURE.md`; requirements live in `.agents/`.

## Status

Steps 1–9 are complete. Steps 8 and 9 were confirmed on an iPhone on 2026-11-18, and the device issues found there are deferred until after step 10. Step 10 (scale validation and cutover) is in progress.

## Steps

| Step | Outcome | Decisions that still matter |
| --- | --- | --- |
| 1–2 | Agent rules; baseline inventory, UI evidence and measurement protocol (`docs/baseline`). | — |
| 3 | SPM package with 15 targets and enforced boundaries (`Scripts/check-module-boundaries.py`); SafeDI 2.2.0 validated, then used only by `SweepComposition`. | `Package.resolved` is ignored, so swift-syntax is unpinned. Each developer or CI trusts the SafeDI plugin once. |
| 4 | Pure domain policies; native `Store`/`Reducer`/`Effect`; test fakes. | The threshold is inclusive (`score ≥ t`); date scopes are inclusive and undated photos are out of scope. Skipped groups don't count toward the 2–3 group buffer. |
| 5 | SwiftData schema v1 with single-transaction commits; a journal for every cross-store write; recovery; reset; an unwired clean-start transition. | Interrupted vector writes roll back, never forward. Reset keeps preferences and statistics. Suppression is any overlap with a group completed in this revision. |
| 6 | One app-owned `VectorizationExecutor`: reconcile → thumbnail → Vision → Qdrant, with checkpoints, Pause/Resume/Retry and the initial gate. | A per-photo failure defers that photo; 10 deferrals in a row stop the pass. The content revision is the Photos modification date. Processing is sequential, in batches of 16. |
| 7 | Lazy foreground discovery: newest-first seeds, connected components, paged exact search; card review and recoverable deletion. | A component touching one pending group grows it; touching several creates a new group. Byte estimates exclude unknown sizes. |
| 8 | `AppLifecycleCoordinator`: continued, scheduled and grace windows; readiness notification. | Any continued-task expiration counts as a manual pause (iOS doesn't distinguish Cancel). Notifications are at most once, and only for passes that did work. |
| 9 | Composition root, onboarding, progress, review, settings and statistics; the rewrite is the default engine and legacy is a Debug switch. | Presets: date range 3 months / 1 / 3 (default) / 5 years / all time; similarity Strict 0.96 / Balanced 0.92 / Loose 0.85. Swipe left = Skip, right = the card's commit action. Cards load a screen-sized image; only the preview loads the original. |

## Lessons

Each of these cost time once. They are explained in code comments where they apply.

**Platform**
- **`BGContinuedProcessingTask` identifiers:**
  - They must start with the bundle ID.
  - The `prefix.*` Info.plist entry is only a pattern. Registering the wildcard itself fails with "not advertised", so each request registers its own `prefix.<UUID>` just before submitting.
  - A request without a registered handler terminates the app.
- **Swift 6 isolation in launch handlers:** a closure created inside a `@MainActor` method is main-actor isolated. iOS calls BGTask launch handlers on its own queue, so the app crashes with `EXC_BREAKPOINT`. Build such closures in a `nonisolated` function.
- **Background Vision:** forcing the CPU fails on device because the CPU model variant is missing ("Missing weights path SceneNet…"). Use the Neural Engine, fall back to the CPU, and never use the GPU (that needs an entitlement).
- **Photos `.fastFormat`:** it returns a single low-quality image that is *not* marked degraded. Use `.highQualityFormat` whenever sharpness matters.
- **Exact cosine threshold:** Qdrant Edge's `scoreThreshold` is exclusive. The adapter passes `threshold.nextDown`.

**Performance**
- **Per-row uniqueness checks:** a `fetchCount` per inserted row makes registration quadratic, because SwiftData processes pending changes before every query. Check a batch with one query.
- **Long store calls:** one store call covering the whole library starves every other call on the store actor. Register in chunks of 500.
- **Unchanged rows:** write only values that changed and skip `save()` when nothing changed, or every launch rewrites the library.

**Lifecycle**
- **Before onboarding:** run no automatic work. Returning from the Photos permission alert counts as an activation and used to start a full-library pass.
- **Refill per batch:** discovery refills after every committed batch, not only at pass end, or review shows "All done" during long passes.
- **Restart, don't queue:** Rescan and date changes restart the pass. Ask for continued processing only when none is active or pending. Keep `waitUntilIdle` blocked across a restart, so windows don't end in the gap between passes.
- **Quiet checks:** a pass after a finished scan is a quiet routine check and shows progress only when there is work.

**Tests**
- **Default ranges:** fixtures dated 1970 fall outside a default "last 3 years" range. Test harnesses use an explicit all-time preset.
- **Waits:** wait on status or discovery streams, never sleep. Give stream-based tests `.timeLimit` so a regression fails instead of hanging.

## Validation

```sh
swift test --package-path Packages/PhotoSweep                      # macOS, ~265 tests
cd Packages/PhotoSweep && xcodebuild test -scheme PhotoSweep \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'     # iOS, ~269 tests; Vision skipped
python3 Scripts/check-module-boundaries.py
python3 .agents/validate.py
```

Vision tests run only on a physical device, because the simulator cannot create Vision's model context.

## Step 10: open

- **Scale:** test with 100,000+ photos from `Scripts/test-photos`, then tune batch, page and retry sizes against device measurements (`docs/baseline/measurement-protocol.md`). The owner runs the device measurements.
- **Cutover:**
  - Wire `LegacyDataTransition`.
  - Remove the legacy engine and Debug switch, its grid code, its Info.plist identifiers and its test target.
  - Remove the legacy originals of the package's adapter and design-system files.
- **Also carried over:**
  - an XCUIAutomation smoke target
  - a Release build
  - pinning swift-syntax and CI plugin trust
  - native-speaker translation review (about 160 machine-translated strings)
  - a check that Claude and Cursor load the agent instructions
