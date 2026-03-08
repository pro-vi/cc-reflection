#!/usr/bin/env bats
# Test that cc-reflect-expand delegates to cc-hall agent correctly

load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'

# ============================================================================
# cc-reflect-expand delegates to cc-hall agent
# ============================================================================
#
# Since v2.0.0, cc-reflection requires cc-hall as a hard dependency.
# cc-reflect-expand calls cc-hall agent with --model and --skip-permissions
# flags derived from centralized config getters.
#
# These tests verify the delegation pattern is correct.

@test "cc-reflect-expand: uses cc-hall agent for interactive and auto modes" {
    # Count actual invocation lines (not comments)
    run bash -c "grep -n 'cc-hall agent' bin/cc-reflect-expand | grep -v '^\s*#' | grep -v '^[0-9]*:#' | wc -l"
    assert_success

    count=$(echo "$output" | tr -d '[:space:]')
    assert_equal "$count" "2"
}

@test "cc-reflect-expand: passes model via cc_get_model" {
    # Verify both cc-hall agent calls include --model with cc_get_model
    run grep -c 'cc_get_model' bin/cc-reflect-expand
    assert_success

    count=$(echo "$output" | tr -d '[:space:]')
    # At least 2 calls (one per mode)
    [ "$count" -ge 2 ]
}

@test "cc-reflect-expand: passes permissions via cc_get_permissions_mode" {
    # Verify both cc-hall agent calls include --skip-permissions conditional
    run grep -c 'cc_get_permissions_mode' bin/cc-reflect-expand
    assert_success

    count=$(echo "$output" | tr -d '[:space:]')
    # At least 2 calls (one per mode)
    [ "$count" -ge 2 ]
}

@test "cc-reflect-expand: no standalone tmux fallback" {
    # Verify there's no _HAS_CC_HALL conditional or ORIGINAL_TMUX handling
    run grep -E '_HAS_CC_HALL|ORIGINAL_TMUX' bin/cc-reflect-expand
    assert_failure
}

@test "cc-reflect-expand: no hardcoded model specifications" {
    # Verify no cc-hall agent calls use hardcoded --model values
    run grep -E 'cc-hall agent.*--model[[:space:]]+(sonnet|haiku|opus)' bin/cc-reflect-expand
    assert_failure
}

@test "cc-reflect-expand: no direct claude invocations" {
    # All Claude invocations should go through cc-hall agent, not direct 'claude' calls
    # Filter out comments, log lines, and the Usage line
    run bash -c "grep -n 'claude ' bin/cc-reflect-expand | grep -vE '(#|cc_log_|echo |Claude Code)' | grep -vE 'cc-hall'"
    assert_failure
}
