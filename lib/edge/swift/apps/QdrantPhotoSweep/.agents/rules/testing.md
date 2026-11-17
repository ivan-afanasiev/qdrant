# testing rules

Classification: C = confirmed product requirement; T = planned technical constraint; V = validation parameter/milestone. IDs map to .agents/requirements.md; source is REWRITE_PLAN.md.

## TEST-01 (C) — Framework/coverage

Swift Testing exclusively for every business unit and integration suite: import Testing, @Test/@Suite, #expect/#require. No XCTestCase/assertions/expectations/dependencies in these targets. XCUIAutomation and its required XCTest harness belong only in a separate UI-test target. Keep fakes/test support out of production graph.

## TEST-02 (T) — Determinism

Use explicit initializers, fresh fakes/graphs, injected clocks/IDs and suspension gates, not sleep timing/global overrides. Async/await tests cover every reducer action/effect and success/failure/boundary of each policy/use case. Separate fast units, real-adapter integration, model/platform smoke tests and physical-device acceptance.

## TEST-03 (T) — Behavior matrix

Test: empty/final batch/cache/edited asset; initial/deferred gate/incremental arrivals; finite retry/systemic errors; range/cosine/chain/>10/giant component; buffer/refill/true exhaustion; skip/suppression/conflicts; threshold/rescan reset; no-default/keep-all/delete-all/favorites; every external-write failure; stale events/cancellation; pause/reset/access/limited authorization; statistics/notification dedup. Use the per-rule checks and requirements.md to confirm coverage.

## TEST-04 (T) — Real adapters

Exercise real temporary Qdrant reopen/upsert/search/delete and SwiftData transactions/reopen, Vision smoke tests and Photos cancellation. Recording image fakes prove vectorization never loads full resolution and only review originals (presented cards/preview) do. DI checks cover graph builds/bindings/lifetimes/bootstrap retry/test isolation. No unit test may access the live library.

## TEST-05 (V) — Physical validation

Device-check Photos dialogs, iCloud availability, lock/suspension/expiration, automatic scheduling/handoff, sustained heat, UI responsiveness and 100,000+ fixture behavior. Simulator/mocks do not establish system scheduling guarantees. Build with Xcode BuildProject; run targeted meaningful tests and required checks; report unrun checks honestly.

## TEST-06 (T) — Delivery/cutover

Implement runnable slices in plan order after rules: baseline, SPM/SafeDI, domain/state, persistence, foreground vectorization, lazy card review, background, presentation/settings, scale/cutover. Isolate rewrite work and old/new fixture stores; never run engines against the same live store. Port useful regressions, remove obsolete code only after replacement coverage, update ARCHITECTURE.md to shipped behavior. Documentation-only changes need no app build.

