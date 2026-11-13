# Simulator UI baseline

## Physical-device retry — 2026-11-13

Xcode lists the connected iPhone on iOS 27.0.1 as the active, eligible build/test destination. A fresh standalone interaction request rejected the physical device; the workspace interaction request explicitly reported that the destination is unsupported and that Device Interaction supports iOS, watchOS and tvOS **simulators** on 27.0+. This is an interaction-tool capability limitation, not evidence that the phone is disconnected. No session opened, app launched, screenshots captured or device state changed during this retry. Physical UI remains unverified.

## Simulator observations

Captured 2026-11-12 using the device-interaction skill and Xcode workspace tools. Destination: iPhone 18 Pro simulator, iOS 27.0. Build/install/run succeeded. Session closed after inspection. No source changes, setting edits, permission grants, photo deletion or local reset were performed.

| State | Evidence | Observed result |
| --- | --- | --- |
| Home, empty results | [Screenshot](artifacts/home-empty-screenshot.png), [hierarchy](artifacts/home-empty-hierarchy.txt) | Scan Complete; No Duplicates Found; library-clean message |
| Settings, top | [Screenshot](artifacts/settings-top-screenshot.png), [hierarchy](artifacts/settings-top-hierarchy.txt) | Navigation worked; zero indexed/duplicate/deletion values; Last Year preset highlighted |
| Settings, bottom | [Screenshot](artifacts/settings-bottom-screenshot.png), [hierarchy](artifacts/settings-bottom-hierarchy.txt) | Scrolling worked; custom dates October 12–November 12, 2026; database/about controls visible |

Captured text was readable with no observed overlap/clipping. A possible existing settings inconsistency is recorded: Last Year was highlighted while custom dates covered one month. This is a runtime observation, not a diagnosed root cause. Do not preserve that mismatch during the rewrite.

The simulator was in an existing state: no onboarding or permission prompt appeared. Zero indexed photos does not prove denied permission or an empty physical library. Card review, populated comparison, image selection, full-resolution preview and onboarding were not exercised. No claim is made about those screens or background/thermal behavior.

The original Xcode destination was Any iOS Device. An iOS 26.5 simulator appeared in destination discovery but could not be selected by workspace device interaction; the already-available iOS 27.0 simulator was used. This does not establish minimum-OS coverage.

Future comparisons should add fixture-driven screenshots for onboarding, authorization error/limited access, vectorization progress/pause/failure, a 2-photo card, a large component, selected/unselected/delete-all states, deferred exhaustion, preview zoom and settings. Repeat in light/dark and accessibility appearance settings. Grid is deliberately not a preservation target.
