#!/usr/bin/env bash

# run_all_tests.sh - Master test runner for cc-reflection
#
# WHY: Centralized test execution with clear output and error reporting
# USAGE: ./tests/run_all_tests.sh [unit|integration|all]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# Determine what to run
RUN_MODE="${1:-all}"

# Ensure tests never touch a developer's real ~/.claude (or fail in sandboxed HOME).
# This also makes CI runs hermetic and prevents flaky state leakage.
TEST_HOME="$(mktemp -d 2>/dev/null || mktemp -d -t cc-reflection-test-home)"
export HOME="$TEST_HOME"
export REFLECTION_BASE="${REFLECTION_BASE:-$HOME/.claude/reflections}"
export CC_LOG_DIR="${CC_LOG_DIR:-$REFLECTION_BASE/logs}"
mkdir -p "$REFLECTION_BASE" "$CC_LOG_DIR" 2>/dev/null || true

cleanup() {
    rm -rf "$TEST_HOME" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  CC-Reflection Test Suite${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check for bun (required for TypeScript tests)
if ! command -v bun &>/dev/null; then
    echo -e "${RED}Error: bun is required for tests${NC}"
    echo "Install: curl -fsSL https://bun.sh/install | bash"
    exit 1
fi

# Determine bats command
if command -v bats &>/dev/null; then
    BATS_CMD="bats"
    echo -e "${GREEN}✓ Using system bats${NC}"
elif [ -x "$SCRIPT_DIR/bats/bin/bats" ]; then
    BATS_CMD="$SCRIPT_DIR/bats/bin/bats"
    echo -e "${GREEN}✓ Using local bats (git submodule)${NC}"
else
    echo -e "${RED}Error: BATS not found${NC}"
    echo ""
    echo "Install options:"
    echo "  1. System-wide: brew install bats-core"
    echo "  2. Project-local: git submodule update --init --recursive"
    exit 1
fi

echo -e "${BLUE}Mode: ${RUN_MODE}${NC}"
echo ""

# Track test results
TOTAL_FAILURES=0

# Run unit tests
if [ "$RUN_MODE" = "all" ] || [ "$RUN_MODE" = "unit" ]; then
    echo -e "${BLUE}Running Unit Tests...${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if [ -d "$SCRIPT_DIR/unit" ] && [ -n "$(ls -A "$SCRIPT_DIR/unit"/*.bats 2>/dev/null)" ]; then
        if $BATS_CMD "$SCRIPT_DIR/unit"/*.bats; then
            echo -e "${GREEN}✓ Unit tests passed${NC}"
        else
            echo -e "${RED}✗ Unit tests failed${NC}"
            TOTAL_FAILURES=$((TOTAL_FAILURES + 1))
        fi
    else
        echo -e "${YELLOW}⚠ No unit tests found${NC}"
    fi
    echo ""
fi

# Run integration tests
if [ "$RUN_MODE" = "all" ] || [ "$RUN_MODE" = "integration" ]; then
    echo -e "${BLUE}Running Integration Tests...${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if [ -d "$SCRIPT_DIR/integration" ] && [ -n "$(ls -A "$SCRIPT_DIR/integration"/*.bats 2>/dev/null)" ]; then
        if $BATS_CMD "$SCRIPT_DIR/integration"/*.bats; then
            echo -e "${GREEN}✓ Integration tests passed${NC}"
        else
            echo -e "${RED}✗ Integration tests failed${NC}"
            TOTAL_FAILURES=$((TOTAL_FAILURES + 1))
        fi
    else
        echo -e "${YELLOW}⚠ No integration tests found${NC}"
    fi
    echo ""
fi

# Run security tests
if [ "$RUN_MODE" = "all" ] || [ "$RUN_MODE" = "security" ]; then
    echo -e "${BLUE}Running Security Tests...${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if [ -d "$SCRIPT_DIR/security" ] && [ -n "$(ls -A "$SCRIPT_DIR/security"/*.bats 2>/dev/null)" ]; then
        if $BATS_CMD "$SCRIPT_DIR/security"/*.bats; then
            echo -e "${GREEN}✓ Security tests passed${NC}"
        else
            echo -e "${RED}✗ Security tests failed${NC}"
            TOTAL_FAILURES=$((TOTAL_FAILURES + 1))
        fi
    else
        echo -e "${YELLOW}⚠ No security tests found${NC}"
    fi
    echo ""
fi

# Summary
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [ $TOTAL_FAILURES -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed${NC}"
    exit 0
else
    echo -e "${RED}✗ $TOTAL_FAILURES test suite(s) failed${NC}"
    exit 1
fi
