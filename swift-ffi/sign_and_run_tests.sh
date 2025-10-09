#!/bin/bash

# Script to run tests with LLDB and capture stack trace on crash
cd /Users/rafael/dev/runar-swift/swift-ffi

# Build the test first
echo "Building test..."
swift build --build-tests

# Run with LLDB to capture crash
echo "Running test with LLDB..."
lldb --batch \
  -o "settings set target.process.stop-on-sharedlibrary-events false" \
  -o "run test --filter FFIE2EIntegrationTest" \
  -o "bt" \
  -o "thread backtrace all" \
  -o "quit" \
  swift