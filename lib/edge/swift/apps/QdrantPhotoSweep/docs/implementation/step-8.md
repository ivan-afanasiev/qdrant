# Step 8 — Background vectorization (2026-11-16)

Step 8 of REWRITE_PLAN.md §10: continuation and automatic scheduling adapters on the shared executor. Exit: expiration/handoff/manual-pause scenarios pass and real-device execution is observed; discovery remains foreground-only.

As agreed when setting up the step, everything is implemented and tested with fakes; **real-device execution will be observed after the step 9 wiring**, so the app keeps running a single engine until then. That part of the exit criteria stays open.

## iOS 26 eligibility (verified in Apple documentation, LIFE-05)

| Mechanism | Used for | Notes |
| --- | --- | --- |
| `BGContinuedProcessingTask` | Explicit user actions: first start, Resume, Retry, Rescan | Submitted from the foreground only for a person's action. The system shows a Live Activity with Cancel. Progress must be reported. Default resources (CPU, no GPU). Strategy `.fail`: start now or not at all. |
| `BGProcessingTask` | iOS-scheduled vectorization while the app is not in use | No external power or network requirement. iOS chooses the time; nothing is guaranteed. |
| `beginBackgroundTask` | Short grace period when an automatic pass is running at background entry | The expiration handler ends the system task synchronously, as UIKit requires. |

The continued task's `expirationHandler` is the only signal for both a person's Cancel and a system termination; the two cannot be told apart.

## Delivered

| Target | Contents |
| --- | --- |
| SweepDomain | `ExecutionWindow` (finish exactly once), `ExecutionWindowKind`, `BackgroundExecutionScheduling`, `ReviewReadyNotifying`, `NotificationPermission`, `CompletedPass`; `WorkflowState.notifiedPassID` |
| SweepUseCases | `AppLifecycleCoordinator` (activation, background entry, user-requested continuation, window runs, expiration, scheduling, readiness notification, foreground discovery refill after each completed pass); `VectorizationExecutor.lastCompletedPass` |
| SweepSystem (iOS) | `BackgroundTaskScheduler` (launch-handler registration, continued and processing requests, grace windows), `SystemTaskWindow`, `GraceWindow`, `UserNotificationReviewNotifier` |
| SweepPersistence | Stores `notifiedPassID` (schema v1 extended in place; not yet shipped) |
| SweepTestSupport | `FakeExecutionWindow`, `FakeBackgroundScheduler`, `FakeReviewNotifier` |

### Behavior

- **Foreground (`appDidBecomeActive`)**: clears a manual pause, resumes vectorization, ends grace windows and refills discovery. Every vectorization pass completed in the foreground triggers a discovery refill, so newly eligible vectors (including the pass that opens the gate) reach review.
- **Background entry**: discovery is suspended at its checkpoint. A running automatic pass gets a grace window unless a continuation is already active. A processing window is scheduled unless the person paused.
- **Windows**:
  - continued → `backgroundContinuation`; scheduled → `backgroundScheduled`; grace keeps the running pass alive
  - every path finishes each window exactly once
  - progress is forwarded to the Live Activity
  - a paused app finishes scheduled windows immediately
- **Expiration**:
  - continued window → manual pause (the agreed meaning of Live Activity Cancel)
  - scheduled or grace window → interrupt and reschedule, but only when no other active window still keeps the pass running
- **Readiness notification**: once per completed background pass that processed photos and left review available. It is claimed in memory before any suspension and persisted before posting, so it is sent at most once. Denied permission never affects vectorization.
- **Discovery never runs in the background.**

## Exit-criteria coverage (`SweepBackgroundTests`, 13 tests)

| Scenario | Tests |
| --- | --- |
| Expiration | scheduled-window expiry interrupts without pausing, reschedules, and the next window resumes from the checkpoint; grace expiry interrupts when nothing else keeps the pass alive; one window expiring while another is active does not stop the pass |
| Handoff | foreground pass continues in a grace window, the app returns, the grace window ends, the pass completes and discovery finds the group |
| Manual pause | Live Activity Cancel (continued expiration) becomes a manual pause that blocks scheduled work until the next opening; a paused app neither schedules nor runs scheduled work |
| Windows | scheduled window runs and finishes once; overlapping windows share one pass and each finishes once; rejected continuation still runs in the foreground; progress reaches the continued window |
| Notifications | one notification per pass; none for a later empty pass; none when permission is denied, without failing vectorization; none twice when overlapping windows finish together |
| Foreground-only discovery | no groups while backgrounded even after the gate opens; groups appear on return to the foreground |

## Found during testing

- **Duplicate notification:** two overlapping windows both passed the persisted "already notified?" check before either recorded it. An in-memory claim is now taken before any `await`.
- **Hidden announcement:** a queued follow-up pass with no work became the "last completed pass" and hid the real one. Only passes that processed photos are now recorded.
- **Missing refill:** discovery never refilled after a foreground pass opened the gate. The coordinator now observes completions.
- **Two test-ordering races** (a window not yet registered; a refill not yet requested) were made deterministic with continuation-based waits instead of timing.

## Confirmed decisions (2026-11-14)

Device observation after step 9; Live Activity Cancel = manual pause; continuation only for explicit user actions; CPU-only background Vision with no external-power requirement. *(Superseded 2026-11-17 by a device finding: background Vision uses the Neural Engine, falling back to the CPU, and never the GPU; see step-9.md.)*

## Further confirmed decisions

The owner confirmed these five choices on 2026-11-16.

1. **Any continued-task expiration counts as manual pause.** The system does not distinguish a person's Cancel from a resource-driven termination, so a terminated continuation also pauses until Resume or the next opening (the cooler choice).
2. **Readiness notifications are at most once**: a crash between recording and posting loses that notification rather than risking a duplicate.
3. **Notifications only for passes that processed photos**, completed while the app was in the background, with review available.
4. **Continued requests use the `.fail` strategy**: if iOS can't start continued processing immediately, the work stays in the foreground instead of starting unexpectedly later.
5. **A processing window is requested on every background entry and after an unfinished window**, unless the person paused; an empty scheduled run finishes quickly.

## Status: complete (2026-11-18)

The items that stayed open here were closed with the step 9 wiring and device runs:

- **Launch handlers** are registered by the app. The scheduled identifier `com.qdrant.edge.QdrantPhotoSweep.scheduledVectorization` is registered at launch. Each continued request registers its own `…continuedVectorization.<UUID>` before submitting; iOS rejects registering the `.*` pattern itself. See step-9.md.
- **Notification permission** is an onboarding step.
- **Device observation:** the owner checked background execution on an iPhone, covering the continued task with its Live Activity, Cancel as pause, the grace window, scheduled processing and the readiness notification. It works.
  - Device runs replaced the CPU-only Vision decision: background Vision uses the Neural Engine, falling back to the CPU, and never the GPU (see step-9.md).
  - The remaining issues found on the device are deferred by the owner until after step 10.

## Validation results

Environment: Xcode 27.2 (27B52), Apple Swift 6.4.2.

| Check | Result |
| --- | --- |
| `swift build --build-tests` (macOS) | No errors or warnings |
| `swift test` (macOS) | 232/232 pass, 0 CoreData errors |
| `SweepBackgroundTests` repeated 60× after the race fixes | 0 failed runs |
| `xcodebuild test -scheme PhotoSweep`, iPhone 17 iOS 26.5 simulator, twice | All suites pass; Vision skipped; 0 CoreData errors |
| iOS simulator build of `SweepSystem` adapters | Compiles without warnings |
| Xcode BuildProject (app + tests) | Succeeds |
| `python3 Scripts/check-module-boundaries.py` | PASS — 15 boundaries, 15 test targets |
