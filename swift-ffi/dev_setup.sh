#!/bin/bash

# Development setup script for Swift FFI package
# This script sets up the complete development environment

set -e

echo "🚀 Setting up Swift FFI development environment..."

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWIFT_PACKAGE="$SCRIPT_DIR"

# Run the build script
echo "📦 Building Rust FFI..."
"$SWIFT_PACKAGE/build_rust_ffi.sh" "$@"

# Verify setup
echo "🔍 Verifying setup..."
cd "$SWIFT_PACKAGE"

# Check if library exists
if [ ! -f "lib/librunar_ffi.dylib" ]; then
    echo "❌ Error: Library not found at lib/librunar_ffi.dylib"
    exit 1
fi

# Check if header exists
if [ ! -f "Sources/CRunarFFI/include/runar_ffi.h" ]; then
    echo "❌ Error: Header not found at Sources/CRunarFFI/include/runar_ffi.h"
    exit 1
fi

echo "✅ Development setup complete!"
echo ""
echo "🎯 Available commands:"
echo "   swift test                    # Run all tests"
echo "   swift test --filter FFIE2E    # Run specific test"
echo "   swift build                   # Build the package"
echo ""
echo "🔄 To rebuild Rust FFI:"
echo "   ./build_rust_ffi.sh [debug|release]"
