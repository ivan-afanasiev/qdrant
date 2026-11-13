# PhotoSweep package

Step 3 isolates rewrite code in one Swift 6 package, targeting iOS 26. The macOS 14 platform entry supports host-side DI and Qdrant tests only; it does not add a Mac application. Photos, Vision and design-system implementations are iOS-only and require iOS validation.

The Xcode host retains `PhotoSweepComposition` outside SwiftUI body reconstruction. This milestone graph is deliberately inert: `BootstrapProbe` validates protocol binding, ownership and async bootstrap injection without opening the live library or stores. It is not the production bootstrap, persistence implementation or background engine. The legacy app continues running its existing engine until replacement slices are ready.

`SweepDomain` holds extracted transport contracts, independent of SafeDI and UI. `SweepQdrant`, `SweepPhotos` and `SweepEmbeddings` contain extracted adapters. The SDK mapping, cosine configuration and image request behavior are preserved. Blocking shard-load retries and dimension-driven destructive rebuilds are omitted from the extracted Qdrant adapter; future use cases coordinate those policies. Legacy originals remain in the host until cutover, so changes to shared behavior must be deliberately applied to the correct implementation.

`SweepDesignSystem` contains the preserved tokens/components and string catalog. Its localized resources explicitly carry the package bundle. Other feature, persistence and state targets establish dependency boundaries; their business implementations belong to later steps.

## Dependency setup

SafeDI is pinned exactly to 2.2.0 in `Package.swift`. The manifest uses SafeDI's default `prebuilt` trait, which fetches the release `SafeDITool` binary artifact for that version; the `sourceBuild` trait is not enabled. `Package.resolved` is ignored by `lib/edge/swift/.gitignore`, so the exact manifest pin is the only committed version constraint; transitive dependencies such as swift-syntax resolve per machine. If Xcode warns that SafeDI is planning generated files with a simpler scanner, run the SafeDI install command from the project's context menu as described in the SafeDI manual. The generator plugin is attached only to `SweepComposition`, where it discovers dependent module annotations and generates the root initializer. Domain and design targets have no SafeDI dependency. Constructors remain explicitly injectable.

Developers and CI need Xcode with Swift 6.2 or newer, the local QdrantEdge package at `../../../..`, and its generated `out/QdrantEdge.xcframework`/Swift bindings. Resolve dependencies and trust the pinned SafeDI macro/build plugin when Xcode prompts; until then, BuildProject fails with "Plugin “SafeDIGenerator” … must be enabled". Do not globally disable plugin validation or sandboxing. Per-invocation `xcodebuild -skipPackagePluginValidation -skipMacroValidation` is acceptable for CI or one-off verification.

## Validation

- `python3 Scripts/check-module-boundaries.py` from the app root checks dependency direction and forbidden imports.
- `swift test --package-path Packages/PhotoSweep` runs host-compatible Swift Testing suites. The iOS-conditional suites must also run on an iOS destination: from this directory, `xcodebuild test -scheme PhotoSweep -destination "id=<simulator-id>"`, using an ID from `-showdestinations`.
- Use Xcode BuildProject for the host app; verify its log includes the PhotoSweep targets and iOS 26 deployment setting before treating a cached build as validation.
- Inspect generated `PhotoSweepComposition` initialization under build plugin outputs. Generated files stay out of version control.

Validation results and remaining limitations are recorded in `docs/implementation/step-3.md` at the app root.
