#!/usr/bin/env bats

# test_seed_status.bats - Unit tests for seed status and freshness tier
#
# Tests the status field (active/archived) and freshness tier emoji computation

load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'

setup() {
    # Create isolated test directory
    TEST_DIR=$(mktemp -d)
    TEST_BASE_DIR="$TEST_DIR/reflections"
    TEST_SEEDS_DIR="$TEST_BASE_DIR/seeds"

    mkdir -p "$TEST_SEEDS_DIR/test-session-123"

    export CLAUDE_SESSION_ID="test-session-123"
    export REFLECTION_BASE="$TEST_BASE_DIR"
}

teardown() {
    rm -rf "$TEST_DIR"
    unset CLAUDE_SESSION_ID
    unset REFLECTION_BASE
}

# ============================================================================
# STATUS FIELD TESTS
# ============================================================================

@test "status defaults to 'active' for seeds without status field" {
    # Create seed without status field
    SEED_ID="seed-$(date +%s)000-test123"
    cat > "$TEST_SEEDS_DIR/test-session-123/$SEED_ID.json" << EOF
{
  "id": "$SEED_ID",
  "title": "Test seed",
  "rationale": "Testing",
  "anchors": [],
  "ttl_hours": 24,
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)",
  "dedupe_key": "test",
  "session_id": "test-session-123"
}
EOF

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" list "$TEST_BASE_DIR"
    assert_success

    # Should have status: active
    echo "$output" | bun -e "
        const seeds = JSON.parse(await Bun.stdin.text());
        if (seeds.length !== 1) throw new Error('Expected 1 seed');
        if (seeds[0].status !== 'active') throw new Error('Expected status to be active, got: ' + seeds[0].status);
        console.log('OK');
    "
}

@test "archiveSeed sets status to 'archived'" {
    # Create active seed
    SEED_ID="seed-$(date +%s)000-archive"
    cat > "$TEST_SEEDS_DIR/test-session-123/$SEED_ID.json" << EOF
{
  "id": "$SEED_ID",
  "title": "Test archive",
  "rationale": "Testing",
  "anchors": [],
  "ttl_hours": 24,
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)",
  "dedupe_key": "arch",
  "session_id": "test-session-123",
  "status": "active"
}
EOF

    # Archive the seed
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" archive "$SEED_ID" "$TEST_BASE_DIR"
    assert_success

    # Verify it was archived
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" get "$SEED_ID" "$TEST_BASE_DIR"
    assert_success

    echo "$output" | bun -e "
        const seed = JSON.parse(await Bun.stdin.text());
        if (seed.status !== 'archived') throw new Error('Expected status to be archived');
        console.log('OK');
    "
}

@test "filter 'active' excludes archived seeds" {
    # Create one active and one archived seed
    SEED1="seed-$(date +%s)001-active"
    SEED2="seed-$(date +%s)002-archived"

    cat > "$TEST_SEEDS_DIR/test-session-123/$SEED1.json" << EOF
{
  "id": "$SEED1",
  "title": "Active seed",
  "rationale": "Test",
  "anchors": [],
  "ttl_hours": 24,
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)",
  "dedupe_key": "act",
  "session_id": "test-session-123",
  "status": "active"
}
EOF

    cat > "$TEST_SEEDS_DIR/test-session-123/$SEED2.json" << EOF
{
  "id": "$SEED2",
  "title": "Archived seed",
  "rationale": "Test",
  "anchors": [],
  "ttl_hours": 24,
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)",
  "dedupe_key": "arc",
  "session_id": "test-session-123",
  "status": "archived"
}
EOF

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" list active "$TEST_BASE_DIR"
    assert_success

    echo "$output" | bun -e "
        const seeds = JSON.parse(await Bun.stdin.text());
        if (seeds.length !== 1) throw new Error('Expected 1 seed, got: ' + seeds.length);
        if (seeds[0].title !== 'Active seed') throw new Error('Expected Active seed');
        console.log('OK');
    "
}

@test "filter 'archived' only shows archived seeds" {
    # Create one active and one archived seed
    SEED1="seed-$(date +%s)001-active"
    SEED2="seed-$(date +%s)002-archived"

    cat > "$TEST_SEEDS_DIR/test-session-123/$SEED1.json" << EOF
{
  "id": "$SEED1",
  "title": "Active seed",
  "rationale": "Test",
  "anchors": [],
  "ttl_hours": 24,
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)",
  "dedupe_key": "act",
  "session_id": "test-session-123",
  "status": "active"
}
EOF

    cat > "$TEST_SEEDS_DIR/test-session-123/$SEED2.json" << EOF
{
  "id": "$SEED2",
  "title": "Archived seed",
  "rationale": "Test",
  "anchors": [],
  "ttl_hours": 24,
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)",
  "dedupe_key": "arc",
  "session_id": "test-session-123",
  "status": "archived"
}
EOF

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" list archived "$TEST_BASE_DIR"
    assert_success

    echo "$output" | bun -e "
        const seeds = JSON.parse(await Bun.stdin.text());
        if (seeds.length !== 1) throw new Error('Expected 1 seed, got: ' + seeds.length);
        if (seeds[0].title !== 'Archived seed') throw new Error('Expected Archived seed');
        console.log('OK');
    "
}

@test "filter 'all' shows both active and archived seeds" {
    # Create one active and one archived seed
    SEED1="seed-$(date +%s)001-active"
    SEED2="seed-$(date +%s)002-archived"

    cat > "$TEST_SEEDS_DIR/test-session-123/$SEED1.json" << EOF
{
  "id": "$SEED1",
  "title": "Active seed",
  "rationale": "Test",
  "anchors": [],
  "ttl_hours": 24,
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)",
  "dedupe_key": "act",
  "session_id": "test-session-123",
  "status": "active"
}
EOF

    cat > "$TEST_SEEDS_DIR/test-session-123/$SEED2.json" << EOF
{
  "id": "$SEED2",
  "title": "Archived seed",
  "rationale": "Test",
  "anchors": [],
  "ttl_hours": 24,
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)",
  "dedupe_key": "arc",
  "session_id": "test-session-123",
  "status": "archived"
}
EOF

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" list all "$TEST_BASE_DIR"
    assert_success

    echo "$output" | bun -e "
        const seeds = JSON.parse(await Bun.stdin.text());
        if (seeds.length !== 2) throw new Error('Expected 2 seeds, got: ' + seeds.length);
        console.log('OK');
    "
}

# ============================================================================
# FRESHNESS TIER TESTS (Time-Based)
# Tiers: 🌱 < 24 hours, 💭 24-72 hours, 💤 > 72 hours, 📦 archived
# ============================================================================

@test "freshness_tier is 🌱 for fresh seed (< 3 hours old)" {
    # Create seed with current timestamp (fresh)
    SEED_ID="seed-$(date +%s)000-fresh"
    cat > "$TEST_SEEDS_DIR/test-session-123/$SEED_ID.json" << EOF
{
  "id": "$SEED_ID",
  "title": "Fresh seed",
  "rationale": "Test",
  "anchors": [],
  "ttl_hours": 24,
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)",
  "dedupe_key": "fresh",
  "session_id": "test-session-123"
}
EOF

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" list "$TEST_BASE_DIR"
    assert_success

    echo "$output" | bun -e "
        const seeds = JSON.parse(await Bun.stdin.text());
        if (seeds[0].freshness_tier !== '🌱') throw new Error('Expected 🌱 for fresh seed, got: ' + seeds[0].freshness_tier);
        console.log('OK');
    "
}

@test "freshness_tier is 💭 for seed between 24-72 hours old" {
    # Create seed from 30 hours ago (24-72 hour window = 💭)
    THIRTY_HOURS_AGO_MS=$(($(date +%s) * 1000 - 30 * 60 * 60 * 1000))
    SEED_ID="seed-${THIRTY_HOURS_AGO_MS}-bubble"
    cat > "$TEST_SEEDS_DIR/test-session-123/$SEED_ID.json" << EOF
{
  "id": "$SEED_ID",
  "title": "Bubble seed",
  "rationale": "Test",
  "anchors": [],
  "ttl_hours": 72,
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)",
  "dedupe_key": "bubble",
  "session_id": "test-session-123"
}
EOF

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" list "$TEST_BASE_DIR"
    assert_success

    echo "$output" | bun -e "
        const seeds = JSON.parse(await Bun.stdin.text());
        if (seeds[0].freshness_tier !== '💭') throw new Error('Expected 💭 for 30-hour-old seed, got: ' + seeds[0].freshness_tier);
        console.log('OK');
    "
}

@test "freshness_tier is 💤 for outdated seed (> 72 hours old)" {
    # Create old seed (from 2020) - way past 72 hour TTL
    OLD_TIMESTAMP="1577836800000"
    SEED_ID="seed-${OLD_TIMESTAMP}-old123"
    cat > "$TEST_SEEDS_DIR/test-session-123/$SEED_ID.json" << EOF
{
  "id": "$SEED_ID",
  "title": "Old seed",
  "rationale": "Test",
  "anchors": [],
  "ttl_hours": 72,
  "created_at": "2020-01-01T00:00:00.000Z",
  "dedupe_key": "old",
  "session_id": "test-session-123"
}
EOF

    # Use 'list-all outdated' to see 💤 seeds
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" list-all outdated "$TEST_BASE_DIR"
    assert_success

    echo "$output" | bun -e "
        const seeds = JSON.parse(await Bun.stdin.text());
        if (seeds[0].freshness_tier !== '💤') throw new Error('Expected 💤, got: ' + seeds[0].freshness_tier);
        console.log('OK');
    "
}

@test "freshness_tier is 📦 for archived seed" {
    # Create archived seed
    SEED_ID="seed-$(date +%s)000-archived"
    cat > "$TEST_SEEDS_DIR/test-session-123/$SEED_ID.json" << EOF
{
  "id": "$SEED_ID",
  "title": "Archived seed",
  "rationale": "Test",
  "anchors": [],
  "ttl_hours": 24,
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)",
  "dedupe_key": "arc",
  "session_id": "test-session-123",
  "status": "archived"
}
EOF

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" list all "$TEST_BASE_DIR"
    assert_success

    echo "$output" | bun -e "
        const seeds = JSON.parse(await Bun.stdin.text());
        if (seeds[0].freshness_tier !== '📦') throw new Error('Expected 📦, got: ' + seeds[0].freshness_tier);
        console.log('OK');
    "
}

@test "archived status takes precedence over outdated" {
    # Create old archived seed
    OLD_TIMESTAMP="1577836800000"
    SEED_ID="seed-${OLD_TIMESTAMP}-arcold"
    cat > "$TEST_SEEDS_DIR/test-session-123/$SEED_ID.json" << EOF
{
  "id": "$SEED_ID",
  "title": "Old archived seed",
  "rationale": "Test",
  "anchors": [],
  "ttl_hours": 24,
  "created_at": "2020-01-01T00:00:00.000Z",
  "dedupe_key": "arcold",
  "session_id": "test-session-123",
  "status": "archived"
}
EOF

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" list all "$TEST_BASE_DIR"
    assert_success

    # Should be 📦 (archived) not 💤 (outdated)
    echo "$output" | bun -e "
        const seeds = JSON.parse(await Bun.stdin.text());
        if (seeds[0].freshness_tier !== '📦') throw new Error('Expected 📦 for archived, got: ' + seeds[0].freshness_tier);
        if (!seeds[0].is_outdated) throw new Error('Expected is_outdated to be true');
        console.log('OK');
    "
}

# ============================================================================
# ARCHIVE/DELETE OPERATIONS
# ============================================================================

@test "archive-all archives all active seeds" {
    # Create two active seeds
    SEED1="seed-$(date +%s)001-one"
    SEED2="seed-$(date +%s)002-two"

    cat > "$TEST_SEEDS_DIR/test-session-123/$SEED1.json" << EOF
{"id":"$SEED1","title":"One","rationale":"Test","anchors":[],"ttl_hours":24,"created_at":"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)","dedupe_key":"one","session_id":"test-session-123","status":"active"}
EOF

    cat > "$TEST_SEEDS_DIR/test-session-123/$SEED2.json" << EOF
{"id":"$SEED2","title":"Two","rationale":"Test","anchors":[],"ttl_hours":24,"created_at":"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)","dedupe_key":"two","session_id":"test-session-123","status":"active"}
EOF

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" archive-all "$TEST_BASE_DIR"
    assert_success

    # Check that both are now archived
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" list archived "$TEST_BASE_DIR"
    assert_success

    echo "$output" | bun -e "
        const seeds = JSON.parse(await Bun.stdin.text());
        if (seeds.length !== 2) throw new Error('Expected 2 archived seeds, got: ' + seeds.length);
        console.log('OK');
    "
}

@test "delete-archived only deletes archived seeds" {
    # Create one active and one archived seed
    SEED1="seed-$(date +%s)001-keep"
    SEED2="seed-$(date +%s)002-delete"

    cat > "$TEST_SEEDS_DIR/test-session-123/$SEED1.json" << EOF
{"id":"$SEED1","title":"Keep me","rationale":"Test","anchors":[],"ttl_hours":24,"created_at":"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)","dedupe_key":"keep","session_id":"test-session-123","status":"active"}
EOF

    cat > "$TEST_SEEDS_DIR/test-session-123/$SEED2.json" << EOF
{"id":"$SEED2","title":"Delete me","rationale":"Test","anchors":[],"ttl_hours":24,"created_at":"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)","dedupe_key":"del","session_id":"test-session-123","status":"archived"}
EOF

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" delete-archived "$TEST_BASE_DIR"
    assert_success

    # Check that only active seed remains
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" list all "$TEST_BASE_DIR"
    assert_success

    echo "$output" | bun -e "
        const seeds = JSON.parse(await Bun.stdin.text());
        if (seeds.length !== 1) throw new Error('Expected 1 seed, got: ' + seeds.length);
        if (seeds[0].title !== 'Keep me') throw new Error('Expected Keep me to remain');
        console.log('OK');
    "
}

# ============================================================================
# FILTER CONFIG TESTS
# ============================================================================

@test "get-filter returns current filter setting" {
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" get-filter "$TEST_BASE_DIR"
    assert_success
    # Should be 'active' by default
    assert_output "active"
}

@test "set-filter updates filter setting" {
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" set-filter all "$TEST_BASE_DIR"
    assert_success
    assert_output "all"

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" get-filter "$TEST_BASE_DIR"
    assert_success
    assert_output "all"
}

@test "cycle-filter cycles through active -> outdated -> archived -> all -> active" {
    # Cycle: active → outdated → archived → all → active
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" set-filter active "$TEST_BASE_DIR"

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" cycle-filter "$TEST_BASE_DIR"
    assert_success
    assert_output "outdated"

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" cycle-filter "$TEST_BASE_DIR"
    assert_success
    assert_output "archived"

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" cycle-filter "$TEST_BASE_DIR"
    assert_success
    assert_output "all"

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" cycle-filter "$TEST_BASE_DIR"
    assert_success
    assert_output "active"
}

@test "set-filter validates input" {
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" set-filter invalid "$TEST_BASE_DIR"
    assert_failure
}

# ============================================================================
# EXPANSION CONCLUDE TESTS
# ============================================================================

@test "conclude adds expansion record to seed" {
    # Create seed
    SEED_ID="seed-$(date +%s)000-conclude"
    cat > "$TEST_SEEDS_DIR/test-session-123/$SEED_ID.json" << EOF
{
  "id": "$SEED_ID",
  "title": "Test seed for conclude",
  "rationale": "Testing conclude functionality",
  "anchors": [],
  "ttl_hours": 24,
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)",
  "dedupe_key": "conc",
  "session_id": "test-session-123"
}
EOF

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" conclude "$SEED_ID" "This seed was expanded and resolved the issue" "$TEST_BASE_DIR"
    assert_success

    # Verify expansion was recorded
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" get "$SEED_ID" "$TEST_BASE_DIR"
    assert_success

    echo "$output" | bun -e "
        const s = JSON.parse(await Bun.stdin.text());
        if (!s.expansions || s.expansions.length !== 1) throw new Error('Expected 1 expansion');
        if (s.expansions[0].conclusion !== 'This seed was expanded and resolved the issue') {
            throw new Error('Wrong conclusion: ' + s.expansions[0].conclusion);
        }
        console.log('OK');
    "
}

@test "conclude with result_path includes path in record" {
    # Create seed
    SEED_ID="seed-$(date +%s)000-withpath"
    cat > "$TEST_SEEDS_DIR/test-session-123/$SEED_ID.json" << EOF
{
  "id": "$SEED_ID",
  "title": "Test seed with result path",
  "rationale": "Testing conclude with path",
  "anchors": [],
  "ttl_hours": 24,
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)",
  "dedupe_key": "path",
  "session_id": "test-session-123"
}
EOF

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" conclude "$SEED_ID" "Concluded with path" "/tmp/result.md" "$TEST_BASE_DIR"
    assert_success

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" get "$SEED_ID" "$TEST_BASE_DIR"
    assert_success

    echo "$output" | bun -e "
        const s = JSON.parse(await Bun.stdin.text());
        if (s.expansions[0].result_path !== '/tmp/result.md') {
            throw new Error('Wrong path: ' + s.expansions[0].result_path);
        }
        console.log('OK');
    "
}

@test "conclude can be called multiple times on same seed" {
    # Create seed
    SEED_ID="seed-$(date +%s)000-multi"
    cat > "$TEST_SEEDS_DIR/test-session-123/$SEED_ID.json" << EOF
{
  "id": "$SEED_ID",
  "title": "Test multiple expansions",
  "rationale": "Testing multiple conclude calls",
  "anchors": [],
  "ttl_hours": 24,
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)",
  "dedupe_key": "multi",
  "session_id": "test-session-123"
}
EOF

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" conclude "$SEED_ID" "First expansion" "$TEST_BASE_DIR"
    assert_success

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" conclude "$SEED_ID" "Second expansion" "$TEST_BASE_DIR"
    assert_success

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" get "$SEED_ID" "$TEST_BASE_DIR"
    assert_success

    echo "$output" | bun -e "
        const s = JSON.parse(await Bun.stdin.text());
        if (s.expansions.length !== 2) throw new Error('Expected 2 expansions, got: ' + s.expansions.length);
        if (s.expansions[0].conclusion !== 'First expansion') throw new Error('Wrong first conclusion');
        if (s.expansions[1].conclusion !== 'Second expansion') throw new Error('Wrong second conclusion');
        console.log('OK');
    "
}

@test "conclude fails for non-existent seed" {
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" conclude "seed-nonexistent-123" "Some conclusion" "$TEST_BASE_DIR"
    assert_success
    # Should return {"success":false} (JSON.stringify output)
    echo "$output" | grep -q '"success":false'
}

@test "conclude requires both seed-id and conclusion" {
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" conclude "$TEST_BASE_DIR"
    assert_failure
}
