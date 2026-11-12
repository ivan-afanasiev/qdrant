# performance rules

Classification: C = confirmed product requirement; T = planned technical constraint; V = validation parameter/milestone. IDs map to .agents/requirements.md; source is REWRITE_PLAN.md.

## PERF-01 (C) — Scale/resource policy

Support 100,000+ photos with balanced speed/battery/heat and responsive UI. Bound resident images/vectors, metadata fetches and discovery frontier; spill large components. Avoid repeated embeddings, full-library recomputation and expensive UI execution. Buffer count is not a bound on component size.

## PERF-02 (V) — Thermal/budgets

Treat excessive heat as a release concern. Test work-budget policy with injected resource/thermal signals; reduce concurrency/yield without setting manual pause. Measure latency, memory, responsiveness, heat and DI build cost on representative devices before choosing batch/concurrency/retry budgets. Do not invent throughput/temperature guarantees. Limit simultaneous glass effects and share effect containers appropriately.

