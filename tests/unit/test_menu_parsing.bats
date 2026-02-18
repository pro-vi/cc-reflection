#!/usr/bin/env bats

# test_menu_parsing.bats - Test menu command extraction
#
# WHY: Menu format uses TAB separator (invisible in display)
# HISTORY: Changed from : to | to handle colons, then to TAB for cleaner UI
# CRITICAL: Menu parsing must handle edge cases robustly

load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load

setup() {
    export REFLECTION_BASE="$(mktemp -d)"
    source "$BATS_TEST_DIRNAME/../../lib/cc-common.sh"
}

teardown() {
    rm -rf "$REFLECTION_BASE"
}

# Helper to create tab-separated menu entries
menu_entry() {
    printf '%s\t%s' "$1" "$2"
}

# ============================================================================
# BASIC MENU PARSING
# ============================================================================

@test "cc_parse_menu_command extracts command after tab" {
    run cc_parse_menu_command "$(menu_entry "Edit with Emacs" "emacs -nw file.txt")"
    assert_success
    assert_output "emacs -nw file.txt"
}

@test "cc_parse_menu_command extracts simple command" {
    run cc_parse_menu_command "$(menu_entry "Label" "echo hello")"
    assert_success
    assert_output "echo hello"
}

@test "cc_parse_menu_command handles command with arguments" {
    run cc_parse_menu_command "$(menu_entry "Run Test" "bun test --watch --verbose")"
    assert_success
    assert_output "bun test --watch --verbose"
}

# ============================================================================
# EDGE CASES - TITLES WITH SPECIAL CHARACTERS
# ============================================================================

@test "cc_parse_menu_command handles title with colon" {
    run cc_parse_menu_command "$(menu_entry "Status: Running" "systemctl status")"
    assert_success
    assert_output "systemctl status"
}

@test "cc_parse_menu_command handles multiple colons in title" {
    run cc_parse_menu_command "$(menu_entry "[REFLECT-SEC] Test: Unvalidated input: req.body (Auto)" "cc-reflect-expand auto seed-123")"
    assert_success
    assert_output "cc-reflect-expand auto seed-123"
}

@test "cc_parse_menu_command handles title with time format" {
    run cc_parse_menu_command "$(menu_entry "Scheduled: 14:30:00" "run-job")"
    assert_success
    assert_output "run-job"
}

@test "cc_parse_menu_command handles URL in title" {
    run cc_parse_menu_command "$(menu_entry "Open https://example.com:8080" "open-url")"
    assert_success
    assert_output "open-url"
}

# ============================================================================
# WHITESPACE HANDLING
# ============================================================================

@test "cc_parse_menu_command trims leading whitespace from command" {
    run cc_parse_menu_command "$(printf 'Label\t  command')"
    assert_success
    assert_output "command"
}

@test "cc_parse_menu_command trims trailing whitespace from command" {
    run cc_parse_menu_command "$(printf 'Label\tcommand  ')"
    assert_success
    assert_output "command"
}

@test "cc_parse_menu_command trims both leading and trailing whitespace" {
    run cc_parse_menu_command "$(printf 'Label\t  command with spaces  ')"
    assert_success
    assert_output "command with spaces"
}

@test "cc_parse_menu_command preserves internal spaces in command" {
    run cc_parse_menu_command "$(menu_entry "Label" "echo hello world")"
    assert_success
    assert_output "echo hello world"
}

# ============================================================================
# SPECIAL CHARACTERS
# ============================================================================

@test "cc_parse_menu_command handles pipe in command" {
    # TAB delimiter allows pipes in commands
    run cc_parse_menu_command "$(menu_entry "Filter" "grep 'error' | wc -l")"
    assert_success
    assert_output "grep 'error' | wc -l"
}

@test "cc_parse_menu_command handles quotes in command" {
    run cc_parse_menu_command "$(menu_entry "Print" 'echo "hello world"')"
    assert_success
    assert_output 'echo "hello world"'
}

@test "cc_parse_menu_command handles single quotes in command" {
    run cc_parse_menu_command "$(menu_entry "Run" "echo 'test message'")"
    assert_success
    assert_output "echo 'test message'"
}

@test "cc_parse_menu_command handles special shell characters" {
    run cc_parse_menu_command "$(menu_entry "Complex" "cmd && other-cmd")"
    assert_success
    assert_output "cmd && other-cmd"
}

# ============================================================================
# REAL-WORLD EXAMPLES FROM CC-REFLECT
# ============================================================================

@test "cc_parse_menu_command handles reflection seed entry" {
    run cc_parse_menu_command "$(menu_entry "🌱 Unvalidated payment input" "cc-reflect-expand interactive seed-1699123456-abc123")"
    assert_success
    assert_output "cc-reflect-expand interactive seed-1699123456-abc123"
}

@test "cc_parse_menu_command handles enhancement option" {
    run cc_parse_menu_command "$(menu_entry "Enhance Prompt (Auto)" "claude-enhance-auto")"
    assert_success
    assert_output "claude-enhance-auto"
}

@test "cc_parse_menu_command handles separator line" {
    run cc_parse_menu_command "$(menu_entry "══ Settings ════════════════════════════" "echo")"
    assert_success
    assert_output "echo"
}

@test "cc_parse_menu_command handles editor entry" {
    run cc_parse_menu_command "$(menu_entry "Edit with Vi" 'vi "/tmp/prompt.md"')"
    assert_success
    assert_output 'vi "/tmp/prompt.md"'
}

# ============================================================================
# ERROR CASES
# ============================================================================

@test "cc_parse_menu_command fails on empty choice" {
    run cc_parse_menu_command ""
    assert_failure
}

@test "cc_parse_menu_command handles choice with no tab (takes whole string)" {
    # If there's no tab, the whole string becomes the command
    # This is graceful degradation
    run cc_parse_menu_command "no-separator-here"
    assert_success
    assert_output "no-separator-here"
}

@test "cc_parse_menu_command fails when command part is empty" {
    run cc_parse_menu_command "$(printf 'Label\t')"
    assert_failure
}

@test "cc_parse_menu_command fails when command part is only whitespace" {
    run cc_parse_menu_command "$(printf 'Label\t   ')"
    assert_failure
}

# ============================================================================
# UNICODE AND EMOJI HANDLING
# ============================================================================

@test "cc_parse_menu_command handles emoji in title" {
    run cc_parse_menu_command "$(menu_entry "🌱 High Priority" "run-task")"
    assert_success
    assert_output "run-task"
}

@test "cc_parse_menu_command handles unicode characters" {
    run cc_parse_menu_command "$(menu_entry "日本語 Label" "command")"
    assert_success
    assert_output "command"
}

# ============================================================================
# COMPARISON WITH OLD SEPARATORS (DEMONSTRATING IMPROVEMENTS)
# ============================================================================

@test "demonstrate why tab separator is better than colon or pipe" {
    # TAB separator handles everything cleanly:
    # - Colons in titles (e.g., "Test: Input validation")
    # - Pipes in commands (e.g., "grep | wc -l")
    # - Invisible in UI (cleaner display)

    complex_entry=$(menu_entry "[REFLECT-SEC] Test: Input validation (Auto)" "grep error | wc -l")
    run cc_parse_menu_command "$complex_entry"
    assert_success
    assert_output "grep error | wc -l"
}
