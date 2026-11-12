# Agent loading and validation

Canonical instructions: .agents/AGENTS.md plus manually routed rules. Edit these files, not aliases. Paths in instructions are relative to the PhotoSweep project root.

| Tool | Entry/link | Behavior |
| --- | --- | --- |
| AGENTS-compatible | AGENTS.md → .agents/AGENTS.md | Short shared entry; read applicable scoped rules by routing table |
| Claude | .claude/CLAUDE.md → ../.agents/AGENTS.md | Shared entry through documented project CLAUDE.md location; no .claude/rules auto-loading of the entire corpus |
| Cursor | root AGENTS.md; .cursor/rules → ../.agents/adapters/cursor | Shared root entry; optional manual .mdc shortcuts route to canonical rule files |

Do not symlink whole .claude/.cursor directories to .agents: settings/runtime files have different semantics. Only instruction entry points are shared. No speculative editor folders are created.

The [Claude memory documentation](https://code.claude.com/docs/en/memory) supports project CLAUDE.md locations and symlinked shared instructions. Its runtime behavior depends on version/user instruction settings. The [Cursor rules documentation](https://cursor.com/docs/rules) supports AGENTS.md and .mdc rules. Manual shortcuts have alwaysApply: false and no globs/description to avoid duplicating scoped content automatically. Neither documentation nor a resolving link proves this particular installed client loaded it.

## Runtime validation status

Filesystem resolution, byte identity, traceability and relocated-copy validation passed on 2026-11-12. Claude CLI version 2.1.128 is installed; Cursor CLI was not found (the executable named agent belongs to Xcode, not Cursor). No new AI session was launched to test instruction ingestion, and no application UI inspection was performed. Therefore Claude/Cursor runtime loading is **not yet exercised**; do not claim otherwise. The CLAUDE.md compatibility entry is intentional for the installed Claude version.

For a new Claude session in this project, inspect /context all (or the installed version's memory inspector) and confirm the project CLAUDE.md entry appears once; ask it to identify the relevant canonical rule IDs for a sample task. In Cursor, confirm the root AGENTS.md is present, manually invoke one rule shortcut and check that it reads the canonical file. Confirm unrelated rules and requirements.md are not automatically included. Record client version and observed results here when exercised. User-wide settings can alter loading.

Run `python3 .agents/validate.py` after edits. It also copies only these artifacts to a temporary directory and checks links there, approximating checkout relocation without touching Git. A true fresh-clone/editor smoke test remains distinct.

Sizes are measured as UTF-8 bytes, words and a rough characters/4 token estimate (not a model tokenizer). The entry budget is approximately 1,000 tokens. See validation output for current counts. Requirements and project-map are reference-only, not auto-loaded.

## Recorded structural check (2026-11-12)

49 unique canonical requirement groups and all 16 decision rows mapped; symlinks, manual wrappers, byte identity and relocated-copy checks passed. No application source, project settings or dependencies changed. No app build was needed.

| File | UTF-8 bytes | Words | Approx tokens |
| --- | --- | --- | --- |
| AGENTS.md | 2864 | 381 | 716 |
| rules/architecture.md | 3947 | 464 | 980 |
| rules/vectorization.md | 2547 | 321 | 634 |
| rules/discovery-review.md | 3336 | 432 | 827 |
| rules/persistence-lifecycle.md | 3035 | 356 | 754 |
| rules/ui.md | 1365 | 171 | 340 |
| rules/testing.md | 2698 | 301 | 672 |
| rules/performance.md | 1013 | 124 | 253 |
| rules/maintenance.md | 1291 | 165 | 322 |
