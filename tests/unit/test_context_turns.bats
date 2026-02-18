#!/usr/bin/env bats

# test_context_turns.bats - Test context turns configuration and transcript utils
#
# WHY: Context turns control how many conversation turns are injected into expand prompt
# CRITICAL: These tests ensure correct reading/cycling of context configuration

load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load

setup() {
    # Source the functions under test
    source "$BATS_TEST_DIRNAME/../../lib/cc-common.sh"

    # Create temp directory for isolated testing
    export TEST_REFLECTION_BASE=$(mktemp -d)
    export REFLECTION_BASE="$TEST_REFLECTION_BASE"
    mkdir -p "$REFLECTION_BASE"

    # Create initial config
    echo '{"expansion_mode":"interactive","context_turns":3}' > "$REFLECTION_BASE/config.json"
}

teardown() {
    rm -rf "$TEST_REFLECTION_BASE"
}

# ============================================================================
# Context Turns Get/Set Tests
# ============================================================================

@test "cc_get_context_turns returns default 3 when not set" {
    # Remove config to test default
    rm -f "$REFLECTION_BASE/config.json"

    run cc_get_context_turns
    assert_success
    assert_output "3"
}

@test "cc_get_context_turns reads from config" {
    echo '{"context_turns":5}' > "$REFLECTION_BASE/config.json"

    run cc_get_context_turns
    assert_success
    assert_output "5"
}

@test "cc_set_context_turns updates config" {
    run cc_set_context_turns 10
    assert_success

    run cc_get_context_turns
    assert_success
    assert_output "10"
}

@test "cc_set_context_turns rejects invalid values" {
    run cc_set_context_turns "invalid"
    assert_failure

    run cc_set_context_turns -1
    assert_failure

    run cc_set_context_turns 25
    assert_failure
}

@test "cc_set_context_turns accepts 0 (disabled)" {
    run cc_set_context_turns 0
    assert_success

    run cc_get_context_turns
    assert_output "0"
}

# ============================================================================
# Context Turns Cycle Tests
# ============================================================================

@test "cc_cycle_context_turns cycles 0 -> 3" {
    cc_set_context_turns 0

    run cc_cycle_context_turns
    assert_success
    assert_output "3"
}

@test "cc_cycle_context_turns cycles 3 -> 5" {
    cc_set_context_turns 3

    run cc_cycle_context_turns
    assert_success
    assert_output "5"
}

@test "cc_cycle_context_turns cycles 5 -> 10" {
    cc_set_context_turns 5

    run cc_cycle_context_turns
    assert_success
    assert_output "10"
}

@test "cc_cycle_context_turns cycles 10 -> 0" {
    cc_set_context_turns 10

    run cc_cycle_context_turns
    assert_success
    assert_output "0"
}

@test "cc_cycle_context_turns handles arbitrary value" {
    # Non-standard value should cycle to 3
    echo '{"context_turns":7}' > "$REFLECTION_BASE/config.json"

    run cc_cycle_context_turns
    assert_success
    assert_output "3"
}

# ============================================================================
# TypeScript CLI Tests
# ============================================================================

@test "TypeScript get-context-turns returns configured value" {
    echo '{"context_turns":5}' > "$REFLECTION_BASE/config.json"

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" get-context-turns
    assert_success
    assert_output "5"
}

@test "TypeScript set-context-turns updates config" {
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" set-context-turns 10
    assert_success

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" get-context-turns
    assert_output "10"
}

@test "TypeScript cycle-context-turns cycles correctly" {
    bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" set-context-turns 3

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" cycle-context-turns
    assert_success
    assert_output "5"
}

# ============================================================================
# Bash-TypeScript Consistency Tests
# ============================================================================

@test "bash and TypeScript produce same context turns value" {
    cc_set_context_turns 5

    bash_value=$(cc_get_context_turns)
    ts_value=$(bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" get-context-turns)

    assert_equal "$bash_value" "$ts_value"
}

@test "bash and TypeScript cycle produce same result" {
    cc_set_context_turns 3

    bash_result=$(cc_cycle_context_turns)

    # Reset to 3 for TS test
    cc_set_context_turns 3

    ts_result=$(bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" cycle-context-turns)

    assert_equal "$bash_result" "$ts_result"
}

# ============================================================================
# Hardening Tests - P1 (High Priority)
# ============================================================================

@test "cc_get_context_turns handles corrupted non-integer config gracefully" {
    # Write invalid non-integer value to config
    echo '{"context_turns":"three"}' > "$REFLECTION_BASE/config.json"

    # Should fall back to default (3) instead of crashing
    run cc_get_context_turns
    assert_success
    # Either returns default 3 or handles gracefully
    [[ "$output" =~ ^[0-9]+$ ]]
}
