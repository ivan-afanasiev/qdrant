# Project map

Reference when locating work; not automatically loaded. Paths are project-root relative; Xcode paths prepend QdrantPhotoSweep/. Architecture: ARCHITECTURE.md. Decisions and lessons: docs/implementation/README.md.

## Where things are

| Area | Entry |
| --- | --- |
| App target | Sources/QdrantPhotoSweep/App.swift (engine switch), Info.plist (BGTask identifiers, background modes) |
| Composition | Packages/PhotoSweep/Sources/SweepComposition/ (`PhotoSweepComposition`, `RewriteBootstrap`, `AppRuntime`, `FeatureFactories`, `LivePlatform`) |
| Executors | Packages/PhotoSweep/Sources/SweepUseCases/{VectorizationExecutor,DiscoveryExecutor,AppLifecycleCoordinator}.swift |
| Use cases | SweepUseCases/{VectorizationSteps,ReviewUseCases,PreferenceUseCases,LocalDataOperations}.swift |
| Persistence | Packages/PhotoSweep/Sources/SweepPersistence/ (SchemaV1, `SwiftDataMetadataStore` + extensions, `LegacyDataTransition`) |
| Adapters | SweepPhotos, SweepEmbeddings, SweepQdrant, SweepSystem (`BackgroundTaskScheduler`) |
| Features | Sweep{Onboarding,Library,Review,Settings}Feature (reducer + view each) |
| Strings | Packages/PhotoSweep/Sources/SweepDesignSystem/Resources/Localizable.xcstrings (en/de/es/ru); add keys with Scripts/add-strings.py |
| Tests | Packages/PhotoSweep/Tests/ (17 targets); fakes in SweepTestSupport |
| Test photos | Scripts/test-photos/ (fake libraries with known duplicate groups) |
| Legacy (removed at cutover) | Sources/QdrantPhotoSweep/ except App.swift; LegacyEngine.swift; Tests/ScanLifecycleTests.swift |
| Xcode | QdrantPhotoSweep.xcodeproj, scheme QdrantPhotoSweep; package scheme PhotoSweep |
| SDK | QdrantEdge package outside the app directory (lib/edge/swift) |

## Package target graph

Enforced by `python3 Scripts/check-module-boundaries.py`.

| Target | Responsibility | Direct dependencies |
| --- | --- | --- |
| SweepDomain | Models, IDs/errors, contracts, policies | Foundation |
| SweepUseCases | Workflows and executors | SweepDomain |
| SweepQdrant | SDK mapping, per-generation shards | SweepDomain, QdrantEdge |
| SweepPhotos | Photo access, images, change monitor, deletion | SweepDomain, Photos |
| SweepEmbeddings | Vision feature prints | SweepDomain, Vision |
| SweepPersistence | SwiftData schema, journals, metadata | SweepDomain, SwiftData |
| SweepSystem | BackgroundTasks, grace windows, notifications | SweepDomain, platform frameworks |
| SweepDesignSystem | Tokens, Liquid Glass, localization | SwiftUI |
| SweepFeatureState | Store/Reducer/Effect | Foundation, Observation |
| Sweep*Feature | Onboarding, Library, Review, Settings | SweepDomain, SweepUseCases, SweepFeatureState, SweepDesignSystem |
| SweepComposition | SafeDI root, runtime, factories, root views | SafeDI, all of the above |
| SweepTestSupport | Deterministic fakes | SweepDomain; test targets only |

## Validation

- App: BuildProject in Xcode (or `xcodebuild -project QdrantPhotoSweep.xcodeproj -scheme QdrantPhotoSweep`).
- Package: `swift test --package-path Packages/PhotoSweep` (macOS); iOS: `xcodebuild test -scheme PhotoSweep -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'` from Packages/PhotoSweep. Vision tests run only on devices.
- Boundaries: `python3 Scripts/check-module-boundaries.py`. Agent rules: `python3 .agents/validate.py` (traceability and links, not app behavior).
- Device baseline and measurement protocol: docs/baseline/.
