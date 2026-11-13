# Step 3 — SPM boundaries and SafeDI validation (draft, 2026-11-13)

Step 3 of REWRITE_PLAN.md §10: create the iOS 26 package targets, extract preserved adapters/design system and run the minimal SafeDI milestone from §4.2. The legacy engine remains active; the rewrite graph is retained by the host but inert.

## Delivered

- `Packages/PhotoSweep` (Swift 6 language mode) with the 15 targets from REWRITE_PLAN.md §4 and dependency directions matching that table.
- App and package deployment floor iOS 26.0. The package's macOS 14 platform only enables host-side tests.
- Extracted adapters: `SweepQdrant` (SDK mapping, cosine configuration; blocking shard-load retries and dimension-driven rebuilds intentionally omitted), `SweepPhotos` (asset/image loading, request cancellation, deletion), `SweepEmbeddings` (Vision feature prints). Contracts live in `SweepDomain`. Legacy originals remain in the host until cutover.
- `SweepDesignSystem` with tokens, components and `Localizable.xcstrings`; strings resolve through the package bundle.
- SafeDI pinned `exact: "2.2.0"`, default `prebuilt` trait; `SafeDIGenerator` plugin only on `SweepComposition`. `SweepDomain`, `SweepDesignSystem`, `SweepFeatureState` and `SweepTestSupport` have no SafeDI dependency.
- Inert graph: `PhotoSweepComposition` (root, `@MainActor`) → `BootstrapApplication` (use case) → `BootstrapResource` contract fulfilled by `BootstrapProbe` (`SweepSystem`) → `LibraryStore` (main-actor feature store via `Instantiator`). The host holds the root as a stored property of the `App` struct, outside `body`.
- `Scripts/check-module-boundaries.py` enforces manifest dependency direction, forbidden imports (recursive), SafeDI-free targets, Swift Testing–only test targets and declared test imports, and fails on targets missing from its map.

## Validation results

Environment: Xcode 27.2 (27B52), Apple Swift 6.4.2, macOS host arm64. Simulators: iPhone 17 iOS 26.5 (`7653498E-…`) and iPhone 17 iOS 27.0 (`3E3503B6-…`).

| Check | Result |
| --- | --- |
| `python3 Scripts/check-module-boundaries.py` | PASS — 15 production/test-support boundaries, 5 test targets. Injected violations (nested SwiftUI import in Domain, XCTest import, undeclared test import, SafeDI on Domain, unknown target) all reported |
| `python3 .agents/validate.py` | PASS |
| `swift test --package-path Packages/PhotoSweep` (macOS) | PASS — Composition 3/3, Qdrant 1/1; iOS-conditional suites compile out |
| `xcodebuild test -scheme PhotoSweep`, iOS 26.5 sim | 7/8 pass — Composition 3/3, Qdrant 1/1, Localization 1/1, PhotoImageRequest 2/2; Vision 0/1 (see limitations) |
| `xcodebuild test`, app scheme `QdrantPhotoSweep`, iOS 26.5 and 27.0 sims | App builds with the package linked; legacy suite 12/13, `visionFeaturePrintRunsWithSelectedComputeDevices` fails (see limitations) |
| Xcode BuildProject | Initially blocked ("Plugin “SafeDIGenerator” … must be enabled"); succeeds after trusting the plugin in Xcode |

Initial CLI runs used per-invocation `-skipPackagePluginValidation -skipMacroValidation`; after the plugin was trusted in Xcode, the same results reproduce without those flags. No global validation setting was changed.

The iOS-conditional package tests were first run in this validation; `VisionEmbeddingTests` initially failed to compile (`allSatisfy(\.isFinite)` inside `#expect`) and was fixed.

## §4.2 checklist status

| Item | Status |
| --- | --- |
| 1. Graph spans contract, adapter, use case, main-actor store with root in SweepComposition | **Accepted with stub**: `BootstrapProbe` stands in for the adapter. Real Qdrant/Photos/Vision adapters are not yet `@Instantiable` or in the graph; wiring them is deferred to the slices that consume them |
| 2. Protocol fulfillment, generated-code visibility, concurrency diagnostics | Verified for the stub graph: `fulfillingAdditionalTypes` binding, generated public `init()` usable from the host and tests, Swift 6 mode builds without diagnostics in package targets |
| 3. Foreground/background share app-scoped instances; feature stores separate | Partial: separate `LibraryStore` instances and shared resource are tested. `foregroundEntry`/`backgroundEntry` both return the same property and no background entry point exists yet, so the shared-instance test is not meaningful evidence |
| 4. Bootstrap failure/retry without duplicate shard owners; independent test graphs | Partial: retry retains one resource and independent roots don't share resources, but retry is tested on a directly constructed use case, not through the graph, and no shard owner is involved |
| 5. Clean/incremental/Release builds, package tests, plugin setup docs | Partial: Debug simulator builds and package tests run; plugin setup is documented in `Packages/PhotoSweep/README.md`. Release build, build-time cost and inspection of generated wiring are **not recorded** |

## Limitations and open items

- **Vision on simulator.** Both the extracted `VisionEmbeddingService` and the unchanged legacy service fail with `Failed to create espresso context` on iOS 26.5 and 27.0 simulators. The step 2 baseline passed 13/13 on a physical iPhone 17 only, so this test has no simulator pass on record. Treat Vision tests as device-only until verified; not attributed to step 3 changes.
- **QdrantEdge deployment mismatch.** Linking emits `ld` warnings: C/assembly objects compiled by the `cc` crate inside `libqdrant_edge_ffi.a` were stamped with the SDK version (iOS 27.1, macOS 27.0) while targets link at 26.0. `lib/edge/swift/build-xcframework.sh` now exports deployment targets matching QdrantEdge's `Package.swift` (iOS 15, macOS 13) and fails if any object requires a newer OS. **Resolved:** after the rebuild, the newest minimum OS in each slice is iOS 15.0, iOS simulator 15.0 and macOS 13.0. Package and app test builds on iOS 26.5 emit no "built for newer version" warnings.
- **Dependency pinning.** `Package.resolved` is ignored by `lib/edge/swift/.gitignore`; only SafeDI's exact manifest pin is committed. Transitive swift-syntax is unpinned.
- **Xcode plugin trust.** Each developer must trust the SafeDI plugin/macros once; CI needs per-invocation skip flags or a pre-trusted environment.
- Not validated: Release configuration, physical-device runs of the package, build-time cost, generated source review, and Claude/Cursor session loading (carried over from step 1).

## Exit assessment

Step 3 exit criteria from REWRITE_PLAN.md §10 — DI checks pass with a pinned release; app builds; resources/localization resolve; dependency direction is enforced. The pinned release, app build, localization and dependency enforcement are met on simulator. The DI checks are met only for the inert stub graph, which the owner has accepted for this step; the gaps above move to the slices that introduce real adapters and the background entry point.
