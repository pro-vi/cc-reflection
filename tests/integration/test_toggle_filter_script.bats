#!/usr/bin/env bats

# test_toggle_filter_script.bats - Tests for bin/cc-reflect-toggle-filter script
#
# WHY: Validates the actual script entrypoint (not just underlying functions)
# TESTS: State transitions, output format, persistence

load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load
load ../test_helper/bats-file/load

SCRIPT_DIR="$BATS_TEST_DIRNAME/../../bin"

setup() {
    # Create isolated test environment
    export TEST_BASE_DIR="$BATS_TMPDIR/test-reflections-$$"
    export REFLECTION_BASE="$TEST_BASE_DIR"
    mkdir -p "$TEST_BASE_DIR"

    # Store original filter to restore after tests
    ORIGINAL_FILTER=$(bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" get-filter "$TEST_BASE_DIR" 2>/dev/null || echo "active")
}

teardown() {
    # Clean up test directory
    rm -rf "$TEST_BASE_DIR"
}

# ============================================================================
# SCRIPT EXISTENCE AND EXECUTABILITY
# ============================================================================

@test "toggle-filter: script exists and is executable" {
    assert_file_exists "$SCRIPT_DIR/cc-reflect-toggle-filter"
    [ -x "$SCRIPT_DIR/cc-reflect-toggle-filter" ]
}

# ============================================================================
# STATE TRANSITIONS
# ============================================================================

@test "toggle-filter: active → outdated" {
    # Set initial state
    bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" set-filter "active" "$TEST_BASE_DIR" >/dev/null

    # Run the script
    run "$SCRIPT_DIR/cc-reflect-toggle-filter"
    assert_success
    assert_output "outdated"
}

@test "toggle-filter: outdated → archived" {
    bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" set-filter "outdated" "$TEST_BASE_DIR" >/dev/null

    run "$SCRIPT_DIR/cc-reflect-toggle-filter"
    assert_success
    assert_output "archived"
}

@test "toggle-filter: archived → all" {
    bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" set-filter "archived" "$TEST_BASE_DIR" >/dev/null

    run "$SCRIPT_DIR/cc-reflect-toggle-filter"
    assert_success
    assert_output "all"
}

@test "toggle-filter: all → active (wrap around)" {
    bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" set-filter "all" "$TEST_BASE_DIR" >/dev/null

    run "$SCRIPT_DIR/cc-reflect-toggle-filter"
    assert_success
    assert_output "active"
}

# ============================================================================
# PERSISTENCE
# ============================================================================

@test "toggle-filter: persists new filter to config" {
    bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" set-filter "active" "$TEST_BASE_DIR" >/dev/null

    # Toggle
    "$SCRIPT_DIR/cc-reflect-toggle-filter" >/dev/null

    # Verify persistence
    result=$(bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" get-filter "$TEST_BASE_DIR")
    assert_equal "$result" "outdated"
}

@test "toggle-filter: full cycle persists all states" {
    bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" set-filter "active" "$TEST_BASE_DIR" >/dev/null

    # Cycle through all 4 states
    "$SCRIPT_DIR/cc-reflect-toggle-filter" >/dev/null  # → outdated
    "$SCRIPT_DIR/cc-reflect-toggle-filter" >/dev/null  # → archived
    "$SCRIPT_DIR/cc-reflect-toggle-filter" >/dev/null  # → all
    "$SCRIPT_DIR/cc-reflect-toggle-filter" >/dev/null  # → active

    # Should be back to active
    result=$(bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" get-filter "$TEST_BASE_DIR")
    assert_equal "$result" "active"
}

# ============================================================================
# OUTPUT FORMAT
# ============================================================================

@test "toggle-filter: outputs only the new filter value (no extra text)" {
    bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" set-filter "active" "$TEST_BASE_DIR" >/dev/null

    run "$SCRIPT_DIR/cc-reflect-toggle-filter"

    # Output should be exactly "outdated" with no extra whitespace/text
    [ "$(echo "$output" | wc -l)" -eq 1 ]
    assert_output "outdated"
}
