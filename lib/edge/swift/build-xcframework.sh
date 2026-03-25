#!/usr/bin/env bash
#
# Build Qdrant Edge as an XCFramework with Swift bindings.
#
# Prerequisites:
#   - Xcode (with command-line tools)
#   - Rust toolchain (rustup)
#   - Required Rust targets (installed automatically by this script)
#
# Usage:
#   ./build-xcframework.sh [--release]
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
if [[ "${1:-}" == "--debug" ]]; then
    PROFILE="debug"
    CARGO_FLAGS=""
fi

# Apple targets to build
TARGETS=(
    "aarch64-apple-ios"           # iOS devices
    "aarch64-apple-ios-sim"       # iOS Simulator (Apple Silicon)
    "x86_64-apple-ios"            # iOS Simulator (Intel)
    "aarch64-apple-darwin"        # macOS (Apple Silicon)
    "x86_64-apple-darwin"         # macOS (Intel)
    "aarch64-apple-tvos"          # tvOS devices
    "aarch64-apple-tvos-sim"      # tvOS Simulator (Apple Silicon)
    "x86_64-apple-tvos"           # tvOS Simulator (Intel)
    "aarch64-apple-visionos"      # visionOS devices
    "aarch64-apple-visionos-sim"  # visionOS Simulator
)

echo "==> Installing required Rust targets..."
for target in "${TARGETS[@]}"; do
    rustup target add "$target" 2>/dev/null || true
done

echo "==> Building static libraries..."
for target in "${TARGETS[@]}"; do
    echo "    Building for $target..."
    cargo build $CARGO_FLAGS \
        --lib \
        --package "$PACKAGE_NAME" \
        --target "$target" \
        --manifest-path "$WORKSPACE_ROOT/Cargo.toml"
done

echo "==> Stripping debug symbols..."
for target in "${TARGETS[@]}"; do
    strip -S "$WORKSPACE_ROOT/target/$target/$PROFILE/$LIB_NAME"
done

echo "==> Creating universal (fat) libraries..."
mkdir -p "$OUT_DIR/ios-simulator-universal"
mkdir -p "$OUT_DIR/macos-universal"
mkdir -p "$OUT_DIR/tvos-simulator-universal"

# iOS Simulator universal (arm64 + x86_64)
lipo -create \
    "$WORKSPACE_ROOT/target/aarch64-apple-ios-sim/$PROFILE/$LIB_NAME" \
    "$WORKSPACE_ROOT/target/x86_64-apple-ios/$PROFILE/$LIB_NAME" \
    -output "$OUT_DIR/ios-simulator-universal/$LIB_NAME"

# macOS universal (arm64 + x86_64)
lipo -create \
    "$WORKSPACE_ROOT/target/aarch64-apple-darwin/$PROFILE/$LIB_NAME" \
    "$WORKSPACE_ROOT/target/x86_64-apple-darwin/$PROFILE/$LIB_NAME" \
    -output "$OUT_DIR/macos-universal/$LIB_NAME"

# tvOS Simulator universal (arm64 + x86_64)
lipo -create \
    "$WORKSPACE_ROOT/target/aarch64-apple-tvos-sim/$PROFILE/$LIB_NAME" \
    "$WORKSPACE_ROOT/target/x86_64-apple-tvos/$PROFILE/$LIB_NAME" \
    -output "$OUT_DIR/tvos-simulator-universal/$LIB_NAME"

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

echo "==> Preparing headers..."
HEADERS_IOS="$OUT_DIR/headers-ios"
HEADERS_SIM="$OUT_DIR/headers-sim"
HEADERS_MAC="$OUT_DIR/headers-mac"
HEADERS_TVOS="$OUT_DIR/headers-tvos"
HEADERS_TVOS_SIM="$OUT_DIR/headers-tvos-sim"
HEADERS_VISIONOS="$OUT_DIR/headers-visionos"
HEADERS_VISIONOS_SIM="$OUT_DIR/headers-visionos-sim"

for hdir in "$HEADERS_IOS" "$HEADERS_SIM" "$HEADERS_MAC" \
            "$HEADERS_TVOS" "$HEADERS_TVOS_SIM" \
            "$HEADERS_VISIONOS" "$HEADERS_VISIONOS_SIM"; do
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

echo "==> Building XCFramework..."
rm -rf "$XCFRAMEWORK_DIR"

xcodebuild -create-xcframework \
    -library "$WORKSPACE_ROOT/target/aarch64-apple-ios/$PROFILE/$LIB_NAME" \
        -headers "$HEADERS_IOS" \
    -library "$OUT_DIR/ios-simulator-universal/$LIB_NAME" \
        -headers "$HEADERS_SIM" \
    -library "$OUT_DIR/macos-universal/$LIB_NAME" \
        -headers "$HEADERS_MAC" \
    -library "$WORKSPACE_ROOT/target/aarch64-apple-tvos/$PROFILE/$LIB_NAME" \
        -headers "$HEADERS_TVOS" \
    -library "$OUT_DIR/tvos-simulator-universal/$LIB_NAME" \
        -headers "$HEADERS_TVOS_SIM" \
    -library "$WORKSPACE_ROOT/target/aarch64-apple-visionos/$PROFILE/$LIB_NAME" \
        -headers "$HEADERS_VISIONOS" \
    -library "$WORKSPACE_ROOT/target/aarch64-apple-visionos-sim/$PROFILE/$LIB_NAME" \
        -headers "$HEADERS_VISIONOS_SIM" \
    -output "$XCFRAMEWORK_DIR"

echo "==> Cleaning up temporary files..."
rm -rf "$HEADERS_IOS" "$HEADERS_SIM" "$HEADERS_MAC" \
       "$HEADERS_TVOS" "$HEADERS_TVOS_SIM" \
       "$HEADERS_VISIONOS" "$HEADERS_VISIONOS_SIM"
rm -rf "$OUT_DIR/ios-simulator-universal" "$OUT_DIR/macos-universal" \
       "$OUT_DIR/tvos-simulator-universal"

echo ""
echo "Done! Output:"
echo "  XCFramework:    $XCFRAMEWORK_DIR"
echo "  Swift bindings: $BINDINGS_DIR"
echo ""
echo "To use in your Swift project, add the XCFramework and the generated"
echo "Swift file ($BINDINGS_DIR/QdrantEdge.swift) to your Xcode project,"
echo "or use the Package.swift in this directory."
