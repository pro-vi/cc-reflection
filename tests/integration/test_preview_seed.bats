#!/usr/bin/env bats

# test_preview_seed.bats - Tests for bin/cc-reflect-preview-seed
#
# WHY: Validates context-aware preview pane generation for different menu items
# TESTS: Section headers, non-seed items, seed items, expansion history

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
}

teardown() {
    rm -rf "$TEST_BASE_DIR"
}

# ============================================================================
# SCRIPT EXISTENCE
# ============================================================================

@test "preview-seed: script exists and is executable" {
    assert_file_exists "$SCRIPT_DIR/cc-reflect-preview-seed"
    [ -x "$SCRIPT_DIR/cc-reflect-preview-seed" ]
}

# ============================================================================
# SECTION HEADER PREVIEW
# ============================================================================

@test "preview-seed: section header shows help text" {
    # Simulate a separator line (contains ══)
    run "$SCRIPT_DIR/cc-reflect-preview-seed" "══ Settings ══════════════════════════"
    assert_success
    # Should show general help
    assert_output --partial "吾日三省吾身"
}

@test "preview-seed: section header includes keybindings" {
    run "$SCRIPT_DIR/cc-reflect-preview-seed" "══ Seeds ═════════════════════════════"
    assert_success
    assert_output --partial "Ctrl-D"
    assert_output --partial "Ctrl-A"
}

# ============================================================================
# NON-SEED ITEM PREVIEWS
# ============================================================================

@test "preview-seed: editor item shows help" {
    run "$SCRIPT_DIR/cc-reflect-preview-seed" "Edit with Vim	vi /tmp/test.txt"
    assert_success
    assert_output --partial "Open"
}

@test "preview-seed: mode toggle shows explanation" {
    run "$SCRIPT_DIR/cc-reflect-preview-seed" "🔄 Mode: Interactive (→ Auto)	cc-reflect-toggle-mode"
    assert_success
    assert_output --partial "Interactive"
    assert_output --partial "Auto"
}

@test "preview-seed: permissions toggle shows explanation" {
    run "$SCRIPT_DIR/cc-reflect-preview-seed" "🔓 Skip permissions: On (→ Off)	cc-reflect-toggle-permissions"
    assert_success
    assert_output --partial "permission"
}

@test "preview-seed: model toggle shows explanation" {
    run "$SCRIPT_DIR/cc-reflect-preview-seed" "🤖 Model: Opus (→ Sonnet)	cc-reflect-toggle-model"
    assert_success
    assert_output --partial "Opus"
    assert_output --partial "Sonnet"
    assert_output --partial "Haiku"
}

@test "preview-seed: filter toggle shows filter options" {
    run "$SCRIPT_DIR/cc-reflect-preview-seed" "🔍 Filter: Active 🌱💭 (→ Outdated)	cc-reflect-toggle-filter"
    assert_success
    assert_output --partial "Active"
    assert_output --partial "Outdated"
    assert_output --partial "Archived"
}

@test "preview-seed: archive action shows explanation" {
    run "$SCRIPT_DIR/cc-reflect-preview-seed" "📦 Archive Outdated Seeds	cc-reflect-archive-outdated"
    assert_success
    assert_output --partial "Archive"
    assert_output --partial "OUTDATED"
}

@test "preview-seed: enhance prompt shows explanation" {
    run "$SCRIPT_DIR/cc-reflect-preview-seed" "Enhance Prompt (Interactive)	claude-spawn-interactive"
    assert_success
    assert_output --partial "prompt"
}

# ============================================================================
# SEED ITEM PREVIEWS
# ============================================================================

@test "preview-seed: seed item shows title and rationale" {
    # Create a test seed
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" write \
        "Preview test seed" \
        "This is the rationale for the seed" \
        "test.ts" \
        "start" \
        "end" \
        "$TEST_BASE_DIR"
    assert_success

    # Extract seed ID from output
    seed_id=$(echo "$output" | grep '"id":' | sed 's/.*"id": "\([^"]*\)".*/\1/')

    # Create menu line format
    menu_line="🌱 Preview test seed	cc-reflect-expand interactive $seed_id"

    run "$SCRIPT_DIR/cc-reflect-preview-seed" "$menu_line"
    assert_success
    assert_output --partial "Preview test seed"
    assert_output --partial "rationale"
}

@test "preview-seed: seed item shows created timestamp" {
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" write \
        "Timestamp test seed" \
        "Rationale" \
        "test.ts" \
        "start" \
        "end" \
        "$TEST_BASE_DIR"
    assert_success

    seed_id=$(echo "$output" | grep '"id":' | sed 's/.*"id": "\([^"]*\)".*/\1/')
    menu_line="🌱 Timestamp test seed	cc-reflect-expand interactive $seed_id"

    run "$SCRIPT_DIR/cc-reflect-preview-seed" "$menu_line"
    assert_success
    assert_output --partial "Created:"
}

@test "preview-seed: seed item shows seed ID" {
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" write \
        "ID display test" \
        "Rationale" \
        "test.ts" \
        "start" \
        "end" \
        "$TEST_BASE_DIR"
    assert_success

    seed_id=$(echo "$output" | grep '"id":' | sed 's/.*"id": "\([^"]*\)".*/\1/')
    menu_line="🌱 ID display test	cc-reflect-expand interactive $seed_id"

    run "$SCRIPT_DIR/cc-reflect-preview-seed" "$menu_line"
    assert_success
    assert_output --partial "$seed_id"
}

# ============================================================================
# EDGE CASES
# ============================================================================

@test "preview-seed: handles empty input gracefully" {
    run "$SCRIPT_DIR/cc-reflect-preview-seed" ""
    # Should not crash - may show default help or nothing
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "preview-seed: handles unknown menu item gracefully" {
    run "$SCRIPT_DIR/cc-reflect-preview-seed" "Unknown Item	unknown-command"
    # Should not crash
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}
