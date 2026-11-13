# Step 5 — Durable persistence (2026-11-13)

Step 5 of REWRITE_PLAN.md §10: redesigned SwiftData schema, journals, stable IDs, revisions, cursors and clean-start transition. Exit: crash/reopen/reset tests pass without legacy migration or library-photo modification. Nothing is wired into the running app yet; the legacy engine remains active.

## Delivered

| Target | Contents |
| --- | --- |
| SweepDomain | Value records (`AssetRecord`, `VectorPointID`, `VectorWriteIntent`, `WorkflowState`, `DiscoveryProgress`, `JournalEntry`, `LibraryStatistics`, `PersistenceError`) and narrow contracts: `AssetRepository`, `VectorWriteJournaling`, `VectorizationPassRepository`, `WorkflowStateRepository`, `DiscoveryProgressRepository`, `ReviewRepository`, `OperationJournal`, `StatisticsRepository`, `LocalDataResetting`. `ComponentExpansion.Snapshot` and `VectorizationPass(outcomes:)` for restoring state |
| SweepPersistence | `PhotoSweepSchemaV1` (`VersionedSchema`, 11 models, enum-like values stored as strings) with `PhotoSweepMigrationPlan`; `LocalDataLocation` (`Application Support/PhotoSweep/v1/{metadata.store, vectors/}`); `MetadataStoreFactory`; `SwiftDataMetadataStore` model actor implementing every contract; `LegacyDataTransition` |
| SweepUseCases | `VectorWriteTransaction`, `ResetLocalData`, `RecoverPendingOperations` |

### Guarantees

- **Single-save transitions.** Committing vectors (asset state + pass outcome + journal close), deferring assets (asset + pass), publishing a group (group + membership + queue position + discovery progress) and completing a group (state + frozen membership + reviewed-group statistic) are each one SwiftData save.
- **Cross-store journal (LIFE-02).** Vector writes record intent before touching Qdrant and close only together with the metadata commit. Recovery rolls back any open write: it deletes the intended points and returns the assets to pending. A point without committed metadata is never treated as success.
- **Stable identity (VEC-05, REV-07).** Each asset gets a random point ID on first registration, unique in the store; a repeating ID generator cannot cause collisions. Groups keep durable IDs, membership changes bump the revision even when the count is unchanged, and lineage (`derivedFrom`) is stored.
- **Cursors and frontiers (REV-03).** Discovery progress stores the seed cursor, exhaustion flag and the in-progress component. Frontier members are stored as rows and appended on checkpoint, not rewritten.
- **Durable review order (REV-05, REV-06).** Fresh and deferred orders survive relaunch, and re-skipping moves a group to the end without duplicates. Completed membership suppresses overlapping components within the discovery revision. `retireGroups(before:)` ends queue, deferral and suppression for older revisions.
- **Statistics (LIFE-08).** Reviewed groups and deleted photos are events keyed by kind and operation ID, so they are recorded at most once. Unknown byte sizes are counted separately and never invented. Photo counts come from asset outcomes.
- **Reset (LIFE-07).** Restartable: journal → clear vector store → clear metadata and store the post-reset workflow state → close. Open deletion journals are kept so started deletions still reconcile. `ResetLocalData` has no photo library dependency.
- **Clean start (LIFE-07, Q2).** `LegacyDataTransition` removes `Documents/qdrant-edge`, `Documents/qdrant-edge-dims`, `Application Support/default.store` (with `-shm`/`-wal`) and the six legacy preference keys, then writes the namespace marker last. It is idempotent and restartable, and leaves unrelated files and the new namespace alone. **It is intentionally not called by the app**: running it while the legacy engine is active would delete that engine's live data. Wire it at cutover (step 10).

## Interpretations to confirm

1. **Reset keeps the date scope, similarity threshold and statistics events.** It clears pause, closes the initial-pass gate and advances the discovery revision and index generation. Statistics describe confirmed changes to the library that a local reset does not undo.
2. **Editing a photo makes it pending immediately** when it is next registered; its old vector stops being eligible before re-vectorization finishes.
3. **Interrupted vector writes are rolled back, never rolled forward**, because the vectors themselves are not journaled.
4. **Suppression is any overlap**: a newly found component that shares at least one photo with a group completed in the current revision does not resurface.
5. **The clean start also clears `hasCompletedOnboarding`**, so existing users see onboarding once after the update.
6. **Finished and superseded passes are deleted**; no pass history is kept.

## Not in this step

Deletion workflow and its recovery (open deletion entries are only preserved and reported) and lineage computation belong to step 7. Composition/SafeDI wiring, bootstrap ordering and live use of the store belong to step 6. Performance with 100,000+ assets, such as a single-save work set of that size, is unmeasured (step 10).

## Validation results

Environment: Xcode 27.2 (27B52), Apple Swift 6.4.2.

| Check | Result |
| --- | --- |
| `swift build --build-tests` (macOS) | No errors or warnings |
| `swift test` (macOS) | 155/155 pass, including 42 SwiftData tests on real temporary store files |
| `SweepPersistenceTests` repeated 15× | 0 failed runs |
| `xcodebuild test -scheme PhotoSweep`, iPhone 17 iOS 26.5 simulator | All suites pass; Vision skipped on simulator; 0 CoreData errors |
| Xcode BuildProject (app + tests) | Succeeds |
| `python3 Scripts/check-module-boundaries.py` | PASS — 15 boundaries, 12 test targets |

Crash scenarios covered by reopening the same store file: after vector-write intent; after vector upsert but before metadata commit; after commit; failed commit; repeated recovery; reset interrupted after its intent; reset interrupted after clearing vectors; reset failing in the vector store and resuming; legacy transition interrupted midway.

A test-fixture issue showed up during validation: the temporary-directory helper deleted its directory from `deinit`, and Swift may release it before stores opened from it finish, causing SQLite I/O errors. The fixture now removes leftovers once per test process instead.
