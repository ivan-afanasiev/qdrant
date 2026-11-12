# maintenance rules

Classification: C = confirmed product requirement; T = planned technical constraint; V = validation parameter/milestone. IDs map to .agents/requirements.md; source is REWRITE_PLAN.md.

## RULE-01 (C) — Agent context

Canonical rules live in .agents. Keep entry roughly under 1,000 tokens, route tasks to scoped files, and keep plan/history/traceability out of automatic context. Every technical requirement needs an ID, source, owner, classification and verification. Deduplicate without losing exceptions; keep accepted changes synchronized.

## RULE-02 (T) — Tool adapters

Use relative repository-internal links; inspect existing tool config and preserve it. Verify tool discovery formats rather than assuming directory links load. Keep settings/caches/credentials outside shared rules. Avoid circular links, auto-loading duplicated prose and speculative integrations. Document actual runtime-loading limitations.

## RULE-03 (T) — Rule maintenance

Edit canonical files, never tool copies. Keep source plan as decisions/rationale and rules as operational extracts; resolve discrepancies explicitly, never silently change a product decision. Update project-map paths as modules land. Report measured file sizes and validation status; revalidate after changes.

