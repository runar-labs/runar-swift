# Task 7: Automated Build Setup for Rust FFI with Apple Features

## Overview
This task creates an automated build system that properly builds the Rust FFI crate with Apple features, copies the necessary files to the Swift package, and configures the Swift package to run tests without manual environment setup.

## 🎯 **Current Problem**
Currently, running Swift tests requires manual setup:
```bash
# This works but is cumbersome:
export DYLD_LIBRARY_PATH=/Users/rafael/dev/runar-swift/runar-rust/target/debug:/Users/rafael/dev/runar-swift/runar-rust/target/debug/deps && swift test -Xlinker -L/Users/rafael/dev/runar-swift/runar-rust/target/debug -Xlinker -lrunar_ffi -q

# This fails with fatalError:
swift test
```

**Note**: This task assumes that Task 6 (Swift FFI API updates) has been completed first. The Swift code needs to be updated to use the new Rust FFI API before this build automation will work.

## 🎯 **Target Solution**
Create a simple build script that:
1. Builds the Rust FFI crate with proper Apple features
2. Copies the built library and headers to the Swift package
3. Configures the Swift package to work without manual environment setup
4. Allows running `swift test` directly (just like before)

**Goal**: Run `swift test` directly without any manual environment setup, just like we could initially.

## 📋 **Required Changes**

### **Phase 1: Create Build Script**

#### **1.1 Create `build_rust_ffi.sh`**
**File:** `swift-ffi/build_rust_ffi.sh`

**Purpose:** Automated script to build Rust FFI with Apple features and set up Swift package

**Script Content:**
```bash
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
```

#### **1.2 Make Script Executable**
```bash
chmod +x swift-ffi/build_rust_ffi.sh
```

### **Phase 2: Update Swift Package Configuration**

#### **2.1 Update Package.swift**
**File:** `swift-ffi/Package.swift`

**Current Issues:**
- Hardcoded paths to `/Users/rafael/dev/runar-rust/target/release`
- No proper library search path for the copied library
- Missing rpath configuration for the copied library

**Required Changes:**
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-ffi",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(name: "SwiftFFI", targets: ["SwiftFFI"]),
        .library(name: "RunarFFI", targets: ["SwiftFFI"]), // Alias for backward compatibility
    ],
    dependencies: [
        .package(url: "https://github.com/valpackett/SwiftCBOR.git", from: "0.5.0"),
        .package(path: "../swift-common"),
    ],
    targets: [
        .target(
            name: "CRunarFFI",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include"),
            ]
        ),
        .target(
            name: "SwiftFFI",
            dependencies: ["CRunarFFI", .product(name: "SwiftCommon", package: "swift-common"), .product(name: "SwiftCBOR", package: "SwiftCBOR")],
            swiftSettings: [],
            linkerSettings: [
                .linkedLibrary("runar_ffi"),
                // Use the copied library in the Swift package
                .unsafeFlags(["-Xlinker", "-L", "-Xlinker", "$(SRCROOT)/lib"]),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "$(SRCROOT)/lib"]),
                // Fallback to Rust workspace (for development)
                .unsafeFlags(["-Xlinker", "-L", "-Xlinker", "/Users/rafael/dev/runar-swift/runar-rust/target/release"]),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "/Users/rafael/dev/runar-swift/runar-rust/target/release"]),
                .unsafeFlags(["-Xlinker", "-L", "-Xlinker", "/Users/rafael/dev/runar-swift/runar-rust/target/release/deps"]),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "/Users/rafael/dev/runar-swift/runar-rust/target/release/deps"]),
            ]
        ),
        .testTarget(
            name: "SwiftFFITests",
            dependencies: ["SwiftFFI", .product(name: "SwiftCBOR", package: "SwiftCBOR")],
            exclude: ["SwiftFFITests/FFIE2EIntegrationTest_baseline.swift.disabled"]
        ),
    ]
)
```

#### **2.2 Update Module Map**
**File:** `swift-ffi/Sources/CRunarFFI/include/module.modulemap`

**Current Content:**
```
module CRunarFFI [system] {
	header "runar_ffi_wrapper.h"
	export *
}
```

**Required Change:**
```
module CRunarFFI [system] {
	header "runar_ffi_wrapper.h"
	link "runar_ffi"
	export *
}
```

### **Phase 3: Create Development Setup Script**

#### **3.1 Create `dev_setup.sh`**
**File:** `swift-ffi/dev_setup.sh`

**Purpose:** One-time development setup script

**Script Content:**
```bash
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
echo "🎯 You can now run:"
echo "   swift test                    # Run all tests"
echo "   swift test --filter FFIE2E    # Run specific test"
echo "   swift build                   # Build the package"
echo ""
echo "🔄 To rebuild Rust FFI after changes:"
echo "   ./build_rust_ffi.sh [debug|release]"
```

### **Phase 4: Update .gitignore**

#### **4.1 Update .gitignore**
**File:** `swift-ffi/.gitignore`

**Add these entries:**
```
# Rust FFI build artifacts
lib/
*.dylib
*.so
*.a

# Build artifacts
.build/
DerivedData/
```

### **Phase 5: Create Documentation**

#### **5.1 Update README.md**
**File:** `swift-ffi/README.md`

**Add development section:**
```markdown
## Development Setup

### Quick Start
```bash
# Set up the development environment
./dev_setup.sh

# Run tests
swift test
```

### Manual Setup
```bash
# Build Rust FFI with Apple features
./build_rust_ffi.sh

# Run tests
swift test
```

### Available Scripts
- `./dev_setup.sh` - Complete development setup (one-time)
- `./build_rust_ffi.sh [debug|release]` - Build Rust FFI (run after Rust changes)
```

## 🧪 **Testing Strategy**

### **Phase 1: Verify Build Script**
1. Run `./build_rust_ffi.sh` and verify:
   - Rust FFI builds successfully with apple-keystore feature
   - Library is copied to `lib/` directory
   - Header is copied to `Sources/CRunarFFI/include/`
   - No build errors

### **Phase 2: Verify Swift Package**
1. Run `swift build` and verify:
   - Package builds successfully
   - No linking errors
   - Library is found and linked

### **Phase 3: Verify Tests**
1. Run `swift test` and verify:
   - All tests pass
   - No fatalError crashes
   - No manual environment setup needed

### **Phase 4: Verify Development Workflow**
1. Run `./dev_setup.sh` and verify:
   - Complete setup works
   - `swift test` runs successfully without manual setup
   - Development environment is ready

## 🚨 **Critical Points**

### **Library Path Resolution**
- **CRITICAL**: The Swift package must find the library without manual DYLD_LIBRARY_PATH
- **CRITICAL**: Use `$(SRCROOT)/lib` for relative paths in Package.swift
- **CRITICAL**: Include both copied library and fallback to Rust workspace

### **Header Synchronization**
- **CRITICAL**: Header file must be copied after each Rust build
- **CRITICAL**: Header must match the built library version
- **CRITICAL**: Module map must link against the correct library

### **Build Mode Consistency**
- **CRITICAL**: Swift package must use the same build mode as Rust
- **CRITICAL**: Debug vs Release builds must be consistent
- **CRITICAL**: Library search paths must match the build mode

## 📊 **Expected Outcomes**

### **Before (Current State)**
- ❌ Manual environment setup required
- ❌ `swift test` fails with fatalError
- ❌ Complex command line with DYLD_LIBRARY_PATH
- ❌ No automated build process

### **After (Target State)**
- ✅ `swift test` works directly
- ✅ Automated build process
- ✅ No manual environment setup
- ✅ Simple development workflow
- ✅ Consistent library and header versions

## 🔄 **Implementation Order**

**Prerequisite**: Complete Task 6 (Swift FFI API updates) first!

1. **Create Build Script** (Phase 1)
2. **Update Swift Package Configuration** (Phase 2)
3. **Create Development Setup Script** (Phase 3)
4. **Update .gitignore** (Phase 4)
5. **Create Documentation** (Phase 5)
6. **Test Everything** (Testing Strategy)

## 📝 **Usage Examples**

### **Development Workflow**
```bash
# Initial setup (one-time)
cd swift-ffi
./dev_setup.sh

# Run tests (just like before!)
swift test

# Run specific test
swift test --filter FFIE2E

# After making Rust changes, rebuild FFI
./build_rust_ffi.sh debug
```

### **CI/CD Integration**
```bash
# In CI pipeline
cd swift-ffi
./build_rust_ffi.sh release
swift test
```

## 🎯 **Success Criteria**

- [ ] `swift test` works without manual environment setup
- [ ] Build script successfully builds Rust FFI with Apple features
- [ ] Library and headers are properly copied to Swift package
- [ ] Swift package finds and links the library correctly
- [ ] All tests pass without crashes
- [ ] Development workflow is simple (just run `swift test`)
- [ ] No hardcoded paths in Package.swift
- [ ] Proper .gitignore for build artifacts
- [ ] Documentation is clear and complete

## 🔧 **Troubleshooting**

### **Common Issues**

1. **Library not found**
   - Check if `lib/librunar_ffi.dylib` exists
   - Verify build script ran successfully
   - Check library search paths in Package.swift

2. **Header mismatch**
   - Ensure header is copied after Rust build
   - Verify header matches library version
   - Check module map configuration

3. **Linking errors**
   - Verify library search paths
   - Check rpath configuration
   - Ensure library is built with correct features

4. **Test failures**
   - Check if library is properly linked
   - Verify FFI function signatures match
   - Check for memory management issues

### **Debug Commands**
```bash
# Check library dependencies
otool -L lib/librunar_ffi.dylib

# Check Swift package configuration
swift package show-dependencies

# Check build settings
swift build --verbose

# Check test output
swift test --verbose
```
