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

packages=(swift-common swift-keys swift-serializer swift-serializer-macros swift-transporter)

echo "== Swift versions =="
swift --version || true

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


