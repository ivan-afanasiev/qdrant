# Qdrant Edge — Swift Bindings

Swift bindings for [Qdrant Edge](https://qdrant.tech/documentation/edge/edge-quickstart/), the embeddable vector search engine. Ships as an **XCFramework** containing pre-compiled static libraries for iOS and macOS.

## What is an XCFramework?

An XCFramework is Apple's distribution format for binary libraries that bundles multiple architecture slices into a single package. Unlike a regular `.framework`, it can contain separate builds for different platforms (iOS device, iOS Simulator, macOS) and CPU architectures — which is required because Apple Silicon Macs, Intel Macs, iPhones, and the Simulator all use different ABIs.

This XCFramework contains seven slices:

| Slice | Architectures | Purpose |
|---|---|---|
| `ios-arm64` | arm64 | Physical iOS devices |
| `ios-arm64_x86_64-simulator` | arm64 + x86_64 | iOS Simulator (Apple Silicon & Intel Macs) |
| `macos-arm64_x86_64` | arm64 + x86_64 | Native macOS apps |
| `tvos-arm64` | arm64 | Physical Apple TV devices |
| `tvos-arm64_x86_64-simulator` | arm64 + x86_64 | tvOS Simulator (Apple Silicon & Intel Macs) |
| `visionos-arm64` | arm64 | Apple Vision Pro |
| `visionos-arm64-simulator` | arm64 | visionOS Simulator (Apple Silicon only) |

## How it works

1. The Rust crate `qdrant-edge-swift` wraps Qdrant Edge types with [UniFFI](https://github.com/mozilla/uniffi-rs) attributes
2. `build-xcframework.sh` cross-compiles the crate for all ten Apple targets, strips binaries, creates universal (fat) libraries via `lipo`, and packages them into an XCFramework
3. UniFFI generates a Swift source file (`QdrantEdge.swift`) with idiomatic Swift types that call into the static library via FFI

## Quick start

```bash
# Install all prerequisites (Rust, protobuf, cross-compilation targets)
make setup

# Build the XCFramework (release mode)
make build

# Check output size
make size
```

All available targets:

```
make help
```

## Integration

After building, add this package to your Swift project via SPM:

```swift
.package(path: "path/to/lib/edge/swift")
```

Then import in your code:

```swift
import QdrantEdge

let shard = try EdgeShard.load(path: dataDir, config: config)
```

See `example/` for a complete demo app.

## Project structure

```
swift/
├── src/              # Rust source — UniFFI wrapper types
│   ├── lib.rs        # EdgeShard (main entry point)
│   ├── config.rs     # Configuration types
│   ├── types.rs      # Point, Vector, Record, etc.
│   ├── filter.rs     # Filter & condition types
│   ├── query.rs      # Query, search, scroll requests
│   ├── update.rs     # Upsert, delete, payload operations
│   └── error.rs      # Error handling
├── bindgen/          # Separate crate for uniffi-bindgen CLI
├── build-xcframework.sh
├── Makefile
├── Package.swift     # SPM package definition
├── example/          # Swift example app
└── out/              # Build output (gitignored)
    ├── QdrantEdge.xcframework
    └── swift-bindings/
```
