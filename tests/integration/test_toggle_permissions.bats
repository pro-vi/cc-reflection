#!/usr/bin/env bats

# test_toggle_permissions.bats - Integration tests for permissions toggle functionality
#
# WHY: Ensures toggle script, bash functions, and TypeScript state manager work together correctly
# TESTS: Toggle script execution, config persistence, flag generation

load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load

setup() {
    # Create isolated test directory
    TEST_DIR=$(mktemp -d)
    ORIGINAL_PWD=$(pwd)
    cd "$TEST_DIR"

    # Create isolated config for testing
    TEST_CONFIG_DIR="$TEST_DIR/.claude/reflections"
    mkdir -p "$TEST_CONFIG_DIR"

    # Create initial config with permissions enabled (default)
    cat > "$TEST_CONFIG_DIR/config.json" << EOF
{
  "enabled": true,
  "ttl_hours": 24,
  "expansion_mode": "interactive",
  "skip_permissions": true,
  "menu_filter": "active"
}
EOF

    # Override config path BEFORE sourcing cc-common.sh
    export REFLECTION_BASE="$TEST_CONFIG_DIR"
    source "$BATS_TEST_DIRNAME/../../lib/cc-common.sh"
}

teardown() {
    cd "$ORIGINAL_PWD"
    rm -rf "$TEST_DIR"
}

@test "toggle-permissions script exists and is executable" {
    TOGGLE_SCRIPT="$BATS_TEST_DIRNAME/../../bin/cc-reflect-toggle-permissions"
    [ -x "$TOGGLE_SCRIPT" ]
}

@test "permissions mode starts as enabled by default" {
    # Use bun to read config directly
    mode=$(bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" get-permissions)
    assert_equal "$mode" "enabled"
}

@test "toggle-permissions switches from disabled to enabled" {
    TOGGLE_SCRIPT="$BATS_TEST_DIRNAME/../../bin/cc-reflect-toggle-permissions"

    # Set to disabled first (since default is now enabled)
    bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" set-permissions disabled > /dev/null

    # Verify initial state is disabled
    initial_mode=$(bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" get-permissions)
    assert_equal "$initial_mode" "disabled"

    # Toggle to enabled (also prints a warning to stderr)
    run "$TOGGLE_SCRIPT"
    assert_success
    assert_line "enabled"

    # Verify state changed
    new_mode=$(bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" get-permissions)
    assert_equal "$new_mode" "enabled"
}

@test "toggle-permissions switches from enabled to disabled" {
    # Set initial state to enabled
    bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" set-permissions enabled > /dev/null

    TOGGLE_SCRIPT="$BATS_TEST_DIRNAME/../../bin/cc-reflect-toggle-permissions"

    # Toggle to disabled
    run "$TOGGLE_SCRIPT"
    assert_success
    assert_output "disabled"

    # Verify state changed
    mode=$(bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" get-permissions)
    assert_equal "$mode" "disabled"
}

@test "permissions state persists in config.json" {
    CONFIG_FILE="$REFLECTION_BASE/config.json"

    # Set to enabled and verify
    bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" set-permissions enabled > /dev/null
    skip_permissions=$(grep skip_permissions "$CONFIG_FILE" | grep -o 'true\|false')
    assert_equal "$skip_permissions" "true"

    # Set to disabled and verify
    bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" set-permissions disabled > /dev/null
    skip_permissions=$(grep skip_permissions "$CONFIG_FILE" | grep -o 'true\|false')
    assert_equal "$skip_permissions" "false"
}

@test "TypeScript set-permissions validates input" {
    # Invalid mode should fail
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" set-permissions invalid
    assert_failure
    assert_output --partial "Invalid permissions mode"
}

@test "TypeScript get-permissions returns enabled or disabled" {
    # Set to enabled
    bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" set-permissions enabled > /dev/null
    mode=$(bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" get-permissions)
    assert_equal "$mode" "enabled"

    # Set to disabled
    bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" set-permissions disabled > /dev/null
    mode=$(bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" get-permissions)
    assert_equal "$mode" "disabled"
}
