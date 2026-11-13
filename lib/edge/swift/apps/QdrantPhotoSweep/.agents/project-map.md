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

Observed project deployment settings still include iOS 17.0; iOS 26 is the rewrite target, not a completed migration. No Packages/PhotoSweep package or SafeDI integration exists at this milestone.

## Planned target graph

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
| SweepLibraryFeature | Vectorization/progress/pause/retry | SweepUseCases, SweepFeatureState, SweepDesignSystem |
| SweepReviewFeature | Cards/comparison/preview | SweepUseCases, SweepFeatureState, SweepDesignSystem |
| SweepSettingsFeature | Scope/threshold/rescan/reset/stats | SweepUseCases, SweepFeatureState, SweepDesignSystem |
| SweepOnboardingFeature | Access/onboarding | SweepUseCases, SweepFeatureState, SweepDesignSystem |
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
- No root `swift test` command applies yet. Record verified package test commands when SPM targets are created.
