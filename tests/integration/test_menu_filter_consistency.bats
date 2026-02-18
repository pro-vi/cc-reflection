#!/usr/bin/env bats

# test_menu_filter_consistency.bats - Cross-language MenuFilter validation tests
#
# WHY: Ensures bash and TypeScript accept/reject the same filter values
# HISTORY: Bug where 'outdated' was accepted by TS but rejected by bash (commit 72c29d2)
# SYNC: Tests both VALID_MENU_FILTERS (bash) and MENU_FILTERS (TypeScript)

load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load

setup() {
    export REFLECTION_BASE="$(mktemp -d)"
    source "$BATS_TEST_DIRNAME/../../lib/cc-common.sh"
    source "$BATS_TEST_DIRNAME/../../lib/validators.sh"
}

teardown() {
    rm -rf "$REFLECTION_BASE"
}

# ============================================================================
# CROSS-LANGUAGE CONSISTENCY TESTS
# ============================================================================

@test "bash and TypeScript accept same set of valid filters" {
    # Get valid filters from bash
    bash_filters="${VALID_MENU_FILTERS[*]}"

    # Get valid filters from TypeScript by testing each
    for filter in all active outdated archived; do
        # Test bash accepts it
        run validate_menu_filter "$filter"
        assert_success "bash should accept '$filter'"

        # Test TypeScript accepts it
        run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" set-filter "$filter"
        assert_success "TypeScript should accept '$filter'"
    done
}

@test "bash and TypeScript reject same invalid filters" {
    invalid_filters=("invalid" "expired" "pending" "deleted" "ALL" "Active" "")

    for filter in "${invalid_filters[@]}"; do
        # Test bash rejects it
        run validate_menu_filter "$filter"
        assert_failure "bash should reject '$filter'"

        # Test TypeScript rejects it
        run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" set-filter "$filter"
        assert_failure "TypeScript should reject '$filter'"
    done
}

@test "'outdated' filter is accepted by both bash and TypeScript" {
    # This specific test prevents regression of the bug fixed in this refactoring

    # Bash validation
    run validate_menu_filter "outdated"
    assert_success "bash validate_menu_filter should accept 'outdated'"

    # Bash cc_set_menu_filter
    run bash -c 'source lib/cc-common.sh && cc_set_menu_filter "outdated"'
    assert_success "bash cc_set_menu_filter should accept 'outdated'"

    # TypeScript CLI
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" set-filter "outdated"
    assert_success "TypeScript set-filter should accept 'outdated'"

    # Verify it was actually set
    result=$(bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" get-filter)
    assert_equal "$result" "outdated"
}

@test "VALID_MENU_FILTERS array contains exactly 4 values" {
    # Ensures we don't accidentally add/remove filters without updating tests
    count=${#VALID_MENU_FILTERS[@]}
    assert_equal "$count" "4"
}

@test "VALID_MENU_FILTERS contains expected values" {
    # Verify exact set of valid filters
    run echo "${VALID_MENU_FILTERS[*]}"
    assert_output "all active outdated archived"
}

@test "TypeScript list command accepts all valid filters" {
    for filter in all active outdated archived; do
        run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" list "$filter"
        assert_success "list should accept '$filter'"
    done
}

@test "TypeScript list-all command accepts all valid filters" {
    for filter in all active outdated archived; do
        run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" list-all "$filter"
        assert_success "list-all should accept '$filter'"
    done
}

@test "TypeScript cycle-filter cycles through all values" {
    # Start from 'active'
    bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" set-filter "active" >/dev/null

    # Cycle: active → outdated
    result=$(bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" cycle-filter)
    assert_equal "$result" "outdated"

    # Cycle: outdated → archived
    result=$(bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" cycle-filter)
    assert_equal "$result" "archived"

    # Cycle: archived → all
    result=$(bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" cycle-filter)
    assert_equal "$result" "all"

    # Cycle: all → active (wrap around)
    result=$(bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" cycle-filter)
    assert_equal "$result" "active"
}

@test "error messages from bash and TypeScript mention all valid filters" {
    # Bash error message
    run validate_menu_filter "invalid"
    assert_failure
    assert_output --partial "all"
    assert_output --partial "active"
    assert_output --partial "outdated"
    assert_output --partial "archived"

    # TypeScript error message
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" set-filter "invalid"
    assert_failure
    assert_output --partial "all"
    assert_output --partial "active"
    assert_output --partial "outdated"
    assert_output --partial "archived"
}
