# Qdrant PhotoSweep — Architecture & Photo Processing Logic

## Table of Contents

1. [High-Level Overview](#1-high-level-overview)
2. [Project Structure](#2-project-structure)
3. [Dependency Injection](#3-dependency-injection)
4. [Navigation Flow](#4-navigation-flow)
5. [Photo Processing Pipeline — Step by Step](#5-photo-processing-pipeline--step-by-step)
6. [Inline Duplicate Detection Algorithm](#6-inline-duplicate-detection-algorithm)
7. [Review & Deletion Flow](#7-review--deletion-flow)
8. [Persistence Layer](#8-persistence-layer)
9. [Background Processing](#9-background-processing)
10. [State Management Pattern](#10-state-management-pattern)
11. [Known Architectural Decisions & Trade-offs](#11-known-architectural-decisions--trade-offs)

---

## 1. High-Level Overview

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Photo      │────>│  Embedding       │────>│  Qdrant Edge    │──┐
│  Library    │     │  Service          │     │  Vector Store   │  │ search after
│  (Photos)   │     │  (Vision FP)     │     │  (on-device)    │  │ each batch
└─────────────┘     └──────────────────┘     └─────────────────┘  │
                                                                   v
                                                           ┌──────────────┐
                                                           │ Similarity   │
                                                           │ Edges        │
                                                           │ (SwiftData)  │
                                                           └──────┬───────┘
                                                                  │ Union-Find
                                                                  v
                                                           ┌──────────────┐
                                                           │ Duplicate    │
                                                           │ Groups       │
                                                           │ (SwiftData)  │
                                                           └──────┬───────┘
                                                                  │ streamed
                                                                  v
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Unified Scan + Review UI                                 │
│        Progress bar at top · Group cards appear as discovered               │
│        Tinder-style swipe · Delete unselected immediately                   │
└─────────────────────────────────────────────────────────────────────────────┘
```

The app takes photos from the user's library, generates vector embeddings using Apple's Vision framework, stores them in an on-device Qdrant Edge vector database, and **detects duplicates inline** by searching for similar vectors immediately after each batch upsert. Discovered similarity edges are persisted in SwiftData and grouped via Union-Find. Groups stream to the UI as they are found, allowing the user to review duplicates while scanning continues.

The **UI is fully decoupled from the pipeline**: it reads groups from SwiftData and never shows pipeline errors. If the scan is interrupted (background suspension, error, system cancel), it auto-resumes transparently when the app returns to the foreground.

---

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

---

## 3. Dependency Injection

### Protocol-Based DI

All services are defined behind protocols (`VectorStoring`, `EmbeddingProviding`, `PhotoLibraryProviding`, `ScanSessionStoring`). A `DependencyProviding` protocol bundles them into a single contract:

```swift
protocol DependencyProviding {
    var vectorStore: any VectorStoring { get }
    var embeddingService: any EmbeddingProviding { get }
    var photoLibrary: any PhotoLibraryProviding { get }
    var scanStore: any ScanSessionStoring { get }
    var settings: AppSettings { get }
}
```

This protocol is the **single source of truth** for all dependencies. Every layer in the app — views, interactors, use cases, background services — consumes `any DependencyProviding` rather than concrete types. Adding a new dependency to the protocol produces compile errors in every conforming type, ensuring nothing is missed.

### Live Implementation

`AppDependencies` is the live conformance, created once in `App.swift → bootstrapDependencies()`:

```swift
final class AppDependencies: DependencyProviding {
    let vectorStore: any VectorStoring       // QdrantVectorStore (actor)
    let embeddingService: any EmbeddingProviding  // VisionEmbeddingService (actor)
    let photoLibrary: any PhotoLibraryProviding   // PhotoLibraryService
    let scanStore: any ScanSessionStoring    // SwiftDataScanStore (@ModelActor)
    let settings: AppSettings                // @Observable, persisted to UserDefaults
}
```

For background tasks, `AppDependencies.forBackground(modelContainer:)` is a static factory that creates a fresh set of services from a `ModelContainer` — eliminating the duplicated construction logic that previously lived in `BackgroundScanService`.

### SwiftUI Environment Injection

The container is injected into the SwiftUI view hierarchy via a custom `EnvironmentKey`:

```
App.swift → .environment(\.dependencies, appDependencies) → child views read @Environment(\.dependencies)
```

**Important**: The environment value is `(any DependencyProviding)?` — only non-nil when `bootstrapStatus == .ready`. Views guard on `dependencies != nil` before doing anything. Non-view code (interactors, coordinators) receives the container via `configure(deps:)` or init injection.

### Test Implementation

`TestDependencies` (`#if DEBUG`) provides a test conformance with default mock implementations for all protocols:

```swift
final class TestDependencies: DependencyProviding {
    init(
        vectorStore: any VectorStoring = MockVectorStore(),
        embeddingService: any EmbeddingProviding = MockEmbeddingService(),
        photoLibrary: any PhotoLibraryProviding = MockPhotoLibrary(),
        scanStore: any ScanSessionStoring = MockScanStore(),
        settings: AppSettings = AppSettings()
    )
}
```

Each mock (`MockVectorStore`, `MockEmbeddingService`, `MockPhotoLibrary`, `MockScanStore`) has configurable properties for test setup and no-op default behavior.

### UseCase Pattern

All business logic lives in `UseCase` structs, never in Views:

```swift
protocol UseCase<Input, Output>: Sendable {
    associatedtype Input: Sendable
    associatedtype Output: Sendable
    func execute(_ input: Input) async throws -> Output
}
```

Each feature defines a `UseCases` bundle, constructed via a factory extension on `DependencyProviding`:

```swift
extension DependencyProviding {
    var reviewUseCases: ReviewFeature.UseCases { ... }
    var groupGridUseCases: GroupGridFeature.UseCases { ... }
    var settingsUseCases: SettingsFeature.UseCases { ... }
}
```

### Feature Namespaces

Each feature is organized as a TCA-inspired namespace enum containing State, Action, reduce, and UseCases:

```swift
enum ReviewFeature {
    struct UseCases: Sendable { ... }
}
// ReviewState, ReviewState.Action, ReviewState.Status defined alongside
```

Data flow for every user action:
```
Simple features: View → UseCase.execute() → async side effect → Action → State.reduce() → pure state update → View re-renders
Complex features: View → interactor.send(intent) → Interactor calls UseCase → Action → State.reduce() → View re-renders (via @Observable)
```

No View ever calls a service directly. No `State.reduce()` ever performs side effects.

---

## 4. Navigation Flow

```
App.swift
 ├── .loading          → ProgressView
 ├── .onboarding       → OnboardingView (welcome → permissions → scan period)
 ├── .failed           → Error view with "Open Settings"
 └── .ready            → RootNavigationView
                             │
                             ├── ScanView (root — auto-detects action on launch)
                             │    ├── Auto-detect: resume interrupted scan / review pending / start new scan
                             │    ├── Cards view (default): review groups one at a time
                             │    ├── Grid view (toggle): InlineGroupGridView with pagination
                             │    │    └── Tap group → NavigationLink to SingleGroupReviewView
                             │    ├── Progress bar / interrupted banner / completed badge
                             │    ├── Cancel button (toolbar, during scan)
                             │    ├── Grid/Cards toggle (toolbar, when groups exist)
                             │    └── Settings gear icon (toolbar) → .settings
                             │
                             └── SettingsView (thin composition root)
                                  ├── SettingsStatsSectionView (photos indexed, last scan, duplicates, deleted)
                                  ├── SettingsScanPeriodSectionView (presets + custom range + "Rescan" button)
                                  ├── SettingsDetectionSectionView (similarity threshold slider)
                                  ├── SettingsDatabaseSectionView (indexed count, clear — owns its own state)
                                  └── SettingsAboutSectionView (engine, embeddings)
```

Navigation uses `NavigationStack(path:)` with `AppRoute` enum (currently only `.settings`).

**Key design**: There is no Home screen. `ScanView` is the permanent root that auto-detects what to do on launch via `LoadInitialStateUseCase`:
1. If there's an interrupted session in the DB → auto-resume scan
2. If there are pending (unreviewed) groups → show review UI
3. Otherwise → auto-start a new scan with the saved date range from Settings

The group grid is displayed **inline** as an alternative view mode (toggled via toolbar), not as a sheet. Both cards and grid views share the same `GroupGridState` which persists across toggles.

**Rescan from Settings**: `AppSettings` exposes a `rescanRequestId: UUID` signal. When the user taps "Rescan with New Period" in `SettingsScanPeriodSectionView`, it bumps the ID and dismisses Settings. `ScanInteractor` internally observes this property via `withObservationTracking`, cancels any active scan, resets review/grid state, and starts a fresh scan with the updated date range.

---

## 5. Photo Processing Pipeline — Step by Step

### Single Unified Phase: Scan with Inline Detection

**Entry point**: App launches → `ScanView` `.task` → `ScanInteractor.send(.launched)` → `autoDetectAndLaunch()` calls `LoadInitialStateUseCase` → determines action → `ContinuousScanCoordinator.startPipeline()` (for new/resumed scans) or `loadNextGroupFromDB()` (for pending review).

**Coordinator role**: The `ContinuousScanCoordinator` is a thin orchestration layer. It:
1. Sets `phase = .scanning(processed: 0, total: 0, groupsFound: 0)`
2. Optionally requests iOS 26+ `BGContinuedProcessingTask` for Live Activity (non-blocking)
3. Immediately calls `runPipeline()` which creates a background `Task`
4. Maintains a `discoveredGroups` array updated via callback from `ScanPipeline`

**Inside `ScanPipeline.run()`** — the actual work:

```
Step 1: Fetch photos
    photoLibrary.fetchAssets(in: dateRange) → [PhotoAsset]
    Each PhotoAsset has: localIdentifier, creationDate, pixelWidth, pixelHeight

Step 2: Create or resume a scan session in SwiftData
    If resumeSessionId != nil → update existing session status to .scanning
    Else → scanStore.createSession() → new UUID

Step 3: For each photo in the fetched list:
    a) Generate a deterministic UUID from the photo's localIdentifier
       deterministicUUID(from: asset.localIdentifier) → stable point ID

    b) Check if already indexed:
       vectorStore.exists(id: pointId)
       If exists → skip, increment counter

    c) Load a 224×224 thumbnail:
       photoLibrary.loadThumbnail(for: asset, size: CGSize(224, 224)) → CGImage

    d) Generate embedding:
       embeddingService.embed(image: cgImage) → [Float]
       Uses VNGenerateImageFeaturePrintRequest (Apple Vision framework)
       Returns a float vector (typically 768 dimensions on modern devices)

    e) On first successful embedding, propagate dimensions:
       configureDimensions(vector.count) → QdrantVectorStore.updateDimensions()

    f) Batch the vector point (id, vector, payload JSON)

    g) Every 20 photos, flush the batch with inline detection:
       1. vectorStore.upsert(points: batch)
       2. scanStore.recordIndexedPhoto(...) — records in SwiftData with full metadata
       3. For each point in the batch:
            vectorStore.search(vector, limit: 10, threshold: 0.92)
            For each neighbor found:
              scanStore.recordSimilarityEdge(source, target, score, sessionId)
       4. If new edges were found:
            scanStore.computeGroupsFromEdges(sessionId) → [DuplicateGroup]
            onGroupsUpdated(groups) — callback to coordinator

Step 4: Flush remaining batch (same inline detection)

Step 5: Update session status to .completed
```

**Cancellation**: Checked every iteration via `Task.isCancelled`. On cancel, session is marked `.interrupted`.

**Progress reporting**: The coordinator polls `ScanState.status` every 150ms from a separate observation `Task` and updates `phase = .scanning(processed:, total:, groupsFound:)`.

**Streaming groups**: The `onGroupsUpdated` callback fires after each batch that discovers new edges. The coordinator updates `discoveredGroups` on the main actor, which the `ScanView` observes and feeds into its embedded `ReviewState`.

---

## 6. Inline Duplicate Detection Algorithm

Detection happens **inside `ScanPipeline.flushBatchWithDetection()`**, interleaved with scanning:

```
For each newly-upserted point in the batch:
    vectorStore.search(vector, limit: 10, threshold: 0.92)
    → Returns up to 10 nearest neighbors above the similarity threshold

    For each result where result.id != point.id:
        scanStore.recordSimilarityEdge(source, target, score, sessionId)
        → Persists a SimilarityEdgeEntity in SwiftData
```

### Group Computation from Edges

After edges are discovered, `SwiftDataScanStore.computeGroupsFromEdges(sessionId:)` runs:

```
Step 1: Fetch all SimilarityEdgeEntity for the session from SwiftData

Step 2: Build Union-Find from edges
    For each edge: union(source, target)

Step 3: Extract connected components
    unionFind.components() → [[String]]
    Each component = a group of transitively similar photos

Step 4: Enrich with metadata from PhotoPointEntity
    For each vector UUID → look up assetLocalId, pixelWidth, pixelHeight, creationDate

Step 5: Replace existing pending DuplicateGroupEntity records
    Delete old pending groups for this session
    Create new DuplicateGroupEntity + GroupMemberEntity for each group

Step 6: Return sorted groups (largest first)
```

**Key advantage**: Union-Find runs on edge data from SwiftData, **not** on in-memory vectors. For 17K photos with ~5% duplicate rate, expect ~1K edges — trivial to load and process.

**Complexity**: Each new point triggers one search (O(K) where K is current index size). Over N total inserts, the amortized cost is O(N²/2) for brute-force — same total as the old approach, but spread over time. The user sees results immediately instead of waiting for two sequential phases.

---

## 7. Review & Deletion Flow

### Database-Driven Review (one group at a time)

The review UI is completely decoupled from the scanning pipeline. Groups are never held in memory as an array — instead, `ReviewState` fetches **one group at a time** from SwiftData via `LoadNextGroupUseCase`:

```
1. useCases.loadNextGroup.execute(())
   → scanStore.loadNextPendingGroup()  (fetch first pending DuplicateGroupEntity)
   → scanStore.pendingGroupCount()     (count remaining for progress display)
   → View dispatches: reviewState.reduce(.didLoadGroup(group, pendingCount: count))

2. User reviews the group (select photos to keep)

3. On skip:
   → useCases.skipGroup.execute(group)
   → reviewState.reduce(.didSkipGroup) → status = .loading → triggers next fetch

4. On delete:
   → useCases.deleteGroup.execute(group, keptIds)
   → Handles photoLibrary.deleteAssets, vectorStore.delete, scanStore.markGroupDeleted
   → reviewState.reduce(.didFinishGroupDeletion) → status = .loading → triggers next fetch

5. When no pending groups remain:
   → .allReviewed if any were reviewed, .noMoreGroups otherwise
```

This ensures the UI **never shifts** when new groups are discovered during scanning — the pipeline writes to the database, and the review UI reads one-at-a-time on user action.

### Inline Review (during scanning — ScanView + ScanInteractor)

The `ScanView` is the **permanent root screen** and a **pure rendering layer**. All orchestration logic lives in `ScanInteractor` — an `@Observable @MainActor` class that owns the coordinator, review state, and grid state.

The `ScanInteractor` acts as a **database-driven controller** fully decoupled from the scan pipeline's lifecycle. The pipeline writes to SwiftData; the interactor reads from it. The user never sees error or failure screens from the pipeline.

- **On launch**: `ScanInteractor` receives `.launched` intent → calls `LoadInitialStateUseCase` to auto-detect the right action (resume/review/new scan)
- **Scanning**: Progress bar at top shows scan progress and groups-found count. Cancel button in toolbar.
- **Interrupted**: A subtle "Resuming scan…" banner replaces the progress bar. The pipeline auto-resumes.
- **Completed**: Brief "Scan complete" badge (interactor manages 3-second timer), then only the review UI remains.
- In **all three states**, the review section is visible and functional:
  - When `coordinator.groupsFoundCount` increases and the review is idle, the interactor triggers a DB fetch (via internal observation loop)
  - **Group cards** are stable — only replaced when the user explicitly skips/deletes
  - If all groups reviewed before scan ends: shows scanning placeholder
  - If scan completes with no groups: shows "No duplicates found"
- **View mode toggle**: Toolbar button sends `.switchViewMode` intent to interactor

### Persistence Resume Review

Review of pending groups happens automatically: when the app launches and finds pending groups in the DB, `ScanView` enters review mode directly without starting a scan.

### Group Grid (inline view mode)

`ScanView` offers a toolbar toggle to switch between cards and grid view modes:

```
InlineGroupGridView (2-column LazyVGrid, paginated from DB)
  └── Tap group → NavigationLink to SingleGroupReviewView
       ├── Skip/delete → pop back to grid, group removed from list
       └── Grid scroll position and loaded pages are preserved
```

The grid uses the parent's `NavigationStack` for drill-down (no separate NavigationStack). `GroupGridState` is owned by `ScanInteractor` so it persists across view mode toggles.

```
GroupGridFeature.UseCases:
  - LoadGroupsPageUseCase  → paginated loading via scanStore.loadPendingGroupsPage(offset:, limit:)
  - LoadGroupByIdUseCase   → fetch full DuplicateGroup for a selected grid cell

GroupGridState (pure reducer):
  - Manages groups: [GroupSummary], totalCount, hasMore, status
  - Actions: didStartLoading, didLoadPage, didFail, didRemoveGroup(UUID)
```

`SingleGroupReviewView` is a self-contained review for one group (reuses `ReviewCardStack` + `ReviewConfirmButton`). Skip/delete calls `ReviewFeature.UseCases`, notifies the grid, and pops via `dismiss()`.

### Review UI State Machine (`ReviewState`)

```
.empty                  → No groups found
.reviewing              → Currently showing group[currentIndex]
  - User taps photos    → toggles keep/unkeep (bestCandidate pre-selected)
  - User swipes/skips   → mark as reviewed, advance to next
  - User taps "Delete"  → transitions to .deletingGroup
.deletingGroup          → Deletion in progress
  → On success          → advance to next group
.allReviewed            → All groups processed, show stats
.failed(error)          → Error state
```

### Deletion (immediate per group)

```
1. Identify unselected photos → idsToDelete = group.photos - keptIds
2. Delete from photo library: photoLibrary.deleteAssets(assetLocalIdentifiers)
   This prompts the iOS system deletion dialog
3. Delete from vector store: vectorStore.delete(ids: deterministicUUIDs)
4. Persist in SwiftData: markGroupDeleted(groupId, keptIds, deletedIds)
5. Advance to next group
```

Photos are deleted **immediately after each group confirmation**, not batched.

---

## 8. Persistence Layer

### SwiftData Entities

```
ScanSessionEntity
├── id: UUID (unique)
├── rangeStart, rangeEnd: Date
├── scannedAt: Date
├── status: String (scanning | completed | interrupted | failed)
├── totalPhotos, indexedPhotos: Int
├── photoPoints: [PhotoPointEntity]  (cascade delete)
├── duplicateGroups: [DuplicateGroupEntity]  (cascade delete)
└── similarityEdges: [SimilarityEdgeEntity]  (cascade delete)

PhotoPointEntity
├── assetLocalId: String (unique)
├── vectorUUID: String
├── embeddingDimensions: Int
├── indexedAt: Date
├── pixelWidth, pixelHeight: Int
├── creationDate: Date?
└── session: ScanSessionEntity?

SimilarityEdgeEntity
├── id: UUID (unique)
├── sourceVectorUUID: String
├── targetVectorUUID: String
├── score: Float
└── session: ScanSessionEntity?

DuplicateGroupEntity
├── id: UUID (unique)
├── status: String (pending | reviewed | deleted)
├── detectedAt: Date
├── session: ScanSessionEntity?
└── members: [GroupMemberEntity]  (cascade delete)

GroupMemberEntity
├── assetLocalId: String
├── vectorUUID: String
├── score: Float
├── pixelWidth, pixelHeight: Int
├── creationDate: Date?
├── isKept: Bool?
└── group: DuplicateGroupEntity?
```

### Access Pattern

All persistence goes through the `ScanSessionStoring` protocol. The concrete `SwiftDataScanStore` is a `@ModelActor`, which gives it its own `ModelContext` on a background thread — safe for concurrent access from any actor.

DTOs (`ScanSessionDTO`, `DuplicateGroupDTO`, `GroupSummary`) are plain `Sendable` structs used to transport data across actor boundaries.

Key query methods:
- `loadNextPendingGroup()` — fetches the first pending group (used by sequential review)
- `loadPendingGroupsPage(offset:limit:)` — paginated loading (used by GroupGridView)
- `loadPendingGroup(id:)` — single group by ID (used when navigating from grid to review)
- `pendingGroupCount()` — total count of pending groups

---

## 9. Background Processing

### 9.1 Three Layers of Background Execution

When a scan is active and the user locks the screen or switches apps, three mechanisms work together:

```
Layer 1: UIApplication.beginBackgroundTask (all iOS versions)
         → ~30 seconds of extended execution after backgrounding
         → Enough to finish the current batch and persist progress

Layer 2: BGProcessingTask with earliestBeginDate=now (all iOS versions)
         → Scheduled urgently when backgrounding during active scan
         → System grants it when conditions allow (plugged in, idle, etc.)
         → Resumes the interrupted scan from SwiftData checkpoint

Layer 3: BGContinuedProcessingTask (iOS 26+ only)
         → Work runs INSIDE the launch handler (Apple's required pattern)
         → Register → submit → system calls launch handler → pipeline runs there
         → Shows Live Activity with progress, user can cancel from there
         → Foreground work transparently continues in background
```

### 9.2 ContinuousScanCoordinator

- Created as a property of `ScanInteractor` (which is `@State` on `ScanView`)
- Uses `Action/reduce` pattern for all state transitions (idle → scanning → completed/interrupted)
- Delegates background task management to `BackgroundTaskManager`
- On iOS 26+:
  1. `startPipeline()` → `startWithContinuedTask()`
  2. Registers the task handler with `BGTaskScheduler.shared.register(...)`
  3. Submits `BGContinuedProcessingTaskRequest` with `.queue` strategy
  4. System invokes the launch handler immediately → pipeline runs inside it
  5. Progress is reported via `task.progress` and `task.updateTitle()`
  6. Work continues even when the app is backgrounded (Live Activity shown)
  7. If submission fails, falls back to plain `Task` (same as iOS < 26)
- On iOS < 26:
  - Runs pipeline in a plain Swift `Task`
  - When app goes to background:
    - `ScanView` forwards `scenePhase` → `ScanInteractor` → calls `coordinator.beginExtendedBackgroundExecution()`
    - `ScanInteractor` schedules `BackgroundScanService.schedule(urgent: true)` as fallback
    - Extended execution buys ~30s to finish the current batch and save state
    - If the scan doesn't finish in time, it's marked `.interrupted` and auto-resumes when the app returns to foreground
- Phases: `idle` → `scanning(processed:total:groupsFound:)` → `completed(groupsFound:)` / `interrupted(processed:total:)`
- **Interrupted auto-resume**: When the pipeline is interrupted (background suspension, error, or system cancellation), the coordinator saves the `dateRange`, `resumeSessionId`, and `deps`. On return to foreground, `resumeIfInterrupted()` automatically restarts the pipeline — no user intervention needed.
- **Explicit cancel** (user taps Cancel): Transitions to `.idle`, clears saved state — no auto-resume.

### 9.3 BackgroundScanService (BGProcessingTask)

- Registered in `App.init()`, scheduled when app enters background
- **Skips work** when `ContinuousScanCoordinator.isForegroundScanActive` is true — avoids double-opening the Qdrant WAL
- **Urgent mode** (`earliestBeginDate = now`): scheduled from `ScanView` when backgrounding during active scan
- **Deferred mode** (`earliestBeginDate = 15 min`): default fallback from `App.swift` scene phase handler
- Uses `AppDependencies.forBackground(modelContainer:)` to create services — same factory as the foreground path, eliminating duplicated construction logic
- Priority order:
  1. Resume interrupted scan session (with inline detection)
  2. Incremental scan for new photos since last completed session (with inline detection)
- Posts local notification when duplicates found
- Re-schedules itself after completion

### 9.4 Scene Phase Handling

```
ScanView (forwards scenePhase to ScanInteractor):
  .background → interactor handles: coordinator.beginExtendedBackgroundExecution()
              + BackgroundScanService.schedule(urgent: true)
  .active    → interactor handles: coordinator.endExtendedBackgroundExecution()
              + coordinator.resumeIfInterrupted() (auto-restarts pipeline if it was interrupted)

App.swift (always):
  .background → BackgroundScanService.schedule()  (deferred, 15 min)
```

The `beginExtendedBackgroundExecution` / `endExtendedBackgroundExecution` pair ensures the UIKit background task token has a proper lifecycle: created on backgrounding, ended on foregrounding (or when the pipeline finishes, whichever comes first). This prevents the "Background Task created over 30 seconds ago" warning.

---

## 10. State Management Pattern

Every feature uses **unidirectional data flow** with three key components:

### Feature Namespace

```swift
enum ReviewFeature {
    struct UseCases: Sendable {
        let deleteGroup: DeleteGroupUseCase
        let skipGroup: SkipGroupUseCase
        let loadNextGroup: LoadNextGroupUseCase
    }
}
```

### Pure State Reducer

```swift
@Observable @MainActor
final class ReviewState {
    enum Status: Equatable { ... }
    enum Action { ... }
    private(set) var status: Status = .idle

    func reduce(_ action: Action) {
        // Pure state transitions only — no async, no service calls
    }
}
```

### View as Orchestrator

Views own `State` and `UseCases`, call use cases for side effects, and dispatch resulting actions through `reduce(_:)`:

```swift
private func deleteCurrentGroup() {
    reviewState.reduce(.didConfirmGroup)
    Task {
        let result = try await useCases.deleteGroup.execute(input)
        reviewState.reduce(.didFinishGroupDeletion(deleted: result.deleted, kept: result.kept))
    }
}
```

### Interactor Pattern (ScanView)

For complex features with multiple state objects and cross-state reactions, an **Interactor** (`@Observable @MainActor class`) sits between the View and the UseCases/State. This keeps the View as a pure rendering layer:

```
View → interactor.send(.intent) → Interactor calls UseCases → Interactor dispatches Actions → States.reduce() → View re-renders (via @Observable)
```

**ScanInteractor** owns `ContinuousScanCoordinator`, `ReviewState`, `GroupGridState`, and all derived properties. It exposes a single `send(_ intent: Intent)` method. The View never calls use cases or dispatches actions directly.

Internal observation loops (via `withObservationTracking`) replace all `.onChange` handlers:
- `coordinator.groupsFoundCount` changes → triggers DB fetch for next group
- `reviewState.isLoading` becomes true → triggers DB fetch
- `coordinator.phase` completes → triggers `showCompletedBadge` timer and DB fetch
- `coordinator.isActive` changes → toggles idle timer
- `viewMode` changes to `.grid` → reloads grid if idle
- `settings.rescanRequestId` changes → cancels scan, resets state, starts new scan

The only `.onChange` remaining on `ScanView` is for `scenePhase` (a SwiftUI `@Environment` value that cannot be observed outside a View).

### Rules

- State is read-only from outside (`private(set)`)
- All mutations go through `reduce(_:)` with explicit actions
- `reduce(_:)` is **pure** — no async, no service calls, no side effects
- Views never call services directly — all business logic lives in `UseCase` structs
- For complex features, an **Interactor** sits between View and UseCases/State (see above)
- Shared UI components (like `ReviewCardStack`, `ReviewConfirmButton`) accept data + callbacks, never hold state
- `ContinuousScanCoordinator` also follows the `Action/reduce` pattern for its phase transitions
- **Large views split into sections**: `SettingsView` is a thin composition root; each `Sections/` view handles one concern (stats, scan period, detection, database, about). Database section owns its own `SettingsState`; others receive data as props.

### Use Cases

Each business operation is a small `UseCase` struct conforming to the shared protocol:

```swift
struct DeleteGroupUseCase: UseCase {
    let photoLibrary: any PhotoLibraryProviding
    let vectorStore: any VectorStoring
    let scanStore: any ScanSessionStoring

    func execute(_ input: DeleteGroupInput) async throws -> DeleteGroupOutput { ... }
}
```

**State classes**: `ScanState`, `ReviewState`, `GroupGridState`, `OnboardingState`, `SettingsState`, `ContinuousScanCoordinator`.

**Interactors**: `ScanInteractor` (orchestrates `ContinuousScanCoordinator`, `ReviewState`, `GroupGridState`).

**Feature namespaces**: `ScanFeature`, `ReviewFeature`, `GroupGridFeature`, `OnboardingFeature`, `SettingsFeature`.

---

## 11. Known Architectural Decisions & Trade-offs

### Inline Search-on-Upsert (streaming detection)
- Scanning and duplicate detection are merged into a **single phase**
- After each batch of 20 photos is upserted, the pipeline immediately searches for neighbors
- Discovered edges are persisted as `SimilarityEdgeEntity` in SwiftData
- Groups are recomputed from edges (Union-Find) and streamed to the UI
- This replaces the old two-phase approach (scan all, then detect all)

### No in-memory vector loading
- The old `scrollAllPoints()` approach that loaded ALL vectors into RAM is eliminated
- Edge data and group computation now live in SwiftData
- For 17K photos with ~5% duplicates: ~1K edges, trivially small to process

### O(N²) total cost, but spread over time
- Qdrant Edge uses plain (appendable) segments with no HNSW index
- Each search is O(K) where K = current index size
- Total: O(N²/2) amortized — same theoretical cost as before
- But: earlier photos are searched against smaller indexes, and the user sees groups immediately
- **Future improvement**: Build HNSW index in Qdrant Edge (Rust changes) for O(N log N) total

### Vector Store Dimensions
- Dimensions are detected dynamically from the first embedding (usually 768)
- Persisted to a marker file (`qdrant-edge-dims`) so the store can be restored without a new scan
- If dimensions change (unlikely), old shard data is deleted and recreated

### Deterministic UUIDs
- `deterministicUUID(from: asset.localIdentifier)` generates a stable UUID via XOR hashing
- Same photo always maps to same vector ID → enables skip-if-exists during resume

### Transitive grouping via Union-Find
- If A is similar to B and B is similar to C, all three end up in the same group
- This can create large groups with photos that are not directly similar to each other
- Groups are sorted by size (largest first) and within a group by megapixels (highest first)

### Embedding model
- Uses `VNGenerateImageFeaturePrintRequest` from Apple's Vision framework
- This produces a "feature print" — a compact representation of the image's visual content
- Resolution: always loads 224×224 thumbnails for embedding (model's expected input size)
- The same 224×224 thumbnail is used regardless of the original photo's resolution

### Unified scan + review screen (DB-driven, pipeline-decoupled, root screen)
- `ScanView` is the **permanent root screen** — there is no Home screen
- On launch, `LoadInitialStateUseCase` queries the DB to auto-detect the right action:
  1. Interrupted session → auto-resume scan
  2. Pending groups → show review UI
  3. Nothing pending → auto-start new scan with saved date range
- The UI is a **read-only projection of the database** — it never displays pipeline errors or failure screens
- Pipeline interruptions (background suspension, errors, cancellation) are transparent to the user:
  - Coordinator transitions to `.interrupted`, auto-resumes on return to foreground
  - A small "Resuming scan…" banner shows while the pipeline restarts
- Only an **explicit user cancel** (toolbar button) stops the scan
- Users can review and delete duplicates while scanning is still in progress
- Statistics (previously on Home) are available in Settings

### Group Grid as inline view mode
- `ScanView` offers a toolbar toggle between cards (one-at-a-time review) and grid (browse all groups)
- The grid view is **inline** in the root screen, not a separate sheet
- `GroupGridState` is owned by `ScanInteractor` so it persists across view mode toggles
- Grid cells use `NavigationLink` for drill-down to `SingleGroupReviewView`
- After reviewing a group, the user pops back to the same scroll position with the reviewed group removed
- Grid loads groups in pages of 20 from SwiftData (`loadPendingGroupsPage`)
- Two-phase image loading in grid cells (fast thumbnail → higher-quality image) with correct aspect ratios

### WAL lock resilience
- Qdrant Edge uses a WAL (Write-Ahead Log) file that only one process can lock at a time
- `QdrantVectorStore.ensureShard()` retries up to 3 times with 500ms/1s backoff on `WouldBlock` errors
- `BackgroundScanService` checks `ContinuousScanCoordinator.isForegroundScanActive` and skips work if a foreground scan already holds the lock
- This prevents the "Resource temporarily unavailable" crash when background and foreground tasks overlap

### Settings decomposition
- `SettingsView` is a thin composition root — no business logic, just assembles section views in a `Form`
- Each `Sections/` view is responsible for one concern:
  - `SettingsStatsSectionView` — receives `ScanStats` as a prop, purely presentational
  - `SettingsScanPeriodSectionView` — binds to `AppSettings`, calls `onRescan` callback
  - `SettingsDetectionSectionView` — binds to `AppSettings` for the threshold slider
  - `SettingsDatabaseSectionView` — owns its own `SettingsState`, calls use cases directly
  - `SettingsAboutSectionView` — static, no state
- This keeps each section independently testable and prevents the type-checker issues that arise from large view bodies

### Rescan via signal (AppSettings.rescanRequestId)
- When the user taps "Rescan with New Period" in Settings, `AppSettings.requestRescan()` bumps a `UUID`
- `ScanInteractor` internally observes this property via `withObservationTracking`
- On change: cancel current scan → reset review/grid state → start fresh scan with `settings.currentDateRange`
- No callback threading through navigation — the shared `@Observable AppSettings` acts as the signal bus

### ScanInteractor (replaces ScanEventHandlers ViewModifier)
- `ScanView` previously had 8+ chained `.onChange` modifiers (later extracted into a `ScanEventHandlers: ViewModifier`)
- The Interactor pattern eliminates ALL `.onChange` handlers from the view (except `scenePhase`, which is SwiftUI-only)
- `ScanInteractor` uses `withObservationTracking` loops to internally observe: `coordinator.phase`, `coordinator.groupsFoundCount`, `coordinator.isActive`, `reviewState.isLoading`, `viewMode`, `settings.rescanRequestId`
- This keeps the view as a pure rendering layer: it reads state and forwards user intents via `interactor.send(_:)`
- The interactor owns all state objects (`ContinuousScanCoordinator`, `ReviewState`, `GroupGridState`) and all derived properties (`hasGroups`, `reviewGroupCounter`, `reviewProgressTotal`)
- Intent enum provides a type-safe contract for all user actions (`launched`, `scenePhaseChanged`, `cancelScan`, `skipGroup`, `deleteGroup`, `toggleKeep`, `switchViewMode`, etc.)
