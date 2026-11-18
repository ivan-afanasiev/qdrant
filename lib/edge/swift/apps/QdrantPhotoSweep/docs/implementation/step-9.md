# Step 9 — Presentation, settings and wiring (2026-11-16)

Step 9 of REWRITE_PLAN.md §10: immediate threshold changes, rescan, statistics, notifications, preview, errors and shared Liquid Glass styling. Exit: all retained screens and navigation match the revised behavior, with no business orchestration in views. The agreed setup adds composition-root and app wiring, background handler registration, and on-device observation of step 8.

## Confirmed decisions (2026-11-16)

1. **Rewrite is the default engine.** A Debug-only launch argument, `-PhotoSweepLegacyEngine YES`, selects the legacy engine instead. The two engines never run together. Legacy data is left untouched until step 10.
2. **Similarity has three presets:** Strict 0.96, Balanced 0.92 (the default) and Loose 0.85.
3. **Date range is chosen from presets only:** last 3 months, last year, last 3 years (the default), last 5 years, or all time. *(Changed by the owner on 2026-11-18 after device use; previously last week, month, 3 months, 6 months, year and all time, with all time as the default.)*
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

## Discovery during long passes (device feedback, 2026-11-17)

Review showed "All done" after 11 groups in a library with hundreds of similar photos. The discovery algorithm (newest-first seeds, connected components, suppression, paged exact search) behaved as specified; two gaps made the result look final too early:

- Discovery refilled only when a vectorization pass ended, so vectors committed during a long pass (new photos, or photos deferred earlier by the background Vision failure and retried) did not reach review until the whole pass finished. The coordinator now requests a refill after every committed batch in the foreground. `discoveryUsesVectorsCommittedDuringALongPass` covers this and fails without the change.
- "All done" was shown whenever discovery was exhausted. It is now shown only when vectorization is not running, paused or failed; otherwise the review area keeps showing "Finding duplicates…" under the progress line.

## Progress over the whole scope (device feedback, 2026-11-17)

Progress used to count only the pass's work set (photos still needing analysis), leaving out photos with reusable vectors from earlier runs. It now covers the whole scope, with reused photos counted as done; pass bookkeeping (completion, deferrals, notifications) is unchanged. This did not explain the device report of about 18,000 photos for "All Time" against more than 30,000 in the legacy app: the later "Reading your library" total showed that the scope itself contains about 18,000 images. Both apps use the same Photos query (all images in the date range), so the legacy number comes from how the legacy app counted, not from photos missing in the rewrite. On the full progress screen the control button is full width and large (Pause in the regular glass style, Resume/Retry prominent), and while running the line under the bar shows the percentage instead of repeating the count.

## Known issues fixed before step 10 (2026-11-17)

- **Progress while preparing.** A new `VectorizationStatus.preparing(done:total:)` covers the access check, library fetch and chunked registration. The progress screen shows "Reading your library: x of y", and continued tasks report the same numbers, so the Live Activity no longer sits at zero during a long first phase. `reconcileReportsProgressAfterFetchAndEveryChunk` covers the reporting; grace windows also treat preparing as working.
- **Memory-bounded review cards.** Cards load a high-quality image sized to the card (longest side = card width × display scale, adjusted for portrait, rounded to 256 px and capped at 4096) through `PhotoLibraryProviding.loadDisplayImage`. Only the full-screen preview decodes the original.
- **Russian strings.** Five older strings with a Latin "é" now use Cyrillic «ё». The two new status strings are translated into de/es/ru (machine translated, pending native review).

## Rescan while running (device feedback, 2026-11-18)

- **One Live Activity.** Each Rescan used to submit a new continued-processing request, so repeated taps showed several Live Activities for one pass. The coordinator now requests continued processing only when no continued window is active or pending, and an active window keeps covering the restarted pass. Before this, `waitUntilIdle` saw the short gap between the old pass stopping and the new one starting, so the window ended early.
- **Restart, not queue.** Rescan and date-range changes call `VectorizationExecutor.restart`, which stops the running pass at a safe boundary, abandons it and starts a fresh pass. Committed vectors are reused. Before, a rescan during a running pass only queued another pass behind it.
- **Back to review.** A successful Rescan closes Settings, so progress and review are visible right away.
- Covered by `repeatedRestartsKeepOneContinuedTaskAndFinishTheLibrary`, `successfulRescanClosesSettings` and `failedRescanStaysOnSettings`.

## Quiet launch checks (device feedback, 2026-11-18)

Every launch reconciles the library to pick up new or edited photos. Since preparation progress was added, that check showed "Reading your library" above the cards even when nothing had changed. A pass is now a quiet routine check when review is open and the last status was idle or completed: it reports neither preparing nor running unless it finds photos to analyze. First scans, rescans, date-range changes and Resume/Retry still show the whole pass. Registration also writes only changed values, so an unchanged library is not saved again on every launch. Covered by `launchCheckAfterAFinishedScanIsQuiet` (fails without the change) and `launchCheckWithNewPhotosStillAnalyzesThem`.

## Layouts for long labels (owner choice, 2026-11-18)

German and Russian labels broke the review controls (three text buttons in one row) and the Settings pickers. The owner picked from preview-only options:

- **Review: option C.** Skip and Keep All are round icon buttons (forward, checkmark) with VoiceOver labels, and the one labeled action (Delete All, Delete N Photos or Keep All) takes the rest of the row.
- **Settings: option B.** The date range and similarity are inline checkmark lists, so each choice has its own row and long labels wrap. Rescan has a refresh icon.

The real views now have `#Preview`s in German and Russian, including the narrow folded iPhone Duo width.

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
