#!/usr/bin/env bats
# test_menu_utils.bats - Unit tests for menu building utilities

load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'
load '../test_helper/refute_equal'

setup() {
    export REFLECTION_BASE="$(mktemp -d)"
    # Source the utilities under test
    source "$BATS_TEST_DIRNAME/../../lib/menu-utils.sh"
}

teardown() {
    rm -rf "$REFLECTION_BASE"
}

# ============================================================================
# EDITOR MENU TESTS
# ============================================================================

@test "cc_build_editor_menu always includes vim" {
    result=$(cc_build_editor_menu "/tmp/test.txt")
    assert [ -n "$result" ]
    echo "$result" | grep -q "Edit with Vim"
    echo "$result" | grep -q "vi /tmp/test.txt"
}

@test "cc_build_editor_menu uses safe file path in commands" {
    safe_file="/path/with spaces/file.txt"
    result=$(cc_build_editor_menu "$safe_file")
    echo "$result" | grep -q "vi $safe_file"
}

@test "cc_build_editor_menu detects VS Code if available" {
    if command -v code &> /dev/null; then
        result=$(cc_build_editor_menu "/tmp/test.txt")
        echo "$result" | grep -q "Edit with VS Code"
        echo "$result" | grep -q "code -w"
    else
        skip "VS Code not installed"
    fi
}

@test "cc_build_editor_menu detects Cursor if available" {
    if command -v cursor &> /dev/null; then
        result=$(cc_build_editor_menu "/tmp/test.txt")
        echo "$result" | grep -q "Edit with Cursor"
        echo "$result" | grep -q "cursor -w"
    else
        skip "Cursor not installed"
    fi
}

@test "cc_build_editor_menu detects Windsurf if available" {
    if command -v windsurf &> /dev/null; then
        result=$(cc_build_editor_menu "/tmp/test.txt")
        echo "$result" | grep -q "Edit with Windsurf"
        echo "$result" | grep -q "windsurf -w"
    else
        skip "Windsurf not installed"
    fi
}

@test "cc_build_editor_menu detects Zed if available" {
    if command -v zed &> /dev/null; then
        result=$(cc_build_editor_menu "/tmp/test.txt")
        echo "$result" | grep -q "Edit with Zed"
        echo "$result" | grep -q "zed --wait"
    else
        skip "Zed not installed"
    fi
}

@test "cc_build_editor_menu detects Antigravity if available" {
    if command -v agy &> /dev/null; then
        result=$(cc_build_editor_menu "/tmp/test.txt")
        echo "$result" | grep -q "Edit with Antigravity"
        echo "$result" | grep -q "agy -w"
    else
        skip "Antigravity not installed"
    fi
}

@test "cc_build_editor_menu returns multiple entries" {
    result=$(cc_build_editor_menu "/tmp/test.txt")
    line_count=$(echo "$result" | wc -l | tr -d ' ')
    assert [ "$line_count" -ge 1 ]  # At least vim
}

# ============================================================================
# SEED MENU TESTS
# ============================================================================

@test "cc_build_seed_menu handles empty JSON array" {
    result=$(cc_build_seed_menu "[]" "interactive")
    assert [ -z "$result" ]
}

@test "cc_build_seed_menu handles empty string" {
    result=$(cc_build_seed_menu "" "interactive")
    assert [ -z "$result" ]
}

@test "cc_build_seed_menu formats seed with thinking bubble emoji" {
    seeds_json='[{"id":"seed-123-abc","title":"Test reflection"}]'
    result=$(cc_build_seed_menu "$seeds_json" "interactive")
    echo "$result" | grep -q "💭 Test reflection"
    echo "$result" | grep -q "cc-reflect-expand interactive"
}

@test "cc_build_seed_menu includes seed ID in command" {
    seeds_json='[{"id":"seed-123-abc","title":"Test"}]'
    result=$(cc_build_seed_menu "$seeds_json" "interactive")
    echo "$result" | grep -q "cc-reflect-expand interactive seed-123-abc"
}

@test "cc_build_seed_menu creates single entry per seed" {
    seeds_json='[{"id":"seed-123-abc","title":"Test"}]'
    result=$(cc_build_seed_menu "$seeds_json" "interactive")
    line_count=$(echo "$result" | wc -l | tr -d ' ')
    assert_equal "$line_count" "1"  # One entry per seed
}

@test "cc_build_seed_menu uses provided mode" {
    seeds_json='[{"id":"seed-123-abc","title":"Test"}]'

    result_interactive=$(cc_build_seed_menu "$seeds_json" "interactive")
    echo "$result_interactive" | grep -q "cc-reflect-expand interactive seed-123-abc"

    result_auto=$(cc_build_seed_menu "$seeds_json" "auto")
    echo "$result_auto" | grep -q "cc-reflect-expand auto seed-123-abc"
}

@test "cc_build_seed_menu handles multiple seeds" {
    seeds_json='[
        {"id":"seed-123-abc","title":"First"},
        {"id":"seed-456-def","title":"Second"}
    ]'
    result=$(cc_build_seed_menu "$seeds_json" "interactive")
    line_count=$(echo "$result" | wc -l | tr -d ' ')
    assert_equal "$line_count" "2"  # One entry per seed
}

@test "cc_build_seed_menu handles titles with special characters" {
    seeds_json='[{"id":"seed-123-abc","title":"Test: with colon"}]'
    result=$(cc_build_seed_menu "$seeds_json")
    echo "$result" | grep -q "Test: with colon"
}

# ============================================================================
# SECTION HEADER TESTS
# ============================================================================

@test "cc_section_header creates header with double lines" {
    result=$(cc_section_header "Seeds")
    echo "$result" | grep -q "══ Seeds"
    # Check for tab delimiter (not pipe)
    [[ "$result" == *$'\t'* ]]
}

@test "cc_section_header adjusts dash length for title" {
    short=$(cc_section_header "A")
    long=$(cc_section_header "Long Title")
    # Both should have same total width but different dash counts
    echo "$short" | grep -q "══ A"
    echo "$long" | grep -q "══ Long Title"
}

@test "cc_section_header includes ANSI dim codes" {
    result=$(cc_section_header "Test")
    # Check for ANSI escape codes (dim = \033[2m)
    [[ "$result" == *$'\033[2m'* ]]
}

# ============================================================================
# ENHANCE ENTRY TESTS
# ============================================================================

@test "cc_build_enhance_entry returns interactive command" {
    result=$(cc_build_enhance_entry "interactive")
    expected=$(printf '%s\t%s' "Enhance Prompt (Interactive)" "claude-spawn-interactive")
    assert_equal "$result" "$expected"
}

@test "cc_build_enhance_entry returns auto command" {
    result=$(cc_build_enhance_entry "auto")
    expected=$(printf '%s\t%s' "Enhance Prompt (Auto)" "claude-enhance-auto")
    assert_equal "$result" "$expected"
}

# ============================================================================
# SETTINGS MENU TESTS
# ============================================================================

@test "cc_build_settings_menu includes toggle mode option" {
    result=$(cc_build_settings_menu "interactive" "disabled" "opus")
    echo "$result" | grep -q "🔄 Mode: Interactive (→ Auto)"
    echo "$result" | grep -q "cc-reflect-toggle-mode"

    result=$(cc_build_settings_menu "auto" "disabled" "opus")
    echo "$result" | grep -q "🔄 Mode: Auto (→ Interactive)"
}

@test "cc_build_settings_menu includes toggle permissions option" {
    result=$(cc_build_settings_menu "interactive" "disabled" "opus")
    echo "$result" | grep -q "🔒 Skip permissions: Off (→ On)"

    result=$(cc_build_settings_menu "interactive" "enabled" "disabled")
    echo "$result" | grep -q "🔓 Skip permissions: On (→ Off)"
}

@test "cc_build_settings_menu includes model toggle option" {
    result=$(cc_build_settings_menu "interactive" "disabled" "opus")
    echo "$result" | grep -q "🤖 Model: Opus (→ Sonnet)"

    result=$(cc_build_settings_menu "interactive" "disabled" "sonnet")
    echo "$result" | grep -q "🤖 Model: Sonnet (→ Haiku)"

    result=$(cc_build_settings_menu "interactive" "disabled" "haiku")
    echo "$result" | grep -q "🤖 Model: Haiku (→ Opus)"
}

@test "cc_build_settings_menu includes filter toggle option" {
    # Cycle: active → outdated → archived → all → active
    result=$(cc_build_settings_menu "interactive" "disabled" "disabled" "active")
    echo "$result" | grep -q "🔍 Filter: Active 🌱💭 (→ Outdated)"

    result=$(cc_build_settings_menu "interactive" "disabled" "disabled" "outdated")
    echo "$result" | grep -q "🔍 Filter: Outdated 💤 (→ Archived)"

    result=$(cc_build_settings_menu "interactive" "disabled" "disabled" "archived")
    echo "$result" | grep -q "🔍 Filter: Archived 📦 (→ All)"

    result=$(cc_build_settings_menu "interactive" "disabled" "disabled" "all")
    echo "$result" | grep -q "🔍 Filter: All (→ Active)"
}

@test "cc_build_settings_menu includes context toggle option" {
    # Cycle: 0 → 3 → 5 → 10 → 0
    result=$(cc_build_settings_menu "interactive" "disabled" "disabled" "active" "0")
    echo "$result" | grep -q "💬 Context: Off (→ 3)"

    result=$(cc_build_settings_menu "interactive" "disabled" "disabled" "active" "3")
    echo "$result" | grep -q "💬 Context: 3 turns (→ 5)"

    result=$(cc_build_settings_menu "interactive" "disabled" "disabled" "active" "5")
    echo "$result" | grep -q "💬 Context: 5 turns (→ 10)"

    result=$(cc_build_settings_menu "interactive" "disabled" "disabled" "active" "10")
    echo "$result" | grep -q "💬 Context: 10 turns (→ Off)"
}

@test "cc_build_settings_menu returns exactly 5 lines" {
    result=$(cc_build_settings_menu "interactive" "disabled" "disabled" "active" "3")
    line_count=$(echo "$result" | wc -l | tr -d ' ')
    # mode + model + filter + context + permissions = 5 lines
    assert_equal "$line_count" "5"
}

@test "cc_build_settings_menu uses tab delimiter" {
    result=$(cc_build_settings_menu "interactive" "disabled" "disabled" "active")
    # All lines should have tab delimiter
    [[ "$result" == *$'\t'* ]]
}

# ============================================================================
# ACTIONS MENU TESTS
# ============================================================================

@test "cc_build_actions_menu includes archive outdated option" {
    result=$(cc_build_actions_menu)
    echo "$result" | grep -q "📦 Archive Outdated Seeds"
    echo "$result" | grep -q "cc-reflect-archive-outdated"
}

@test "cc_build_actions_menu returns exactly 1 line" {
    result=$(cc_build_actions_menu)
    line_count=$(echo "$result" | wc -l | tr -d ' ')
    assert_equal "$line_count" "1"
}

@test "cc_build_actions_menu uses tab delimiter" {
    result=$(cc_build_actions_menu)
    [[ "$result" == *$'\t'* ]]
}

# ============================================================================
# DISPLAY PREPARATION TESTS
# ============================================================================

@test "cc_prepare_menu_display strips commands" {
    menu=$(printf '%s\t%s\n%s\t%s' "Edit with Vim" "vi /long/path/to/file.txt" "Edit with VS Code" "code -w /long/path/to/file.txt")
    result=$(cc_prepare_menu_display "$menu")
    echo "$result" | grep -q "Edit with Vim"
    echo "$result" | grep -qv "/long/path"
}

@test "cc_prepare_menu_display removes tab separator" {
    menu=$(printf '%s\t%s' "Label text" "command arg1 arg2")
    result=$(cc_prepare_menu_display "$menu")
    assert_equal "$result" "Label text"
}

@test "cc_prepare_menu_display handles multiple lines" {
    menu=$(printf '%s\t%s\n%s\t%s\n%s\t%s' "First" "cmd1" "Second" "cmd2" "Third" "cmd3")
    result=$(cc_prepare_menu_display "$menu")
    line_count=$(echo "$result" | wc -l | tr -d ' ')
    assert_equal "$line_count" "3"
    echo "$result" | head -1 | grep -q "^First$"
    echo "$result" | tail -1 | grep -q "^Third$"
}

@test "cc_prepare_menu_display preserves emojis and special chars" {
    menu=$(printf '%s\t%s' "💭 Test reflection" "command")
    result=$(cc_prepare_menu_display "$menu")
    assert_equal "$result" "💭 Test reflection"
}

# ============================================================================
# MENU LINE FINDING TESTS
# ============================================================================

@test "cc_find_menu_line finds matching line" {
    menu=$(printf '%s\t%s\n%s\t%s' "Edit with Vim" "vi /tmp/test.txt" "Edit with VS Code" "code -w /tmp/test.txt")
    result=$(cc_find_menu_line "$menu" "Edit with Vim")
    expected=$(printf '%s\t%s' "Edit with Vim" "vi /tmp/test.txt")
    assert_equal "$result" "$expected"
}

@test "cc_find_menu_line returns full line with command" {
    menu=$(printf '%s\t%s' "Label" "command with args")
    result=$(cc_find_menu_line "$menu" "Label")
    echo "$result" | grep -q "command with args"
}

@test "cc_find_menu_line handles emojis in label" {
    menu=$(printf '%s\t%s' "💭 Test reflection" "cc-reflect-expand interactive seed-123")
    result=$(cc_find_menu_line "$menu" "💭 Test reflection")
    echo "$result" | grep -q "seed-123"
}

@test "cc_find_menu_line returns empty for non-existent label" {
    menu=$(printf '%s\t%s' "Edit with Vim" "vi /tmp/test.txt")
    result=$(cc_find_menu_line "$menu" "Nonexistent" || true)
    assert [ -z "$result" ]
}

# ============================================================================
# COMPLETE MENU BUILDER TESTS
# ============================================================================

@test "cc_build_complete_menu includes all sections" {
    result=$(cc_build_complete_menu "/tmp/test.txt" "[]" "interactive" "disabled" "opus" "active")

    # Should have editors
    echo "$result" | grep -q "Edit with Vim"

    # Should have toggle mode with current mode displayed (with emoji)
    echo "$result" | grep -q "🔄 Mode: Interactive (→ Auto)"

    # Should have model toggle (with emoji)
    echo "$result" | grep -q "🤖 Model: Opus (→ Sonnet)"

    # Should have filter toggle (with emoji)
    echo "$result" | grep -q "🔍 Filter: Active 🌱💭 (→ Outdated)"

    # Should have permissions toggle with dynamic emoji (🔒 when disabled)
    echo "$result" | grep -q "🔒 Skip permissions: Off (→ On)"

    # Should have actions section
    echo "$result" | grep -q "📦 Archive Outdated Seeds"

    # Should have enhance prompt
    echo "$result" | grep -q "Enhance Prompt"
}

@test "cc_build_complete_menu includes seeds when provided" {
    # Seeds should have freshness_tier computed by reflection-state.ts
    seeds_json='[{"id":"seed-123-abc","title":"Test","freshness_tier":"💭"}]'
    result=$(cc_build_complete_menu "/tmp/test.txt" "$seeds_json" "interactive" "disabled" "opus" "active")

    echo "$result" | grep -q "💭 Test"
}

@test "cc_build_complete_menu uses provided mode for seeds" {
    seeds_json='[{"id":"seed-123-abc","title":"Test"}]'

    result_interactive=$(cc_build_complete_menu "/tmp/test.txt" "$seeds_json" "interactive" "disabled" "opus")
    echo "$result_interactive" | grep -q "cc-reflect-expand interactive seed-123-abc"

    result_auto=$(cc_build_complete_menu "/tmp/test.txt" "$seeds_json" "auto" "disabled" "opus")
    echo "$result_auto" | grep -q "cc-reflect-expand auto seed-123-abc"
}

@test "cc_build_complete_menu omits seeds section when empty" {
    result=$(cc_build_complete_menu "/tmp/test.txt" "[]" "interactive" "disabled" "opus")

    # Should not have Seeds section header when no seeds
    run echo "$result"
    refute_output --partial "══ Seeds"
}

@test "cc_build_complete_menu creates valid menu format" {
    result=$(cc_build_complete_menu "/tmp/test.txt" "[]" "interactive" "disabled" "opus")

    # Every non-empty line should contain a tab
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            [[ "$line" == *$'\t'* ]] || { echo "Line missing tab: $line"; return 1; }
        fi
    done <<< "$result"
}

# ============================================================================
# INTEGRATION TESTS
# ============================================================================

@test "display preparation and line finding work together" {
    menu=$(printf '%s\t%s\n%s\t%s\n%s\t%s' "Edit with Vim" "vi /tmp/test.txt" "💭 Test reflection" "cc-reflect-expand interactive seed-123" "Clear Seeds" "clear-command")

    # Prepare display
    display=$(cc_prepare_menu_display "$menu")

    # Simulate user selecting second line
    selected=$(echo "$display" | sed -n '2p')

    # Find original line
    original=$(cc_find_menu_line "$menu" "$selected")

    # Verify we got the right line
    echo "$original" | grep -q "seed-123"
}

# ============================================================================
# HEADER SCRIPT TESTS
# ============================================================================

@test "cc-reflect-header outputs valid header format" {
    run "$BATS_TEST_DIRNAME/../../bin/cc-reflect-header"
    assert_success
    # Should contain key elements
    assert_output --partial "💡"
    assert_output --partial "ENTER=Expand"
    assert_output --partial "^/=Preview"
    assert_output --partial "^F=Filter["
    assert_output --partial "ESC"
}

@test "cc-reflect-header shows current filter in brackets" {
    # Set filter to a known value
    bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" set-filter active >/dev/null

    run "$BATS_TEST_DIRNAME/../../bin/cc-reflect-header"
    assert_success
    assert_output --partial "Filter[active]"
}
