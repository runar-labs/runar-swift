#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <timeout_seconds> <command> [args...]" >&2
  exit 2
fi

TIMEOUT="$1"; shift
CMD=("$@")

echo "[timeout:${TIMEOUT}s] Running: ${CMD[*]}"

# Start the command in background
"${CMD[@]}" &
PID=$!

# On Ctrl-C or termination, kill the whole tree
killtree() {
  local root=$1
  # Try graceful
  pkill -TERM -P "$root" 2>/dev/null || true
  kill -TERM "$root" 2>/dev/null || true
  sleep 1
  # Hard kill leftovers
  pkill -KILL -P "$root" 2>/dev/null || true
  kill -KILL "$root" 2>/dev/null || true
}
trap 'echo "[timeout] Caught signal, killing PID $PID"; killtree "$PID"; exit 130' INT TERM

# Wait up to TIMEOUT seconds
elapsed=0
while kill -0 "$PID" 2>/dev/null; do
  if [[ "$elapsed" -ge "$TIMEOUT" ]]; then
    echo "[timeout] Command exceeded ${TIMEOUT}s. Killing process tree..." >&2
    killtree "$PID"
    exit 124
  fi
  sleep 1
  elapsed=$((elapsed+1))
done

# Reap exit code
wait "$PID" || exit $?
