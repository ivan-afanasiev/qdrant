# discovery review rules

Classification: C = confirmed product requirement; T = planned technical constraint; V = validation parameter/milestone. IDs map to .agents/requirements.md; source is REWRITE_PLAN.md.

## REV-01 (C) — Discovery

Discover only in foreground after the initial gate. Search committed compatible vectors; query seeds AND candidates must satisfy the date range. Use an inclusive cosine threshold (score ≥ threshold, 0–1) and inclusive date bounds; undated assets are outside every scope. Use connected components: A–B–C can be one group without A–C matching. Do not claim exact equality or all-pairs similarity.

## REV-02 (C) — Ready buffer

Keep 2–3 unreviewed groups including current card. Review/skip triggers refill. Pause discovery when full, truly exhausted or backgrounded; never pause vectorization because buffer is full. An empty buffer is not exhaustion. Skipped groups do not count toward the buffer.

## REV-03 (T) — Lazy algorithm

Use a durable seed order, newest photos first (creation date descending), and a deduplicated component frontier. Fully expand a component against its captured eligible generation before publication; transactionally save group/membership/progress. Persist/spill frontier for large groups, resume after interruption. No eager whole-library recomputation on each refill. Route later vectors into subsequent discovery work.

## REV-04 (V) — Search completeness

Validate SDK retrieval capabilities and use completeness-aware expanded/paged neighborhoods. Top-10 is not complete. Record practical limits and test them; do not silently split chains. Buffer size limits ready groups, not search work or member count.

## REV-05 (C) — Skip

Skip is durable deferral, not completion/protection. Persist before advancing; on failure retain card. Show all other eligible groups, including undiscovered ones, before deferred groups; cycle deferred groups in durable order without duplicate queue entries.

## REV-06 (C) — Suppression

Completed groups stay suppressed when new photos match until explicit rescan/threshold reset. Track reviewed membership/lineage so regenerated IDs cannot bypass decisions. Skipped groups still follow deferral. Existing review continues during incremental vectorization.

## REV-07 (T) — Group identity/conflicts

Use durable IDs and membership revisions/merge-split lineage, not wholesale group replacement. Keep open-card snapshot/selection stable. Validate revision and availability on commit; missing/stale groups produce visible conflict/refresh, never silent success. Retire obsolete cards on threshold/rescan; reconcile in-flight deletions despite old revisions.

## REV-08 (C) — Selection

Start with no keep selection. Permit explicit delete-all; favorites get no special protection. Empty selection never triggers deletion itself. Keep-all completes review; Skip only defers.

## REV-09 (T) — Deletion

Validate exact selection/revision/authorization/access; persist operation ID and intended assets plus statistics metadata; request Photos deletion; record confirmed outcome; reconcile vectors/assets/edges/groups/queue; commit review/stats exactly once then refill. On user rejection retain card and count nothing.

## REV-10 (T) — Deletion recovery

After Photos succeeds, downstream failure is recoverable cleanup, not blind repeated deletion. Reconcile uncertain outcomes; limited access is not proof of deletion. Retain journal until cleanup completes; late old-revision results still reconcile.

