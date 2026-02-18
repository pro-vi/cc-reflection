#!/usr/bin/env bats

# test_seed_ttl.bats - Test seed TTL expiration using seed ID timestamp
#
# WHY: Ensure TTL uses system-generated timestamp from seed ID, not potentially Claude-supplied created_at
# CRITICAL: Tests prevent reliance on untrusted timestamps

load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load
load ../test_helper/bats-file/load

setup() {
    # Create temp test directory
    TEST_BASE_DIR="$(mktemp -d)"
    TEST_SEEDS_DIR="$TEST_BASE_DIR/seeds"

    # Create a session directory
    SESSION_ID="test-session-123"
    mkdir -p "$TEST_SEEDS_DIR/$SESSION_ID"

    # Set env var for reflection-state.ts to use
    export REFLECTION_BASE="$TEST_BASE_DIR"
    export CLAUDE_SESSION_ID="$SESSION_ID"
}

teardown() {
    # Clean up temp directory
    rm -rf "$TEST_BASE_DIR"
    unset REFLECTION_BASE
    unset CLAUDE_SESSION_ID
}

# ============================================================================
# TIMESTAMP EXTRACTION TESTS
# ============================================================================

@test "seed ID timestamp extraction: valid format returns timestamp" {
    # Create seed with current timestamp (not expired)
    TIMESTAMP="$(date +%s)000"  # Current time in milliseconds
    SEED_ID="seed-${TIMESTAMP}-abc123"

    # Seed should not be expired (created just now, 24hr TTL)
    cat > "$TEST_SEEDS_DIR/test-session-123/$SEED_ID.json" << EOF
{
  "id": "$SEED_ID",
  "title": "Test seed",
  "rationale": "Testing timestamp extraction",
  "anchors": [],
  "ttl_hours": 24,
  "created_at": "2099-01-01T00:00:00.000Z",
  "dedupe_key": "test",
  "session_id": "test-session-123"
}
EOF

    export CLAUDE_SESSION_ID="test-session-123"

    # Seed should be found (not expired based on seed ID timestamp)
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" list "$TEST_BASE_DIR"
    assert_success

    # Should contain the seed with is_outdated: false
    echo "$output" | bun -e "
        const seeds = JSON.parse(await Bun.stdin.text());
        if (seeds.length !== 1) throw new Error('Expected 1 seed, got ' + seeds.length);
        if (seeds[0].is_outdated) throw new Error('Expected is_outdated to be false');
        console.log('OK');
    "
}

@test "seed ID timestamp extraction: old timestamp marks seed as outdated" {
    # Create seed with old timestamp (from 2020)
    OLD_TIMESTAMP="1577836800000"  # 2020-01-01
    SEED_ID="seed-${OLD_TIMESTAMP}-old123"

    # Even though created_at says 2099, seed ID timestamp is old
    cat > "$TEST_SEEDS_DIR/test-session-123/$SEED_ID.json" << EOF
{
  "id": "$SEED_ID",
  "title": "Old seed",
  "rationale": "Testing old timestamp expiration",
  "anchors": [],
  "ttl_hours": 2,
  "created_at": "2099-01-01T00:00:00.000Z",
  "dedupe_key": "old",
  "session_id": "test-session-123"
}
EOF

    export CLAUDE_SESSION_ID="test-session-123"

    # Seed should be marked as outdated (not deleted)
    # Use 'list all' to see outdated seeds (default 'active' filter excludes 💤)
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" list all "$TEST_BASE_DIR"
    assert_success

    # Should contain the seed with is_outdated: true
    echo "$output" | bun -e "
        const seeds = JSON.parse(await Bun.stdin.text());
        if (seeds.length !== 1) throw new Error('Expected 1 seed, got ' + seeds.length);
        if (!seeds[0].is_outdated) throw new Error('Expected is_outdated to be true');
        console.log('OK');
    "
}

@test "seed ID timestamp extraction: invalid format treats as expired" {
    # Create seed with invalid ID format
    INVALID_ID="invalid-format-123"

    cat > "$TEST_SEEDS_DIR/test-session-123/$INVALID_ID.json" << EOF
{
  "id": "$INVALID_ID",
  "title": "Invalid seed",
  "rationale": "Testing invalid format handling",
  "anchors": [],
  "ttl_hours": 24,
  "created_at": "2099-01-01T00:00:00.000Z",
  "dedupe_key": "invalid",
  "session_id": "test-session-123"
}
EOF

    export CLAUDE_SESSION_ID="test-session-123"

    # Seed should be skipped (invalid ID format)
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" list "$TEST_BASE_DIR" 2>&1

    # Should show warning about invalid ID (different message than isExpired)
    assert_output --partial "Skipping seed with invalid ID"
}

@test "seed ID timestamp extraction: current timestamp not expired" {
    # Create seed with current timestamp
    CURRENT_TIMESTAMP="$(date +%s)000"  # Current time in milliseconds
    SEED_ID="seed-${CURRENT_TIMESTAMP}-current"

    cat > "$TEST_SEEDS_DIR/test-session-123/$SEED_ID.json" << EOF
{
  "id": "$SEED_ID",
  "title": "Current seed",
  "rationale": "Testing current timestamp",
  "anchors": [],
  "ttl_hours": 2,
  "created_at": "2020-01-01T00:00:00.000Z",
  "dedupe_key": "current",
  "session_id": "test-session-123"
}
EOF

    export CLAUDE_SESSION_ID="test-session-123"

    # Seed should be found (not outdated, even though created_at is old)
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" list "$TEST_BASE_DIR"
    assert_success

    # Should contain the seed with is_outdated: false
    echo "$output" | bun -e "
        const seeds = JSON.parse(await Bun.stdin.text());
        if (seeds.length !== 1) throw new Error('Expected 1 seed, got ' + seeds.length);
        if (seeds[0].id !== '$SEED_ID') throw new Error('Wrong seed ID');
        if (seeds[0].is_outdated) throw new Error('Expected is_outdated to be false');
        console.log('OK');
    "
}

@test "seed sorting: uses seed ID timestamp not created_at" {
    # Create three seeds with different timestamps
    # Seed IDs in chronological order: older -> middle -> newer
    # created_at in reverse order to test that sorting uses seed ID

    # Use current time minus offsets to ensure none are expired
    BASE_TS="$(date +%s)"
    OLDER_TS="$((BASE_TS - 3600))000"   # 1 hour ago
    MIDDLE_TS="$((BASE_TS - 1800))000"  # 30 min ago
    NEWER_TS="${BASE_TS}000"            # Now

    cat > "$TEST_SEEDS_DIR/test-session-123/seed-${OLDER_TS}-old.json" << EOF
{
  "id": "seed-${OLDER_TS}-old",
  "title": "Older seed",
  "rationale": "Testing sorting",
  "anchors": [],
  "ttl_hours": 24,
  "created_at": "2099-01-03T00:00:00.000Z",
  "dedupe_key": "old",
  "session_id": "test-session-123"
}
EOF

    cat > "$TEST_SEEDS_DIR/test-session-123/seed-${MIDDLE_TS}-mid.json" << EOF
{
  "id": "seed-${MIDDLE_TS}-mid",
  "title": "Middle seed",
  "rationale": "Testing sorting",
  "anchors": [],
  "ttl_hours": 24,
  "created_at": "2099-01-02T00:00:00.000Z",
  "dedupe_key": "mid",
  "session_id": "test-session-123"
}
EOF

    cat > "$TEST_SEEDS_DIR/test-session-123/seed-${NEWER_TS}-new.json" << EOF
{
  "id": "seed-${NEWER_TS}-new",
  "title": "Newer seed",
  "rationale": "Testing sorting",
  "anchors": [],
  "ttl_hours": 24,
  "created_at": "2099-01-01T00:00:00.000Z",
  "dedupe_key": "new",
  "session_id": "test-session-123"
}
EOF

    export CLAUDE_SESSION_ID="test-session-123"

    # Seeds should be sorted by seed ID timestamp (newest first), not created_at
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" list "$TEST_BASE_DIR"
    assert_success

    # Verify order: newer -> middle -> older (based on seed ID, not created_at)
    echo "$output" | bun -e "
        const seeds = JSON.parse(await Bun.stdin.text());
        if (seeds.length !== 3) throw new Error('Expected 3 seeds, got ' + seeds.length);
        if (seeds[0].title !== 'Newer seed') throw new Error('First should be newer seed');
        if (seeds[1].title !== 'Middle seed') throw new Error('Second should be middle seed');
        if (seeds[2].title !== 'Older seed') throw new Error('Third should be older seed');
        console.log('OK');
    "
}
