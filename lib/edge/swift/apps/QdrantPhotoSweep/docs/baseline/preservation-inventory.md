# Preservation and extraction inventory

Paths below are relative to Sources/QdrantPhotoSweep unless stated otherwise. Source snapshot/hashes are recorded in artifacts/source-manifest.json. This inventory describes observed code, not proof of runtime correctness.

| Area | Current source / symbol | Preserve | Deliberate replacement / extraction check |
| --- | --- | --- | --- |
| Qdrant ownership/config | Services/QdrantVectorStore.swift; ensureShard | One actor-owned EdgeShard; unnamed dense vector; cosine distance; lazy load and close | App-scoped DI ownership; no second background shard; remove silent dimension-only reset policy |
| Qdrant writes | QdrantVectorStore._upsert / _delete | UUID PointId mapping; single vector; JSON payload; UpdateOperation SDK calls | Journal cross-store work; preserve errors; verify idempotent replay with real temporary shard |
| Qdrant queries | _search / _scroll / _count / _exists | SDK request/result mapping; threshold, pagination token, payload flags and exact count request | Existing search lacks scope filter and offset; top-10 pipeline cap is not complete. Validate existence/scroll semantics and missing IDs with real SDK tests |
| Qdrant startup | loadShardWithRetry / updateDimensions | Working SDK loading integration | Current string-matched lock retry blocks with Thread.sleep; marker writes/removal suppress errors. Rework lifecycle/retry policy, not SDK bindings |
| Photos authorization/query | Services/PhotoLibraryService.swift | Read-write authorization; authorized/limited accepted; image assets; inclusive creation-date range, newest first | Keep limited-access semantics; add use-case boundary/change reconciliation and bounded enumeration contract |
| Metadata conversion | Utilities/PHAssetExtensions.swift; toPhotoAsset | localIdentifier, creation date, pixel dimensions | fileSize currently nil; estimates must stay unknown until supported metadata is available |
| Request bridge | PHAssetExtensions.swift; PhotoImageRequest | Lock-protected exactly-once continuation and request-ID/cancellation handling | Retain race tests; add late request-ID and real request cancellation coverage during extraction |
| Image requests | loadCGImage / loadHighQualityCGImage / requestCGImage | Fast/aspectFill versus highQuality/exact/aspectFit; async network-enabled requests; ignore degraded callbacks | Errors currently wrap cancellation into typed AppError; preserve cancellation signal to caller without breaking semantics |
| Pipeline images | Features/Scan/ScanPipeline.swift | 224×224 thumbnail passed to embeddings | Pipeline/state/coordinator coupling is replaced; never request full-resolution originals for indexing |
| Card images | Features/Review/PhotoCardView.swift; loadImages | Fast 300×300 image, then display-sized HQ request capped at 1200 on each axis; aspect ratio, selection/date/preview controls | State name fullImage does NOT imply original-size request. Keep bounded presentation loading behind use cases; small assets may already fit requested bounds |
| Preview | Features/Review/FullscreenPhotoView.swift | Asset pixel-dimension HQ request only on explicit preview; thumbnail fallback; fit/zoom/pan/double-tap/dismiss | Move loading behind use case; surface unavailable state; retain transient gesture state |
| Embeddings | Services/VisionEmbeddingService.swift | VNGenerateImageFeaturePrintRequest; Float feature data; detected dimensions; errors retain Vision domain/code | Current background CPU-device choice is inspected, not device-validated; lifecycle policy becomes injected/testable; track model/preprocessing compatibility |
| Cards/compare | ReviewCardStack, GroupComparisonView, PhotoCardView, ReviewSubviews | Tinder-like interaction/presentation, scrolling group comparison, shared state views | No preselected keep; explicit delete-all; defer Skip; versioned groups; replace delayed DispatchQueue business callbacks with state/effects |
| Design system | DesignSystem/QColors, QTypography, QLayout, QIcons, QAnimation, QComponents | Tokens, branded colors, spacing, typography hierarchy, icon vocabulary and motion character | Complete Liquid Glass treatment centrally; retain legibility/accessibility; no wholesale redesign |
| Resources | Assets.xcassets; Resources/Localizable.xcstrings; DesignSystem/L10n.swift | App icon, accent color, localized keys | Move owned resources to SPM bundles and update lookups; legacy scan/grid copy needs behavioral review |
| Grid | Features/GroupGrid | None of the standalone grid mode is required | Remove toggle/routes/grid-specific state/pagination; retain group comparison used by cards |
| Old workflows | ScanPipeline, ScanInteractor, coordinators/background services, SwiftDataScanStore orchestration | Regression invariants only | Separate vectorization/discovery; journals, stable revisions, bounded buffer, native state/use cases, new reset policy |

## Concrete visual anchors

- Brand colors include amaranth #DC244C, violet #8547FF, blue #2F6FF0 and teal #038585.
- Spacing scale: 2, 4, 8, 12, 16, 20, 24, 32, 48. Corner radii: 6, 8, 12, 16, 20 and pill.
- Default spring: response 0.4, dampingFraction 0.8. Other transitions: easeInOut 0.3 and 0.15.
- Card swipe source uses 30% screen-width threshold or predicted translation beyond ±500, rotation offset/30, and 0.25s exit. These describe visual baseline, not new immutable business requirements.
- Preview double-tap toggles 1×/3×; magnification settles between 1× and 6×.
- Localization catalog has 117 keys; source language en; entries include de/en/es/ru.
- Custom retained views currently use ultraThinMaterial and solid button styles; no explicit glassEffect/glass button modifiers were found. System controls may still receive platform styling, so source search alone is not a visual audit.

## Extraction acceptance checklist

- [ ] Qdrant mapping parity proven with a temporary real shard (upsert/search/scroll/count/delete/reopen and absent IDs).
- [ ] Photos authorization/range/cancellation and image request behavior characterized behind the extracted adapter.
- [ ] Recording image fake distinguishes bounded card images from full-resolution preview.
- [ ] Vision smoke test passes on each supported device tier; background compute behavior checked physically.
- [ ] App icon, accent, all localized resources and preview lookups survive package extraction.
- [ ] Card/preview gestures and retained screen states compared to evidence; intended selection/grid/Liquid Glass changes accounted for.

These checks belong to subsequent extraction work. Existing test coverage is described separately; unchecked items are not implied to pass.
