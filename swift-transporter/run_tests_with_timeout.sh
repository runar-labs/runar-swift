#!/bin/bash

# Test runner script with timeouts to prevent hanging tests
# Usage: ./run_tests_with_timeout.sh [test_name]

set -e

# Default timeout in seconds
DEFAULT_TIMEOUT=60

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🧪 Running RunarTransporter tests with timeout protection...${NC}"

# Function to run tests with timeout
run_tests_with_timeout() {
    local test_name="$1"
    local timeout="${2:-$DEFAULT_TIMEOUT}"
    
    echo -e "${YELLOW}⏱️  Running tests with ${timeout}s timeout...${NC}"
    
    if [ -n "$test_name" ]; then
        echo -e "${YELLOW}🎯 Running specific test: $test_name${NC}"
        $TIMEOUT_CMD $timeout swift test --filter "$test_name" || {
            echo -e "${RED}❌ Test '$test_name' failed or timed out after ${timeout}s${NC}"
            return 1
        }
    else
        echo -e "${YELLOW}🚀 Running all tests...${NC}"
        $TIMEOUT_CMD $timeout swift test || {
            echo -e "${RED}❌ Tests failed or timed out after ${timeout}s${NC}"
            return 1
        }
    fi
    
    echo -e "${GREEN}✅ Tests completed successfully!${NC}"
}

# Check if timeout command is available (try both system and Homebrew versions)
TIMEOUT_CMD=""
if command -v timeout &> /dev/null; then
    TIMEOUT_CMD="timeout"
elif command -v gtimeout &> /dev/null; then
    TIMEOUT_CMD="gtimeout"
else
    echo -e "${RED}❌ 'timeout' command not found. Please install it or use a different method.${NC}"
    echo -e "${YELLOW}💡 On macOS, you can install it with: brew install coreutils${NC}"
    exit 1
fi

# Run tests
if [ $# -eq 0 ]; then
    # No arguments - run all tests
    run_tests_with_timeout
elif [ $# -eq 1 ]; then
    # One argument - run specific test
    run_tests_with_timeout "$1"
elif [ $# -eq 2 ]; then
    # Two arguments - run specific test with custom timeout
    run_tests_with_timeout "$1" "$2"
else
    echo -e "${RED}❌ Usage: $0 [test_name] [timeout_seconds]${NC}"
    echo -e "${YELLOW}Examples:${NC}"
    echo -e "  $0                    # Run all tests with default timeout"
    echo -e "  $0 DiscoveryServiceTests  # Run specific test with default timeout"
    echo -e "  $0 DiscoveryServiceTests 30  # Run specific test with 30s timeout"
    exit 1
fi