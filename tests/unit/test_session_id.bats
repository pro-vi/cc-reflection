#!/usr/bin/env bats

# test_session_id.bats - Test session ID consistency
#
# WHY: Session ID mismatch between bash and TypeScript caused production bugs
# CRITICAL: These tests prevent hash mismatches that break seed storage

load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load
load ../test_helper/refute_equal

setup() {
    export REFLECTION_BASE="$(mktemp -d)"
    # Source the functions under test
    source "$BATS_TEST_DIRNAME/../../lib/cc-common.sh"

    # Create temp working directory
    TEST_DIR=$(mktemp -d)
    ORIGINAL_PWD=$(pwd)
    cd "$TEST_DIR"

    # Clear environment to test default behavior (directory-based hashing)
    unset CLAUDE_SESSION_ID
    unset CC_DICE_SESSION_ID
    unset CC_REFLECTION_SESSION_ID
}

teardown() {
    cd "$ORIGINAL_PWD"
    rm -rf "$TEST_DIR"
    rm -rf "$REFLECTION_BASE"
}

@test "bash cc_get_session_id returns 12-char MD5 hash of pwd" {
    run cc_get_session_id
    assert_success
    # MD5 hash truncated to 12 hex characters (matches Reflection skill format)
    assert_output --regexp '^[a-f0-9]{12}$'
}

@test "TypeScript getSessionId returns 12-char MD5 hash of pwd" {
    run bun "$BATS_TEST_DIRNAME/../../lib/session-id.ts"
    assert_success
    # MD5 hash truncated to 12 hex characters (matches Reflection skill format)
    assert_output --regexp '^[a-f0-9]{12}$'
}

@test "bash and TypeScript produce identical session IDs" {
    # CRITICAL TEST: This is the core cross-language compatibility check
    # If this fails, seeds won't be found by the menu

    bash_session=$(cc_get_session_id)
    ts_session=$(bun "$BATS_TEST_DIRNAME/../../lib/session-id.ts")

    assert_equal "$bash_session" "$ts_session"
}

@test "CLAUDE_SESSION_ID environment variable takes precedence in bash" {
    export CLAUDE_SESSION_ID="custom-session-123"

    run cc_get_session_id
    assert_success
    assert_output "custom-session-123"
}

@test "CLAUDE_SESSION_ID environment variable takes precedence in TypeScript" {
    export CLAUDE_SESSION_ID="custom-session-456"

    run bun "$BATS_TEST_DIRNAME/../../lib/session-id.ts"
    assert_success
    assert_output "custom-session-456"
}

@test "both bash and TypeScript respect same CLAUDE_SESSION_ID" {
    export CLAUDE_SESSION_ID="shared-session-789"

    bash_session=$(cc_get_session_id)
    ts_session=$(bun "$BATS_TEST_DIRNAME/../../lib/session-id.ts")

    assert_equal "$bash_session" "shared-session-789"
    assert_equal "$ts_session" "shared-session-789"
}

@test "hash excludes trailing newline (matches Reflection skill)" {
    # This test verifies we match Reflection skill's `echo -n "$PWD"` behavior
    # We must NOT include the newline for cross-tool compatibility

    # Get hash using echo -n (no newline, matches Reflection skill)
    if command -v md5sum &>/dev/null; then
        pwd_no_newline=$(echo -n "$(pwd)" | md5sum | cut -d' ' -f1 | head -c 12)
    elif command -v md5 &>/dev/null; then
        # macOS
        pwd_no_newline=$(echo -n "$(pwd)" | md5 | head -c 12)
    fi

    session_id=$(cc_get_session_id)

    assert_equal "$pwd_no_newline" "$session_id"
}

@test "different directories produce different session IDs" {
    # Get ID in first directory
    id1=$(cc_get_session_id)

    # Create and move to second directory
    TEST_DIR2=$(mktemp -d)
    cd "$TEST_DIR2"

    # Get ID in second directory
    id2=$(cc_get_session_id)

    # They should be different
    refute_equal "$id1" "$id2"

    # Cleanup
    cd "$ORIGINAL_PWD"
    rm -rf "$TEST_DIR2"
}

@test "session ID is deterministic for same directory" {
    # Get ID twice from same directory
    id1=$(cc_get_session_id)
    id2=$(cc_get_session_id)

    # Should be identical
    assert_equal "$id1" "$id2"
}

@test "TypeScript CLI mode outputs only session ID" {
    # When run as CLI, should output ONLY the session ID (for scripting)
    run bun "$BATS_TEST_DIRNAME/../../lib/session-id.ts"
    assert_success

    # Should be either:
    # - 36-char UUID (Claude Code session): xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    # - 12-char hex hash (project hash fallback): [a-f0-9]{12}
    # Accept either format for flexibility
    assert_output --regexp '^[a-f0-9-]+$'

    # Verify correct length (12 for hash, 36 for UUID)
    [ "${#output}" -eq 12 ] || [ "${#output}" -eq 36 ]
}

@test "TypeScript DEBUG mode shows additional info" {
    export DEBUG=1
    export CLAUDE_SESSION_ID="debug-test"

    run bun "$BATS_TEST_DIRNAME/../../lib/session-id.ts" 2>&1
    assert_success

    # Should contain debug info on stderr
    assert_output --partial "CLAUDE_SESSION_ID env var"
}
