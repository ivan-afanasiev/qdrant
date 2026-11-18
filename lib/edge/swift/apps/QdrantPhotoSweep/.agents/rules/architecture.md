# architecture rules

Classification: C = confirmed product requirement; T = planned technical constraint; V = validation parameter/milestone. IDs map to .agents/requirements.md; source is REWRITE_PLAN.md.

## ARC-01 (C) — Platform/modules

Target iPhone, iOS 26+. Use one local SPM package at Packages/PhotoSweep; keep Xcode host for signing, entitlements, system registration and composition. Retain QdrantEdge, Photos, Vision feature prints, cosine similarity and SwiftData; no TCA or Combine orchestration.

## ARC-02 (T) — Module graph

Use the target graph in .agents/project-map.md. Features depend on use cases, native feature state and design system, never concrete adapters/Photos/SwiftData/QdrantEdge. Domain/use cases never import UI; adapters never depend on each other. Test support is test-only. Keep PHAsset and persistence objects out of feature state; isolate image transport.

## ARC-03 (C) — Business/state

Route intent → action → synchronous deterministic reducer → effect/use case → result action → state → SwiftUI. Main-actor native stores own observation/effects; views dispatch intents. Business operations enter through narrow use cases with immutable inputs; pure helpers stay synchronous. No service-locator lookup or universal protocol forcing all operations into async/throwing shapes.

## ARC-04 (T) — Concurrency

Separate vectorization/discovery progress and owners. Use revision/operation-tagged async events, including same-count membership changes; specify buffering/coalescing/subscriber cancellation. Never pass UI state into pipelines. View disappearance cancels subscriptions, not app-owned vectorization. Reject stale results, but still reconcile already-started external operations.

## ARC-05 (T) — Errors/states

Distinguish transient infrastructure failure, unavailable asset, authorization, incompatible embeddings, review conflict and declined deletion. Vectorization: idle/running/pausedByUser/interrupted/failed/completed-with-deferred-count. Discovery: waitingForInitialPass/searching/bufferReady/suspended/exhausted/failed. Internal task cancellation is not a user-facing Cancel workflow.

## ARC-06 (V) — SafeDI adoption

SafeDI 2.2.0 is pinned for the early validation slice; adopted in SweepComposition only (see docs/implementation/README.md). Validate a graph spanning contract, adapter, use case and main-actor feature store before broad adoption. Verify protocol bindings, visibility, concurrency, clean/incremental/Release builds and package tests; record build cost/generated wiring and developer/CI setup. Report blockers before reconsidering Factory; do not weaken boundaries or add both frameworks.

## ARC-07 (T) — DI graph

Put the generated root in SweepComposition; retain its exported entry in the Xcode host outside body reconstruction. Add SafeDI products to annotated targets and generator where output is needed; verify SPM discovery in this workspace. Keep domain, pure policies and design system SafeDI-free. Use explicit initializers; annotations are wiring only.

## ARC-08 (T) — DI lifetime/bootstrap

App scope owns one vector repository/shard, metadata repository, vectorization executor and system adapters for UI/background. Feature stores and observations are separate; operation inputs are immutable and never global registrations. Tests/previews get fresh graphs/fakes. Construction performs no shard opening/migration; BootstrapApplication is explicit async throwing work. Verify retry never duplicates shard ownership; graph validity alone does not prove thread safety.

## ARC-09 (T) — Resources/use cases

Move resources/localization with owning modules and fix bundle lookups. Cover bootstrap/access/preferences/recovery; vectorization/reconciliation; discovery/refill/suspend; review/selection/skip/deletion; thumbnail/preview; scope/threshold/rescan/reset/stats; lifecycle/scheduling/readiness; resource-budget policies with use cases. Keep presentation-only drag/zoom state local.
