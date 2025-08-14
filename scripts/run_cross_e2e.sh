#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "[run_cross_e2e] Building Rust interop bins..." >&2
eval "$($ROOT_DIR/scripts/build_rust_interop.sh | sed -n 's/^CLIENT_BIN=\(.*\)$/CLIENT_BIN="\1"/p; s/^SERVER_BIN=\(.*\)$/SERVER_BIN="\1"/p')"

if [[ -z "${CLIENT_BIN:-}" || -z "${SERVER_BIN:-}" ]]; then
  echo "Failed to resolve interop binaries" >&2
  exit 1
fi

TEMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TEMP_DIR"; }
trap cleanup EXIT

echo "[run_cross_e2e] Temp dir: $TEMP_DIR" >&2

echo "[run_cross_e2e] Running Swift tests (filter CrossLanguageE2E)..." >&2
pushd "$ROOT_DIR/swift-transporter" >/dev/null

# Export paths for the XCTest to consume
export RUNAR_RUST_CLIENT_BIN="$CLIENT_BIN"
export RUNAR_RUST_SERVER_BIN="$SERVER_BIN"
export RUNAR_E2E_TMPDIR="$TEMP_DIR"

RUST_LOG=info,runar_node=debug,runar_transport_tests=debug,quinn=info swift test --filter CrossLanguageE2E | cat

popd >/dev/null


