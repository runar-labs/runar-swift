#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "[run_cross_e2e] Building Rust interop bins..." >&2
# shellcheck disable=SC2046
eval "$($ROOT_DIR/scripts/build_rust_interop.sh | sed -n 's/^CLIENT_BIN=\(.*\)$/CLIENT_BIN="\1"/p; s/^SERVER_BIN=\(.*\)$/SERVER_BIN="\1"/p')"

# Fallback resolution if eval didn't populate paths
if [[ -z "${CLIENT_BIN:-}" || -z "${SERVER_BIN:-}" ]]; then
	if [[ -n "${RUNAR_RUST_DIR:-}" ]]; then
		if [[ -z "${CLIENT_BIN:-}" ]]; then
			CAND_CLIENT=$(command -v find >/dev/null 2>&1 && find "$RUNAR_RUST_DIR/target/release" -type f -name quic_interop_client -perm -111 2>/dev/null | head -n1 || true)
			[[ -n "${CAND_CLIENT:-}" ]] && CLIENT_BIN="$CAND_CLIENT"
		fi
		if [[ -z "${SERVER_BIN:-}" ]]; then
			CAND_SERVER=$(command -v find >/dev/null 2>&1 && find "$RUNAR_RUST_DIR/target/release" -type f -name quic_interop_server -perm -111 2>/dev/null | head -n1 || true)
			[[ -n "${CAND_SERVER:-}" ]] && SERVER_BIN="$CAND_SERVER"
		fi
	fi
fi

if [[ -z "${CLIENT_BIN:-}" || -z "${SERVER_BIN:-}" ]]; then
	echo "Failed to resolve interop binaries" >&2
	exit 1
fi

echo "[run_cross_e2e] Resolved CLIENT_BIN=$CLIENT_BIN" >&2
echo "[run_cross_e2e] Resolved SERVER_BIN=$SERVER_BIN" >&2

TEMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TEMP_DIR"; }
trap cleanup EXIT

echo "[run_cross_e2e] Temp dir: $TEMP_DIR" >&2

echo "[run_cross_e2e] Running Swift tests (filter CrossLanguageE2E) with timeout..." >&2
pushd "$ROOT_DIR/swift-transporter" >/dev/null

# Export paths for the XCTest to consume
export RUNAR_RUST_CLIENT_BIN="$CLIENT_BIN"
export RUNAR_RUST_SERVER_BIN="$SERVER_BIN"
export RUNAR_E2E_TMPDIR="$TEMP_DIR"

# Use gtimeout if available (macOS), fallback to timeout
TIMEOUT_CMD="timeout"
if command -v gtimeout >/dev/null 2>&1; then TIMEOUT_CMD="gtimeout"; fi

# 90s overall timeout for this focused suite
RUST_LOG=info,runar_node=debug,runar_transport_tests=debug,quinn=info $TIMEOUT_CMD 90 swift test --filter CrossLanguageE2E -v | cat

popd >/dev/null


