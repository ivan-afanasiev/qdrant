# PhotoSweep agent entry

Build an iPhone photo-similarity app using the agreed rewrite requirements. Paths below are relative to the PhotoSweep project root, including when this file is read through a symlink.

## Before editing

Read only the applicable rule files from this table; cross-cutting changes require multiple files. Do not automatically read the full plan, all rules or the requirement map. If this entry is already loaded, do not reload it through another tool alias.

| Task | Read |
| --- | --- |
| Modules, use cases, state, concurrency, DI | .agents/rules/architecture.md |
| Photos, embeddings, indexing, scope/settings | .agents/rules/vectorization.md |
| Similarity search, buffer, cards, selection/deletion | .agents/rules/discovery-review.md |
| Storage, recovery, background, pause, reset, stats | .agents/rules/persistence-lifecycle.md |
| SwiftUI, design, navigation, images | .agents/rules/ui.md |
| Any business logic change or tests | .agents/rules/testing.md |
| Scale, heat, resource scheduling | .agents/rules/performance.md |
| Instructions or tool configuration | .agents/rules/maintenance.md; .agents/tooling.md |

Read .agents/project-map.md to locate current code and validation entry points. Planned SPM modules are not implemented yet. ARCHITECTURE.md describes old code, not the target behavior.

## Non-negotiable boundaries

- iPhone/iOS 26+ target; SPM, use cases, native unidirectional state; Swift Testing for unit/integration tests.
- Preserve Qdrant SDK integration, Photos loading, Vision/cosine and SwiftData. SafeDI requires an early validation milestone.
- Vectorization may run foreground/background. Discovery is foreground-only and maintains 2–3 ready groups after the initial vectorization pass. Deferred assets and later arrivals have explicit exceptions: read scoped rules.
- Thumbnails for processing/cards; full resolution only for preview. Card review only; remove grid in the rewrite.
- Never confuse unavailable access with deleted photos, or report cross-store operations complete before durable recovery requirements are met.
- Do not implement beyond the requested step. Keep rules synchronized when accepted requirements change.

## Working conventions

Use Xcode project tools when available, BuildProject for app builds, and DocumentationSearch for current Apple APIs. Otherwise use targeted rg searches. Use 4-space Swift indentation, PascalCase types, camelCase members, private SwiftUI state and explicit types; avoid force unwraps. Prefer async/await over Combine.

Run relevant checks from testing.md/project-map.md; report actual results and untested limitations. Edit canonical .agents files rather than symlink aliases. Detailed requirement traceability is in .agents/requirements.md; rationale and sequencing are in REWRITE_PLAN.md. Read those only for ambiguity or coverage audits.

