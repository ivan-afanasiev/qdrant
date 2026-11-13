# Repeatable baseline measurement protocol

This is a procedure, not measured performance. No app-specific device heat/energy/throughput budget has been established. Simulator wall time and a passing build cannot substitute for those values.

## Device matrix

| Slot | Selection | Purpose | Availability at baseline |
| --- | --- | --- | --- |
| D1 | iPhone 17 (iPhone18,3), iOS 27.0.1 (24A446) | Current-user reproduction, heat and scheduler behavior | Initially offline; came online and ran the 13 tests |
| D2 | Small-screen/older physical iPhone supported by iOS 26, running a supported iOS 26 version | Lower resource tier and minimum OS family | Not connected; do not infer a model from simulator inventory |
| S1 | iPhone 18 Pro simulator, iOS 27.0 | Build/tests and initial UI evidence only | Available through Xcode device interaction |
| S2 | iPhone simulator on iOS 26.5 | Minimum OS-family UI/adapter regression | Listed by destination discovery; interaction availability must be confirmed |

D1 plus D2 define representative physical coverage; reuse D1 for both only if it actually satisfies the lower-tier criterion. Record hardware identifier, OS/build, storage, battery health/level, charging, Low Power Mode and display settings per run. No purchasing recommendation is implied.

## Controlled fixtures

Use a dedicated test library and separate old/new app stores, never reset the user's personal library to manufacture a cold baseline. Record fixture ID/hash, asset count, pixel-size distribution, local/iCloud mix, date scope, similarity threshold, index/model state and authorization level.

| Fixture | Workload |
| --- | --- |
| F0 | Empty and single-photo smoke cases |
| F1 | Fixed 1,000 local photos; known small similar groups, unique images, mixed dimensions/orientations |
| F2 | 10,000 local photos; known >10-member group and long transitive chain |
| F3 | 100,000+ asset/vector metadata fixture; separate real Photos library run for image-processing cost |
| F4 | F1 with offline iCloud-only photos and one intentionally invalid/unavailable asset |
| F5 | F1 plus newly added/edited/removed photos during review, including match to completed group |

Fixture sets are specified, not created by this step. Synthetic metadata scale testing does not measure actual Photos enumeration/download/embedding costs.

## Run conditions and samples

1. Record source revision, configuration, Xcode/device/OS, fixture, range/threshold, authorization, network, charging and initial thermal state. Use the same conditions for before/after comparisons.
2. Use Release for performance comparisons with matching symbols; run without debugger except during targeted diagnosis. Keep Debug test timing separate.
3. Cool to comparable idle state before each run. Fix brightness and network conditions; do not compare local-only to cloud-download runs.
4. Run three comparable samples per workload; retain raw values, report median and range. Use separate runs for CPU, allocations and power to limit profiler interference.
5. For each sample, run to completion or a defined 10-minute observation window; record incomplete/censored runs rather than converting them to throughput guarantees. For memory growth, include at least three workload cycles where feasible.
6. Capture cold local indexing, warm no-change rescan, first-group latency, 20 review/refill actions, one explicit preview, background/lock handoff, expiration/resume and F5 incremental review. The old combined pipeline cannot isolate lazy discovery; report that mismatch.
7. Never delete fixture photos without an explicitly selected disposable set; deletion/recovery tests otherwise use fakes.

## Metrics and acceptance decision

| Metric | Record | Comparison / interpretation |
| --- | --- | --- |
| Vectorization | Successful/deferred count, wall duration, images/s, download duration separately | Compare equal fixture/scope and compatible cache state |
| Discovery | Time to first ready group, refill p50/p95, query count, visited assets, component size | Buffer fullness must stop new discovery; do not accept hidden eager scan |
| Memory | Peak resident/physical footprint, retained images/vectors, post-cycle trend | Demonstrate bounded working set; growing library metadata alone is not evidence of bounded image memory |
| CPU / work | CPU time/utilization, dominant stacks, repeated image/embedding calls | Confirm hotspot with samples; source suspicion is not diagnosis |
| Responsiveness | Hitches, long main-thread work, review/preview latency | Same screen interactions and refresh-rate conditions |
| Thermal / energy | Thermal-state timeline, time in elevated states, power metrics when supported, charging/ambient conditions | Device thermalState is not degrees Celsius; battery percent alone is too coarse |
| Background | Start/expiry/completion times, checkpoint, resume ID, indexed delta, overlap/shard ownership | Simulator/manual launch does not prove automatic scheduling |
| Correctness | Scope, duplicates/omissions, stale commits, stats/notification outcomes | Must pass independently of faster timing |

Set numeric resource budgets after D1/D2 results; record the chosen thresholds and rationale before performance acceptance. Non-negotiable functional gates already exist: no background discovery, single shared shard/executor, preserved checkpoints, bounded batch work and responsive review.

## Instrument commands

Installed command surface was checked with xctrace help, help record and help list. Templates include Time Profiler, CPU Profiler, Allocations, Animation Hitches, SwiftUI, Power Profiler and Swift Concurrency. Device/template enumeration required permission for Instruments' system cache; no cache sandbox bypass is part of the project.

Use an actual online device ID and running app PID, not the bundle identifier as a PID. The following is a template, not an executed trace:

```sh
xcrun xctrace record --template 'Time Profiler' \
  --device '<online-device-id>' --attach '<app-pid>' \
  --time-limit 60s --output '<new-output-path>.trace'
```

Inspect with help for the installed version, then toc → list tracks → show. Keep traces/symbols in a local artifact directory; record relative evidence locations and summary metrics, not private photo content or device identifiers in version control. No all-process trace is necessary for an app baseline.

## Run record

Append a row per actual run to measurement-results.csv. Required fields: run ID, revision, device tier/model, OS, fixture, configuration, scenario, duration, successful/deferred counts, peak footprint, CPU time, thermal states, evidence path, result/limitation. Leave unavailable numeric fields blank; never use zero as “not measured.”
