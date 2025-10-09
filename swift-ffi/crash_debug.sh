#!/bin/bash

set -e

# Set environment variables
export DYLD_LIBRARY_PATH="/Users/rafael/dev/runar-swift/runar-rust/target/release:/Users/rafael/dev/runar-swift/runar-rust/target/release/deps"
export RUST_LOG=trace
export RUST_BACKTRACE=1

echo "Starting crash debug script..."
echo "Environment:"
echo "DYLD_LIBRARY_PATH=$DYLD_LIBRARY_PATH"
echo "RUST_LOG=$RUST_LOG"
echo "RUST_BACKTRACE=$RUST_BACKTRACE"

# Run the test and capture output
echo "Running test..."
cd /Users/rafael/dev/runar-swift/swift-ffi

# Use timeout to prevent hanging
timeout 30s swift test --filter FFIE2EIntegrationTest 2>&1 | tee crash_output.log

echo "Test completed. Check crash_output.log for details."

