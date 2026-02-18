#!/usr/bin/env bats

# Unit tests for session ID prefix matching (git-style)
# Tests the findSessionByPrefix() logic in reflection-state.ts

load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'
load '../test_helper/bats-file/load'

setup() {
    # Create temp test directory
    TEST_BASE_DIR="$(mktemp -d)"
    TEST_SEEDS_DIR="$TEST_BASE_DIR/seeds"
    mkdir -p "$TEST_SEEDS_DIR"

    # Set env var for reflection-state.ts to use
    export REFLECTION_BASE="$TEST_BASE_DIR"

    # Create mock session directories
    mkdir -p "$TEST_SEEDS_DIR/abc123def456"
    mkdir -p "$TEST_SEEDS_DIR/abc456ghi789"
    mkdir -p "$TEST_SEEDS_DIR/xyz789"

    # Use current timestamp so seeds aren't expired
    CURRENT_TS="$(date +%s)000"

    # Create a seed in one of them
    cat > "$TEST_SEEDS_DIR/abc123def456/seed-${CURRENT_TS}-test.json" << EOF
{
  "id": "seed-${CURRENT_TS}-test",
  "title": "Test seed",
  "rationale": "Testing prefix matching",
  "anchors": [],
  "ttl_hours": 2,
  "created_at": "2025-11-09T19:00:00.000Z",
  "dedupe_key": "test",
  "session_id": "abc123def456"
}
EOF
}

teardown() {
    # Clean up temp directory
    rm -rf "$TEST_BASE_DIR"
    unset REFLECTION_BASE
}

# ============================================================================
# PREFIX MATCHING TESTS
# ============================================================================

@test "prefix matching: exact match returns correct session" {
    export CLAUDE_SESSION_ID="abc123def456"

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" list "$TEST_BASE_DIR"
    assert_success

    # Should return the seed from abc123def456
    echo "$output" | bun -e "
        const seeds = JSON.parse(await Bun.stdin.text());
        if (seeds.length !== 1) throw new Error('Expected 1 seed');
        if (seeds[0].session_id !== 'abc123def456') throw new Error('Wrong session');
        console.log('OK');
    "
}

@test "prefix matching: unambiguous short prefix matches correctly" {
    # "xyz" only matches "xyz789"
    export CLAUDE_SESSION_ID="xyz"

    # Create a seed in xyz789 for testing (use current timestamp)
    CURRENT_TS="$(date +%s)000"
    cat > "$TEST_SEEDS_DIR/xyz789/seed-${CURRENT_TS}-xyz.json" << EOF
{
  "id": "seed-${CURRENT_TS}-xyz",
  "title": "XYZ seed",
  "rationale": "Testing xyz prefix",
  "anchors": [],
  "ttl_hours": 2,
  "created_at": "2025-11-09T19:00:00.000Z",
  "dedupe_key": "xyz",
  "session_id": "xyz789"
}
EOF

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" list "$TEST_BASE_DIR"
    assert_success

    echo "$output" | bun -e "
        const seeds = JSON.parse(await Bun.stdin.text());
        if (seeds.length !== 1) throw new Error('Expected 1 seed, got ' + seeds.length);
        if (seeds[0].session_id !== 'xyz789') throw new Error('Wrong session: ' + seeds[0].session_id);
        console.log('OK');
    "
}

@test "prefix matching: ambiguous prefix fails with helpful error" {
    # "abc" matches both "abc123def456" and "abc456ghi789"
    export CLAUDE_SESSION_ID="abc"

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" list "$TEST_BASE_DIR"
    assert_failure

    # Error should mention both matching sessions
    assert_output --partial "Ambiguous"
    assert_output --partial "abc123def456"
    assert_output --partial "abc456ghi789"
}

@test "prefix matching: longer prefix resolves ambiguity" {
    # "abc123" only matches "abc123def456"
    export CLAUDE_SESSION_ID="abc123"

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" list "$TEST_BASE_DIR"
    assert_success

    echo "$output" | bun -e "
        const seeds = JSON.parse(await Bun.stdin.text());
        if (seeds.length !== 1) throw new Error('Expected 1 seed');
        if (seeds[0].session_id !== 'abc123def456') throw new Error('Wrong session');
        console.log('OK');
    "
}

@test "prefix matching: non-existent prefix returns empty" {
    export CLAUDE_SESSION_ID="nonexistent"

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" list "$TEST_BASE_DIR"
    assert_success
    assert_output "[]"
}

@test "prefix matching: 12-char prefix matches 12-char directory" {
    # Simulate Reflection skill creating 12-char session
    mkdir -p "$TEST_SEEDS_DIR/e447ff4b9e86"
    CURRENT_TS="$(date +%s)000"
    cat > "$TEST_SEEDS_DIR/e447ff4b9e86/seed-${CURRENT_TS}-short.json" << EOF
{
  "id": "seed-${CURRENT_TS}-short",
  "title": "Short session seed",
  "rationale": "Testing 12-char session",
  "anchors": [],
  "ttl_hours": 2,
  "created_at": "2025-11-09T19:00:00.000Z",
  "dedupe_key": "short",
  "session_id": "e447ff4b9e86"
}
EOF

    export CLAUDE_SESSION_ID="e447ff4b9e86"

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" list "$TEST_BASE_DIR"
    assert_success

    echo "$output" | bun -e "
        const seeds = JSON.parse(await Bun.stdin.text());
        if (seeds.length !== 1) throw new Error('Expected 1 seed');
        if (seeds[0].session_id !== 'e447ff4b9e86') throw new Error('Wrong session');
        console.log('OK');
    "
}

@test "prefix matching: exact match preferred over prefix match" {
    # Create both 12-char and 32-char directories that collide
    mkdir -p "$TEST_SEEDS_DIR/e447ff4b9e86"
    mkdir -p "$TEST_SEEDS_DIR/e447ff4b9e862e1c93681b568047bcd4"

    # Create seed in exact match directory
    CURRENT_TS="$(date +%s)000"
    cat > "$TEST_SEEDS_DIR/e447ff4b9e86/seed-${CURRENT_TS}-exact.json" << EOF
{
  "id": "seed-${CURRENT_TS}-exact",
  "title": "Exact match seed",
  "rationale": "Testing exact match preference",
  "anchors": [],
  "ttl_hours": 2,
  "created_at": "2025-11-09T19:00:00.000Z",
  "dedupe_key": "exact",
  "session_id": "e447ff4b9e86"
}
EOF

    # Should prefer exact match (e447ff4b9e86) over prefix match
    export CLAUDE_SESSION_ID="e447ff4b9e86"

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" list "$TEST_BASE_DIR"
    assert_success
    echo "$output" | bun -e "
        const seeds = JSON.parse(await Bun.stdin.text());
        if (seeds.length !== 1) throw new Error('Expected 1 seed');
        if (seeds[0].title !== 'Exact match seed') throw new Error('Wrong seed');
        console.log('OK');
    "
}
