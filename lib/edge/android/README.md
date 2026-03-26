# Qdrant Edge — Android (Kotlin)

Kotlin/Android bindings for [Qdrant Edge](https://qdrant.tech/documentation/edge/edge-quickstart/),
built from the shared `qdrant-edge-ffi` Rust crate via [UniFFI](https://github.com/mozilla/uniffi-rs).

## Architecture

The build produces native shared libraries (`.so`) for two Android ABIs:

| ABI             | Target triple               | Devices                  |
|-----------------|----------------------------|--------------------------|
| `arm64-v8a`     | `aarch64-linux-android`    | Modern phones/tablets    |
| `x86_64`        | `x86_64-linux-android`     | Emulators (Intel/AMD)    |

> **Note:** 32-bit targets (`armeabi-v7a`, `x86`) are excluded because upstream
> Rust dependencies in Qdrant's tree overflow on 32-bit const evaluation.

These are packaged into an AAR library alongside auto-generated Kotlin bindings.

## Quick Start

```bash
# 1. Install prerequisites
make setup

# 2. Build native libs + generate Kotlin bindings
make build

# 3. (Optional) Build the AAR via Gradle
make aar

# 4. Check library sizes
make size
```

## Prerequisites

- **Rust** (via `rustup`) + `cargo-ndk`
- **Android NDK** — set `ANDROID_NDK_HOME` or have it installed under `$ANDROID_HOME/ndk/`
- **Protocol Buffers** — `brew install protobuf` (needed by a build dependency)
- **Android SDK** — for Gradle AAR builds (optional for just `.so` + bindings)

## Project Structure

```
android/
├── build-aar.sh             # Cross-compile Rust + generate Kotlin bindings
├── Makefile                  # Setup, build, size, clean targets
├── settings.gradle.kts       # Gradle multi-module project
├── build.gradle.kts          # Root Gradle build
├── qdrant-edge/              # Android library module
│   ├── build.gradle.kts
│   ├── proguard-rules.pro    # ProGuard/R8 keep rules for JNA + UniFFI
│   └── src/main/
│       ├── AndroidManifest.xml
│       ├── jniLibs/          # Native .so files (populated by build-aar.sh)
│       └── kotlin/           # Generated Kotlin bindings (populated by build-aar.sh)
└── example/                  # Example Android app
    ├── build.gradle.kts
    └── src/main/
        ├── AndroidManifest.xml
        └── kotlin/.../MainActivity.kt
```

## Integration

### From source (Gradle composite build)

Add to your `settings.gradle.kts`:

```kotlin
includeBuild("path/to/qdrant/lib/edge/android") {
    dependencySubstitution {
        substitute(module("tech.qdrant:qdrant-edge")).using(project(":qdrant-edge"))
    }
}
```

### From AAR

1. Run `make aar` to produce `qdrant-edge/build/outputs/aar/qdrant-edge-release.aar`
2. Copy the AAR to your project's `libs/` directory
3. Add to your `build.gradle.kts`:

```kotlin
dependencies {
    implementation(files("libs/qdrant-edge-release.aar"))
    implementation("net.java.dev.jna:jna:5.14.0@aar")
}
```

## Makefile Targets

| Target        | Description                                      |
|---------------|--------------------------------------------------|
| `setup`       | Install all prerequisites                        |
| `build`       | Cross-compile + generate Kotlin bindings (release)|
| `build-debug` | Same but debug mode                              |
| `aar`         | Build + package AAR via Gradle                   |
| `size`        | Show per-ABI .so sizes                           |
| `clean`       | Remove all build artifacts                       |
| `help`        | Show available targets                           |
