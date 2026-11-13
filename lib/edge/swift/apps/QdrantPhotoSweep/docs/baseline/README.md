# Rewrite baseline — 2026-11-12

This is step 2 (Establish the baseline), following shared agent rules. Application code and dependency configuration are unchanged. This directory separates observed evidence from future validation.

## Evidence

- Source revision: `1f4dd09bb8189e023ce2c1d495924ef72d55c17d`; working tree was clean at baseline start.
- Xcode 27.2 (27B52); xctrace 27.2 (27B52).
- Current project: iPhone-only, deployment setting iOS 17.0, Swift language setting 5.0. The rewrite targets iOS 26+; that migration has not happened.
- Simulator app build/launch and screenshots: see [UI evidence](ui-evidence.md).
- Existing tests: **13/13 passed**, none skipped, on physical iPhone 17 (iPhone18,3), iOS 27.0.1 (24A446). See [regression map](regression-map.md), [execution result](artifacts/test-results.json) and [test summary](artifacts/test-summary.txt). The 0.176s suite duration is test timing, not a scan-performance measurement.
- Preserved code and deliberate replacements: [preservation inventory](preservation-inventory.md).
- Repeatable measurements and outstanding device work: [measurement protocol](measurement-protocol.md).
- Machine-readable source/resource hashes and test discovery: artifacts/source-manifest.json and artifacts/test-inventory.json.

## Current limits

A paired physical iPhone was initially offline, then became available for the test run. No thermal, battery, throughput or background-scheduler result is inferred from passing tests or simulator execution. Device performance results are tracked separately in [measurement-results.csv](measurement-results.csv). The protocol is ready; physical performance acceptance is not established. Physical device-interaction session attempts were rejected even though Xcode could run tests. The later process-discovery attempt was interrupted before a result was collected; no profiling trace was produced.

On 2026-11-13, a fresh retry confirmed the physical phone is an eligible active Xcode destination, but workspace Device Interaction explicitly supports only simulators on OS 27.0+. Physical UI inspection remains blocked by that tool limitation; see [UI evidence](ui-evidence.md).

Source inspection identifies potential costs (whole asset-list loading, per-batch group recomputation, UI-state polling and synchronous work); it does not prove which causes the reported heat. Do not use this baseline as a performance diagnosis.

The existing suite covers 13 tests, not all business logic. New rules change some old semantics, so preserve the useful invariants rather than mechanically porting every assertion. No new architecture or implementation tests are added in this baseline-only step.

## Final artifact validation (2026-11-13)

All 86 source/resource hashes still match the pre-rewrite snapshot. All 13 discovered tests map to passing recorded results and the regression inventory. Relative document/artifact links and the agent-rule validator pass. Application code, test implementations, project configuration and dependencies remain unchanged. Step 2’s inventory, regression map and measurement protocol are delivered; physical performance measurements remain explicitly outstanding.
