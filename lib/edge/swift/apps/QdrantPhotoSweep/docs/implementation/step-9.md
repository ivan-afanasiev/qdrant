# Step 9 — Presentation, settings and wiring (2026-11-16)

Step 9 of REWRITE_PLAN.md §10: immediate threshold changes, rescan, statistics, notifications, preview, errors and shared Liquid Glass styling. Exit: all retained screens and navigation match the revised behavior, with no business orchestration in views. The agreed setup adds composition-root and app wiring, background handler registration, and on-device observation of step 8.

## Confirmed decisions (2026-11-16)

1. **Rewrite is the default engine.** A Debug-only launch argument, `-PhotoSweepLegacyEngine YES`, selects the legacy engine instead. The two engines never run together. Legacy data is left untouched until step 10.
2. **Similarity has three presets:** Strict 0.96, Balanced 0.92 (the default) and Loose 0.85.
3. **Date range is chosen from presets only:** last week, month, 3 months, 6 months, year, or all time.
4. **Notification permission is an onboarding step.** The order is welcome → photo access → notifications → date range → Start.

## Delivered

| Area | Contents |
| --- | --- |
| Composition (`SweepComposition`) | `PhotoSweepComposition` SafeDI root; `PlatformAdapters`/`PlatformServices` (live iOS adapters, macOS stubs for host tests); `AppRuntime` (store, both executors, lifecycle coordinator); `RewriteBootstrap` (shared, retryable `start()`, pending-operation recovery, window delivery); root view with scene-phase routing and `BootstrapFailedView`; `AppShellView` (onboarding or main screen: progress or review, plus Settings); `FeatureFactories` |
| Domain / use cases | `DateScopePreset`, `SimilarityPreset`; `WorkflowState.datePreset` and `isOnboardingCompleted`; `LoadPreferences`, `RequestPhotoAccess`, `RequestNotificationPermission`, `CompleteOnboarding`, `UpdateDateScope`, `UpdateSimilarityThreshold`, `RescanLibrary`, `LoadStatistics`, `ResetAppData`; `DiscoveryExecutor.stop()` |
| Features | Onboarding reducer and view; `LibraryProgressView`; review cards, comparison, full-screen preview and Keep All; Settings reducer and view with statistics |
| Design system | `qGlassPanel`; new `L10n` entries, translated into de/es/ru |
| Host app | `EngineSelection` in `App.swift`; legacy root moved unchanged into `LegacyEngine.swift`; `Info.plist` lists `com.qdrant.edge.QdrantPhotoSweep.scheduledVectorization` and `com.qdrant.edge.QdrantPhotoSweep.continuedVectorization.*`. Device runs showed two rules: continued identifiers must start with the bundle ID, and the `.*` entry is only a pattern. Registering the wildcard itself is rejected ("not advertised"), so each continued request registers its own `prefix.<UUID>` identifier right before submitting it. A request without a registered handler terminates the app, so nothing is submitted after a rejected registration. The legacy engine registers its wildcard the same way and was silently falling back to foreground execution; it is left unchanged until cutover; member import visibility is enabled |
| Removed | Step 3 validation scaffolding (`BootstrapResource`, `BootstrapProbe`, `BootstrapApplication`, `LibraryStore`); SafeDI is now used only by `SweepComposition` |

## Interpretations

- **Date presets are rolling windows with an open end.** The executor resolves the range again at the start of every pass using an injected clock, so new photos are always in scope.
- **Changing the date range:**
  - closes the initial gate
  - starts a new discovery revision
  - requests a user-initiated pass (continued processing)
  - reopens review when the scoped pass completes
- **Changing the threshold** applies immediately as a new discovery revision. It reuses existing vectors and does no re-vectorization.
- **Rescan** reconciles the library again, reuses unchanged vectors and reopens review after the pass.
- **Reset:**
  - stops both executors
  - clears the current shard and starts a new index generation and revision
  - analyzes the library again
  - keeps the preferences (date range, threshold, onboarding completed) and the deletion history and statistics
  - never touches photos
- **Cards:** swiping is Skip; the Skip button is the accessible alternative. Cards and comparison show an 800 px thumbnail first; since device feedback on 2026-11-17 they then load the original, with a spinner in the top-left corner while it loads.
- **Library observation** is registered only once photo access exists.
- **No automatic work before onboarding completes** (device feedback, 2026-11-17). Activation, scheduled and grace windows are skipped until Start. Previously, returning from the Photos permission alert started an "All Time" pass whose single huge metadata call held the store, so Start never finished saving. Registration now runs in chunks of 500 photos, and point-ID uniqueness takes one query per batch instead of one per photo.
- **Settings:** controls are disabled while an operation runs; failures show a dismissable alert; reset requires confirmation. "Storage freed" is an estimate that excludes deletions with an unknown size; those deletions are counted in a separate footer.

## Device findings for background Vision (2026-11-17)

- **Neural Engine, not CPU-only.** Forcing every Vision stage onto the CPU in the background (step 8 decision) failed on device with `Missing weights path SceneNet…` (`ESPRESSO_STATUS_ERROR_IO`): the CPU variant of the feature-print model was not present. Every background embedding failed, progress stalled, and iOS ended the continued task. Background requests now use the Neural Engine when available and fall back to the CPU; the GPU is still never used, which keeps the heat goal of the original decision.
- **No progress after expiry.** Expired continued tasks no longer receive progress updates. Their Live Activity is already gone, and late updates logged `Couldn't find bgContinuedProcessing-… in the list of started activities`.

## Localization

There are 50 new keys. Sub-agents translated them into de, es and ru, and the catalog now reports 0 new strings per locale, all marked `machine_translated`.

- **English plural forms:** three keys with a count (`library.unavailable %lld`, `notification.reviewReady.bodyUnavailable %lld`, `settings.stats.unknownSizes %lld`) now have English one/other forms, so the singular reads correctly.
- **Russian «é»:** some Russian strings from before the rewrite use the Latin "é" (U+00E9) where «е»/«ё» belongs, e.g. in `review.deletedPhotosNote`. They were left unchanged.
- **Review needed:** native-speaker review is recommended.

## Accessibility and Liquid Glass

Code review confirmed the following:
- icon-only buttons (preview, close, settings) have labels
- the decorative onboarding icon is hidden from accessibility
- kept photos carry the selected trait
- card animation respects Reduce Motion
- controls use the standard `.glass` / `.glassProminent` styles, `GlassEffectContainer` and `qGlassPanel`

None of this has been checked on screen; see below.

## Not yet done

- **Device observation is still open.** This covers step 8's background execution (continued task and Live Activity, scheduled processing, grace window, notifications) and the step 9 journeys on a physical iPhone.
- **No visual pass yet.** Light/dark mode, Reduce Transparency, Dynamic Type and localized layouts have not been checked; for example, the German review controls with three buttons in one row might be truncated.
- **No XCUIAutomation smoke-test target.** The step 9 exit criteria don't require one, so it is deferred to the step 10 device journeys.
- **The legacy engine and its data remain** until cutover in step 10.

## Validation results

Environment: Xcode 27.2 (27B52), Apple Swift 6.4.2.

| Check | Result |
| --- | --- |
| `swift test --package-path Packages/PhotoSweep` (macOS) | 253 pass, 0 failures |
| `xcodebuild test -scheme PhotoSweep`, iPhone 17 iOS 26.5 simulator | TEST SUCCEEDED, 257 pass; Vision skipped on the simulator |
| Xcode BuildProject (app and tests) | Succeeds with 0 warnings |
| Legacy `QdrantPhotoSweepTests` (earlier in step 9) | 13/13 pass; Vision skipped on the simulator |
| `python3 Scripts/check-module-boundaries.py` | PASS: 15 boundaries, 17 test targets |
| `python3 .agents/validate.py` | PASS: 49 requirements, 16 product decisions |
