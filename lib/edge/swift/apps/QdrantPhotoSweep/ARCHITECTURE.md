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

---

## 2. Project Structure

```
Sources/QdrantPhotoSweep/
├── App.swift                          # Entry point, bootstrap, scene phase
├── Core/
│   ├── AppError.swift                 # Unified error enum
│   ├── DatePreset.swift               # Date range presets (last week, month, etc.)
│   ├── Dependencies.swift             # DI container + AppSettings + EnvironmentKey
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
│   ├── ContinuousScanCoordinator.swift# Orchestrates unified scan pipeline, optional iOS 26 BG
│   └── BackgroundScanService.swift    # BGProcessingTask fallback for background work
├── Features/
│   ├── Scan/
│   │   ├── ScanPipeline.swift         # Core logic: embed → upsert → search → persist edges → groups
│   │   ├── ScanState.swift            # Scan progress state machine
│   │   └── ScanView.swift             # Unified scan + review UI
│   ├── DuplicateDetection/
│   │   ├── DuplicateGroup.swift       # PhotoReference + DuplicateGroup models
│   │   └── UnionFind.swift            # Generic union-find data structure
│   ├── Review/
│   │   ├── SwipeReviewView.swift      # Persistence-resume review (pending groups from DB)
│   │   ├── ReviewState.swift          # Review state machine
│   │   ├── GroupComparisonView.swift  # Grid of photos in a group
│   │   ├── PhotoCardView.swift        # Individual photo card with async loading
│   │   └── FullscreenPhotoView.swift  # Fullscreen photo with zoom
│   ├── Home/
│   │   ├── HomeView.swift             # Dashboard with banners + stats
│   │   ├── HomeState.swift            # Home data loading + state
│   │   └── StatCard.swift             # Stat display component
│   ├── Onboarding/
│   │   ├── OnboardingState.swift      # Onboarding step management
│   │   ├── OnboardingWelcomeStep.swift
│   │   ├── OnboardingPermissionStep.swift
│   │   └── OnboardingScanPeriodStep.swift
│   └── Settings/
│       ├── SettingsView.swift         # Settings UI
│       └── SettingsState.swift        # Settings state
├── Navigation/
│   ├── AppRoute.swift                 # Route enum (scan, review, settings)
│   └── RootNavigationView.swift       # NavigationStack + destination routing
├── DesignSystem/                      # Colors, typography, icons, layout tokens, L10n
└── Utilities/
    ├── UUIDHelpers.swift              # deterministicUUID(from:) for stable point IDs
    └── PHAssetExtensions.swift        # PHAsset → PhotoAsset conversion
```

---

## 3. Dependency Injection

All services are created once in `App.swift → bootstrapDependencies()` and bundled into a `Dependencies` struct:

```swift
struct Dependencies {
    let vectorStore: any VectorStoring       // QdrantVectorStore (actor)
    let embeddingService: any EmbeddingProviding  // VisionEmbeddingService (actor)
    let photoLibrary: any PhotoLibraryProviding   // PhotoLibraryService
    let scanStore: any ScanSessionStoring    // SwiftDataScanStore (@ModelActor)
    let settings: AppSettings                // @Observable, persisted to UserDefaults
}
```

This is injected into the SwiftUI environment via a custom `EnvironmentKey`:

```
App.swift → .environment(\.dependencies, deps) → every child view reads @Environment(\.dependencies)
```

**Important**: `Dependencies` is only non-nil when `bootstrapStatus == .ready`. Views guard on `dependencies != nil` before doing anything.

---

## 4. Navigation Flow

```
App.swift
 ├── .loading          → ProgressView
 ├── .onboarding       → OnboardingView (welcome → permissions → scan period)
 ├── .failed           → Error view with "Open Settings"
 └── .ready            → RootNavigationView
                             │
                             ├── HomeView (root)
                             │    ├── "Start Scanning" button    → .scan(dateRange)
                             │    ├── "Resume Scan" banner       → .scan(dateRange, sessionId)
                             │    ├── "Review Duplicates" banner → .review
                             │    └── Settings gear icon         → .settings
                             │
                             ├── ScanView (unified scan + review)
                             │    └── On finished → clears path (back to Home)
                             │
                             ├── SwipeReviewView (persistence resume only)
                             │    └── On finished → clears path (back to Home)
                             │
                             └── SettingsView
```

Navigation uses `NavigationStack(path:)` with `AppRoute` enum.

**Key change**: The `.scan` route now shows a **unified screen** that handles both scanning and reviewing. Groups appear as cards during the scan. The `.review` route is only used when resuming review of already-persisted pending groups (e.g., from a Home banner).

---

## 5. Photo Processing Pipeline — Step by Step

### Single Unified Phase: Scan with Inline Detection

**Entry point**: User taps "Start Scanning" on Home → navigates to `ScanView` → `.task` calls `startPipeline()` → `ContinuousScanCoordinator.startPipeline()`.

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

The review UI is completely decoupled from the scanning pipeline. Groups are never held in memory as an array — instead, `ReviewState` fetches **one group at a time** from SwiftData:

```
1. ReviewState.loadNextGroup(from: scanStore)
   → scanStore.loadNextPendingGroup()  (fetch first pending DuplicateGroupEntity)
   → scanStore.pendingGroupCount()     (count remaining for progress display)

2. User reviews the group (select photos to keep)

3. On skip/delete:
   → Mark group as reviewed/deleted in SwiftData
   → ReviewState transitions to .loading
   → .loading triggers another loadNextGroup() fetch

4. When no pending groups remain:
   → .allReviewed if any were reviewed, .noMoreGroups otherwise
```

This ensures the UI **never shifts** when new groups are discovered during scanning — the pipeline writes to the database, and the review UI reads one-at-a-time on user action.

### Inline Review (during scanning — ScanView)

The unified `ScanView` embeds a `ReviewState` and displays Tinder-style group cards:

- **Progress bar** at top shows scan progress and groups-found count
- When `coordinator.groupsFoundCount` increases and the review is idle, a DB fetch is triggered
- **Group cards** are stable — only replaced when the user explicitly skips/deletes
- **When scan finishes**: progress bar disappears, remaining groups can still be reviewed
- **If all groups reviewed before scan ends**: shows "waiting for more groups" placeholder

### Persistence Resume Review

`SwipeReviewView` uses the same DB-driven `ReviewState` — used when returning to review from a Home banner.

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

DTOs (`ScanSessionDTO`, `DuplicateGroupDTO`) are plain `Sendable` structs used to transport data across actor boundaries.

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

- Created as `@State` on `ScanView`
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
    - `ScanView` observes scene phase → calls `coordinator.beginExtendedBackgroundExecution()`
    - `ScanView` schedules `BackgroundScanService.schedule(urgent: true)` as fallback
    - Extended execution buys ~30s to finish the current batch and save state
    - If the scan doesn't finish in time, it's marked `.interrupted` and resumed later
- Phases: `idle` → `scanning(processed:total:groupsFound:)` → `completed(groups:)` / `failed` / `cancelled`

### 9.3 BackgroundScanService (BGProcessingTask)

- Registered in `App.init()`, scheduled when app enters background
- **Urgent mode** (`earliestBeginDate = now`): scheduled from `ScanView` when backgrounding during active scan
- **Deferred mode** (`earliestBeginDate = 15 min`): default fallback from `App.swift` scene phase handler
- Creates fresh service instances (no access to Environment)
- Priority order:
  1. Resume interrupted scan session (with inline detection)
  2. Incremental scan for new photos since last completed session (with inline detection)
- Posts local notification when duplicates found
- Re-schedules itself after completion

### 9.4 Scene Phase Handling

```
ScanView (when scan is active):
  .background → coordinator.beginExtendedBackgroundExecution() (iOS < 26 safety net)
              + BackgroundScanService.schedule(urgent: true)

App.swift (always):
  .background → BackgroundScanService.schedule()  (deferred, 15 min)
```

---

## 10. State Management Pattern

Every feature uses **unidirectional data flow** via `@Observable @MainActor` classes:

```swift
@Observable @MainActor
final class SomeState {
    enum Action { case didSomething, didFail(AppError) }
    private(set) var status: Status = .idle

    func reduce(_ action: Action) {
        switch action {
        case .didSomething: status = .done
        case .didFail(let e): status = .failed(e)
        }
    }
}
```

- State is read-only from outside (`private(set)`)
- All mutations go through `reduce(_:)` with explicit actions
- Views switch on state cases — no if/else for UI branches
- Long-running work happens in `async` methods that call `reduce()` with results

**State classes in the app**: `ScanState`, `ReviewState`, `HomeState`, `OnboardingState`, `SettingsState`.

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

### Unified scan + review screen
- `ScanView` combines scanning progress with Tinder-style group review
- Users can review and delete duplicates while scanning is still in progress
- `SwipeReviewView` is kept as a separate route only for persistence resume (opening from Home banner)
