# persistence lifecycle rules

Classification: C = confirmed product requirement; T = planned technical constraint; V = validation parameter/milestone. IDs map to .agents/requirements.md; source is REWRITE_PLAN.md.

## LIFE-01 (C) — Metadata

Use redesigned SwiftData repositories: assets/content/vector/embedding/outcome; vectorization scope/work/checkpoints/deferrals; discovery threshold/generation/cursor/frontier; groups/memberships/decisions/skip queue; operation journals and confirmed stats events. Transport values, not persistence objects.

## LIFE-02 (T) — Cross-store journal

Qdrant and metadata have no shared transaction. Journal intent → external write → metadata/checkpoint commit → close journal. Replay idempotently at each boundary; never report durable completion early. Coordinate short mutations/generation publication/reset/deletion; no global lease across whole passes, downloads or user input.

## LIFE-03 (C) — Pause

Pause checkpoints and persists suppression of foreground/background automatic vectorization until Resume or next app opening. Activation and explicit Retry clear manual pause. System interruption is distinct and resumable. No user Cancel control; internal cancellation remains for replacement/reset/expiration. Cancel in the system's continued-processing Live Activity counts as manual pause.

## LIFE-04 (C) — Background

Support continued foreground vectorization and automatic iOS-scheduled work using one executor/shard graph. Background discovery is forbidden; suspend/checkpoint its frontier on background entry. Thin adapters register/schedule/report completion and expiration; checkpoint on expiry. Background Vision never uses the GPU: Neural Engine when available, else CPU (the CPU-only model variant can be missing on device); scheduled processing does not require external power. Activation reconnects observations and refills only when gate permits.

## LIFE-05 (V) — System eligibility

Verify iOS 26 API eligibility for automatic versus user-initiated continuation. BGContinuedProcessingTask is submitted only for explicit user actions that start or restart vectorization (first start, Resume, Retry, Rescan) and must report progress; automatic passes use a short background grace period and BGProcessingTask. Balance every execution opportunity with completion; duplicate handlers cannot launch competing passes. Never promise immediate/indefinite execution or execution after force-quit.

## LIFE-06 (C) — Notifications

Notify once per eligible completed background pass when authorized: photos ready for review, not groups discovered. Deferred photos do not block readiness after pass completion. Handle denied notification authorization without failing vectorization.

## LIFE-07 (C) — Clean start/reset

No legacy migration required: versioned local namespace and idempotent bootstrap transition retire old index/metadata/preferences/history/review data, never photos. Until cutover (step 10) the rewrite ignores legacy data and the transition stays unwired; a debug-only launch switch may select the legacy engine, never both engines at once. Reset stops mutations, invalidates effects and coherently clears index/compatibility/metadata/checkpoints/review state. Reconcile external deletion journals before retirement; reset is restartable.

## LIFE-08 (C) — Statistics

Show vectorized/unavailable photos, reviewed groups, deleted photos and estimated storage freed through a use case. Use durable outcomes and confirmed events with scope/generation IDs; no retry/reset double counting. Unknown byte sizes stay unknown; savings are estimates, not immediately reclaimed device storage.

