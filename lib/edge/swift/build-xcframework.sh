#!/usr/bin/env bash
#
# Build Qdrant Edge as an XCFramework with Swift bindings.
#
# Prerequisites:
#   - Xcode (with command-line tools)
#   - Rust toolchain (rustup)
#   - For tvOS/visionOS: nightly toolchain + rust-src (see `make setup`)
#
# Usage:
#   ./build-xcframework.sh [--debug] [--all-platforms]
#
#   --debug          Build in debug mode (faster compile, larger binary)
#   --all-platforms  Include tvOS and visionOS (tier-3, requires nightly)
#
# Output:
#   out/QdrantEdge.xcframework   - The XCFramework
#   out/swift-bindings/          - Generated Swift source and headers

set -euo pipefail

# Ensure Cargo uses the standard target directory
unset CARGO_TARGET_DIR
unset CARGO_BUILD_TARGET_DIR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
OUT_DIR="$SCRIPT_DIR/out"
BINDINGS_DIR="$OUT_DIR/swift-bindings"
XCFRAMEWORK_DIR="$OUT_DIR/QdrantEdge.xcframework"

CRATE_NAME="qdrant_edge_swift"
LIB_NAME="lib${CRATE_NAME}.a"
PACKAGE_NAME="qdrant-edge-swift"

# Parse args
PROFILE="release"
CARGO_FLAGS="--release"
ALL_PLATFORMS=false

for arg in "$@"; do
    case "$arg" in
        --debug) PROFILE="debug"; CARGO_FLAGS="" ;;
        --all-platforms) ALL_PLATFORMS=true ;;
    esac
done

# ── Targets ──────────────────────────────────────────────────────────────────

# Tier 1/2 — build with stable toolchain
STABLE_TARGETS=(
    "aarch64-apple-ios"           # iOS devices
    "aarch64-apple-ios-sim"       # iOS Simulator (Apple Silicon)
    "x86_64-apple-ios"            # iOS Simulator (Intel)
    "aarch64-apple-darwin"        # macOS (Apple Silicon)
    "x86_64-apple-darwin"         # macOS (Intel)
)

# Tier 3 — require nightly + -Z build-std
TIER3_TARGETS=()
if $ALL_PLATFORMS; then
    TIER3_TARGETS=(
        "aarch64-apple-tvos"          # tvOS devices
        "aarch64-apple-tvos-sim"      # tvOS Simulator (Apple Silicon)
        "x86_64-apple-tvos"           # tvOS Simulator (Intel)
        "aarch64-apple-visionos"      # visionOS devices
        "aarch64-apple-visionos-sim"  # visionOS Simulator
    )
fi

ALL_TARGETS=("${STABLE_TARGETS[@]}" ${TIER3_TARGETS[@]+"${TIER3_TARGETS[@]}"})

# ── Build ────────────────────────────────────────────────────────────────────

echo "==> Installing required Rust targets..."
for target in "${STABLE_TARGETS[@]}"; do
    rustup target add "$target" 2>/dev/null || true
done

echo "==> Building static libraries..."
for target in "${STABLE_TARGETS[@]}"; do
    echo "    Building for $target (stable)..."
    cargo build $CARGO_FLAGS \
        --lib \
        --package "$PACKAGE_NAME" \
        --target "$target" \
        --manifest-path "$WORKSPACE_ROOT/Cargo.toml"
done
for target in ${TIER3_TARGETS[@]+"${TIER3_TARGETS[@]}"}; do
    echo "    Building for $target (nightly + build-std)..."
    cargo +nightly build $CARGO_FLAGS \
        --lib \
        --package "$PACKAGE_NAME" \
        --target "$target" \
        --manifest-path "$WORKSPACE_ROOT/Cargo.toml" \
        -Z build-std
done

echo "==> Stripping debug symbols..."
for target in "${ALL_TARGETS[@]}"; do
    strip -S "$WORKSPACE_ROOT/target/$target/$PROFILE/$LIB_NAME"
done

# ── Universal (fat) libraries ────────────────────────────────────────────────

echo "==> Creating universal (fat) libraries..."
mkdir -p "$OUT_DIR/ios-simulator-universal"
mkdir -p "$OUT_DIR/macos-universal"

lipo -create \
    "$WORKSPACE_ROOT/target/aarch64-apple-ios-sim/$PROFILE/$LIB_NAME" \
    "$WORKSPACE_ROOT/target/x86_64-apple-ios/$PROFILE/$LIB_NAME" \
    -output "$OUT_DIR/ios-simulator-universal/$LIB_NAME"

lipo -create \
    "$WORKSPACE_ROOT/target/aarch64-apple-darwin/$PROFILE/$LIB_NAME" \
    "$WORKSPACE_ROOT/target/x86_64-apple-darwin/$PROFILE/$LIB_NAME" \
    -output "$OUT_DIR/macos-universal/$LIB_NAME"

if $ALL_PLATFORMS; then
    mkdir -p "$OUT_DIR/tvos-simulator-universal"
    lipo -create \
        "$WORKSPACE_ROOT/target/aarch64-apple-tvos-sim/$PROFILE/$LIB_NAME" \
        "$WORKSPACE_ROOT/target/x86_64-apple-tvos/$PROFILE/$LIB_NAME" \
        -output "$OUT_DIR/tvos-simulator-universal/$LIB_NAME"
fi

# ── Swift bindings ───────────────────────────────────────────────────────────

echo "==> Generating Swift bindings..."
mkdir -p "$BINDINGS_DIR"

cargo run \
    --package "qdrant-edge-swift-bindgen" \
    --bin uniffi-bindgen \
    --manifest-path "$WORKSPACE_ROOT/Cargo.toml" \
    -- generate \
    --library "$WORKSPACE_ROOT/target/aarch64-apple-ios/$PROFILE/$LIB_NAME" \
    --language swift \
    --out-dir "$BINDINGS_DIR"

echo "==> Renaming generated bindings to PascalCase..."
mv "$BINDINGS_DIR/${CRATE_NAME}.swift" "$BINDINGS_DIR/QdrantEdge.swift"
mv "$BINDINGS_DIR/${CRATE_NAME}FFI.h" "$BINDINGS_DIR/QdrantEdgeFFI.h"
mv "$BINDINGS_DIR/${CRATE_NAME}FFI.modulemap" "$BINDINGS_DIR/QdrantEdgeFFI.modulemap" 2>/dev/null || true

# ── Headers & modulemap ─────────────────────────────────────────────────────

echo "==> Preparing headers..."

HEADER_DIRS=("$OUT_DIR/headers-ios" "$OUT_DIR/headers-sim" "$OUT_DIR/headers-mac")
if $ALL_PLATFORMS; then
    HEADER_DIRS+=(
        "$OUT_DIR/headers-tvos" "$OUT_DIR/headers-tvos-sim"
        "$OUT_DIR/headers-visionos" "$OUT_DIR/headers-visionos-sim"
    )
fi

for hdir in "${HEADER_DIRS[@]}"; do
    rm -rf "$hdir"
    mkdir -p "$hdir"
    cp "$BINDINGS_DIR/QdrantEdgeFFI.h" "$hdir/"
    cat > "$hdir/module.modulemap" << 'MODULEMAP'
module qdrant_edge_swiftFFI {
    header "QdrantEdgeFFI.h"
    link "qdrant_edge_swift"
    export *
}
MODULEMAP
done

# ── XCFramework ──────────────────────────────────────────────────────────────

echo "==> Building XCFramework..."
rm -rf "$XCFRAMEWORK_DIR"

XCFRAMEWORK_ARGS=(
    -library "$WORKSPACE_ROOT/target/aarch64-apple-ios/$PROFILE/$LIB_NAME"
        -headers "$OUT_DIR/headers-ios"
    -library "$OUT_DIR/ios-simulator-universal/$LIB_NAME"
        -headers "$OUT_DIR/headers-sim"
    -library "$OUT_DIR/macos-universal/$LIB_NAME"
        -headers "$OUT_DIR/headers-mac"
)

if $ALL_PLATFORMS; then
    XCFRAMEWORK_ARGS+=(
        -library "$WORKSPACE_ROOT/target/aarch64-apple-tvos/$PROFILE/$LIB_NAME"
            -headers "$OUT_DIR/headers-tvos"
        -library "$OUT_DIR/tvos-simulator-universal/$LIB_NAME"
            -headers "$OUT_DIR/headers-tvos-sim"
        -library "$WORKSPACE_ROOT/target/aarch64-apple-visionos/$PROFILE/$LIB_NAME"
            -headers "$OUT_DIR/headers-visionos"
        -library "$WORKSPACE_ROOT/target/aarch64-apple-visionos-sim/$PROFILE/$LIB_NAME"
            -headers "$OUT_DIR/headers-visionos-sim"
    )
fi

xcodebuild -create-xcframework "${XCFRAMEWORK_ARGS[@]}" -output "$XCFRAMEWORK_DIR"

# ── Cleanup ──────────────────────────────────────────────────────────────────

echo "==> Cleaning up temporary files..."
rm -rf "${HEADER_DIRS[@]}"
rm -rf "$OUT_DIR/ios-simulator-universal" "$OUT_DIR/macos-universal"
if $ALL_PLATFORMS; then
    rm -rf "$OUT_DIR/tvos-simulator-universal"
fi

echo ""
echo "Done! Output:"
echo "  XCFramework:    $XCFRAMEWORK_DIR"
echo "  Swift bindings: $BINDINGS_DIR"
if ! $ALL_PLATFORMS; then
    echo ""
    echo "Note: tvOS/visionOS not included. Use --all-platforms to add them."
fi
echo ""
echo "To use in your Swift project, add the XCFramework and the generated"
echo "Swift file ($BINDINGS_DIR/QdrantEdge.swift) to your Xcode project,"
echo "or use the Package.swift in this directory."
