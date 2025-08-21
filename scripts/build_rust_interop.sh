#!/usr/bin/env bash
set -euo pipefail

# Build the Rust interop binaries and print their absolute paths
# Uses RUNAR_RUST_DIR if set; otherwise tries a local submodule fallback

resolve_repo_dir() {
  if [[ -n "${RUNAR_RUST_DIR:-}" ]]; then
    echo "$RUNAR_RUST_DIR"
    return 0
  fi
  # Fallback: local runar-rust directory
  local here
  here="$(cd "$(dirname "$0")/.." && pwd)"
  local submodule="$here/runar-rust"
  if [[ -d "$submodule" ]]; then
    echo "$submodule"
    return 0
  fi
  echo "RUNAR_RUST_DIR not set and no runar-rust directory found at $submodule" >&2
  exit 1
}

rust_repo="$(resolve_repo_dir)"

# The test crate path where the binaries live
crate_dir="$rust_repo/runar-transport-tests"
if [[ ! -d "$crate_dir" ]]; then
  echo "Expected crate directory not found: $crate_dir" >&2
  exit 1
fi

echo "[build_rust_interop] Using Rust repo: $rust_repo" >&2
pushd "$crate_dir" >/dev/null

# Build with JSON messages to capture executable paths (portable, no bash 4 mapfile)
bins=$(cargo build --release --message-format json | jq -r 'select(.reason=="compiler-artifact" and (.target.kind|index("bin"))) | .executable')

client_bin=""; server_bin=""
while IFS= read -r b; do
  [ -z "$b" ] && continue
  base="$(basename "$b")"
  if [ "$base" = "quic_interop_client" ]; then client_bin="$b"; fi
  if [ "$base" = "quic_interop_server" ]; then server_bin="$b"; fi
done <<EOF
$bins
EOF

if [[ -z "$client_bin" || -z "$server_bin" ]]; then
  echo "Failed to resolve interop binaries" >&2
  exit 1
fi

echo "CLIENT_BIN=$client_bin"
echo "SERVER_BIN=$server_bin"

popd >/dev/null


