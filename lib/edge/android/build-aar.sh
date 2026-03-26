#!/usr/bin/env bash
#
# Build Qdrant Edge as an AAR with Kotlin bindings for Android.
#
# Prerequisites:
#   - Rust toolchain (rustup)
#   - Android NDK (via $ANDROID_NDK_HOME or Android SDK's ndk-bundle)
#   - cargo-ndk (`cargo install cargo-ndk`)
#
# Usage:
#   ./build-aar.sh [--debug]
#
#   --debug   Build in debug mode (faster compile, larger binary)
#
# Output:
#   out/kotlin-bindings/   - Generated Kotlin source
#   qdrant-edge/src/main/jniLibs/  - Native .so libraries per ABI

set -euo pipefail

unset CARGO_TARGET_DIR
unset CARGO_BUILD_TARGET_DIR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
OUT_DIR="$SCRIPT_DIR/out"
BINDINGS_DIR="$OUT_DIR/kotlin-bindings"
JNILIBS_DIR="$SCRIPT_DIR/qdrant-edge/src/main/jniLibs"

CRATE_NAME="qdrant_edge_ffi"
LIB_NAME="lib${CRATE_NAME}.so"
PACKAGE_NAME="qdrant-edge-ffi"

PROFILE="release"
CARGO_FLAGS="--release"

for arg in "$@"; do
    case "$arg" in
        --debug) PROFILE="debug"; CARGO_FLAGS="" ;;
    esac
done

# Android target triple / ABI pairs (parallel arrays — bash 3.2 compatible)
# 32-bit targets (armv7/x86) are excluded: Qdrant's dependency tree
# includes crates that overflow on 32-bit const evaluation (e.g. bitm).
TARGETS=(
    "aarch64-linux-android"
    "x86_64-linux-android"
)
ABIS=(
    "arm64-v8a"
    "x86_64"
)

# ── Preflight checks ────────────────────────────────────────────────────────

if ! command -v cargo-ndk >/dev/null 2>&1; then
    echo "ERROR: cargo-ndk not found. Install with: cargo install cargo-ndk"
    exit 1
fi

if [ -z "${ANDROID_NDK_HOME:-}" ]; then
    if [ -z "${ANDROID_HOME:-}" ]; then
        echo "ERROR: ANDROID_NDK_HOME or ANDROID_HOME must be set."
        echo "  export ANDROID_NDK_HOME=/path/to/ndk"
        exit 1
    fi
    NDK_DIR=$(ls -d "$ANDROID_HOME/ndk/"* 2>/dev/null | sort -V | tail -1 || true)
    if [ -z "$NDK_DIR" ]; then
        echo "ERROR: No NDK found under \$ANDROID_HOME/ndk/. Install an NDK via SDK Manager."
        exit 1
    fi
    export ANDROID_NDK_HOME="$NDK_DIR"
    echo "==> Using NDK at: $ANDROID_NDK_HOME"
fi

# ── Install targets ─────────────────────────────────────────────────────────

echo "==> Installing required Rust targets..."
for target in "${TARGETS[@]}"; do
    rustup target add "$target" 2>/dev/null || true
done

# ── Build shared libraries ──────────────────────────────────────────────────

echo "==> Building shared libraries..."
for i in "${!TARGETS[@]}"; do
    target="${TARGETS[$i]}"
    abi="${ABIS[$i]}"
    echo "    Building for $target ($abi)..."
    cargo ndk \
        --target "$target" \
        --platform 24 \
        -- build $CARGO_FLAGS \
        --lib \
        --package "$PACKAGE_NAME" \
        --manifest-path "$WORKSPACE_ROOT/Cargo.toml"
done

# ── Copy .so files to jniLibs ───────────────────────────────────────────────

echo "==> Copying .so files to jniLibs..."
for i in "${!TARGETS[@]}"; do
    target="${TARGETS[$i]}"
    abi="${ABIS[$i]}"
    src="$WORKSPACE_ROOT/target/$target/$PROFILE/$LIB_NAME"
    dest="$JNILIBS_DIR/$abi/$LIB_NAME"
    mkdir -p "$JNILIBS_DIR/$abi"
    cp "$src" "$dest"

    if [ "$PROFILE" = "release" ]; then
        strip_bin="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)/bin/llvm-strip"
        if [ -f "$strip_bin" ]; then
            "$strip_bin" "$dest"
        fi
    fi

    echo "    $abi: $(du -sh "$dest" | cut -f1)"
done

# ── Generate Kotlin bindings ────────────────────────────────────────────────

echo "==> Generating Kotlin bindings..."
mkdir -p "$BINDINGS_DIR"

FIRST_TARGET="${TARGETS[0]}"
cargo run \
    --package "qdrant-edge-ffi-bindgen" \
    --bin uniffi-bindgen \
    --manifest-path "$WORKSPACE_ROOT/Cargo.toml" \
    -- generate \
    --library "$WORKSPACE_ROOT/target/$FIRST_TARGET/$PROFILE/$LIB_NAME" \
    --language kotlin \
    --out-dir "$BINDINGS_DIR"

# ── Copy Kotlin sources into library module ─────────────────────────────────

KOTLIN_SRC_DIR="$SCRIPT_DIR/qdrant-edge/src/main/kotlin"
echo "==> Copying Kotlin bindings to library module..."

if [ -d "$BINDINGS_DIR" ]; then
    find "$BINDINGS_DIR" -name "*.kt" | while read -r kt_file; do
        rel_path="${kt_file#"$BINDINGS_DIR"/}"
        dest_file="$KOTLIN_SRC_DIR/$rel_path"
        mkdir -p "$(dirname "$dest_file")"
        cp "$kt_file" "$dest_file"
        echo "    Copied: $rel_path"
    done
fi

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "Done! Output:"
echo "  Kotlin bindings: $BINDINGS_DIR"
echo "  jniLibs:         $JNILIBS_DIR"
echo ""
echo "Per-ABI .so sizes:"
for i in "${!TARGETS[@]}"; do
    abi="${ABIS[$i]}"
    so_file="$JNILIBS_DIR/$abi/$LIB_NAME"
    if [ -f "$so_file" ]; then
        echo "  $abi: $(du -sh "$so_file" | cut -f1)"
    fi
done
echo ""
echo "To build the AAR:"
echo "  cd $(basename "$SCRIPT_DIR") && ./gradlew :qdrant-edge:assembleRelease"
echo "  Output: qdrant-edge/build/outputs/aar/qdrant-edge-release.aar"
