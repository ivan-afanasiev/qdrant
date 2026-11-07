# Qdrant PhotoSweep — Architecture & Photo Processing Logic

This document describes the current Swift implementation. Behavior and limitations below reflect the code, including places where persistence, cancellation, or UI refreshes are best-effort.

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

Pipeline failures become the coordinator's interrupted phase rather than a pipeline error screen. Review and grid operations have their own error handling. Foreground activation attempts to resume an interrupted coordinator; this is not a continuous retry loop.

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
│   ├── ContinuousScanCoordinator.swift# Orchestrates unified scan pipeline (Action/reduce)
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

`DependencyProviding` supplies `vectorStore`, `embeddingService`, `photoLibrary`, `scanStore`, and `settings`. The service contracts are `VectorStoring`, `EmbeddingProviding`, `PhotoLibraryProviding`, and `ScanSessionStoring`.

`AppDependencies` holds the live implementations:

| Dependency | Implementation | Responsibility |
| --- | --- | --- |
| Vector store | `QdrantVectorStore` actor | Owns a lazily opened Edge shard |
| Embeddings | `VisionEmbeddingService` actor | Generates Vision feature prints |
| Photos | `PhotoLibraryService` | Authorization, asset queries, image loading, deletion |
| Persistence | `SwiftDataScanStore` model actor | Sessions, indexed-photo metadata, edges, groups |
| Settings | `AppSettings` observable class | UserDefaults preferences and rescan signal |

Foreground services are constructed in `App.bootstrapDependencies(settings:)`. Background work constructs a separate set through `AppDependencies.forBackground(modelContainer:)`. These are separate construction paths, not one shared factory or a shared shard instance.

The SwiftUI environment contains an optional dependency container, populated only for the ready bootstrap state. `ScanInteractor.configure(deps:)` stores it once. Use cases receive their specific dependencies; foreground and background pipeline builders cast the vector store to `QdrantVectorStore` to configure dimensions.

`UseCase<Input, Output>` is a Sendable protocol with an asynchronous throwing `execute` method. Feature bundles group use cases, with factories on `DependencyProviding` for review, grid, and settings. Scan use cases are assembled by the interactor.

`TestDependencies` and configurable mock implementations are available under `#if DEBUG`.

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

This lookup does not first convert leftover scanning sessions to interrupted.

Settings rescan changes `AppSettings.rescanRequestId`. The interactor observes it, cancels work, replaces review/grid state, and starts a new session for the current range. Existing vectors, sessions, and groups remain stored.

## 5. Photo Processing Pipeline

The main implementation is `Features/Scan/ScanPipeline.swift`.

### Starting and reporting progress

`ContinuousScanCoordinator.startPipeline` saves the range, supplied resume ID, and dependencies; transitions to scanning; starts a Swift task immediately; then requests optional continued-processing support.

A separate task polls `ScanState.status` every 150 ms to update coordinator progress and any attached background task. The pipeline's `onGroupCountChanged` callback updates `groupsFoundCount` on the main actor.

### Processing steps

1. Fetch image assets whose creation dates fall within the inclusive range, newest first. The full asset metadata list is loaded into memory.
2. Create a session, or best-effort mark the supplied session scanning.
3. For each asset:
   - Check task cancellation.
   - Derive a stable vector UUID from its local identifier using XOR hashing.
   - Check Qdrant for that UUID. Existing points count as indexed and processed, but are not embedded or searched again.
   - Request a 224×224 thumbnail and generate a Vision feature print.
   - Read float elements from the observation; dimensions come from the returned element count, not a fixed model size.
   - On the first successful embedding in this run, configure the vector store dimensions.
   - Add the point and photo metadata to a batch. Payload JSON includes asset ID, creation date, and pixel dimensions.
   - Advance processed progress even if image loading or embedding failed.
4. Flush each batch of 20 successfully embedded points, then any remaining points.
5. Best-effort mark the session completed with the indexed count and transition scan state to completed.

The indexed count includes existing points and newly flushed points. It differs from the processed count, which also includes assets whose embedding failed.

### Batch flush

```text
upsert all batch vectors
 → record each photo's metadata in SwiftData
 → search each batch vector (limit 10, configured threshold)
 → discard self matches
 → persist each remaining similarity edge under the current session
 → if matches were found and a count callback exists:
      compute and persist groups
      report groups.count when nonempty
```

Foreground scans capture `settings.similarityThreshold` when the pipeline is created. Background scans omit that argument and use the default, 0.92. Changing the slider does not alter an already-created pipeline.

### Errors and cancellation

Image loading/embedding failures skip that asset. Metadata writes, edge writes, group computation, and session status updates use best-effort error handling. Asset fetch, existence checks, upserts, searches, and new-session creation can fail the pipeline.

Cancellation at the main asset-loop boundary marks the session interrupted and the scan state cancelled without flushing the pending in-memory batch. Cancellation inside the search loop returns from that flush, potentially after vectors were written but before all edges or groups were computed.

The foreground coordinator converts task cancellation or failed/cancelled scan state into interruption and best-effort interrupts all scanning sessions. It does not expose the pipeline error as a review failure.

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

Edges are inserted individually without pair deduplication. Reviewed/deleted group records remain, but their members and edges are not excluded when recomputing components.

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
- These automatic card refreshes do not include allReviewed.
- Loading state triggers another database fetch after advancing.
- Current cards are not replaced merely because a new batch is discovered.
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
| `PhotoPointEntity` | Unique assetLocalId, vectorUUID, embedding dimensions, indexedAt, image dimensions, creation date | Optional session |
| `SimilarityEdgeEntity` | Unique UUID, source/target vector UUIDs, score | Optional session |
| `DuplicateGroupEntity` | Unique UUID, status, detectedAt | Optional session; cascades to members |
| `GroupMemberEntity` | Asset/vector identifiers, score, image metadata, optional isKept | Optional group |

Session statuses are scanning, completed, interrupted, and failed. The pipeline primarily writes scanning/completed/interrupted; a scan-state failure does not itself persist the failed session status. Group statuses are pending, reviewed, and deleted.

Photo metadata insertion is skipped when the asset ID already exists; it is not reassigned to the latest session or refreshed. `scannedAt` is set when a session is created, not when it completes.

Pending-group list, next-group, and page queries filter across all sessions and sort by detectedAt ascending. Despite its name, `loadPendingGroup(id:)` queries only the ID and does not filter status.

Statistics count stored photo metadata, all group records, and deleted-group members flagged as not kept. They are historical database counts, not a reconciliation with the current photo library or vector shard.

## 9. Background Processing

### Continued-processing support

`ContinuousScanCoordinator.register()` registers the continued task handler at app initialization on iOS 26 and later.

The foreground pipeline starts independently of that handler. After starting work, `BackgroundTaskManager.requestContinuedTaskSupport` registers the active coordinator reference and submits a request with localized title/subtitle. The code does not explicitly set the request strategy.

When the handler arrives, it attaches the task to the active coordinator; it does not start the pipeline. If no active coordinator exists, it completes the task unsuccessfully. The manager sets progress to 100 total units, updates completed percentage, and connects expiration to cancellation of the existing work task. There are no dynamic title updates. Submission errors are ignored and the Swift task continues.

### Extended UIKit execution

On backgrounding during an active scan, the interactor invokes `ManageBackgroundExecutionUseCase`, which begins a UIKit background task and submits an urgent processing request. Expiration cancels work and ends the UIKit token. Foreground activation ends the token and calls `resumeIfInterrupted()`. Pipeline completion also ends background support. No fixed execution duration is guaranteed by this code.

`App` separately submits a deferred processing request on background entry.

### BGProcessingTask fallback

`BackgroundScanService`:

- Requests neither external power nor network connectivity.
- Uses now as earliestBeginDate for urgent scheduling, or 15 minutes later for deferred scheduling; these are request dates, not guaranteed start times.
- Skips work if the foreground coordinator's active flag is true.
- Creates separate background dependencies and asynchronously closes their vector store on exit.
- First resumes the latest interrupted session, if any.
- Then checks for new assets using the latest completed session's scannedAt through its saved range end. If the count is positive, it scans scannedAt through now.
- Uses the default similarity threshold rather than the user's configured threshold.
- Tracks the latest group-count callback, not an accumulated count across runs.
- Posts a local notification for a positive count when notification authorization already permits it. Otherwise it requests authorization and returns without posting that notification.
- Completes the system task based on a nonnegative result and reschedules itself.

Cancellation returns a negative result, with active sessions interrupted at the post-run cancellation checks. The fallback does not inspect failed scan state, so an uncancelled pipeline failure can still produce a successful system-task result.

### Resume and cancel semantics

The coordinator retains the date range, dependencies, and resume ID originally supplied to startPipeline. Foreground resume uses these values. A newly created session ID is not reported back by the pipeline, so a fresh foreground run resumed in the same coordinator can create another session.

Explicit cancel clears saved range/dependencies and immediately moves to idle. The cancelled task can later execute its interruption cleanup and move the phase to interrupted again. Cleared dependencies prevent that coordinator from automatically restarting, but interrupted sessions remain eligible for later launch/background resumption. Cancellation is not awaited before a rescan starts.

## 10. State Management

Feature state generally uses observable main-actor classes, private-set properties, explicit actions, and synchronous reducers. Feature namespaces bundle use cases.

```text
ScanView intent
 → ScanInteractor
 → use case / coordinator
 → asynchronous service operation
 → state action
 → observable state update
 → view rendering
```

Simpler feature views call use cases and dispatch reducer actions themselves. `SettingsView` composes section views and loads statistics. Its database section owns settings state. `SingleGroupReviewView` uses local SwiftUI state instead of `ReviewState`.

Reducers primarily update state; the coordinator reducer also updates the static foreground-active flag used by the background service. The interactor directly manages orchestration state such as view mode and completion-badge visibility. Thus the code does not enforce a universal rule that every mutation goes through a pure reducer.

Design-system files centralize typography, colors, spacing, icons, animation, components, and localized string access. Image presentation and gestures retain view-local state.

## 11. Current Trade-offs and Limitations

### Cross-store consistency and resume

Qdrant upserts precede metadata, edge, and group writes, with no shared transaction. A failure or cancellation after upsert can leave a vector without complete SwiftData data. Later runs skip existing vectors and do not retry that point's detection or metadata write.

Rescan means another pass over the chosen range, not rebuilding existing vectors or recomputing all similarity relationships at a new threshold. Startup only resumes explicitly interrupted sessions; leftover scanning sessions from abrupt termination are not normalized by the initial-state use case.

### Group identity and concurrent review

Recomputation replaces pending groups with new IDs. A card or grid detail can retain a snapshot whose persistent group was removed. Mark-reviewed/deleted methods return without error if the ID no longer exists. Reviewed/deleted components can also be recreated as pending because their edges remain eligible for grouping.

Grid pagination uses offsets into a changing pending set. Loaded pages and the current card are not a transactionally consistent view of the database.

### Memory and search work

Vectors are retained for the current batch rather than loaded wholesale for detection. However, the pipeline loads all selected asset metadata, and each group recomputation loads all session edges plus all photo-point metadata.

Each newly inserted point triggers one nearest-neighbor search. The app does not explicitly build an HNSW index or specify search parameters; actual search cost depends on Qdrant Edge's shard implementation. Repeated full group recomputation adds work beyond vector search.

### Vector dimensions, IDs, and clearing

Dimensions are restored from the sibling qdrant-edge-dims marker and detected from Vision output. A different stored dimension closes the shard and removes its directory before reuse; SwiftData is not reset with it. The app requests 224×224 thumbnails as its own preprocessing choice, not a documented fixed input requirement in this implementation.

Deterministic UUIDs use XOR folding with UUID version/variant bits. They provide stable mapping but no collision detection.

`ClearDatabaseUseCase` scrolls and deletes Qdrant points in pages of 100. It does not clear SwiftData sessions, metadata, edges, groups, or the dimensions marker.

### Shard ownership

`QdrantVectorStore` opens lazily and retries recognized transient lock errors up to three attempts, sleeping 500 ms and then 1 second. Foreground and background dependencies can own separate store actors for the same path. The foreground-active check reduces overlap, but it is not an exclusive ownership lock; inactive foreground dependencies can still retain an open shard.
