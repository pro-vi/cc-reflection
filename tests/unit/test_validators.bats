#!/usr/bin/env bats

# test_validators.bats - Test all validation functions
#
# WHY: Validators prevent malformed input from causing cryptic errors
# GOAL: Fail fast with clear error messages

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
# SEED ID VALIDATION
# ============================================================================

@test "validate_seed_id accepts correct format" {
    run validate_seed_id "seed-1699123456-a1b2c3d"
    assert_success
}

@test "validate_seed_id accepts seed with long timestamp" {
    run validate_seed_id "seed-17001234567890-xyz123"
    assert_success
}

@test "validate_seed_id rejects missing prefix" {
    run validate_seed_id "1699123456-a1b2c3d"
    assert_failure
    assert_output --partial "Invalid seed ID format"
}

@test "validate_seed_id rejects wrong prefix" {
    run validate_seed_id "test-1699123456-a1b2c3d"
    assert_failure
}

@test "validate_seed_id rejects underscore separator" {
    run validate_seed_id "seed_1699123456_a1b2c3d"
    assert_failure
}

@test "validate_seed_id rejects non-numeric timestamp" {
    run validate_seed_id "seed-abc123456-a1b2c3d"
    assert_failure
}

@test "validate_seed_id rejects uppercase in random part" {
    run validate_seed_id "seed-1699123456-A1B2C3D"
    assert_failure
}

@test "validate_seed_id rejects empty string" {
    run validate_seed_id ""
    assert_failure
}

@test "validate_seed_id rejects seed ID with special characters" {
    run validate_seed_id "seed-1699123456-a@b#c"
    assert_failure
}

# ============================================================================
# MODE VALIDATION
# ============================================================================

@test "validate_mode accepts interactive" {
    run validate_mode "interactive"
    assert_success
}

@test "validate_mode accepts auto" {
    run validate_mode "auto"
    assert_success
}

@test "validate_mode rejects manual" {
    run validate_mode "manual"
    assert_failure
    assert_output --partial "Invalid mode: manual"
}

@test "validate_mode rejects uppercase INTERACTIVE" {
    run validate_mode "INTERACTIVE"
    assert_failure
}

@test "validate_mode rejects empty string" {
    run validate_mode ""
    assert_failure
}

@test "validate_mode shows valid modes in error message" {
    run validate_mode "wrong"
    assert_failure
    assert_output --partial "Valid modes: interactive, auto"
}

# ============================================================================
# FILE PATH VALIDATION
# ============================================================================

@test "validate_file_exists succeeds for existing file" {
    temp_file=$(mktemp)
    run validate_file_exists "$temp_file"
    assert_success
    rm "$temp_file"
}

@test "validate_file_exists fails for non-existent file" {
    run validate_file_exists "/tmp/nonexistent-file-12345.txt"
    assert_failure
    assert_output --partial "File not found"
}

@test "validate_file_exists fails for directory" {
    temp_dir=$(mktemp -d)
    run validate_file_exists "$temp_dir"
    assert_failure
    rmdir "$temp_dir"
}

@test "validate_file_exists fails for empty path" {
    run validate_file_exists ""
    assert_failure
    assert_output --partial "File path is empty"
}

@test "validate_file_exists fails for unreadable file" {
    temp_file=$(mktemp)
    chmod 000 "$temp_file"

    run validate_file_exists "$temp_file"
    assert_failure
    assert_output --partial "File not readable"

    # Cleanup (restore permissions first)
    chmod 644 "$temp_file"
    rm "$temp_file"
}

# ============================================================================
# MENU FILTER VALIDATION
# ============================================================================

@test "validate_menu_filter accepts 'all'" {
    run validate_menu_filter "all"
    assert_success
}

@test "validate_menu_filter accepts 'active'" {
    run validate_menu_filter "active"
    assert_success
}

@test "validate_menu_filter accepts 'outdated'" {
    run validate_menu_filter "outdated"
    assert_success
}

@test "validate_menu_filter accepts 'archived'" {
    run validate_menu_filter "archived"
    assert_success
}

@test "validate_menu_filter rejects invalid filter" {
    run validate_menu_filter "invalid"
    assert_failure
    assert_output --partial "Invalid menu filter"
}

@test "validate_menu_filter rejects empty string" {
    run validate_menu_filter ""
    assert_failure
}

@test "validate_menu_filter rejects uppercase" {
    run validate_menu_filter "ALL"
    assert_failure
}

@test "validate_menu_filter shows valid filters in error message" {
    run validate_menu_filter "wrong"
    assert_failure
    assert_output --partial "Valid filters:"
    assert_output --partial "all"
    assert_output --partial "active"
    assert_output --partial "outdated"
    assert_output --partial "archived"
}

# ============================================================================
# COMBINED VALIDATION SCENARIOS
# ============================================================================

@test "all validators work together in sequence" {
    # Simulate validating parameters for cc-reflect-expand

    # Valid seed ID
    run validate_seed_id "seed-1699123456-abc123"
    assert_success

    # Valid mode
    run validate_mode "interactive"
    assert_success
}

@test "validation failures provide actionable error messages" {
    # Each validation should tell user what went wrong AND what's expected

    run validate_seed_id "bad-id"
    assert_failure
    assert_output --partial "Expected format:"

    run validate_mode "wrong"
    assert_failure
    assert_output --partial "Valid modes:"
}
