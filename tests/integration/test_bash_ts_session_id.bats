#!/usr/bin/env bats

# test_bash_ts_session_id.bats - Cross-language session ID integration tests
#
# WHY: This is the MOST CRITICAL test - ensures bash and TypeScript agree on session IDs
# HISTORY: Production bug where seeds weren't showing in menu due to hash mismatch
# CRITICAL: If these tests fail, the entire reflection system breaks

load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load
load ../test_helper/refute_equal

setup() {
    export REFLECTION_BASE="$(mktemp -d)"
    # Clear all session env vars to ensure directory-based hash tests work
    unset CC_DICE_SESSION_ID
    unset CC_REFLECTION_SESSION_ID

    source "$BATS_TEST_DIRNAME/../../lib/cc-common.sh"

    # Create isolated test directory
    TEST_DIR=$(mktemp -d)
    ORIGINAL_PWD=$(pwd)
    cd "$TEST_DIR"

    # Track project hash for session UUID files (within REFLECTION_BASE)
    PROJECT_HASH=$(cc_get_project_hash)
    SESSION_UUID_DIR="$REFLECTION_BASE/sessions/$PROJECT_HASH"

    # Use unique test session to avoid conflicts
    export CLAUDE_SESSION_ID="test-session-$$-$RANDOM"

    # Create test seed directory (within REFLECTION_BASE)
    TEST_SEEDS_DIR="$REFLECTION_BASE/seeds/$CLAUDE_SESSION_ID"
    mkdir -p "$TEST_SEEDS_DIR"
}

teardown() {
    cd "$ORIGINAL_PWD"
    rm -rf "$TEST_DIR"
    rm -rf "$REFLECTION_BASE"
}

@test "bash and TypeScript produce identical session IDs from same directory" {
    # Unset env var to test directory-based hashing
    unset CLAUDE_SESSION_ID

    bash_id=$(cc_get_session_id)
    ts_id=$(bun "$BATS_TEST_DIRNAME/../../lib/session-id.ts")

    # CRITICAL: If this fails, seeds won't be found
    assert_equal "$bash_id" "$ts_id"
}

@test "bash and TypeScript both respect CLAUDE_SESSION_ID env var" {
    export CLAUDE_SESSION_ID="test-env-session-123"

    bash_id=$(cc_get_session_id)
    ts_id=$(bun "$BATS_TEST_DIRNAME/../../lib/session-id.ts")

    assert_equal "$bash_id" "test-env-session-123"
    assert_equal "$ts_id" "test-env-session-123"
    assert_equal "$bash_id" "$ts_id"
}

@test "bash and TypeScript use Claude session UUID file when present" {
    unset CLAUDE_SESSION_ID

    # Simulate a Claude Code hook recording the current session UUID
    SESSION_UUID="0544041b-7da2-432f-8477-7829dcdb9e00"
    mkdir -p "$SESSION_UUID_DIR"
    echo "$SESSION_UUID" >"$SESSION_UUID_DIR/current"

    bash_id=$(cc_get_session_id)
    ts_id=$(bun "$BATS_TEST_DIRNAME/../../lib/session-id.ts")

    assert_equal "$bash_id" "$SESSION_UUID"
    assert_equal "$ts_id" "$SESSION_UUID"
}

@test "session IDs change with different directories (bash and TS agree)" {
    unset CLAUDE_SESSION_ID

    # Get IDs in first directory
    dir1=$(mktemp -d)
    cd "$dir1"
    bash_id1=$(cc_get_session_id)
    ts_id1=$(bun "$BATS_TEST_DIRNAME/../../lib/session-id.ts")

    # Get IDs in second directory
    dir2=$(mktemp -d)
    cd "$dir2"
    bash_id2=$(cc_get_session_id)
    ts_id2=$(bun "$BATS_TEST_DIRNAME/../../lib/session-id.ts")

    # Different directories = different IDs
    refute_equal "$bash_id1" "$bash_id2"
    refute_equal "$ts_id1" "$ts_id2"

    # But bash and TS still agree within each directory
    assert_equal "$bash_id1" "$ts_id1"
    assert_equal "$bash_id2" "$ts_id2"

    # Cleanup
    cd "$ORIGINAL_PWD"
    rm -rf "$dir1" "$dir2"
}

@test "reflection state manager uses same session ID as bash" {
    # Get session ID from bash
    bash_id=$(cc_get_session_id)

    # Create a test seed with TypeScript
    result=$(bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" write \
        "Integration Test" "Test rationale" "test.ts" "start" "end")

    # Extract session_id from JSON result
    ts_session=$(echo "$result" | bun -e "const r = JSON.parse(await Bun.stdin.text()); console.log(r.seed?.session_id || 'none');")

    # CRITICAL: State manager must use same session ID
    assert_equal "$bash_id" "$ts_session"
}

@test "cc-reflect can find seeds created by reflection-state.ts" {
    # This tests the full integration: TypeScript creates, bash finds

    # Create a seed using TypeScript
    result=$(bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" write \
        "Test Security Seed" "Integration test" "test.ts" "code start" "code end")

    # Verify seed was created
    echo "$result" | grep -q '"success": true'

    # List seeds using TypeScript (simulates what cc-reflect does)
    seeds_json=$(bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" list)

    # Should find the seed we just created
    echo "$seeds_json" | grep -q "Test Security Seed"

    # Verify bash can see the seed files
    bash_session=$(cc_get_session_id)
    seed_dir="$REFLECTION_BASE/seeds/$bash_session"

    # Directory should exist and contain JSON files
    [ -d "$seed_dir" ]
    [ "$(ls -1 "$seed_dir"/*.json 2>/dev/null | wc -l)" -gt 0 ]
}

@test "seeds from same project are visible across sessions" {
    # Create seed in session 1
    export CLAUDE_SESSION_ID="session-1"
    result1=$(bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" write \
        "Session 1 Seed" "Test" "test.ts" "start" "end")
    echo "$result1" | grep -q '"success": true'

    # Switch to session 2 (same project directory = same project_hash)
    export CLAUDE_SESSION_ID="session-2"

    # List seeds - should find session 1's seed (same project)
    seeds=$(bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" list)

    run echo "$seeds"
    assert_output --partial "Session 1 Seed"
}

@test "seeds from different projects are isolated" {
    # Create seed in project A
    export CLAUDE_SESSION_ID="session-a"
    export PWD="/fake/project-a"
    result1=$(bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" write \
        "Project A Seed" "Test" "test.ts" "start" "end")
    echo "$result1" | grep -q '"success": true'

    # Switch to project B (different PWD = different project_hash)
    export CLAUDE_SESSION_ID="session-b"
    export PWD="/fake/project-b"

    # List seeds - should not find project A's seed
    seeds=$(bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" list)

    run echo "$seeds"
    refute_output --partial "Project A Seed"
}

@test "bash cc_get_session_id can be used as environment variable for TypeScript" {
    unset CLAUDE_SESSION_ID

    # Get session ID from bash
    bash_id=$(cc_get_session_id)

    # Use it as env var for TypeScript
    export CLAUDE_SESSION_ID="$bash_id"

    # TypeScript should use the env var
    ts_id=$(bun "$BATS_TEST_DIRNAME/../../lib/session-id.ts")

    assert_equal "$bash_id" "$ts_id"
}

@test "newline handling is consistent across platforms" {
    unset CLAUDE_SESSION_ID

    # Get IDs
    bash_id=$(cc_get_session_id)
    ts_id=$(bun "$BATS_TEST_DIRNAME/../../lib/session-id.ts")

    # Both should exclude newline (matching Reflection skill `echo -n "$PWD"`)
    # and truncate to 12 chars
    if command -v md5sum &>/dev/null; then
        expected=$(echo -n "$(pwd)" | md5sum | cut -d' ' -f1 | head -c 12)
    elif command -v md5 &>/dev/null; then
        expected=$(echo -n "$(pwd)" | md5 | head -c 12)
    fi

    assert_equal "$bash_id" "$expected"
    assert_equal "$ts_id" "$expected"
}
