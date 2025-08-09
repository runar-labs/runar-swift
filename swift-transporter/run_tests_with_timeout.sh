#!/bin/bash

# Run Swift tests with timeout
# Usage: ./run_tests_with_timeout.sh [timeout_seconds] [test_filter]

TIMEOUT=${1:-30}  # Default 30 seconds
FILTER=${2:-""}   # Default no filter

echo "Running Swift tests with ${TIMEOUT}s timeout..."

# Start the test process in background
if [ -z "$FILTER" ]; then
    swift test &
else
    swift test --filter "$FILTER" &
fi

TEST_PID=$!

# Wait for timeout or completion
for i in $(seq 1 $TIMEOUT); do
    if ! kill -0 $TEST_PID 2>/dev/null; then
        break
    fi
    sleep 1
done

# Check if process is still running
if kill -0 $TEST_PID 2>/dev/null; then
    echo "Tests timed out after ${TIMEOUT}s, killing process tree..."
    pkill -TERM -P $TEST_PID 2>/dev/null || true
    kill -9 $TEST_PID 2>/dev/null || true
    exit 124
else
    wait $TEST_PID
    EXIT_CODE=$?
    echo "Tests finished (exit ${EXIT_CODE})"
    exit $EXIT_CODE
fi