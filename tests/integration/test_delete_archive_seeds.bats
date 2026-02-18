#!/usr/bin/env bats

# test_delete_archive_seeds.bats - Tests for delete/archive menu parsing harness
#
# WHY: Ensures menu line parsing works correctly for Ctrl+D/A keybindings
# TESTS: Emoji pattern matching, tab delimiter extraction, seed ID parsing
# NOTE: Does not test terminal interaction (confirmation prompts)

load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load

setup() {
    export REFLECTION_BASE="$(mktemp -d)"
    source "$BATS_TEST_DIRNAME/../../lib/cc-common.sh"
}

teardown() {
    rm -rf "$REFLECTION_BASE"
}

# Helper: Create menu line with tab separator (matches cc-reflect menu format)
menu_line() {
    local label="$1"
    local command="$2"
    printf '%s\t%s' "$label" "$command"
}

# ============================================================================
# DELETE SCRIPT - HARNESS TESTS
# ============================================================================

@test "delete-seed: script exists and is executable" {
    [ -x "$BATS_TEST_DIRNAME/../../bin/cc-reflect-delete-seed" ]
}

@test "delete-seed: rejects non-seed lines (no emoji)" {
    run "$BATS_TEST_DIRNAME/../../bin/cc-reflect-delete-seed" \
        "$(menu_line "Not a seed" "cc-reflect-expand interactive seed-123")"
    assert_failure
    assert_output --partial "Not a seed line"
}

@test "delete-seed: rejects editor menu lines" {
    run "$BATS_TEST_DIRNAME/../../bin/cc-reflect-delete-seed" \
        "$(menu_line "Edit with Vim" "vi /tmp/file.txt")"
    assert_failure
    assert_output --partial "Not a seed line"
}

@test "delete-seed: rejects settings menu lines" {
    run "$BATS_TEST_DIRNAME/../../bin/cc-reflect-delete-seed" \
        "$(menu_line "Mode: Interactive" "cc-reflect-toggle-mode")"
    assert_failure
    assert_output --partial "Not a seed line"
}

@test "delete-seed: accepts fresh seed emoji" {
    # Will fail later (seed not found) but should pass emoji check
    run "$BATS_TEST_DIRNAME/../../bin/cc-reflect-delete-seed" \
        "$(menu_line "🌱 Fresh seed" "cc-reflect-expand interactive seed-999-notfound")"
    # Should get past emoji check, fail on "seed not found"
    assert_failure
    assert_output --partial "Seed not found"
}

@test "delete-seed: accepts thinking emoji" {
    run "$BATS_TEST_DIRNAME/../../bin/cc-reflect-delete-seed" \
        "$(menu_line "💭 Thinking seed" "cc-reflect-expand interactive seed-999-notfound")"
    assert_failure
    assert_output --partial "Seed not found"
}

@test "delete-seed: accepts outdated emoji" {
    run "$BATS_TEST_DIRNAME/../../bin/cc-reflect-delete-seed" \
        "$(menu_line "💤 Old seed" "cc-reflect-expand interactive seed-999-notfound")"
    assert_failure
    assert_output --partial "Seed not found"
}

@test "delete-seed: accepts archived emoji" {
    run "$BATS_TEST_DIRNAME/../../bin/cc-reflect-delete-seed" \
        "$(menu_line "📦 Archived seed" "cc-reflect-expand interactive seed-999-notfound")"
    assert_failure
    assert_output --partial "Seed not found"
}

@test "delete-seed: extracts seed ID from tab-separated command" {
    # The fact that it says "Seed not found: seed-123-abc" proves ID was extracted
    run "$BATS_TEST_DIRNAME/../../bin/cc-reflect-delete-seed" \
        "$(menu_line "🌱 Test Seed" "cc-reflect-expand interactive seed-123-abc")"
    assert_failure
    assert_output --partial "seed-123-abc"
}

@test "delete-seed: handles seed ID with long timestamp" {
    run "$BATS_TEST_DIRNAME/../../bin/cc-reflect-delete-seed" \
        "$(menu_line "🌱 Test" "cc-reflect-expand auto seed-1699123456789-xyz123")"
    assert_failure
    assert_output --partial "seed-1699123456789-xyz123"
}

@test "delete-seed: fails when command missing seed ID" {
    run "$BATS_TEST_DIRNAME/../../bin/cc-reflect-delete-seed" \
        "$(menu_line "🌱 Bad command" "cc-reflect-expand interactive")"
    assert_failure
    assert_output --partial "Could not extract seed ID"
}

# ============================================================================
# ARCHIVE SCRIPT - HARNESS TESTS
# ============================================================================

@test "archive-seed: script exists and is executable" {
    [ -x "$BATS_TEST_DIRNAME/../../bin/cc-reflect-archive-seed" ]
}

@test "archive-seed: rejects non-seed lines (no emoji)" {
    run "$BATS_TEST_DIRNAME/../../bin/cc-reflect-archive-seed" \
        "$(menu_line "Not a seed" "cc-reflect-expand interactive seed-123")"
    assert_failure
    assert_output --partial "Not a seed line"
}

@test "archive-seed: toggles archived seeds to unarchive" {
    # When seed is already archived (📦), script should attempt to unarchive
    # Will fail with "Seed not found" because seed doesn't exist, but that proves
    # it's trying to process it (toggle) rather than skipping
    run "$BATS_TEST_DIRNAME/../../bin/cc-reflect-archive-seed" \
        "$(menu_line "📦 Already archived" "cc-reflect-expand interactive seed-999-archived")"
    assert_failure
    assert_output --partial "Seed not found"
}

@test "archive-seed: accepts fresh seed emoji" {
    run "$BATS_TEST_DIRNAME/../../bin/cc-reflect-archive-seed" \
        "$(menu_line "🌱 Fresh seed" "cc-reflect-expand interactive seed-999-notfound")"
    assert_failure
    assert_output --partial "Seed not found"
}

@test "archive-seed: extracts seed ID from tab-separated command" {
    run "$BATS_TEST_DIRNAME/../../bin/cc-reflect-archive-seed" \
        "$(menu_line "🌱 Test Seed" "cc-reflect-expand auto seed-456-def")"
    assert_failure
    assert_output --partial "seed-456-def"
}

@test "archive-seed: fails when command missing seed ID" {
    run "$BATS_TEST_DIRNAME/../../bin/cc-reflect-archive-seed" \
        "$(menu_line "💭 Bad command" "cc-reflect-expand auto")"
    assert_failure
    assert_output --partial "Could not extract seed ID"
}

# ============================================================================
# TAB DELIMITER REGRESSION TESTS
# ============================================================================

@test "delete-seed: uses tab delimiter not pipe" {
    # This test specifically guards against the bug where pipe was used instead of tab
    # If using pipe delimiter, this would fail to extract the command
    run "$BATS_TEST_DIRNAME/../../bin/cc-reflect-delete-seed" \
        "$(menu_line "🌱 Tab|Separated" "cc-reflect-expand interactive seed-tab-test")"
    assert_failure
    # Should extract seed ID correctly (proves tab parsing works)
    assert_output --partial "seed-tab-test"
}

@test "archive-seed: uses tab delimiter not pipe" {
    run "$BATS_TEST_DIRNAME/../../bin/cc-reflect-archive-seed" \
        "$(menu_line "💭 Tab|Separated" "cc-reflect-expand auto seed-tab-test")"
    assert_failure
    assert_output --partial "seed-tab-test"
}

@test "delete-seed: handles title with pipe character" {
    # Pipe in title should not break parsing (it's not the delimiter)
    run "$BATS_TEST_DIRNAME/../../bin/cc-reflect-delete-seed" \
        "$(menu_line "🌱 Choice A | Choice B" "cc-reflect-expand interactive seed-pipe-test")"
    assert_failure
    assert_output --partial "seed-pipe-test"
}

@test "archive-seed: handles title with colon character" {
    # Colon in title should not break parsing
    run "$BATS_TEST_DIRNAME/../../bin/cc-reflect-archive-seed" \
        "$(menu_line "💭 Time: 12:34:56" "cc-reflect-expand auto seed-colon-test")"
    assert_failure
    assert_output --partial "seed-colon-test"
}

# ============================================================================
# EMOJI PATTERN MATCHING
# ============================================================================

@test "CC_SEED_EMOJI_PATTERN is defined" {
    [ -n "$CC_SEED_EMOJI_PATTERN" ]
}

@test "CC_SEED_EMOJI_PATTERN matches all tier emojis" {
    [[ "🌱 Fresh" =~ $CC_SEED_EMOJI_PATTERN ]]
    [[ "💭 Thinking" =~ $CC_SEED_EMOJI_PATTERN ]]
    [[ "💤 Outdated" =~ $CC_SEED_EMOJI_PATTERN ]]
    [[ "📦 Archived" =~ $CC_SEED_EMOJI_PATTERN ]]
}

@test "CC_SEED_EMOJI_PATTERN rejects non-seed emojis" {
    [[ ! "✏️ Edit" =~ $CC_SEED_EMOJI_PATTERN ]]
    [[ ! "🔄 Mode" =~ $CC_SEED_EMOJI_PATTERN ]]
    [[ ! "🤖 Model" =~ $CC_SEED_EMOJI_PATTERN ]]
}
