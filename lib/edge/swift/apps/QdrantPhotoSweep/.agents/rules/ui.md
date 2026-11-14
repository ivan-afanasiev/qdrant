# ui rules

Classification: C = confirmed product requirement; T = planned technical constraint; V = validation parameter/milestone. IDs map to .agents/requirements.md; source is REWRITE_PLAN.md.

## UI-01 (C) — Presentation

iPhone/iOS 26+, SwiftUI wherever practical. Preserve design tokens, localization, gestures, Tinder-like cards, group comparison and fullscreen preview. The rewrite review flow has no grid/toggle/routes/grid-only state/use cases/tests and no grid pagination API; legacy grid code is deleted with the legacy engine at cutover.

## UI-02 (C) — Liquid Glass

Apply consistent Liquid Glass via shared design-system styling and standard controls; custom effects only where needed. Audit onboarding, progress, cards, comparison, preview controls, settings, sheets and errors. Keep photos readable; verify light/dark, Reduce Transparency and Reduce Motion. Check current Apple documentation before adopting APIs.

## UI-03 (T) — View boundary

Views render and dispatch; zoom/drag may remain local. Resource bundles/localization/previews must survive SPM extraction. Use image use cases per vectorization.md; do not hide full-resolution requests or business orchestration inside views.

## UI-04 (C) — Feedback

Expose vectorization progress, unavailable counts, Pause/Resume/Retry, loading/conflict/failure states and settings/stats. No Cancel or grid UI. Preserve user choices on failure and require explicit deletion action.

