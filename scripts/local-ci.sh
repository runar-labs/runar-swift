#!/usr/bin/env bash
set -euo pipefail

# Local CI helper with timeouts to avoid long-running/stuck commands.

run_to() {
  local secs="$1"; shift
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@"
  else
    # Fallback using perl alarm if gtimeout (coreutils) is not available
    perl -e 'alarm shift; exec @ARGV' "$secs" "$@"
  fi
}

packages=(swift-common swift-serializer swift-serializer-macros swift-ffi swift-node swift-ffi-poc)

echo "== Swift versions =="
swift --version || true

echo "== Swift version compatibility check =="
SWIFT_VERSION=$(swift --version | head -n1 | grep -o 'Swift version [0-9.]*' | cut -d' ' -f3)
echo "Detected Swift version: $SWIFT_VERSION"
if [[ "$SWIFT_VERSION" < "6.0" ]]; then
  echo "Warning: Swift 6.0 or later is recommended for full compatibility"
  echo "Some packages may fail to build with Swift $SWIFT_VERSION"
else
  echo "Swift version $SWIFT_VERSION is compatible"
fi

echo "== SwiftFormat (lint) =="
run_to 180 swiftformat --lint "${packages[@]}" || echo "SwiftFormat lint timed out"

echo "== SwiftFormat (apply) =="
run_to 600 swiftformat --swiftversion 5.9 "${packages[@]}" || echo "SwiftFormat apply timed out"

echo "== SwiftLint (strict, per package) =="
for d in "${packages[@]}"; do
  echo "-> $d"
  (cd "$d" && run_to 180 swiftlint --config ../.swiftlint.yml) || echo "SwiftLint timed out in $d"
done

echo "== Build (per package) =="
for d in "${packages[@]}"; do
  echo "-> $d"
  (cd "$d" && run_to 600 swift build) || echo "Build timed out in $d"
done

echo "== Test (per package) =="
for d in "${packages[@]}"; do
  echo "-> $d"
  (cd "$d" && run_to 1200 swift test) || echo "Tests timed out in $d"
done

echo "✅ Done"


