# PhotoSweep package

The whole app engine: Swift 6, iOS 26. The macOS 14 platform entry exists only so host-side tests (DI, Qdrant, persistence, use cases) run with `swift test`. Photos, Vision, BackgroundTasks and UI code are iOS-only. Module layout and runtime are described in `ARCHITECTURE.md` at the app root.

## Setup

- **Xcode:** Swift 6.2 or newer.
- **QdrantEdge:** the local package at `../../../..`, with its generated `out/QdrantEdge.xcframework` and Swift bindings. Build them with `lib/edge/swift/build-xcframework.sh`.
- **SafeDI:** pinned exactly to 2.2.0 using the prebuilt `SafeDITool`; only `SweepComposition` uses its generator plugin.
  - Trust the plugin and macros once when Xcode asks. Until then, the build fails with "Plugin “SafeDIGenerator” … must be enabled".
  - CI can pass `-skipPackagePluginValidation -skipMacroValidation` per invocation instead.
- **Pinning:** `Package.resolved` is ignored by `lib/edge/swift/.gitignore`, so transitive versions (swift-syntax) resolve per machine.

## Validation

```sh
swift test --package-path Packages/PhotoSweep        # from the app root, macOS
xcodebuild test -scheme PhotoSweep \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'   # from this directory, iOS
```

More commands and the lessons learned during the rewrite are in `docs/implementation/README.md`.
