# Project map

Reference when locating work; not automatically loaded.

## Current implementation

Filesystem paths are project-root relative. Xcode paths prepend QdrantPhotoSweep/.

| Area | Current entry |
| --- | --- |
| App/bootstrap | Sources/QdrantPhotoSweep/App.swift; Core/Dependencies.swift |
| Preserved adapters | Sources/QdrantPhotoSweep/Services/{QdrantVectorStore,PhotoLibraryService,VisionEmbeddingService}.swift |
| Image helpers | Sources/QdrantPhotoSweep/Utilities/PHAssetExtensions.swift; Features/Review/{PhotoCardView,FullscreenPhotoView}.swift |
| Old orchestration | Sources/QdrantPhotoSweep/Features/Scan/{ScanPipeline,ScanInteractor,ScanState}.swift |
| Old lifecycle | Sources/QdrantPhotoSweep/Services/{ContinuousScanCoordinator,ScanExecutionController,BackgroundTaskManager,BackgroundScanService}.swift |
| Metadata/contracts | Sources/QdrantPhotoSweep/Core/Persistence/; Core/Protocols/ |
| Retained presentation | Sources/QdrantPhotoSweep/DesignSystem/; Features/Review/; Resources/Localizable.xcstrings |
| Settings/grid to replace | Sources/QdrantPhotoSweep/Features/Settings/; Features/GroupGrid/ |
| Existing tests | Tests/ScanLifecycleTests.swift (Swift Testing) |
| Xcode project/scheme | QdrantPhotoSweep.xcodeproj; shared scheme QdrantPhotoSweep; test target QdrantPhotoSweepTests |
| SDK | Existing QdrantEdge package (outside app directory); Xcode exposes QdrantEdge/Package.swift and generated bindings |

The host deployment setting is now iOS 26. Packages/PhotoSweep contains Swift 6 module boundaries, extracted adapters/design resources and an inert SafeDI 2.2.0 validation graph. The host retains this graph without running a second engine. Legacy adapter/design originals remain until cutover. SweepDomain holds the step 4 pure policies (gate, retry, pause, component expansion, discovery/buffer, review queue/selection); SweepFeatureState holds Store/Reducer/Effect; Library/Review features hold reducers without views; SweepPersistence holds SwiftData schema v1, `SwiftDataMetadataStore` and the unwired `LegacyDataTransition`; SweepUseCases holds `VectorWriteTransaction`, `ResetLocalData`, `RecoverPendingOperations` and the unwired `VectorizationExecutor` (with `ReconcilePhotoLibrary`, `VectorizePhoto`); SweepQdrant adds `QdrantStoreProvider` (per-generation shards); SweepPhotos adds `PhotoLibraryChangeMonitor`. Step 7 adds the unwired `DiscoveryExecutor`, review/deletion use cases (`LoadNextReviewGroup`, `SkipGroup`, `CommitReviewDecision`, `ReconcileDeletion`, `LoadReviewImage`) and `ReviewClient.live`. Step 8 adds the unwired `AppLifecycleCoordinator` (SweepUseCases) and iOS adapters `BackgroundTaskScheduler` / `UserNotificationReviewNotifier` (SweepSystem). Settings and onboarding targets are scaffolds. See docs/implementation/step-3.md, step-4.md, step-5.md, step-6.md, step-7.md and step-8.md for validation status. The package's macOS declaration supports host-side tests, not a Mac app.

## Package target graph

| Target | Responsibility | Direct dependencies |
| --- | --- | --- |
| SweepDomain | Models, IDs/errors, contracts, policies | Foundation as needed |
| SweepUseCases | Application/business workflows | SweepDomain |
| SweepQdrant | SDK mapping, shard owner | SweepDomain, QdrantEdge |
| SweepPhotos | Photo access, images, observation, deletion | SweepDomain, Photos/image frameworks |
| SweepEmbeddings | Feature prints | SweepDomain, Vision/image frameworks |
| SweepPersistence | Journals, metadata/preferences/schema | SweepDomain, SwiftData |
| SweepSystem | Lifecycle/background/resource/notification adapters | SweepDomain, platform frameworks |
| SweepDesignSystem | Tokens, Liquid Glass, localization/components | SwiftUI |
| SweepFeatureState | Minimal native stores/effects | Foundation, Observation |
| SweepLibraryFeature | Vectorization/progress/pause/retry | SweepDomain, SweepUseCases, SweepFeatureState, SweepDesignSystem |
| SweepReviewFeature | Cards/comparison/preview | SweepDomain, SweepUseCases, SweepFeatureState, SweepDesignSystem |
| SweepSettingsFeature | Scope/threshold/rescan/reset/stats | SweepDomain, SweepUseCases, SweepFeatureState, SweepDesignSystem |
| SweepOnboardingFeature | Access/onboarding | SweepDomain, SweepUseCases, SweepFeatureState, SweepDesignSystem |
| SweepComposition | Generated graph, feature factories, app entry | SafeDI, feature/use-case/adapter targets |
| SweepTestSupport | Deterministic fixtures/fakes | SweepDomain; test targets only |

Annotated participating targets additionally depend on SafeDI after validation; domain/policies/design system do not. Plugin placement follows the tested package-root integration.

## Use-case inventory

BootstrapApplication, RequestPhotoAccess, RecoverPendingOperations, LoadPreferences;
ReconcilePhotoLibrary, StartOrResumeVectorization, PauseVectorization, RetryVectorization, VectorizePhotoBatch, ObserveVectorization;
BeginDiscoveryRevision, RefillReviewBuffer, DiscoverNextComponent, ObserveReviewAvailability, SuspendDiscovery;
LoadNextReviewGroup, ValidateKeepSelection, SkipGroup, CommitReviewDecision, DeleteSelectedPhotos;
LoadThumbnail, LoadPreviewImage;
UpdateDateScope, UpdateSimilarityThreshold, RescanLibrary, ResetLocalData, LoadStatistics;
HandleAppActivation, HandleExecutionExpiration, EvaluateBackgroundEligibility, ScheduleVectorization, NotifyReviewReady, EvaluateWorkBudget.

## Validation entry points

- In Xcode: BuildProject for application build; discover Xcode test tools and select the QdrantPhotoSweepTests target in the shared scheme. XcodeRefreshCodeIssuesInFile is a focused diagnostic, not a full build.
- Agent rules: `python3 .agents/validate.py` checks traceability, links, wrappers and relocatability. It does not verify app behavior or editor runtime loading.
- Baseline evidence is in docs/baseline/README.md: simulator build/launch/UI capture succeeded and 13/13 existing Swift Testing tests passed on iPhone 17, iOS 27.0.1. This does not establish device performance or scheduling behavior.
- CLI fallback when Xcode tools are unavailable: `xcodebuild -project QdrantPhotoSweep.xcodeproj -scheme QdrantPhotoSweep -showdestinations`, then build/test with an actual available destination ID. This fallback has not been executed in this milestone; do not invent a simulator name.
- Package validation: `swift test --package-path Packages/PhotoSweep`; iOS-only tests additionally require an iOS destination. `python3 Scripts/check-module-boundaries.py` checks dependency direction. See docs/implementation/step-3.md, step-4.md, step-5.md, step-6.md, step-7.md and step-8.md for actual results and limitations.
