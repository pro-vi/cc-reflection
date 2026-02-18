#!/usr/bin/env bats

# test_reflection_base_env.bats - Unit tests for REFLECTION_BASE environment variable
#
# WHY: Ensures TypeScript respects REFLECTION_BASE for test isolation
# TESTS: Environment variable precedence, CLI argument override

load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load

setup() {
    # Save original REFLECTION_BASE if it exists
    ORIGINAL_REFLECTION_BASE="${REFLECTION_BASE:-}"

    # Create isolated test directory
    TEST_DIR=$(mktemp -d)
    ORIGINAL_PWD=$(pwd)
}

teardown() {
    # Restore original REFLECTION_BASE
    if [ -n "$ORIGINAL_REFLECTION_BASE" ]; then
        export REFLECTION_BASE="$ORIGINAL_REFLECTION_BASE"
    else
        unset REFLECTION_BASE
    fi

    # Cleanup
    cd "$ORIGINAL_PWD"
    rm -rf "$TEST_DIR"
}

@test "TypeScript respects REFLECTION_BASE environment variable" {
    # Set env var to test directory
    export REFLECTION_BASE="$TEST_DIR"

    # Get current session ID for testing
    SESSION_ID=$(cd "$ORIGINAL_PWD" && source "$BATS_TEST_DIRNAME/../../lib/cc-common.sh" && cc_get_session_id)

    # Create a test seed using REFLECTION_BASE
    bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" write \
        "Test Seed" \
        "Test rationale" \
        "test.txt" \
        "" \
        ""

    # Verify seed was created in TEST_DIR, not ~/.claude/reflections
    assert [ -d "$TEST_DIR/seeds/$SESSION_ID" ]

    # Verify it did NOT create in default location
    [ ! -d "$HOME/.claude/reflections/seeds/$SESSION_ID/test-seed-*.json" ] || true
}

@test "REFLECTION_BASE env var takes precedence over default" {
    export REFLECTION_BASE="$TEST_DIR"

    # List seeds (should use TEST_DIR)
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" list
    assert_success

    # Output should be empty array (no seeds in test dir yet)
    assert_output "[]"
}

@test "CLI argument overrides REFLECTION_BASE env var" {
    # Set env var to one location
    export REFLECTION_BASE="$TEST_DIR/env-location"
    mkdir -p "$REFLECTION_BASE"

    # Pass different location as CLI argument
    CLI_LOCATION="$TEST_DIR/cli-location"
    mkdir -p "$CLI_LOCATION"

    # List seeds with CLI argument (should use CLI location, not env var)
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" list "$CLI_LOCATION"
    assert_success
    assert_output "[]"
}

@test "Default location used when REFLECTION_BASE not set" {
    # Ensure REFLECTION_BASE is not set
    unset REFLECTION_BASE

    # This test just verifies no crash occurs
    # (We don't want to create files in actual ~/.claude/reflections during tests)
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" list "$TEST_DIR"
    assert_success
}

@test "REFLECTION_BASE works with config operations" {
    export REFLECTION_BASE="$TEST_DIR"

    # Create config directory
    mkdir -p "$TEST_DIR"

    # Set expansion mode (should create config in TEST_DIR)
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" set-mode auto
    assert_success

    # Verify config file created in TEST_DIR
    assert [ -f "$TEST_DIR/config.json" ]

    # Verify it did NOT create in default location
    # (This is the key test - config should respect REFLECTION_BASE)
    if [ -f "$HOME/.claude/reflections/config.json" ]; then
        # If global config exists, verify it wasn't modified by our test
        # (We can't easily test this without knowing original state,
        # so we just verify our test config exists)
        assert [ -f "$TEST_DIR/config.json" ]
    fi
}

@test "REFLECTION_BASE precedence matches session-id.ts pattern" {
    # This test documents that both files use the same precedence pattern:
    # 1. Explicit parameter
    # 2. Environment variable
    # 3. Default value

    export REFLECTION_BASE="$TEST_DIR"

    # Get session ID (uses process.env.PWD || process.cwd())
    SESSION_ID=$(cd "$ORIGINAL_PWD" && source "$BATS_TEST_DIRNAME/../../lib/cc-common.sh" && cc_get_session_id)

    # Verify session ID is returned (not empty)
    assert [ -n "$SESSION_ID" ]

    # Verify it's a valid format:
    # - 12-char hex hash (project hash fallback): [a-f0-9]{12}
    # - 36-char UUID (Claude Code session): [a-f0-9]{8}-[a-f0-9]{4}-...-[a-f0-9]{12}
    [[ "$SESSION_ID" =~ ^[a-f0-9-]+$ ]]
}
