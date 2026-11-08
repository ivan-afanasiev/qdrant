# Qdrant PhotoSweep — Architecture & Photo Processing Logic

This document describes the current Swift implementation. Foreground and background scans share services and an exclusive execution controller. The limitations section distinguishes retryable checkpoints from remaining cross-store and review constraints.

## Table of Contents

1. [High-Level Overview](#1-high-level-overview)
2. [Project Structure](#2-project-structure)
3. [Dependency Injection](#3-dependency-injection)
4. [Navigation Flow](#4-navigation-flow)
5. [Photo Processing Pipeline](#5-photo-processing-pipeline)
6. [Inline Duplicate Detection](#6-inline-duplicate-detection)
7. [Review and Deletion](#7-review-and-deletion)
8. [Persistence](#8-persistence)
9. [Background Processing](#9-background-processing)
10. [State Management](#10-state-management)
11. [Current Trade-offs and Limitations](#11-current-trade-offs-and-limitations)

## 1. High-Level Overview

PhotoSweep finds visually similar images using Apple Vision feature prints and an on-device Qdrant Edge vector store. Similarity is based on cosine scores, not exact file equality.

```text
Photo library → thumbnails → Vision float vectors → Qdrant Edge
                                                       │
                                             search each new batch
                                                       ↓
                                          SwiftData similarity edges
                                                       │
                                                   Union-Find
                                                       ↓
                                          SwiftData duplicate groups
                                                       │
                                         use cases read groups/pages
                                                       ↓
                                           Cards / grid review UI

ScanPipeline → group count callback → ContinuousScanCoordinator
                                            │
                                 ScanInteractor observes changes
                                            │
                                conditionally reloads from SwiftData
```

Scanning and detection share one pipeline. After each batch, groups are persisted and a count is reported; full group arrays are not delivered to the coordinator or review UI. Review can proceed while scanning continues. The card UI holds one group snapshot, and the grid holds paginated summaries.

Pipeline failures become the coordinator's interrupted phase rather than a pipeline error screen. Review and grid operations have their own error handling. Foreground activation attempts to resume an interrupted coordinator. If activation races with cancellation cleanup, the cancelled run also checks for foreground activation on exit. Pipeline errors do not trigger an unbounded retry loop.

## 2. Project Structure


```
Sources/QdrantPhotoSweep/
├── App.swift                          # Entry point, bootstrap, scene phase
├── Core/
│   ├── AppError.swift                 # Unified error enum
│   ├── DatePreset.swift               # Date range presets (last week, month, etc.)
│   ├── Dependencies.swift             # DependencyProviding protocol, AppDependencies, EnvironmentKey
│   ├── TestDependencies.swift         # #if DEBUG: TestDependencies + mock implementations
│   ├── UseCase.swift                  # UseCase<Input, Output> protocol
│   ├── Persistence/
│   │   ├── ScanSessionEntity.swift    # @Model: scan session + ScanSessionStatus enum
│   │   ├── ScanSessionDTO.swift       # DTO for cross-actor transport
│   │   ├── ScanSessionStoring.swift   # Protocol for all persistence operations
│   │   ├── SwiftDataScanStore.swift   # @ModelActor: concrete SwiftData implementation
│   │   ├── SimilarityEdgeEntity.swift # @Model: similarity relationship between two vectors
│   │   ├── DuplicateGroupEntity.swift # @Model: duplicate group + DuplicateGroupStatus enum
│   │   ├── DuplicateGroupDTO.swift    # DTO for duplicate groups
│   │   ├── PhotoPointEntity.swift     # @Model: indexed photo with metadata
│   │   └── GroupMemberEntity.swift    # @Model: individual photo in a group
│   └── Protocols/
│       ├── VectorStoring.swift        # Protocol for vector DB operations
│       ├── EmbeddingProviding.swift   # Protocol for embedding generation
│       └── PhotoLibraryProviding.swift# Protocol for photo library access
├── Services/
│   ├── QdrantVectorStore.swift        # Actor: Qdrant Edge shard management
│   ├── VisionEmbeddingService.swift   # Actor: Apple Vision feature prints
│   ├── PhotoLibraryService.swift      # Photos framework wrapper
│   ├── ContinuousScanCoordinator.swift# Owns foreground run identity, cancellation, resume
│   ├── ScanExecutionController.swift  # Exclusive foreground/background scan execution
│   ├── BackgroundTaskManager.swift    # BG task registration, extended execution, BGContinuedProcessingTask
│   └── BackgroundScanService.swift    # BGProcessingTask fallback for background work
├── Features/
│   ├── Scan/
│   │   ├── ScanPipeline.swift         # Core logic: embed → upsert → search → persist edges → groups
│   │   ├── ScanState.swift            # ScanFeature namespace + ScanState (scan progress state machine)
│   │   ├── ScanInteractor.swift       # @Observable orchestrator: owns coordinator/review/grid state, handles intents
│   │   ├── ScanView.swift             # Pure rendering layer: reads interactor state, forwards intents
│   │   └── UseCases/
│   │       ├── LoadInitialStateUseCase.swift
│   │       ├── StartScanUseCase.swift
│   │       ├── CancelScanUseCase.swift
│   │       └── ManageBackgroundExecutionUseCase.swift
│   ├── DuplicateDetection/
│   │   ├── DuplicateGroup.swift       # PhotoReference + DuplicateGroup models
│   │   └── UnionFind.swift            # Generic union-find data structure
│   ├── Review/
│   │   ├── ReviewState.swift          # ReviewFeature namespace + ReviewState (pure reducer)
│   │   ├── GroupComparisonView.swift  # Grid of photos in a group
│   │   ├── PhotoCardView.swift        # Individual photo card with async loading
│   │   ├── FullscreenPhotoView.swift  # Fullscreen photo with zoom
│   │   ├── Components/
│   │   │   ├── ReviewCardStack.swift  # Shared swipe gesture + card rendering
│   │   │   └── ReviewSubviews.swift   # Shared status views (deleting, all done, failed, etc.)
│   │   └── UseCases/
│   │       ├── DeleteGroupUseCase.swift
│   │       ├── SkipGroupUseCase.swift
│   │       ├── LoadNextGroupUseCase.swift
│   │       ├── LoadGroupsPageUseCase.swift  # Paginated group summaries for grid
│   │       └── LoadGroupByIdUseCase.swift   # Single group fetch for grid → review
│   ├── GroupGrid/
│   │   ├── GroupGridState.swift       # GroupGridFeature namespace + GroupGridState (pure reducer)
│   │   ├── GroupGridView.swift        # InlineGroupGridView + GroupGridCell (inline in ScanView)
│   │   └── SingleGroupReviewView.swift# Self-contained single-group review (used from grid drill-down)
│   ├── Onboarding/
│   │   ├── OnboardingState.swift      # OnboardingFeature namespace + OnboardingState
│   │   ├── OnboardingView.swift
│   │   ├── OnboardingWelcomeStep.swift
│   │   ├── OnboardingPermissionStep.swift
│   │   ├── OnboardingScanPeriodStep.swift
│   │   └── UseCases/
│   │       └── RequestPhotoAccessUseCase.swift
│   └── Settings/
│       ├── SettingsView.swift         # Thin composition root (delegates to section views)
│       ├── SettingsState.swift        # SettingsFeature namespace + SettingsState (database section)
│       ├── Sections/
│       │   ├── SettingsStatsSectionView.swift       # Statistics grid (receives ScanStats)
│       │   ├── SettingsScanPeriodSectionView.swift   # Presets, custom range, rescan button
│       │   ├── SettingsDetectionSectionView.swift    # Similarity threshold slider
│       │   ├── SettingsDatabaseSectionView.swift     # Indexed count, clear DB (owns SettingsState)
│       │   └── SettingsAboutSectionView.swift        # Static engine/embeddings info
│       └── UseCases/
│           ├── ClearDatabaseUseCase.swift
│           ├── LoadDatabaseInfoUseCase.swift
│           └── LoadStatsUseCase.swift
├── Navigation/
│   ├── AppRoute.swift                 # Route enum (settings only)
│   └── RootNavigationView.swift       # NavigationStack with ScanView as root
├── DesignSystem/                      # Colors, typography, icons, layout tokens, L10n
└── Utilities/
    ├── UUIDHelpers.swift              # deterministicUUID(from:) for stable point IDs
    ├── AppLog.swift                   # Structured os.Logger instances per feature
    └── PHAssetExtensions.swift        # PHAsset → PhotoAsset conversion
```

[File truncated: 695 more lines available. Use 'offset' and 'limit' parameters to read more content.]

## 3. Dependency Injection

`DependencyProviding` supplies `vectorStore`, `embeddingService`, `photoLibrary`, `scanStore`, and `settings`. Services are accessed through `VectorStoring`, `EmbeddingProviding`, `PhotoLibraryProviding`, and `ScanSessionStoring`.

| Dependency | Implementation | Responsibility |
| --- | --- | --- |
| Vector store | `QdrantVectorStore` actor | Owns one lazily opened Edge shard |
| Embeddings | `VisionEmbeddingService` actor | Generates CPU-backed Vision feature prints |
| Photos | `PhotoLibraryService` | Authorization, asset queries, cancellable image loading, deletion |
| Persistence | `SwiftDataScanStore` model actor | Sessions, photo metadata, detection checkpoints, edges, groups |
| Settings | `AppSettings` observable class | UserDefaults preferences and rescan signal |

Both launch paths await `AppDependencies.shared(modelContainer:settings:)`. A cached initialization task prevents concurrent foreground/background startup from constructing separate shard owners. Before returning the shared services, initialization marks stale scanning sessions interrupted once per process. Initialization failures are propagated and can be retried.

The optional SwiftUI dependency environment is populated only when bootstrap is ready. The interactor stores it once; use cases receive their specific dependencies. Pipeline builders configure dimensions through the concrete Qdrant store.

`UseCase<Input, Output>` is a Sendable protocol with asynchronous throwing execution. Scan use cases that access settings or the coordinator are main-actor isolated. Feature bundles group review, grid, settings, and scan operations.

`TestDependencies` and configurable mocks are available in debug builds. The `QdrantPhotoSweepTests` target uses Swift Testing and in-memory SwiftData for lifecycle regression coverage.

## 4. Navigation Flow

```text
App
 ├─ loading → progress
 ├─ onboarding → welcome, photo permission, scan period
 ├─ failed → authorization error and Open Settings
 └─ ready → RootNavigationView / NavigationStack
              ├─ ScanView (permanent root)
              │    ├─ cards
              │    └─ inline grid → SingleGroupReviewView
              └─ SettingsView
                   ├─ statistics
                   ├─ scan period and rescan
                   ├─ similarity threshold
                   ├─ vector database information and clear
                   └─ about
```

`App.init()` creates the SwiftData container for all five model types and registers both background handlers. Container creation failure calls `fatalError`. Bootstrap accepts full or limited photo authorization, restores vector dimensions from disk, and injects live dependencies.

`ScanView.task` configures the interactor and sends `.launched`. `LoadInitialStateUseCase` chooses, in order:

1. Resume the latest session explicitly marked interrupted, using its saved date range and ID.
2. Show pending groups if any exist across sessions.
3. Start a new scan using the saved settings range.

Shared-service initialization recovers leftover scanning sessions before this lookup. Explicitly cancelled sessions are not selected for resume.

Settings rescan changes `AppSettings.rescanRequestId`. The interactor awaits cancellation and cleanup, replaces review/grid state, and starts a new session for the current range. This explicit user action requests continued-processing support on supported systems. Automatic launch scans use ordinary foreground execution with background fallback. Existing stored data remains.

## 5. Photo Processing Pipeline

The main implementation is `Features/Scan/ScanPipeline.swift`. It returns `ScanOutcome`, containing the session ID, completed/interrupted/failed status, and group count.

### Execution and progress

The foreground coordinator assigns each run a UUID. Progress, group-count callbacks, and completion affect state only while that UUID is current. The pipeline reports its session ID immediately after session creation/resumption, so subsequent foreground resumes use the same persisted session.

`ScanExecutionController` serializes whole scan lifetimes. Background requests decline if another run owns execution. Foreground requests cancel an existing worker and await its cleanup before acquiring execution. Cancellation of the caller propagates to its exact worker task.

A foreground observation task polls scan state every 150 ms for UI and system-task progress. Group callbacks report counts, not full group arrays.

### Processing steps

1. Fetch image assets in the inclusive date range, newest first.
2. Create a session or mark the supplied session scanning; report its ID.
3. For each asset, check cancellation and derive its deterministic UUID.
4. Skip only if both the Qdrant point exists and SwiftData records completed detection at this pipeline's similarity threshold.
5. Otherwise load a 224×224 thumbnail, generate a Vision float vector, configure dimensions on the first successful embedding, and collect metadata in a batch.
6. Flush every 20 successful embeddings and the final partial batch.
7. Check cancellation before completion and persist the session's indexed count/status.

The processed count includes attempted photos; indexed count includes skipped completed points and successfully flushed points. Embedding failures allow other photos to proceed, but the run ends failed/interrupted so unavailable photos can be retried.

### Durable detection checkpoint

Each batch performs:

```text
check cancellation
 → upsert vectors
 → save photo metadata with detectionThreshold cleared
 → search each vector at the captured threshold (limit 10)
 → persist idempotent similarity edges
 → recompute and persist groups
 → mark the batch's detectionThreshold
 → report group count
```

All persistence errors in this sequence propagate. A missing or mismatched checkpoint causes re-embedding and detection even if a vector already exists. This repairs interrupted upserts and legacy metadata without a checkpoint. Group computation runs even without a UI callback or newly discovered matches, so saved edges from an earlier partial attempt can be materialized.

Foreground and background builders both capture the user's configured threshold. Changing settings does not mutate a running pipeline.

### Errors and cancellation

Cancellation is checked between asynchronous processing steps and before marking completion. Search-loop cancellation throws instead of returning a successful partial flush. Failures and cancellation checkpoint only the affected session as interrupted; checkpoint-write failures are logged.

Photos image requests bridge task cancellation to `PHImageManager.cancelImageRequest` and resume their continuations exactly once, including cancellation before request-ID publication. Vision requests explicitly choose supported CPU devices for every compute stage, allowing background work without requiring GPU access.

Explicit user cancellation is handled by the coordinator after the pipeline unwinds and persists the session as cancelled. The worker saves this status before relinquishing its scan lease.

## 6. Inline Duplicate Detection

Qdrant is configured with one unnamed dense vector using cosine distance. Searches have no date/session filter and can match any retained point in the shard, including points from previous scans outside the currently selected range. The limit of 10 applies before self matches are removed.

`SwiftDataScanStore.computeGroupsFromEdges(sessionId:)`:

1. Fetches all edges for the session.
2. Unions source and target UUIDs into connected components.
3. Records each UUID's maximum incident edge score.
4. Fetches all stored photo metadata and builds a UUID lookup.
5. Converts components into groups, omitting missing metadata and components with fewer than two remaining photos.
6. Sorts photos by megapixels and selects the highest-resolution photo as the initial keep candidate.
7. Deletes the session's existing pending group records, then creates fresh group/member records.
8. Saves and returns in-memory groups sorted by size, largest first.

Persisted group IDs are newly generated during each recomputation. The temporary returned group IDs are not reused for persistence; callers currently consume only the count. Review queries order persisted groups by detection time, not group size.

New edge endpoints are canonicalized and existing pairs within the session are updated, making batch retries idempotent. Legacy duplicate rows are not bulk-migrated. Reviewed/deleted group records remain, but their members and edges are not excluded when recomputing components.

Union-Find is transitive: A–B and B–C can produce one group even if A and C do not meet the threshold. The score on a member is its maximum incident edge score, not a guarantee of similarity to every member.

## 7. Review and Deletion

### Card review

`ReviewState` owns one `currentGroup`, its keep selections, pending count, and in-memory review statistics. `LoadNextGroupUseCase` reads the next pending group and pending count from SwiftData. The best candidate is selected initially, and users can toggle selections.

Actual states are:

```text
idle → loading → reviewing → deletingGroup → loading
                    │
                    └─ skip → loading

loading with no group → noMoreGroups / allReviewed
operation failure → failed(error)
```

`ScanInteractor` observes coordinator count changes, review loading, coordinator phase/activity, view mode, and rescan requests using re-armed `withObservationTracking` callbacks.

- A changed positive group count fetches a card only when review is idle or noMoreGroups; the same handler reloads the grid if visible.
- Completion shows a three-second badge, conditionally fetches a card, and reloads a visible grid.
- These automatic card refreshes also include allReviewed, allowing newly discovered groups to become visible.
- Loading state triggers another database fetch after advancing.
- Current cards are not replaced merely because a new batch is discovered.
- Foreground activation reloads idle, exhausted, or fully reviewed cards and the visible grid, so background results become visible.
- Coordinator activity controls the application idle timer; teardown re-enables it.

A count notification is not a complete database change stream: a changed group composition with the same count does not trigger the count-based refresh.

### Skip and delete

Skipping marks the group reviewed with all member UUIDs kept. In card mode, the interactor advances review state before the asynchronous persistence call completes and ignores its errors.

Deletion is sequential:

1. Compute unselected asset IDs.
2. If none are unselected, mark the group reviewed and return without deleting.
3. Delete assets through Photos.
4. Delete corresponding deterministic UUIDs from Qdrant.
5. Mark the SwiftData group deleted and record kept/deleted member flags.
6. Update review statistics and advance.

These operations are not one transaction. Failure after Photos deletion can leave later stores unchanged. Deletion does not remove indexed-photo metadata or similarity edges.

### Grid review

`InlineGroupGridView` displays a two-column grid of summaries in pages of 20. Its view performs initial/next-page use cases and reduces the shared `GroupGridState`; the interactor also has grid reload/loading paths. The state object belongs to the interactor, so loaded summaries survive mode changes unless explicitly reset or reloaded.

Navigation uses the parent stack. A detail loader fetches a full group by ID and presents `SingleGroupReviewView`, which owns local keep selections. Skip or successful delete notifies the parent to remove the summary, then dismisses. A delete error restores the detail controls without presenting an error message; skip errors are ignored.

Grid cells load a thumbnail followed by a higher-quality image through Photos helpers. Image views perform image-loading work directly, so the use-case boundary applies to feature operations rather than every framework call.

## 8. Persistence

All scan persistence is exposed through `ScanSessionStoring`. `SwiftDataScanStore` is a model actor with its own model context. DTOs carry Sendable values across isolation boundaries; actor isolation should not be described as a guarantee of a dedicated background thread.

| Entity | Stored data | Relationships |
| --- | --- | --- |
| `ScanSessionEntity` | Unique UUID, date range, creation-time scannedAt, status, total/indexed counts | Cascades to photo points, groups, edges |
| `PhotoPointEntity` | Unique assetLocalId, vectorUUID, embedding dimensions, optional detectionThreshold, indexedAt, image dimensions, creation date | Optional session |
| `SimilarityEdgeEntity` | Unique UUID, source/target vector UUIDs, score | Optional session |
| `DuplicateGroupEntity` | Unique UUID, status, detectedAt | Optional session; cascades to members |
| `GroupMemberEntity` | Asset/vector identifiers, score, image metadata, optional isKept | Optional group |

Session statuses are scanning, completed, interrupted, cancelled, and failed. The pipeline writes scanning/completed/interrupted; failures remain resumable as interrupted, while explicit cancellation uses cancelled. Group statuses are pending, reviewed, and deleted.

Existing photo metadata is refreshed during reprocessing and its detection checkpoint is cleared before searching; its original session relationship is retained. `scannedAt` is set when a session is created, not when it completes.

Pending-group list, next-group, and page queries filter across all sessions and sort by detectedAt ascending. Despite its name, `loadPendingGroup(id:)` queries only the ID and does not filter status.

Statistics count stored photo metadata, all group records, and deleted-group members flagged as not kept. They are historical database counts, not a reconciliation with the current photo library or vector shard.

## 9. Background Processing

### Continued processing for user-initiated scans

On iOS 26 and later, `ContinuousScanCoordinator.register()` registers the wildcard handler at app initialization. Its identifier prefix matches the product bundle ID: `com.qdrant.edge.QdrantPhotoSweep.continuousScan.*`.

Explicit Settings rescans opt into continued processing. Each request has a unique run UUID suffix and uses the fail-if-not-immediately-admitted strategy. A request-to-run map ensures late delivery cannot attach to another scan.

When admitted, the launch handler attaches the system task and starts that run's pipeline. If submission fails, an ordinary foreground task starts instead and the error is logged. Automatic launch scans do not submit user-initiated system tasks.

The manager reports percentage progress, completes the system task after cleanup, and cancels any outstanding request when the run finishes. System expiration/cancellation follows the explicit-cancel path and does not automatically restart the job. Because the callback does not distinguish user cancellation from other expiration, both conservatively persist cancelled status.

### UIKit execution allowance

Backgrounding an active foreground scan starts a UIKit background task only if no continued-processing task is attached. Attaching continued support ends the shorter UIKit allowance, so its expiration cannot cancel an admitted continued task. UIKit expiration cancels the specific run; its session remains interrupted and resumable.

Tokens have generation IDs to reject stale expiration callbacks. Foreground activation and normal completion end the allowance. No fixed execution duration is assumed.

The interactor schedules an urgent processing fallback while scanning. The app-level background handler submits a deferred request only when no foreground scan is active, avoiding replacement of an urgent request with a later one.

### BGProcessingTask fallback

`BackgroundScanService`:

1. Checks cancellation, foreground activity, photo authorization, and completed onboarding without prompting for permission in the background.
2. Awaits the shared service container and tries to acquire exclusive execution without replacing another scan.
3. Resumes the latest interrupted session.
4. If that succeeds, counts newly created photos from the latest completed session's scannedAt through now; the subsequent incremental scan uses that same interval.
5. Uses the configured similarity threshold and checks the explicit pipeline outcome.
6. Reports failure for failed/interrupted work, and success for completed or deliberately skipped work.
7. Posts a notification for completed discoveries only when authorization already permits it, then reschedules.

The request requires neither external power nor network connectivity. Urgent earliestBeginDate is now; deferred is 15 minutes later. Scheduling remains system-controlled. Image requests may still need network access for iCloud photos; unavailable images produce a retryable interrupted scan.

The fallback does not create or close a second vector store. The shared actor retains sole shard ownership across foreground and background use.

### Resume and cancel

Foreground interruption retains the actual session ID, range, and dependencies. On activation, resume enters the same start path and requests continued support again if the original user-initiated run opted in. A cancellation/activation race is handled after worker cleanup.

Explicit cancellation invalidates the run ID, cancels and awaits its task, persists cancelled status, finishes system support, and returns to idle. Replacement work cannot start through that coordinator while it is stopping. Old callbacks cannot overwrite a replacement run.

## 10. State Management

Feature state generally uses observable main-actor classes, private-set properties, explicit actions, and synchronous reducers.

```text
ScanView intent → ScanInteractor → use case / coordinator
 → exclusive execution controller → pipeline / services
 → run-checked state update → observable UI rendering
```

The coordinator owns its phase directly and isolates task handles, saved dependencies, and run identifiers with `@ObservationIgnored`. `ScanExecutionController` owns the execution task, not UI state.

Simpler feature views call use cases and dispatch reducer actions themselves. `SettingsView` composes sections and loads statistics. Its database section owns settings state. `SingleGroupReviewView` uses local SwiftUI state rather than `ReviewState`.

Design-system files centralize typography, colors, spacing, icons, animation, components, and localized string access. Image presentation and gestures retain view-local state.

## 11. Current Trade-offs and Limitations

### Cross-store consistency

Qdrant and SwiftData do not share a transaction. The detection checkpoint makes interrupted scan writes retryable, but photo deletion still spans Photos, Qdrant, and SwiftData sequentially. Partial deletion failures are not rolled back.

The optional detectionThreshold field defaults to nil for existing metadata. The first subsequent scan reprocesses those points to establish checkpoints. Threshold changes also reprocess points, but historical groups and edges from previous sessions are retained.

Dimension changes recreate the vector shard without clearing SwiftData. Deterministic IDs still use XOR folding without collision detection. Clearing the database still deletes only Qdrant points, not SwiftData history or the dimensions marker.

### Group identity and concurrent review

Group recomputation still replaces pending groups with new IDs. An open card/detail can therefore hold a stale ID; mark-reviewed/deleted methods return without error if that record no longer exists. Reviewed/deleted components are not excluded from later recomputation.

Grid pagination uses offsets into a changing pending set. Loaded pages and current cards are snapshots, not a transactionally consistent database view.

### Resource use

The pipeline loads the selected asset metadata list and retains vectors for the current batch. Each group computation loads all session edges and all photo-point metadata. Search cost depends on Qdrant Edge's implementation; the app does not explicitly build an HNSW index.

Vision is pinned to CPU for reliable execution without background GPU privileges, which can trade throughput for predictable execution across app states. Individual synchronous Vision/Qdrant calls finish before the next cancellation check.

### Validation

The shared Xcode scheme includes the Swift Testing target under `Tests/ScanLifecycleTests.swift`. Coverage includes interrupted upserts, final-batch cancellation, detection without UI callbacks, threshold propagation, idempotent edges, stale-session recovery, incremental ranges, exclusive scan handoff, continuation cancellation races, coordinator resume, explicit cancellation/replacement, and CPU Vision execution.

System scheduling, continued-task Live Activity delivery, device locking, and physical-device expiration behavior still require device validation. Simulator tests establish application logic, not system scheduling guarantees.
