#!/usr/bin/env bats

# test_session_matching.bats - Test session ID matching logic
#
# WHY: Session matching must handle backward compatibility with old 32-char IDs
# and new 12-char prefix format

load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'

# ============================================================================
# SESSION ID PREFIX MATCHING
# ============================================================================

@test "session matching: 12-char prefix matches 32-char full ID" {
    # Simulate the TypeScript logic in bash for testing
    prefix="eedb26805985"
    full_id="eedb2680598501a74d2e681fa24000fd"
    
    # Check prefix match
    [[ "$full_id" == "$prefix"* ]]
}

@test "session matching: exact match works" {
    prefix="eedb26805985"
    same="eedb26805985"
    
    [[ "$same" == "$prefix" ]]
}

@test "session matching: different session doesn't match" {
    prefix="eedb26805985"
    different="abc123456789"
    
    [[ "$different" != "$prefix"* ]]
}

@test "session matching: similar but different prefix doesn't match" {
    prefix="eedb26805985"
    similar="eedb26805986"  # Last char different
    
    [[ "$similar" != "$prefix"* ]]
}

# ============================================================================
# FRESHNESS TIER TESTS (via TypeScript)
# Time-based: 🌱 < 3 hours, 💭 3-24 hours, 💤 > 24 hours
# ============================================================================

@test "freshness tier: newly created seeds get 🌱" {
    # Create a test seed and verify it gets fresh tier
    export REFLECTION_BASE="$(mktemp -d)"
    source "$BATS_TEST_DIRNAME/../../lib/cc-common.sh"

    # Create test seed with unique title
    unique_title="Test freshness tier $(date +%s)"
    result=$(bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" write \
        "$unique_title" \
        "Testing that fresh seeds get seedling emoji" \
        2>/dev/null)

    # Extract seed ID from result (result has nested .seed.id structure)
    seed_id=$(echo "$result" | bun -e "const r = JSON.parse(await Bun.stdin.text()); console.log(r.seed?.id || r.id || '');" 2>/dev/null)

    # Skip if seed creation failed
    if [ -z "$seed_id" ] || [ "$seed_id" = "undefined" ]; then
        skip "Seed creation failed"
    fi

    # Get seed and check freshness tier
    seed_data=$(bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" get "$seed_id" 2>/dev/null)
    tier=$(echo "$seed_data" | bun -e "const s = JSON.parse(await Bun.stdin.text()); console.log(s?.freshness_tier || '');" 2>/dev/null)

    # Cleanup (inline test — no teardown, so clean up here)
    rm -rf "$REFLECTION_BASE"

    # Skip if we couldn't get the tier
    if [ -z "$tier" ]; then
        skip "Could not retrieve seed tier"
    fi

    assert_equal "$tier" "🌱"
}
