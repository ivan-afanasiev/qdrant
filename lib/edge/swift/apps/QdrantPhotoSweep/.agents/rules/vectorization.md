# vectorization rules

Classification: C = confirmed product requirement; T = planned technical constraint; V = validation parameter/milestone. IDs map to .agents/requirements.md; source is REWRITE_PLAN.md.

## VEC-01 (C) — Triggers/cache

Start automatically on launch and new/changed photos in selected scope, but only after onboarding completes (no scope is chosen before Start). Reconcile identity/content revisions; reuse valid compatible vectors. Capture an initial work set or stable cursor. Commit eligible vectors before discovery can consume them.

## VEC-02 (C) — Initial gate

Initial review/discovery waits until every scoped photo is successfully vectorized or explicitly deferred. Show unavailable counts. Later arrivals during review do not reopen this gate or block current cards; make committed new vectors eligible for foreground discovery.

## VEC-03 (C) — Failure policy

Retry temporary failures finitely, preserving progress; inject clock and classify errors. Defer individually unavailable photos after applicable attempts and continue. Systemic store/model failures stop the pass and expose Retry after applicable attempts; do not mislabel every photo unavailable or loop indefinitely. Only per-asset load failures defer; transient infrastructure failures count toward the systemic limit. Retry limits are validation parameters.

## VEC-04 (C) — Photos/images

Preserve Photos queries, cancellable thumbnail requests and full-image preview behavior. Vectorization uses thumbnails only. Review cards show a thumbnail first and then load the original once presented (with a loading indicator); preview loads the original. Allow required iCloud downloads on Wi-Fi/cellular. Do not download originals merely to estimate bytes saved.

## VEC-05 (T) — Compatibility/identity

Track embedding model/revision, preprocessing and dimensions. Use stable collision-aware vector identity. Replace silent dimension-driven shard deletion with a recoverable index-generation transition coordinated with metadata. Point existence alone is not successful vectorization; follow persistence journal rules.

## VEC-06 (C) — Settings

Threshold changes immediately invalidate pending cards/effects, reuse vectors, reset review/skip decisions and restart foreground discovery subject to initial gate. Rescan reconciles scope, vectorizes new/changed photos, then starts fresh discovery/review order with reusable vectors. Date-range changes retire obsolete discovery and start a scoped pass with reuse. Never restore deleted photos.

## VEC-07 (T) — Library reconciliation

Reconcile edits/removals/access changes and invalidate affected snapshots. Distinguish inaccessible from confirmed deleted. Newly indexed matches must respect completed-group suppression in discovery-review.md.

