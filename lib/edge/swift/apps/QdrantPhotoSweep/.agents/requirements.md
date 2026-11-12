# Requirement coverage map

Reference only; do not load automatically. Each ID has one canonical owner. C = confirmed product behavior; T = planned technical constraint; V = validation parameter/milestone, not a completed implementation. Source numbers refer to REWRITE_PLAN.md sections or Q decisions. Rules specify details and exceptions; this table routes validation.

| ID | Class | Plan source | Owner | Implementation area | Verification |
| --- | --- | --- | --- | --- | --- |
| ARC-01 | C | 1; Q4–Q7; 4 | [architecture](rules/architecture.md) | Platform/modules | Build manifests enforce targets |
| ARC-02 | T | 4 | [architecture](rules/architecture.md) | Module graph | Import/dependency audit |
| ARC-03 | C | 1; Q5; 5 | [architecture](rules/architecture.md) | Business/state | Reducer and use-case tests |
| ARC-04 | T | 5; 6.1 | [architecture](rules/architecture.md) | Concurrency | Late-event/cancellation tests |
| ARC-05 | T | 5; 6.1 | [architecture](rules/architecture.md) | Errors/states | Transition/error tests |
| ARC-06 | V | 4.1–4.2 | [architecture](rules/architecture.md) | SafeDI adoption | Minimal cross-module build milestone |
| ARC-07 | T | 4.1 | [architecture](rules/architecture.md) | DI graph | Composition/import tests |
| ARC-08 | T | 4.1–4.2 | [architecture](rules/architecture.md) | DI lifetime/bootstrap | Identity/bootstrap/retry tests |
| ARC-09 | T | 4; 5 | [architecture](rules/architecture.md) | Resources/use cases | Build/preview and contract inventory |
| VEC-01 | C | Q7; Q13; 6.2 | [vectorization](rules/vectorization.md) | Triggers/cache | New/edited/reused-vector tests |
| VEC-02 | C | Q3; Q14; 6.2 | [vectorization](rules/vectorization.md) | Initial gate | Gate/deferred/incoming tests |
| VEC-03 | C | Q13–Q14; 5; 6.2 | [vectorization](rules/vectorization.md) | Failure policy | Clock-controlled retry tests |
| VEC-04 | C | 1; 3; Q14; 6.2 | [vectorization](rules/vectorization.md) | Photos/images | Recording image fake + device checks |
| VEC-05 | T | 6.2 | [vectorization](rules/vectorization.md) | Compatibility/identity | Mismatch/collision/replay tests |
| VEC-06 | C | Q11; 6.4 | [vectorization](rules/vectorization.md) | Settings | Scope/revision/rescan tests |
| VEC-07 | T | 6.4 | [vectorization](rules/vectorization.md) | Library reconciliation | Access/edit/removal tests |
| REV-01 | C | Q1; Q3; Q8–Q9; 6.3 | [discovery-review](rules/discovery-review.md) | Discovery | Scope/chain/foreground tests |
| REV-02 | C | Q3; 6.3 | [discovery-review](rules/discovery-review.md) | Ready buffer | Capacity/refill/exhaustion tests |
| REV-03 | T | 6.3 | [discovery-review](rules/discovery-review.md) | Lazy algorithm | Frontier/restart/large-component tests |
| REV-04 | V | 6.3 | [discovery-review](rules/discovery-review.md) | Search completeness | SDK capability + >10-hit/chain fixtures |
| REV-05 | C | Q10; 7 | [discovery-review](rules/discovery-review.md) | Skip | Ordering/persistence failure tests |
| REV-06 | C | 2 supplemental decisions; Q11; 6.4; 7 | [discovery-review](rules/discovery-review.md) | Suppression | Incremental-match/reset tests |
| REV-07 | T | 6.4; 7 | [discovery-review](rules/discovery-review.md) | Group identity/conflicts | Same-count/merge/split/stale tests |
| REV-08 | C | Q12; 7 | [discovery-review](rules/discovery-review.md) | Selection | Empty/keep-all/delete-all tests |
| REV-09 | T | 7 | [discovery-review](rules/discovery-review.md) | Deletion | Failure at every boundary |
| REV-10 | T | 7 | [discovery-review](rules/discovery-review.md) | Deletion recovery | Crash/unknown-outcome tests |
| LIFE-01 | C | Q6; 6.1; 7 | [persistence-lifecycle](rules/persistence-lifecycle.md) | Metadata | SwiftData transaction/reopen tests |
| LIFE-02 | T | 6.1–6.2 | [persistence-lifecycle](rules/persistence-lifecycle.md) | Cross-store journal | Injected crash/replay tests |
| LIFE-03 | C | Q13; 6.1; 8 | [persistence-lifecycle](rules/persistence-lifecycle.md) | Pause | Pause/activation/expiration tests |
| LIFE-04 | C | Q1; Q13; 8 | [persistence-lifecycle](rules/persistence-lifecycle.md) | Background | Shared-executor/device lifecycle checks |
| LIFE-05 | V | 8 | [persistence-lifecycle](rules/persistence-lifecycle.md) | System eligibility | Apple docs + device validation |
| LIFE-06 | C | Q15; 8 | [persistence-lifecycle](rules/persistence-lifecycle.md) | Notifications | Authorization/dedup/device tests |
| LIFE-07 | C | Q2; 7 | [persistence-lifecycle](rules/persistence-lifecycle.md) | Clean start/reset | Reset/restart/photo-preservation tests |
| LIFE-08 | C | Q15; 7 | [persistence-lifecycle](rules/persistence-lifecycle.md) | Statistics | Confirmed/idempotent/unknown-size tests |
| UI-01 | C | Q4; Q16; 1; 3; 7 | [ui](rules/ui.md) | Presentation | UI route/design review |
| UI-02 | C | Q16; 3 | [ui](rules/ui.md) | Liquid Glass | Retained-screen/device appearance checks |
| UI-03 | T | 3; 4; 5 | [ui](rules/ui.md) | View boundary | Store/preview/image contract tests |
| UI-04 | C | Q13–Q15; 9 | [ui](rules/ui.md) | Feedback | UI journey checks |
| TEST-01 | C | 1; 9; 11 | [testing](rules/testing.md) | Framework/coverage | Test imports + unit inventory |
| TEST-02 | T | 9 | [testing](rules/testing.md) | Determinism | Async/reducer race suites |
| TEST-03 | T | 9 | [testing](rules/testing.md) | Behavior matrix | Requirement verification inventory |
| TEST-04 | T | 4.2; 9 | [testing](rules/testing.md) | Real adapters | Temporary store/device tests |
| TEST-05 | V | 9; 10; 11 | [testing](rules/testing.md) | Physical validation | Device acceptance report |
| TEST-06 | T | 10; 11 | [testing](rules/testing.md) | Delivery/cutover | Milestone checklist |
| PERF-01 | C | Q15–Q16; 3; 8 | [performance](rules/performance.md) | Scale/resource policy | 100,000+ fixtures and device report |
| PERF-02 | V | 3; 8; 10 | [performance](rules/performance.md) | Thermal/budgets | Injected thermal tests + measured budgets |
| RULE-01 | C | 1; 10.1 | [maintenance](rules/maintenance.md) | Agent context | Validator + loading report |
| RULE-02 | T | 10.1 | [maintenance](rules/maintenance.md) | Tool adapters | Symlink/format/relocation checks |
| RULE-03 | T | 10.1; 11 | [maintenance](rules/maintenance.md) | Rule maintenance | Coverage/source review |

## Source coverage audit

| Plan source | Requirements |
| --- | --- |
| 1 / 11 requirements and acceptance | ARC-01–09, VEC-01–07, REV-01–10, LIFE-01–08, UI-01–04, TEST-01–06, PERF-01–02, RULE-01–03 |
| Q1 | REV-01, LIFE-04–05 |
| Q2 | LIFE-07 |
| Q3 | VEC-02, REV-02–04 |
| Q4 | ARC-01, UI-01 |
| Q5 | ARC-03–05 |
| Q6 | LIFE-01–02 |
| Q7 | ARC-01, VEC-05 |
| Q8 | REV-01, REV-03–04 |
| Q9 | REV-01, VEC-06 |
| Q10 | REV-05 |
| Q11 | VEC-06, REV-06–07 |
| Q12 | REV-08–10 |
| Q13 | VEC-01, VEC-03, LIFE-03–05 |
| Q14 | VEC-02–04, VEC-07 |
| Q15 | LIFE-06, LIFE-08, PERF-01–02 |
| Q16 | LIFE-04–05, UI-01–02, PERF-01–02 |
| 2 supplemental arrivals and reviewed matches | VEC-02, VEC-07, REV-06–07 |
| 3 preservation, visual consistency, heat | ARC-01, VEC-04–05, UI-01–03, PERF-01–02 |
| 4 / 4.1 / 4.2 modules and DI | ARC-01–02, ARC-06–09; project-map.md target graph |
| 5 use cases/data flow | ARC-03–05, ARC-09; project-map.md use-case inventory |
| 6.1 durable state/ownership | ARC-04–05, ARC-08, LIFE-01–03 |
| 6.2 vectorization | VEC-01–05, LIFE-02 |
| 6.3 discovery | REV-01–04 |
| 6.4 settings/incremental changes | VEC-06–07, REV-06–07 |
| 7 review/deletion/reset/stats | REV-05–10, LIFE-07–08 |
| 8 background/resources | LIFE-03–06, PERF-01–02 |
| 9 test matrix | TEST-01–05 and verification column above |
| 10 sequence / 10.1 rules | TEST-06, RULE-01–03 |

All requirements are extracted, not implemented by this milestone. Future verification results belong with the implementation/test inventory; do not mark application requirements passed merely because this map exists.
