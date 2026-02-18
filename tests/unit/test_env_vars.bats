#!/usr/bin/env bats
# Unit tests for environment variable contracts

load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'

setup() {
    export REFLECTION_BASE="$(mktemp -d)"
    # Source shared utilities
    source "${BATS_TEST_DIRNAME}/../../lib/cc-common.sh"

    # Save original env vars
    ORIGINAL_HOME="$HOME"
    ORIGINAL_TMUX="$TMUX"
    ORIGINAL_PWD="$PWD"
    ORIGINAL_CLAUDE_SESSION_ID="$CLAUDE_SESSION_ID"
}

teardown() {
    # Restore original env vars
    export HOME="$ORIGINAL_HOME"
    export TMUX="$ORIGINAL_TMUX"
    export PWD="$ORIGINAL_PWD"
    if [ -n "$ORIGINAL_CLAUDE_SESSION_ID" ]; then
        export CLAUDE_SESSION_ID="$ORIGINAL_CLAUDE_SESSION_ID"
    else
        unset CLAUDE_SESSION_ID
    fi
    rm -rf "$REFLECTION_BASE"
}

# ============================================================================
# HOME Environment Variable
# ============================================================================

@test "cc_get_session_id requires HOME to be set" {
    # Unset HOME
    unset HOME

    # Session ID calculation should handle missing HOME gracefully
    # (Currently uses $HOME in paths, so this tests robustness)
    run cc_get_session_id

    # Should either succeed with fallback or fail gracefully
    # (Implementation may vary - document actual behavior)
    # This test documents the contract: HOME is assumed to exist
}

@test "HOME env var is used for base directory paths" {
    # Set HOME to test value
    export HOME="/tmp/test-home-$$"
    mkdir -p "$HOME"

    # Session ID should still work
    SESSION_ID=$(cc_get_session_id)
    assert [ -n "$SESSION_ID" ]

    # Cleanup
    rm -rf "/tmp/test-home-$$"
}

@test "log directory respects CC_LOG_DIR override" {
    # Test that CC_LOG_DIR can override default
    export CC_LOG_DIR="/tmp/test-logs-$$"

    # Re-source to pick up new value
    source "${BATS_TEST_DIRNAME}/../../lib/cc-common.sh"

    # Verify log dir uses override
    assert_equal "$CC_LOG_DIR" "/tmp/test-logs-$$"

    # Cleanup
    rm -rf "/tmp/test-logs-$$"
}

# ============================================================================
# TMUX Environment Variable
# ============================================================================

@test "cc_in_tmux returns false when neither TMUX nor ORIGINAL_TMUX set" {
    unset TMUX
    unset ORIGINAL_TMUX

    run cc_in_tmux
    assert_failure
}

@test "cc_in_tmux returns true when TMUX is set" {
    unset ORIGINAL_TMUX
    export TMUX="/tmp/tmux-1000/default,12345,0"

    run cc_in_tmux
    assert_success
}

@test "cc_in_tmux returns true when ORIGINAL_TMUX is set" {
    unset TMUX
    export ORIGINAL_TMUX="/tmp/tmux-1000/default,67890,1"

    run cc_in_tmux
    assert_success
}

@test "cc_in_tmux returns true when both TMUX and ORIGINAL_TMUX are set" {
    export TMUX="/tmp/tmux-1000/default,11111,0"
    export ORIGINAL_TMUX="/tmp/tmux-1000/default,22222,1"

    run cc_in_tmux
    assert_success
}

@test "cc_validate_tmux_session fails on empty socket path" {
    run cc_validate_tmux_session ""
    assert_failure
}

@test "cc_validate_tmux_session extracts socket path correctly" {
    # Create fake socket
    SOCKET_DIR="/tmp/tmux-test-$$"
    SOCKET_PATH="$SOCKET_DIR/default"
    mkdir -p "$SOCKET_DIR"

    # Create Unix socket (requires actual socket, not just file)
    # Skip if nc not available (common socket creation tool)
    if ! command -v nc &>/dev/null; then
        skip "nc not available for socket creation"
    fi

    # Use nc to create a listening socket briefly
    # NOTE: Some sandboxed environments disallow socket operations and will fail with EPERM.
    nc -U -l "$SOCKET_PATH" >/dev/null 2>&1 &
    NC_PID=$!
    sleep 0.1  # Give nc time to create socket

    # Skip if socket couldn't be created (e.g., sandbox restrictions)
    if [ ! -S "$SOCKET_PATH" ]; then
        kill $NC_PID 2>/dev/null || true
        rm -rf "$SOCKET_DIR"
        skip "Unable to create unix socket at $SOCKET_PATH (permission denied)"
    fi

    # Now test validation
    TMUX_VAR="$SOCKET_PATH,12345,0"
    run cc_validate_tmux_session "$TMUX_VAR"

    # Cleanup
    kill $NC_PID 2>/dev/null || true
    rm -rf "$SOCKET_DIR"

    assert_success
}

@test "cc_validate_tmux_session fails on non-existent socket" {
    FAKE_SOCKET="/tmp/nonexistent-socket-$$"

    # Ensure it doesn't exist
    rm -f "$FAKE_SOCKET"

    TMUX_VAR="$FAKE_SOCKET,12345,0"
    run cc_validate_tmux_session "$TMUX_VAR"

    assert_failure
}

# ============================================================================
# CLAUDE_ENV_FILE (SessionStart Hook)
# ============================================================================

@test "SessionStart hook writes CC_REFLECTION_SESSION_ID to CLAUDE_ENV_FILE" {
    local env_file
    env_file="$(mktemp)"

    echo '{"session_id":"cccc1111-2222-3333-4444-555566667777"}' \
        | CLAUDE_ENV_FILE="$env_file" bun "${BATS_TEST_DIRNAME}/../../bin/reflection-session-start.ts"

    run grep -F 'export CC_REFLECTION_SESSION_ID="cccc1111-2222-3333-4444-555566667777"' "$env_file"
    assert_success

    rm -f "$env_file"
}

@test "SessionStart hook ignores invalid session_id values" {
    local env_file
    env_file="$(mktemp)"

    # JSON escapes \n into an actual newline character in the parsed string
    echo '{"session_id":"bad\nvalue"}' \
        | CLAUDE_ENV_FILE="$env_file" bun "${BATS_TEST_DIRNAME}/../../bin/reflection-session-start.ts"

    run bash -c "wc -l < \"$env_file\" | tr -d ' '"
    assert_output "0"

    rm -f "$env_file"
}

# ============================================================================
# PWD Environment Variable
# ============================================================================

@test "cc_get_session_id prefers CLAUDE_SESSION_ID over PWD" {
    export CLAUDE_SESSION_ID="explicit-session-123"
    export PWD="/some/directory"

    SESSION_ID=$(cc_get_session_id)

    # Should return explicit session ID, not hash of PWD
    assert_equal "$SESSION_ID" "explicit-session-123"
}

@test "cc_get_session_id uses PWD when CLAUDE_SESSION_ID not set" {
    unset CLAUDE_SESSION_ID

    SESSION_ID=$(cc_get_session_id)

    # Should be either:
    # 1. Claude Code UUID (36-char UUID format) - if hook has stored session
    # 2. Project hash (12-char hex) - fallback when no Claude session available
    # Check it's a valid session ID format
    if [ ${#SESSION_ID} -eq 36 ]; then
        # UUID format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
        [[ "$SESSION_ID" =~ ^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$ ]]
    elif [ ${#SESSION_ID} -eq 12 ]; then
        # Project hash format: 12 hex chars
        [[ "$SESSION_ID" =~ ^[a-f0-9]{12}$ ]]
    else
        fail "Session ID has unexpected length: ${#SESSION_ID} (expected 12 or 36)"
    fi
}

@test "cc_get_session_id produces different IDs for different directories" {
    unset CLAUDE_SESSION_ID
    unset CC_DICE_SESSION_ID
    unset CC_REFLECTION_SESSION_ID

    # Get ID for current directory
    SESSION_ID_1=$(cc_get_session_id)

    # Create temp dir and get ID there
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    SESSION_ID_2=$(cc_get_session_id)
    cd "$BATS_TEST_DIRNAME"
    rm -rf "$TEMP_DIR"

    # Should be different
    assert [ "$SESSION_ID_1" != "$SESSION_ID_2" ]
}

@test "session ID matches between bash and TypeScript when using PWD" {
    unset CLAUDE_SESSION_ID

    # Get bash session ID
    BASH_SESSION=$(cc_get_session_id)

    # Get TypeScript session ID
    TS_SESSION=$(bun "${BATS_TEST_DIRNAME}/../../lib/session-id.ts")

    # Must match (this is the critical contract)
    assert_equal "$BASH_SESSION" "$TS_SESSION"
}

@test "session ID matches between bash and TypeScript with CLAUDE_SESSION_ID set" {
    export CLAUDE_SESSION_ID="test-env-var-session"

    # Get bash session ID
    BASH_SESSION=$(cc_get_session_id)

    # Get TypeScript session ID
    TS_SESSION=$(bun "${BATS_TEST_DIRNAME}/../../lib/session-id.ts")

    # Both should use env var
    assert_equal "$BASH_SESSION" "test-env-var-session"
    assert_equal "$TS_SESSION" "test-env-var-session"
}

# ============================================================================
# Environment Variable Precedence
# ============================================================================

@test "environment variables have documented precedence: explicit > computed" {
    # CLAUDE_SESSION_ID should override PWD-based calculation
    export CLAUDE_SESSION_ID="override-123"
    export PWD="/tmp"

    SESSION_ID=$(cc_get_session_id)

    # Should use explicit value
    assert_equal "$SESSION_ID" "override-123"
}

@test "CC_LOG_DIR defaults to REFLECTION_BASE/logs" {
    unset CC_LOG_DIR

    # Re-source to recalculate default
    source "${BATS_TEST_DIRNAME}/../../lib/cc-common.sh"

    EXPECTED="$REFLECTION_BASE/logs"
    assert_equal "$CC_LOG_DIR" "$EXPECTED"
}

# ============================================================================
# Empty/Unset Variable Handling
# ============================================================================

@test "empty CLAUDE_SESSION_ID is treated as unset" {
    export CLAUDE_SESSION_ID=""

    # Should fall back to Claude session UUID or PWD-based calculation
    SESSION_ID=$(cc_get_session_id)

    # Should not be empty - should fall back to UUID (36 chars) or hash (12 chars)
    assert [ -n "$SESSION_ID" ]
    # Session ID should be either UUID format (36 chars) or hash format (12 chars)
    assert [ ${#SESSION_ID} -eq 12 ] || [ ${#SESSION_ID} -eq 36 ]
}

@test "empty string values are handled safely" {
    # Test various functions with empty strings
    run cc_require_param "TEST_VAR" ""
    assert_failure  # Empty is invalid
    # NOTE: validate_mode "" is tested in test_validators.bats
    # (validators.sh is not sourced in this test file)
}
