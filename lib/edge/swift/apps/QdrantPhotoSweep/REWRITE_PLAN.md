# PhotoSweep rewrite plan

Status: shared agent rules/entry points implemented (step 1); baseline inventory, source snapshot, simulator UI evidence, 13 passing device tests and measurement protocol recorded (step 2). Step 3 delivered SPM boundaries, extracted adapters/resources and an inert SafeDI validation slice (stub graph accepted; see docs/implementation/step-3.md). Step 4 delivered domain policies, native store/reducer infrastructure, Library/Review reducers and test fakes without persistence or live pipelines; see docs/implementation/step-4.md. Step 5 delivered the SwiftData schema v1, journals, recovery/reset use cases and an unwired clean-start transition; see docs/implementation/step-5.md. Physical performance measurements and Claude/Cursor session-loading checks remain outstanding. The legacy engine remains active until cutover.
Based on ARCHITECTURE.md and inspection of the scan pipeline, Photos and Qdrant adapters, deletion/reset use cases, and lifecycle tests.

## 1. Confirmed requirements

- Modular architecture using Swift Package Manager.
- Establish a shared, token-efficient .agents ruleset and tool entry points before implementation; extract and trace all technical requirements from this plan.
- Unit tests for every business logic unit, using Swift Testing exclusively. Unit and integration test targets must not use XCTest.
- Use cases as the entry points for application/business operations.
- Unidirectional data flow.
- Integrate a DI framework; SafeDI is the proposed choice, validated in an early integration milestone.
- SwiftUI wherever practical.
- Preserve the Qdrant SDK integration, Photos loading behavior, thumbnail-based processing, full-resolution loading only for preview, and the card-based UI/design system; remove grid mode and complete Liquid Glass adoption.
- Target iPhone on iOS 26+, with native Swift stores/reducers, SwiftData metadata, and Apple Vision feature prints.

Section 2 records the agreed product behavior. Sections 3–11 translate it into an implementation plan. Exact performance budgets, retry limits and batch sizes are engineering parameters to establish through validation, not unresolved product choices.

## 2. Product decisions

| ID | Decision | Implementation consequence |
| --- | --- | --- |
| Q1 — decided | Photo-library vectorization may run in the foreground and continue in the background when iOS permits. Duplicate discovery runs only in the foreground. | Separate indexing/vectorization from duplicate discovery. Background execution must not discover review groups. Automatic iOS—scheduled vectorization is also enabled when the system grants background execution time (Q13). |
| Q2 — decided | Rebuild all local app data; no migration of the existing index, scan history, settings, or review decisions is required. | Library photos remain untouched. Implement a clean local-data transition for the rewrite. |
| Q3 — decided | Complete vectorization of the selected library scope before starting duplicate discovery and review. Then maintain a buffer of 2–3 unreviewed groups, replenishing it after each review. Discovery runs only in the foreground and pauses when the buffer is full. Vectorization may run in the foreground and background. | Discovery starts after the vectorization pass finishes: every photo is vectorized or explicitly deferred as unavailable under Q14. Review uses successful photos and reports unavailable ones. Stop replenishing when eligible results are exhausted. The review buffer does not limit vectorization. |
| Q4 — decided | iPhone only for now, with iOS 26 as the minimum supported version. | Set app and package deployment requirements to iOS 26; iPad and other platforms are outside the current scope. |
| Q5 — decided | Use small, project-owned native Swift stores and reducers for unidirectional data flow; do not adopt TCA. | Implement minimal shared state/effect infrastructure with structured concurrency. This decision does not authorize unrelated third-party dependencies. |
| Q6 — decided | Keep SwiftData for local metadata, with a redesigned schema and repository layer. Qdrant remains the vector store. | Implement metadata persistence and recovery records behind repository contracts; test transactions and reopen/recovery behavior. |
| Q7 — decided | Retain Apple Vision feature prints and cosine similarity. | Preserve the current embedding approach; the rewrite focuses on architecture and reliability rather than comparing embedding models. Track embedding compatibility for safe reuse. |
| Q8 — decided | Find visually similar photos, including different shots of the same scene. Allow similarity chains: A–B and B–C may form one group even when A and C do not match directly. A separate exact-duplicate category is outside scope. | Use connected—component grouping; do not imply that every pair within a group meets the similarity threshold. |
| Q9 — decided | Compare only photos within the selected date range; every member of a group must fall within that range. | Apply the scope to both query photos and candidate matches, even when the index retains vectors from other ranges. |
| Q10 — decided | Skip defers a group until all other available groups have been reviewed. It does not permanently dismiss the group or protect its photos from future suggestions. | Prioritize other eligible groups, including those not yet discovered, before returning deferred groups. Do not treat an empty prefetch buffer as discovery exhaustion. |
| Q11 — decided | A similarity-threshold change takes effect immediately: invalidate pending groups and restart foreground lazy discovery using existing compatible vectors. Rescan reuses existing compatible vectors, vectorizes new or changed photos in the selected scope, then restarts duplicate discovery. Both reset review order and skip deferrals, treating discovered groups as fresh results. | Cancel obsolete discovery and reject stale results. Preserve the vectorization-completion prerequisite. Resetting review order never restores deleted library photos. |
| Q12 — decided | Open each group without a default keep selection; the user chooses which photos to keep. Allow the user to explicitly delete every photo in a group; keeping at least one is not required. Treat favorites like other photos, without special deletion protection. | An empty initial selection must not itself trigger deletion; deletion requires an explicit user action. |
| Q13 — decided | Start vectorization automatically on launch and when new or changed photos are detected, within the selected scope. Also allow iOS-scheduled background vectorization while the app is not in use, whenever the system grants execution time. A manual pause suppresses vectorization, including background work, until the next app opening, when it resumes automatically. | Duplicate discovery remains foreground-only. Background scheduling does not guarantee immediate execution. Provide Pause and Resume controls, with no separate user-facing Cancel control. Internal task cancellation remains necessary for safe interruption and replacement. Automatically retry temporary vectorization failures a limited number of times, preserving completed work; show a Retry button when those attempts are exhausted. Classify errors explicitly and avoid unbounded retry loops. |
| Q14 — decided | If an individual photo cannot be loaded or vectorized after applicable retries, defer it and continue. Allow review of successfully vectorized photos after the pass finishes, showing that some photos were unavailable. | Every photo in scope must be either successfully vectorized or explicitly deferred before discovery starts; unresolved in-flight work still blocks discovery. This exception refines Q3's completion requirement. Allow required iCloud photo downloads over both Wi-Fi and cellular, subject to system availability. |
| Q15 — decided; budgets to measure | Design and test for libraries of 100,000+ photos. Balance vectorization speed with battery use and heat, keeping the app responsive. | Use bounded image/vector batches and scalable metadata queries; validate large-library behavior. Establish measurable latency/memory budgets on representative devices. Send a notification when background vectorization finishes and review can begin, subject to notification authorization; do not imply groups have already been discovered. Show vectorized-photo and unavailable-photo counts, reviewed-group and deleted-photo counts, plus estimated storage freed. Base deletion statistics on confirmed outcomes, avoid double-counting retries, and label storage savings as an estimate. |
| Q16 — decided | Prioritize unreliable background work, recurring discovery failures, excessive iPhone heat, grid glitches, and inconsistent Liquid Glass styling. Remove grid mode for now and retain only Tinder-like card review. | Background reliability applies to vectorization; discovery remains foreground-only per Q1. Add device lifecycle regressions, heat/resource acceptance checks, and a consistent Liquid Glass pass across retained screens. |

### New photos during review — decided

When new photos arrive during an active review, keep existing results available and let review continue while those photos are vectorized. Make newly vectorized photos eligible for foreground discovery once ready. The initial vectorization-pass gate in Q3 applies before starting review; later arrivals do not restart that gate or block the current review. Preserve the open group's snapshot and validate its revision when committing a decision.

### New matches to reviewed groups — decided

Newly vectorized matches must not resurface an already reviewed group until an explicit rescan or threshold change resets discovery/review decisions. Preserve completed review decisions within the current discovery revision. A skipped group is deferred rather than completed and still returns according to Q10. Test incremental arrivals against completed groups so adding a match cannot silently reset their review status.

## 3. Preserve and replace boundaries

Preserve the QdrantEdge dependency and working SDK request/response mapping behind a vector repository interface. Preserve one owner of an open shard. Move index reset, embedding compatibility, and recovery policy into use cases instead of retaining silent dimension-driven deletion as business behavior.

Preserve Photos asset querying, thumbnail loading, image-request cancellation, and full-image preview loading behind a Photos adapter. Characterize these paths before moving them. The architecture document describes richer loading helpers than are visible in the inspected PhotoLibraryService file; inventory the actual helper implementations and call sites during extraction.

Preserve design tokens, components, localization, gestures, Tinder-like card presentation, and fullscreen preview. Remove grid mode, its navigation toggle, pagination-only use cases and grid-specific state/tests from the rewrite scope. Rebind retained views to new state/actions. Apply consistent Liquid Glass styling across retained screens. Pure transient presentation state such as zoom or drag offset can stay local to SwiftUI.

Replace scan orchestration, UI/business coupling, lifecycle coordination, persistence model ownership, group identity, review transactions, settings side effects, and bootstrap/recovery. Existing tests are regression evidence to port by behavior, not a mandate to reproduce old internals.

### Visual consistency and heat acceptance

Audit onboarding, vectorization progress, card review controls, group comparison, fullscreen-preview controls, settings, sheets and error states for consistent Liquid Glass treatment. Prefer standard SwiftUI controls and shared design-system styling; use custom glass effects where needed. Keep photo content readable and validate light/dark appearances, Reduce Transparency and Reduce Motion. Limit simultaneous glass effects and share effect containers where appropriate, following [Apple's Liquid Glass guidance](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views).

Treat excessive heat as a release blocker to investigate on representative physical iPhones. Define device-based acceptance budgets during implementation rather than inventing unmeasured throughput or temperature guarantees. Use bounded concurrency, avoid redundant embedding/search work, and test resource-policy responses to thermal pressure with injected conditions. Validate both vectorization and foreground discovery during sustained use.

### Dependency injection framework

The owner requires a DI framework and is interested in SafeDI after using Factory. Plan for SafeDI, subject to the integration checks below. Do not add Factory alongside it or silently substitute frameworks if validation fails.

## 4. SPM structure

Use one local package, Packages/PhotoSweep, with compiler-enforced target boundaries and iOS 26 as its deployment floor. The Xcode application remains the iPhone-only host for signing, entitlements, system registration and dependency composition.

| Target | Responsibility | Dependencies |
| --- | --- | --- |
| SweepDomain | Value models, typed IDs/errors, repository contracts and pure policies | Foundation where needed |
| SweepUseCases | Vectorization, discovery, review, settings, recovery, authorization and image-loading operations | SweepDomain |
| SweepQdrant | Preserved SDK mapping and single shard owner | SweepDomain, QdrantEdge |
| SweepPhotos | Preserved asset/image loading, authorization, change observation and deletion integration | SweepDomain, Photos and image frameworks |
| SweepEmbeddings | Apple Vision feature prints | SweepDomain, Vision and image frameworks |
| SweepPersistence | SwiftData metadata, journals, preferences and schema versioning | SweepDomain, SwiftData |
| SweepSystem | Background execution, lifecycle/resource signals and notification adapters | SweepDomain, platform frameworks |
| SweepDesignSystem | Existing tokens, shared Liquid Glass presentation, localization and reusable components | SwiftUI |
| SweepFeatureState | Minimal native store/effect infrastructure | Foundation, Observation |
| SweepLibraryFeature | Vectorization progress, availability, Pause/Resume/Retry UI | SweepDomain value types, SweepUseCases, SweepFeatureState, SweepDesignSystem |
| SweepReviewFeature | Tinder-like cards, group comparison and fullscreen preview | SweepDomain value types, SweepUseCases, SweepFeatureState, SweepDesignSystem |
| SweepSettingsFeature | Scope, threshold, rescan, reset and statistics UI | SweepDomain value types, SweepUseCases, SweepFeatureState, SweepDesignSystem |
| SweepOnboardingFeature | Authorization and onboarding UI | SweepDomain value types, SweepUseCases, SweepFeatureState, SweepDesignSystem |
| SweepComposition | SafeDI production graph and feature factories; exported app entry point | SafeDI, feature/use-case and adapter targets |
| SweepTestSupport | Deterministic fakes and fixtures, test-only | SweepDomain |

The app retains one composition root exported by SweepComposition, which injects narrow use cases into feature stores. The app routes system callbacks into application use cases from that same graph. Features use SweepDomain value types and contracts but do not import concrete adapters, QdrantEdge, Photos or SwiftData. Domain and use cases do not import UI modules. Adapters do not depend on each other. Isolate image transport behind a small image contract; do not expose PHAsset or SwiftData model objects to feature state.

No TCA, Combine-based orchestration, grid module or grid pagination API. Keep test support out of production dependency graphs. Move resources and string catalogs with their owning modules, update bundle lookup, and verify localization/previews.

### 4.1 SafeDI integration

SafeDI generates constructor-based dependency trees and checks their wiring at build time. Its hierarchical model fits the planned app and feature lifetimes. This is a project-fit assessment, not proof of compatibility with our build. See the [SafeDI overview](https://github.com/dfed/SafeDI).

Keep the generated root in the local package's SweepComposition target, with the Xcode host constructing and retaining its exported entry point. The documented SPM plugin can discover dependent-module sources; Xcode-project plugin integration needs additional source-directory configuration. Prefer the package-root arrangement and verify it in the actual workspace. Add SafeDI products to annotated targets and the generator to targets that need generated output. Keep SweepDomain, pure policies and SweepDesignSystem independent of SafeDI. See the [integration manual](https://github.com/dfed/SafeDI/blob/main/Documentation/Manual.md).

Use ordinary explicit initializers throughout. Annotate participating implementations/use cases/feature factories where useful; annotations are wiring metadata, not permission to perform dependency lookups inside business logic. Record SafeDI as an additional dependency for those targets in the manifest. Select and pin a tested release; do not rely on APIs from the moving main branch.

| Lifetime | Ownership rule |
| --- | --- |
| Application | One vector repository/shard owner, metadata repository, vectorization executor and system adapters shared by UI and background entry points |
| Feature | Separate native stores and cancellable observation tasks, receiving app-owned use cases/dependencies |
| Operation | Immutable scope, revision, group snapshot and operation ID passed as inputs; never globally registered mutable values |
| Test/preview | Fresh graph or direct initializer-injected fakes per test/preview; no shared production stores or global override state |

SafeDI construction must not open a shard, perform migrations or assume asynchronous bootstrap succeeds. BootstrapApplication remains an explicit, throwing asynchronous workflow. Hold the root outside SwiftUI body reconstruction; background launch initializes the same retained root rather than building a second graph. Dependency-graph validation does not establish correct actor isolation, race freedom or external-store consistency.

### 4.2 Early DI validation milestone

Before broad adoption:
1. Build a minimal graph spanning domain contracts, an adapter, a use case and a main-actor feature store, with the root in SweepComposition.
2. Verify protocol fulfillment, generated-code visibility and Swift concurrency diagnostics using the actual Xcode/Swift toolchain and pinned release.
3. Prove foreground and background entry points receive identical app-scoped instances, while feature stores remain separate.
4. Verify bootstrap failure/retry without duplicate shard owners, and independently constructed unit-test/preview graphs without live Photos access.
5. Run clean and incremental app builds, package tests and Release configuration; document plugin setup for developers and CI.

Keep unit tests based on explicit initializers and deterministic fakes. Generated graph helpers may support integration tests/previews after verifying their availability in the pinned release. Record build-time cost and inspect generated wiring during this milestone. If SafeDI cannot satisfy these checks, report the concrete blocker before revisiting Factory; do not weaken module boundaries to force adoption.

## 5. Use cases and unidirectional data flow

SwiftUI intent → feature action → synchronous reducer → effect invoking a use case → result/event action → reducer → new state → SwiftUI.

Native main-actor stores own observable state, effect tasks and action dispatch. Reducers are deterministic; views render state and dispatch intents. Zoom and transient drag offsets can remain view-local. Technical adapters perform I/O; use cases own business sequencing. Pure policy helpers remain synchronous, independently testable units invoked by use cases.

| Area | Use-case responsibilities |
| --- | --- |
| Bootstrap | BootstrapApplication, RequestPhotoAccess, RecoverPendingOperations, LoadPreferences |
| Vectorization | ReconcilePhotoLibrary, StartOrResumeVectorization, PauseVectorization, RetryVectorization, VectorizePhotoBatch, ObserveVectorization |
| Discovery | BeginDiscoveryRevision, RefillReviewBuffer, DiscoverNextComponent, ObserveReviewAvailability, SuspendDiscovery |
| Review | LoadNextReviewGroup, ValidateKeepSelection, SkipGroup, CommitReviewDecision, DeleteSelectedPhotos |
| Images | LoadThumbnail, LoadPreviewImage |
| Settings | UpdateDateScope, UpdateSimilarityThreshold, RescanLibrary, ResetLocalData, LoadStatistics |
| System integration | HandleAppActivation, HandleExecutionExpiration, EvaluateBackgroundEligibility, ScheduleVectorization, NotifyReviewReady |
| Resource policy | EvaluateWorkBudget from execution context, thermal/resource signals and current work |

Each use case receives only its required contracts and immutable inputs. Do not force observation streams or synchronous policies into one universal async-throwing protocol. Do not introduce a dependency-container lookup inside business units.

Vectorization and discovery expose separate progress and status. Neither accepts UI state or calls a UI reducer. Deliver explicit revision-tagged events through async sequences, including membership changes even if counts stay unchanged. Specify buffering, coalescing and subscriber cancellation. Reject obsolete effect results by operation and revision IDs. A disappearing view cancels its subscriptions; it must not accidentally terminate app-owned background vectorization.

Use-case and domain errors distinguish transient infrastructure failures, individual unavailable assets, authorization problems, incompatible embeddings, review conflicts and user-declined deletion. Retrying a photo is different from retrying a broken store or model.

## 6. Separate vectorization and lazy discovery

### 6.1 Durable state and ownership

Keep separate durable models for:
- Asset identity/content revision, vector ID, embedding compatibility and vectorization outcome.
- Vectorization pass: selected date scope, enumerated work, checkpoints, deferred assets and completion.
- Discovery revision: scope, threshold, eligible index generation, seed cursor and component-expansion frontier.
- Groups/memberships, review decisions, skip ordering and the bounded review queue.
- Recoverable external operations and confirmed statistics events.

Vectorization states include idle, running, pausedByUser, interrupted, failed and completed (with deferred-asset count). Discovery states include waitingForInitialPass, searching, bufferReady, suspended, exhausted and failed. There is no user-facing Cancel control or cancelled-session resume policy.

One app-owned vectorization executor controls a pass. Foreground and background entry points reuse it and the same shard owner. Discovery has its own foreground-only task owner. Coordinate short mutations, deletion, reset and generation publication without blocking review behind an entire library pass. Never hold a global mutation lease while waiting for user input or image downloads.

Manual Pause checkpoints work and blocks both automatic foreground work and background work until Resume or the next app opening. App activation clears that manual pause and resumes eligible work. System interruption does not imply manual pause. Internal cancellation is still used for safe task replacement, expiration and reset.

### 6.2 Vectorization workflow

1. Resolve authorization and the selected date scope; capture an initial pass work set or stable enumeration cursor.
2. Reconcile asset content revisions and index compatibility. Reuse valid existing vectors.
3. Load thumbnails, generate Vision feature prints and write vectors in bounded batches.
4. Journal intended writes, upsert vectors, commit metadata/checkpoints, then finish the journal entry.
5. Retry temporary failures with a finite policy and injected clock. Defer individual assets that remain unavailable and continue; a systemic failure stops work and exposes Retry after applicable attempts.
6. Finish the initial pass only when every included asset is vectorized or explicitly deferred. Present unavailable counts. Discovery can then start.
7. Continue detecting additions/edits automatically. During an active review, vectorize new photos without blocking existing cards; publish newly eligible assets after their writes commit.

Use the existing thumbnail and full-image loading mechanisms. Permit needed iCloud downloads over Wi-Fi and cellular. Full-resolution loading remains exclusive to explicit preview; vectorization must never require it. Reuse metadata for size estimates rather than downloading originals solely to compute savings.

Track model/revision, preprocessing and dimensions, not just dimension count. Replace silent shard deletion on mismatch with a recoverable generation transition that also handles metadata. Use stable collision-aware vector identity. Qdrant and SwiftData cannot share a transaction: test replay after each boundary and never infer successful vectorization solely from point existence.

### 6.3 Foreground discovery and buffer

After the initial pass, search only within the selected date range and committed compatible vectors. Both query seeds and candidate matches must satisfy scope. Use cosine similarity and connected components, including transitive chains.

Maintain a configurable capacity of 2–3 unreviewed groups, counting the current card. Each completed review or skip requests refill. Stop finding new groups when the buffer is full, all eligible work is exhausted, or the app leaves the foreground. A full buffer never stops vectorization.

Discovery must be lazy at the group level, not a hidden full-library scan performed on every refill:
1. Select the next eligible seed from a durable ordered cursor.
2. Expand its connected component through a persisted frontier, visiting each member and deduplicating edges.
3. Complete the component for the captured eligible-data revision before publishing it; a group may require many queries and contain many photos.
4. Persist the group, membership and cursor/frontier progress transactionally.
5. Repeat only until the review buffer is full.

Do not assume the existing top-10 nearest-neighbor result is a complete neighborhood. Validate SDK query capabilities and implement a completeness-aware paged/expanded retrieval strategy. Record and test any practical limits explicitly. Large components may spill frontier/member state to persistence; do not silently split chains or retain all library vectors in memory to meet the buffer target.

The 2–3-group buffer bounds ready groups, not all search work or group size. Persist cursors/frontiers so interruption resumes rather than restarting expensive searches. Pin component expansion to an eligible-data generation; route later indexed arrivals into subsequent discovery work.

### 6.4 Settings changes and incoming photos

| Trigger | Required behavior |
| --- | --- |
| Threshold change | Immediately invalidate pending groups and old discovery effects; create a new discovery revision using reusable vectors; reset review order and skip deferrals. Discovery still runs only in the foreground and respects the initial-pass gate. |
| Explicit Rescan | Reconcile scope; vectorize new/changed photos and defer unavailable ones; then restart discovery with fresh review order/decisions. Reuse compatible vectors. |
| Date-scope change | Cancel obsolete discovery and start a scoped vectorization pass; every returned group member must satisfy the new range. Reuse compatible vectors already present. |
| New photos during review | Continue current review; vectorize additions and make committed vectors eligible for later foreground discovery without reopening the initial gate. |
| New match to completed group | Preserve the completed decision and do not resurface that group until rescan or threshold reset. Track suppression against reviewed membership so regenerated IDs cannot bypass it. |
| Photo edit/removal or access change | Reconcile validity and invalidate affected snapshots as necessary; distinguish missing permission from confirmed deletion. |

An open card retains a versioned snapshot. Changes must not silently modify its keep selection. Commit checks the current revision and asset availability, returning a visible conflict/refresh result when needed. Threshold/rescan replacement retires obsolete cards; coordinate with any already-started deletion so confirmed outcomes still reconcile correctly.

## 7. Review, deletion, reset and statistics

### Card review

Retain only Tinder-like review and fullscreen preview; remove the grid toggle, grid routes and grid-only state/use cases. Keep group comparison needed to select individual photos.

A group opens with no keep selection. Users may select any subset, including none, and explicitly delete all photos. Favorites receive no special protection. Empty selection alone never invokes deletion. Keeping all is a completed review decision; Skip is deferral.

Use stable group IDs and membership revisions. Component expansion publishes a completed snapshot; subsequent changes preserve identity where appropriate and record merge/split lineage instead of replacing every pending group. Suppression of completed decisions survives incoming matches for the current discovery revision. Resetting discovery decisions never restores deleted photos.

Skip persists deferral before advancing the card. Deferred groups return only after other eligible groups have been reviewed, including groups not yet discovered. An empty ready buffer is not proof of exhaustion. Keep deferred ordering durable; after exhaustion, cycle deferred groups in order rather than producing duplicate queue entries.

### Recoverable deletion

1. Validate the group revision, exact keep/delete sets, authorization and currently accessible assets.
2. Persist an operation ID and deletion intent, including metadata needed for statistics.
3. Request Photos deletion through the preserved adapter.
4. Record the confirmed outcome and reconcile vectors, asset metadata, edges, groups and queue entries.
5. Commit the review decision and statistics exactly once, then advance/refill the card buffer.

If the user declines Photos deletion, retain the card and do not count deletion. A failure after Photos succeeds enters recoverable cleanup, not a blind repeat of the destructive request. Unknown outcomes require reconciliation; limited-library access must not be interpreted as evidence of deletion. Late completion from an older discovery revision must still finish its journal and statistics safely.

### Local reset and rollout

No legacy data migration is required. Introduce a versioned local store/index namespace for the rewrite and retire legacy app data through an explicit, idempotent bootstrap transition. This resets old preferences, history and review decisions as agreed and never touches library photos.

The ResetLocalData use case stops active mutations, invalidates effects and coherently resets the vector index, compatibility metadata, SwiftData records, journals and review state. Recovery of an already-started external deletion must remain possible before its journal is retired. Keep reset itself restartable.

### Statistics

Show vectorized photos, unavailable photos, reviewed groups, deleted photos and estimated storage freed. Current photo counts come from durable asset outcomes; reviewed/deleted counts come from confirmed idempotent events. Scope/generation tagging prevents obsolete events from altering the active workflow incorrectly. Review-order resets do not double-count an earlier deletion.

Label storage savings as an estimate, handle unknown sizes without inventing values, and do not present deleted bytes as immediately reclaimed device storage. Statistics loading is a use case, not ad hoc counting in views.

## 8. Background execution and resource control

Both continuation of foreground vectorization and iOS-scheduled automatic vectorization are in scope. Duplicate discovery never runs in the background.

Implement a thin system adapter for registration, scheduling, execution windows, expiration and completion reporting. Route all work into the same vectorization use cases and shared dependencies. Validate iOS 26 APIs and eligibility requirements against Apple documentation during implementation, including which mechanisms support automatic work versus explicitly user-initiated continuation. Do not assume an automatically launched pass qualifies for every continuation API.

On background entry, suspend discovery and checkpoint its frontier. Vectorization continues only while execution is permitted; expiration cancels it at a safe boundary and preserves retryable progress. Background callbacks honor a persisted manual pause. Foreground activation resumes eligible vectorization, reconnects observations and requests discovery refill only when the initial gate is satisfied.

Prevent duplicate handlers/workers from opening another shard or running competing vectorization passes. Balance every acquired system execution opportunity with a completion result. Scheduling does not guarantee immediate execution, execution after force-quit, or indefinite processing.

Post one readiness notification per eligible completed background pass when notification authorization permits it. Deferred photos do not prevent readiness if the pass is otherwise complete. Say that photos are ready for review, not that duplicate groups were discovered in the background.

For 100,000+ photo libraries, bound images, vectors, frontier state and database fetches. Keep heavy work off UI execution paths. Make work-budget policy testable with injected thermal/resource signals; reduce concurrency or yield under pressure without turning it into a manual pause. Measure physical-device latency, memory, responsiveness and thermal behavior before setting final batch/concurrency budgets. Balanced speed, battery use and heat is the target.

## 9. Test plan

Use Swift Testing exclusively for all unit and integration suites, including business policies, use cases, reducers, DI composition and adapters. Use import Testing, @Test, @Suite, #expect and #require; do not introduce XCTestCase, XCTest assertions or XCTest expectations into these targets. Async tests use async/await and deterministic synchronization. Keep XCUIAutomation-based user journeys in a separate UI-test target; any XCTest harness required for UI automation is confined to that target. Maintain an inventory mapping each use case, reducer and policy to meaningful success, failure and boundary scenarios. Keep test support out of the shipping target graph.

| Area | Required scenarios |
| --- | --- |
| Domain policies | Date boundaries; identity/content revisions; vector validity; compatibility; cosine threshold boundaries; A–B–C chain grouping; empty keep selection |
| Vectorization | Empty library; final batch; reused vectors; edited/new assets; bounded retry; per-photo deferral versus systemic failure; Wi-Fi/cellular availability |
| Initial gate | Review blocked during initial work; allowed after successful/deferred outcomes; unavailable count visible; later arrivals never block active review |
| Durable recovery | Interruption after every external write; replay without duplicates; checkpoint never skips uncommitted work; store reopen |
| Discovery | Foreground-only; complete component expansion; more than ten matches; giant chain; scope on both sides; durable frontier; no full-library recomputation per refill |
| Buffer | Capacity 2–3 including current card; refill after review/skip; full-buffer pause; resume after activation; true exhaustion distinct from temporary emptiness |
| Incremental changes | Review continues during new vectorization; new vectors become eligible; completed groups do not resurface; stale membership detected on commit |
| Skip | Persistence failure retains card; other undiscovered groups take priority; durable deferred ordering; no duplicate entries |
| Settings | Immediate threshold revision; stale callbacks ignored; rescan reuses vectors; review/skip decisions reset; date-range isolation |
| Review/deletion | No default keep selection; delete all allowed explicitly; favorites unchanged; user rejection; keep-all completion; failure at each cleanup boundary |
| Statistics | Confirmed outcomes only; replay counted once; unknown byte sizes; estimates labeled; revision changes do not duplicate deletion totals |
| Pause/lifecycle | Manual pause blocks background work; next opening resumes; no Cancel UI; expiration/relaunch; overlapping callbacks; observer cancellation |
| Background | Scheduled and continued vectorization use one executor/shard; no discovery; notification authorization and deduplication; denied execution |
| Authorization | Denied/restricted/limited; access changes during work; inaccessible versus deleted assets; iCloud-unavailable photos |
| Reset | Legacy clean-start transition; reset during work; reset interruption; deletion journal reconciled before retirement; photos untouched |
| DI composition | Cross-module graph generation; protocol bindings; shared app instances; separate feature/test scopes; actor isolation; bootstrap retry; clean/incremental/Release builds |
| Reducers/effects | Every action/state transition; cancellation ownership; late completion; surfaced errors/retry; no business work hidden in views |
| Adapters | Real temporary Qdrant reopen/upsert/search/delete; SwiftData transaction/reopen behavior; preserved Photos cancellation; Vision smoke tests |
| UI | Onboarding; progress/Pause/Resume/Retry; Tinder-like cards; skip/delete-all; preview; settings; no grid route/toggle; consistent Liquid Glass |
| Scale/resources | 100,000+ metadata/vector fixtures; bounded resident images/vectors; large components; thermal-policy tests; sustained device responsiveness |

Inject clocks, IDs and controllable async dependencies. Use explicit suspension gates for race tests instead of sleep-based timing. Separate fast unit tests from model/platform-dependent integration suites and physical-device scenarios. Port relevant existing lifecycle regressions into the correct module tests.

Recording image fakes must prove that vectorization/card thumbnails never load full-resolution images and that preview does. Device acceptance covers actual Photos dialogs, iCloud downloads, lock/suspension, system expiration, automatic scheduling and sustained heat. Simulator tests cannot guarantee system scheduling behavior.

## 10. Delivery sequence and exit criteria

1. **Establish shared agent rules — implemented, runtime loading checks outstanding.** Canonical .agents rules, requirement map, project map, AGENTS/Claude entry symlinks and manual Cursor adapters are in place. The validator passes 49 requirement groups, all 16 decisions and relocated symlink checks. See .agents/tooling.md for measured context sizes and the unexercised client-session loading checks; do not equate filesystem checks with runtime ingestion.
2. **Establish the baseline — inventory and test/UI evidence recorded; physical performance pending.** See docs/baseline/README.md for preserved-code/resource inventory, 86-file source snapshot, all 13 test mappings/results, simulator screenshots and the device measurement protocol. All 13 existing tests pass on iPhone 17 / iOS 27.0.1. Device heat, energy, controlled workload throughput and scheduler acceptance remain unmeasured; do not treat passing tests as those measurements.
3. **Create SPM boundaries and validate SafeDI.** Add iOS 26 package targets and tests, retain an iPhone-only app host, extract preserved adapters/design system, and implement the minimal SafeDI composition milestone in section 4.2. Exit: DI checks pass with a pinned release; app builds, resources/localization resolve, dependency direction is enforced.
4. **Build domain/state contracts — delivered; see docs/implementation/step-4.md.** Implement separate vectorization/discovery models, native reducers/effects, policies and fakes. Exit: deterministic tests cover the agreed gates, retries, pause, buffer and review semantics.
5. **Implement durable persistence — delivered; see docs/implementation/step-5.md.** Add redesigned SwiftData schema, journals, stable IDs, revisions, cursors and clean-start transition. Exit: crash/reopen/reset tests pass without legacy migration or library-photo modification.
6. **Deliver foreground vectorization.** Authorization → reconciliation → thumbnails → Vision → Qdrant → durable pass completion/deferred outcomes. Exit: cache reuse, automatic triggers, Pause/Resume/Retry and initial review gate pass end to end.
7. **Deliver lazy discovery and card review.** Component expansion → 2–3-group buffer → selection/skip → recoverable deletion/refill. Exit: scoped chain semantics, incremental arrivals, suppression and failure recovery pass; grid is removed.
8. **Deliver background vectorization.** Add continuation and automatic scheduling adapters on the shared executor. Exit: expiration/handoff/manual-pause scenarios pass and real-device execution is observed; discovery remains foreground-only.
9. **Complete presentation and settings.** Immediate threshold changes, rescan, statistics, notifications, preview, errors and shared Liquid Glass styling. Exit: all retained screens and navigation match the revised behavior, with no direct business orchestration in views.
10. **Validate scale and cut over.** Exercise 100,000+ fixtures and physical-device resource scenarios, tune bounded work, remove old pipeline/coordinators/global dependencies, and rewrite ARCHITECTURE.md. Exit: builds/tests/device journeys pass and the production app has one vectorization implementation and one foreground discovery implementation.

Use an isolated rewrite branch with incremental runnable slices. Never run old and new engines against the same live stores concurrently. Temporary comparative validation uses separate fixture stores and one selected production composition root.

### 10.1 Shared agent rules — first implementation deliverable

Create a repository-owned .agents directory as the canonical home for agent instructions before changing application architecture. Extract the full set of technical requirements from this document, including the product decisions that constrain implementation. Do not copy the whole plan into automatically loaded instructions.

Proposed organization:

| Canonical file | Purpose / when to read |
| --- | --- |
| .agents/AGENTS.md | Short entry point: project purpose, non-negotiable invariants, rule routing and essential build/test guidance |
| .agents/rules/architecture.md | SPM graph, use-case boundaries, native unidirectional state, Swift concurrency and SafeDI ownership |
| .agents/rules/vectorization.md | Photos/Vision/Qdrant preservation, compatibility, initial gate, incremental updates, retries and deferral |
| .agents/rules/discovery-review.md | Foreground-only discovery, connected components, scoped matches, bounded buffer, skip/suppression, selection and deletion |
| .agents/rules/persistence-lifecycle.md | SwiftData journals/recovery, shared shard, reset, pause/resume, background eligibility and notifications |
| .agents/rules/ui.md | iPhone/iOS 26+, SwiftUI, design-system reuse, Liquid Glass, card-only navigation and preview loading |
| .agents/rules/testing.md | Swift Testing exclusively for unit/integration tests, separate UI automation, deterministic fakes and required validation by change type |
| .agents/rules/performance.md | 100,000+ photos, bounded work, thermal/resource policy and measured acceptance budgets |
| .agents/requirements.md | Requirement IDs mapped to source sections/Q IDs, owning rule, implementation area and verification criterion; reference only |
| .agents/project-map.md | Concise module/file entry points and verified build/test commands; distinguish current code from planned modules |

Each rule must be actionable and preserve exceptions. For example, the initial vectorization gate must include deferred photos and the exception for later arrivals during review. Capture both confirmed decisions and implementation commitments; label provisional choices such as SafeDI's validation milestone and unmeasured budgets accurately. Exclude rejected alternatives, conversation history and obsolete current-code behavior from normative rules.

**Extraction procedure:**
1. Inventory every requirement in sections 1–11 and the supplemental decisions. Assign stable IDs; mark each as confirmed product behavior, planned technical constraint, or validation parameter.
2. Deduplicate requirements without losing their conditions. Give each requirement one owning rule file and link related rules rather than repeating paragraphs.
3. Map each requirement to a test, build check, review check or physical-device acceptance check. Reconcile against every decision-table row, module boundary, workflow and completion criterion.
4. Put only universally relevant constraints and a task-to-rule routing table in the entry file. Agents read the applicable rule files before editing their area; cross-cutting work follows all relevant links.
5. Review the extracted rules against the plan for omissions and contradictions. Update rules and the requirement map with future accepted changes; preserve the plan as rationale and delivery sequencing, not a competing rule copy.

**Tool entry points and symlinks:**
- Create a relative root AGENTS.md symlink to .agents/AGENTS.md for tools that discover that entry point.
- Provide relative links from .claude, .cursor and other actively supported tool instruction locations into the canonical .agents content. Inspect existing paths first; preserve any tool-owned settings rather than replacing nonempty directories.
- A directory symlink alone is not evidence that a tool loads instructions. Verify each supported tool's current discovery paths, file formats, scoping and symlink handling before choosing its layout.
- Where a tool accepts the shared directory layout, link its instruction directory to the canonical directory. Where it requires a distinct entry filename or metadata wrapper, use a minimal tool-specific entry file/link that routes to the same canonical rules. Keep tool-specific metadata separate from shared prose.
- Do not create speculative integrations for every possible editor. Cover the tools in use, starting with AGENTS-compatible tools, Claude and Cursor, and document any unsupported loading behavior.
- Avoid absolute machine paths, duplicate auto-loading of the same rule, circular links and symlinks that escape the repository. Do not symlink caches, credentials or runtime settings into the shared rules directory.

**Token budget and acceptance:**
- Target no more than roughly 1,000 tokens for the always-loaded shared entry; keep specialized rules concise and load them by task. Correctness takes precedence over a hard token cap.
- Keep the full requirement map, architecture narrative and historical planning out of automatic context. Prefer short rules with explicit references over repetitive examples.
- Verify links resolve after a fresh checkout and confirm actual instruction loading for each configured tool. If a tool cannot be exercised locally, record that limitation rather than claiming support.
- Exit only when every extracted technical requirement has an owner and verification mapping, tool entry points load the canonical content, and no competing copies exist.
- Record the measured size of the entry and scoped rule files. This milestone creates instructions and links; it does not implement the application rewrite.

## 11. Completion criteria

- Canonical .agents rules cover all technical requirements, stay synchronized with accepted changes, and load through verified tool entry points without duplicated instructions.
- iPhone/iOS 26+ app uses SPM modules, native unidirectional state, use cases, SwiftData and preserved Qdrant/Photos/Vision integration.
- SafeDI generates the production composition graph, with verified app/feature lifetimes and shared foreground/background services; domain policies remain framework-independent.
- Every business unit has meaningful deterministic Swift Testing tests and required integration coverage; unit and integration test targets contain no XCTest dependencies.
- Automatic vectorization works in foreground and permitted background windows, with durable recovery, pause/resume, finite retries and per-photo deferral.
- Initial review waits for pass completion; later arrivals do not block current review.
- Discovery is foreground-only, range-scoped and lazy, with a 2–3-group buffer and tested connected-component semantics.
- Skip ordering, completed-group suppression, immediate threshold changes and incremental rescan follow the recorded decisions.
- No preselected keep photo; explicit delete-all is supported; deletion/reset recover without false success or duplicated statistics.
- Grid mode is removed; Tinder-like review, thumbnail-only processing and full-image preview remain; Liquid Glass is consistent across retained screens.
- Large-library memory/resource behavior and physical-device heat meet measured acceptance budgets.
- Readiness notifications and statistics report confirmed, appropriately qualified outcomes.
- Builds, module tests, adapter integration tests and device journeys pass; obsolete code is removed and ARCHITECTURE.md matches the implementation.

This is a documentation-only change. Build/test execution belongs to the implementation phases above.
