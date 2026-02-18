#!/usr/bin/env bats

# test_menu_scripts.bats - Tests for bin/cc-reflect-build-menu and bin/cc-reflect-rebuild-menu
#
# WHY: Validates the actual script entrypoints for menu generation
# TESTS: Output format, section presence, tab separation, label extraction

load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load
load ../test_helper/bats-file/load

SCRIPT_DIR="$BATS_TEST_DIRNAME/../../bin"

setup() {
    # Create isolated test environment
    export TEST_BASE_DIR="$BATS_TMPDIR/test-reflections-$$"
    export REFLECTION_BASE="$TEST_BASE_DIR"
    mkdir -p "$TEST_BASE_DIR"
    mkdir -p "$TEST_BASE_DIR/seeds"
    mkdir -p "$TEST_BASE_DIR/logs"

    # Create a test file path (doesn't need to exist for menu building)
    TEST_FILE="$BATS_TMPDIR/test-prompt-$$.txt"
    touch "$TEST_FILE"
}

teardown() {
    rm -rf "$TEST_BASE_DIR"
    rm -f "$TEST_FILE"
}

# ============================================================================
# SCRIPT EXISTENCE
# ============================================================================

@test "build-menu: script exists and is executable" {
    assert_file_exists "$SCRIPT_DIR/cc-reflect-build-menu"
    [ -x "$SCRIPT_DIR/cc-reflect-build-menu" ]
}

@test "rebuild-menu: script exists and is executable" {
    assert_file_exists "$SCRIPT_DIR/cc-reflect-rebuild-menu"
    [ -x "$SCRIPT_DIR/cc-reflect-rebuild-menu" ]
}

# ============================================================================
# BUILD-MENU OUTPUT FORMAT
# ============================================================================

@test "build-menu: outputs tab-separated format" {
    run "$SCRIPT_DIR/cc-reflect-build-menu" "$TEST_FILE"
    assert_success

    # Should have at least some lines with tabs
    echo "$output" | grep -q $'\t'
}

@test "build-menu: includes editor section with vim" {
    run "$SCRIPT_DIR/cc-reflect-build-menu" "$TEST_FILE"
    assert_success
    assert_output --partial "Edit with Vim"
}

@test "build-menu: includes settings section" {
    run "$SCRIPT_DIR/cc-reflect-build-menu" "$TEST_FILE"
    assert_success
    assert_output --partial "Mode:"
    assert_output --partial "Model:"
    assert_output --partial "Filter:"
}

@test "build-menu: includes actions section" {
    run "$SCRIPT_DIR/cc-reflect-build-menu" "$TEST_FILE"
    assert_success
    assert_output --partial "Archive Outdated"
}

@test "build-menu: includes enhance prompt option" {
    run "$SCRIPT_DIR/cc-reflect-build-menu" "$TEST_FILE"
    assert_success
    assert_output --partial "Enhance Prompt"
}

@test "build-menu: handles empty seed list" {
    # No seeds in TEST_BASE_DIR/seeds
    run "$SCRIPT_DIR/cc-reflect-build-menu" "$TEST_FILE"
    assert_success
    # Should still have editors and settings
    assert_output --partial "Edit with Vim"
    assert_output --partial "Mode:"
}

@test "build-menu: each non-separator line has tab delimiter" {
    run "$SCRIPT_DIR/cc-reflect-build-menu" "$TEST_FILE"
    assert_success

    # Check that non-empty, non-separator lines have tabs
    echo "$output" | while IFS= read -r line; do
        # Skip empty lines and separator lines (══)
        if [ -n "$line" ] && ! echo "$line" | grep -q "══"; then
            # Line should contain a tab
            echo "$line" | grep -q $'\t' || {
                echo "Line missing tab: $line"
                return 1
            }
        fi
    done
}

# ============================================================================
# REBUILD-MENU OUTPUT FORMAT
# ============================================================================

@test "rebuild-menu: outputs labels only (no tabs)" {
    run "$SCRIPT_DIR/cc-reflect-rebuild-menu" "$TEST_FILE"
    assert_success

    # Should NOT have any tabs in output
    ! echo "$output" | grep -q $'\t'
}

@test "rebuild-menu: strips commands from build-menu output" {
    # Get rebuild-menu output
    rebuild_output=$("$SCRIPT_DIR/cc-reflect-rebuild-menu" "$TEST_FILE")

    # Should have labels like "Edit with Vim" but not the command portion
    echo "$rebuild_output" | grep -q "Edit with Vim"

    # Should not contain actual commands
    ! echo "$rebuild_output" | grep -q "vim "
}

@test "rebuild-menu: handles all section types" {
    run "$SCRIPT_DIR/cc-reflect-rebuild-menu" "$TEST_FILE"
    assert_success

    # Check that major sections are present
    assert_output --partial "Edit with"
    assert_output --partial "Mode:"
}

# ============================================================================
# WITH SEEDS
# ============================================================================

@test "build-menu: shows seeds when present" {
    # Create a test seed using the proper API
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" write \
        "Test seed for menu" \
        "Test rationale" \
        "test.ts" \
        "start" \
        "end" \
        "$TEST_BASE_DIR"
    assert_success
    assert_output --partial '"success": true'

    run "$SCRIPT_DIR/cc-reflect-build-menu" "$TEST_FILE"
    assert_success
    assert_output --partial "Test seed for menu"
}
