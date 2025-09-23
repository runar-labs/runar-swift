#!/bin/bash

# Build script for Rust FFI with Apple features
# This script builds the Rust FFI crate and sets up the Swift package

set -e  # Exit on any error

# Configuration
RUST_WORKSPACE="/Users/rafael/dev/runar-swift/runar-rust"
SWIFT_PACKAGE="/Users/rafael/dev/runar-swift/swift-ffi"
BUILD_MODE="${1:-release}"  # Default to release, can be overridden with 'debug'

echo "🔧 Building Rust FFI with Apple features..."
echo "   Build mode: $BUILD_MODE"
echo "   Rust workspace: $RUST_WORKSPACE"
echo "   Swift package: $SWIFT_PACKAGE"

# Change to Rust workspace
cd "$RUST_WORKSPACE"

# Clean previous builds
echo "🧹 Cleaning previous builds..."
cargo clean -p runar_ffi

# Build with Apple features
echo "🔨 Building Rust FFI crate with apple-keystore feature..."
if [ "$BUILD_MODE" = "debug" ]; then
    cargo build -p runar_ffi --features apple-keystore
    TARGET_DIR="target/debug"
else
    cargo build -p runar_ffi --features apple-keystore --release
    TARGET_DIR="target/release"
fi

# Verify the library was built
LIBRARY_PATH="$RUST_WORKSPACE/$TARGET_DIR/librunar_ffi.dylib"
if [ ! -f "$LIBRARY_PATH" ]; then
    echo "❌ Error: Library not found at $LIBRARY_PATH"
    exit 1
fi

echo "✅ Rust FFI library built successfully at $LIBRARY_PATH"

# Copy library to Swift package
echo "📦 Copying library to Swift package..."
SWIFT_LIB_DIR="$SWIFT_PACKAGE/lib"
mkdir -p "$SWIFT_LIB_DIR"
cp "$LIBRARY_PATH" "$SWIFT_LIB_DIR/"

# Copy header file
echo "📄 Copying header file..."
HEADER_SOURCE="$RUST_WORKSPACE/runar-ffi/include/runar_ffi.h"
HEADER_DEST="$SWIFT_PACKAGE/Sources/CRunarFFI/include/runar_ffi.h"
cp "$HEADER_SOURCE" "$HEADER_DEST"

echo "✅ Build setup complete!"
echo "   Library: $SWIFT_LIB_DIR/librunar_ffi.dylib"
echo "   Header: $HEADER_DEST"
echo ""
echo "🚀 You can now run: cd $SWIFT_PACKAGE && swift test"
