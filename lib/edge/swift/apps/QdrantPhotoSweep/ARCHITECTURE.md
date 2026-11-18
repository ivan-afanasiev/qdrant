# PhotoSweep architecture

PhotoSweep finds similar photos on an iPhone (iOS 26+) and lets the person review them as cards. Everything runs on device: Apple Vision computes a feature print per photo, Qdrant Edge stores and searches the vectors, and SwiftData keeps the metadata.

The app target only selects an engine. The rewrite in `Packages/PhotoSweep` is the default; the legacy app in `Sources/QdrantPhotoSweep` stays behind the Debug launch argument `-PhotoSweepLegacyEngine YES` until the step 10 cutover. Its old description is in git history.

## Modules

`Scripts/check-module-boundaries.py` enforces the dependency direction: features → use cases → domain, with adapters implementing domain contracts.

| Layer | Targets | Responsibility |
| --- | --- | --- |
| Domain | `SweepDomain` | Value types, IDs, contracts and pure policies (gate, retry, pause, components, buffer, presets). No frameworks. |
| Use cases | `SweepUseCases` | `VectorizationExecutor`, `DiscoveryExecutor`, `AppLifecycleCoordinator`, review, deletion, preference and reset use cases. |
| Adapters | `SweepPhotos`, `SweepEmbeddings`, `SweepQdrant`, `SweepPersistence`, `SweepSystem` | Photos, Vision, per-generation Qdrant shards, the SwiftData schema with journals, and BackgroundTasks/notifications. |
| State and UI | `SweepFeatureState`, `SweepDesignSystem`, `Sweep{Onboarding,Library,Review,Settings}Feature` | A minimal `Store`/`Reducer`/`Effect`, tokens, Liquid Glass, strings, and one reducer and view per feature. |
| Composition | `SweepComposition` | The SafeDI root, `RewriteBootstrap`, `AppRuntime`, root and shell views, feature factories. |

Views render state and send actions. All work goes through use cases bound in `FeatureFactories`.

## Runtime

`RewriteBootstrap` opens the store once, recovers open journals and builds one `AppRuntime`. Foreground and background entry points share that runtime, so there is exactly one executor of each kind.

**Vectorization** runs as passes: request access → resolve the date preset → fetch and register photos (chunks of 500) → analyze each photo without a reusable vector, from a 224 px thumbnail → write the vectors to Qdrant and commit the metadata in one transaction.
- **Recovery:** each vector write is journaled, so a crash rolls it back.
- **Failures:** a photo that fails is deferred; 10 failures in a row stop the pass.
- **Initial gate:** review opens only after the first pass for the current scope completes. Later passes add photos without closing it.
- **Controls:** Pause, Resume and Retry come from the person; Rescan and a date change restart the pass.

**Discovery** runs only in the foreground and keeps 2–3 ready groups.
- **Expansion:** it takes the newest unexamined photo, expands its connected component with paged, exact, date-filtered cosine search (A–B–C can group without A–C matching) and publishes the group in one transaction.
- **Refill:** it refills after every committed vectorization batch, so long passes feed review continuously.

**Review** shows one group per card.
- **Selection:** tap photos to keep them.
- **Swipes:** left is Skip; right is the commit action (Delete All, Delete N, or Keep All).
- **Deletion:** goes through the Photos confirmation and a journal. Photos you can no longer access are never treated as deleted.
- **Images:** cards show a thumbnail, then a sharp screen-sized image; only the full-screen preview decodes the original.

**Background.** Every window ends exactly once, and discovery never runs in the background.
- **Continued processing:** a person's action (Start, Resume, Retry, Rescan) runs on as a continued task with a Live Activity, where Cancel counts as Pause.
- **Grace and scheduled windows:** leaving the app during automatic work gives a short grace window; iOS-scheduled processing continues the pass later.
- **Vision:** in the background it uses the Neural Engine or the CPU, never the GPU.
- **Notification:** one "ready to review" notification follows a background pass that did work.

**Revisions.** A threshold change, rescan, date change or reset starts a new discovery revision. Open cards are retired, and completed groups stay suppressed within a revision. A model change starts a new index generation (a new Qdrant shard).

## Data

| Store | Contents |
| --- | --- |
| SwiftData (`SchemaV1`) | Assets with content revision, vector state and point ID; passes; groups and membership; review order; discovery progress; journals; statistics events; workflow state (scope, threshold, gate, revisions, pause, preferences). |
| Qdrant Edge | One shard per index generation: point = vector + `{asset, created}` payload. |
| Photos | The source of truth for photos; only deletions the person confirmed are applied. |

## Testing

Swift Testing only, with deterministic fakes from `SweepTestSupport`. The tests cover:
- reducers and policies
- SwiftData recovery and reopening
- a real Qdrant shard
- end-to-end vectorization, discovery, deletion and background scenarios

`Scripts/test-photos` generates large photo libraries with known duplicate groups. Commands and lessons learned are in `docs/implementation/README.md`.
