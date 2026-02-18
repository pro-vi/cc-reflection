#!/usr/bin/env bash
# validators.sh - Input validation functions for cc-reflection

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cc-common.sh"

# ============================================================================
# MENU FILTER VALIDATION
# ============================================================================

# NOTE: VALID_MENU_FILTERS array is defined in cc-common.sh (sourced above)
# SYNC: Must match MENU_FILTERS constant in lib/reflection-state.ts:42

# Validate menu filter value
# WHY: Centralized validation prevents missing values (e.g., 'outdated' bug)
# RETURNS: 0 if valid, 1 if invalid
# TESTED BY: tests/unit/test_validators.bats::validate menu filter
#
# Usage: if validate_menu_filter "$filter"; then ...; fi
validate_menu_filter() {
    local filter="$1"

    # Uses _cc_is_valid_menu_filter from cc-common.sh for actual validation
    if _cc_is_valid_menu_filter "$filter"; then
        cc_log_debug "Valid menu filter: $filter"
        return 0
    fi

    cc_log_error "Invalid menu filter: $filter (expected: ${VALID_MENU_FILTERS[*]})"
    echo "Error: Invalid menu filter: $filter" >&2
    echo "Valid filters: ${VALID_MENU_FILTERS[*]}" >&2
    return 1
}

# ============================================================================
# SEED ID VALIDATION
# ============================================================================

# Validate seed ID format
# WHY: Prevent malformed seed IDs from causing cryptic errors
# ASSUMPTION: Seed IDs follow format: seed-TIMESTAMP-RANDOM
# TESTED BY: tests/test_param_validation.bats::validate correct seed ID format
#
# Usage: if validate_seed_id "$SEED_ID"; then ...; fi
validate_seed_id() {
    local seed_id="$1"

    # Expected format: seed-<digits>-<alphanumeric>
    # Example: seed-1699123456-a1b2c3d
    if [[ "$seed_id" =~ ^seed-[0-9]+-[a-z0-9]+$ ]]; then
        cc_log_debug "Valid seed ID: $seed_id"
        return 0
    else
        cc_log_error "Invalid seed ID format: $seed_id (expected: seed-TIMESTAMP-RANDOM)"
        echo "Error: Invalid seed ID format: $seed_id" >&2
        echo "Expected format: seed-TIMESTAMP-RANDOM (e.g., seed-1699123456-a1b2c3d)" >&2
        return 1
    fi
}

# ============================================================================
# MODE VALIDATION
# ============================================================================

# Validate expansion mode
# WHY: Prevent invalid modes from being passed to cc-reflect-expand
# ASSUMPTION: Only two modes: interactive and auto
# TESTED BY: tests/test_param_validation.bats::validate modes
#
# Usage: if validate_mode "$MODE"; then ...; fi
validate_mode() {
    local mode="$1"

    case "$mode" in
    interactive | auto)
        cc_log_debug "Valid mode: $mode"
        return 0
        ;;
    *)
        cc_log_error "Invalid mode: $mode (expected: interactive or auto)"
        echo "Error: Invalid mode: $mode" >&2
        echo "Valid modes: interactive, auto" >&2
        return 1
        ;;
    esac
}

# ============================================================================
# FILE PATH VALIDATION
# ============================================================================

# Validate file exists and is readable
# WHY: Fail early if required files are missing
#
# Usage: if validate_file_exists "$filepath"; then ...; fi
validate_file_exists() {
    local filepath="$1"

    if [ -z "$filepath" ]; then
        cc_log_error "File path is empty"
        echo "Error: File path is empty" >&2
        return 1
    fi

    if [ ! -f "$filepath" ]; then
        cc_log_error "File not found: $filepath"
        echo "Error: File not found: $filepath" >&2
        return 1
    fi

    if [ ! -r "$filepath" ]; then
        cc_log_error "File not readable: $filepath"
        echo "Error: File not readable: $filepath" >&2
        return 1
    fi

    cc_log_debug "Valid file: $filepath"
    return 0
}

# ============================================================================
# SEED TITLE VALIDATION
# ============================================================================

# Validate seed title for shell injection safety
# WHY: Prevent shell injection attacks through malicious seed titles
# SECURITY: Seed titles are displayed in fzf menu and used in shell commands
# TESTED BY: tests/security/test_shell_injection.bats
#
# Rejects titles containing shell metacharacters that could be used for injection:
#   $ - Command substitution
#   ` - Command substitution (backticks)
#   ' - Single quote (breaks out of quoted strings)
#   " - Double quote (breaks out of quoted strings)
#   | - Pipe (could chain commands)
#   ; - Command separator
#   & - Background execution
#   \ - Escape character
#   < > - Redirection operators
#   ( ) - Subshell
#   { } - Command grouping
#
# Usage: if validate_seed_title "$title"; then ...; fi
validate_seed_title() {
    local title="$1"

    # Reject if empty
    if [ -z "$title" ]; then
        cc_log_error "Seed title cannot be empty"
        echo "Error: Seed title cannot be empty" >&2
        return 1
    fi

    # Reject titles with dangerous shell metacharacters and control characters
    # SYNC: Must match FORBIDDEN_CHARS in lib/reflection-state.ts
    # Pattern explanation:
    #   \$ - Dollar sign (command substitution)
    #   \` - Backtick (command substitution)
    #   \' - Single quote
    #   \" - Double quote
    #   \| - Pipe
    #   ; - Semicolon
    #   & - Ampersand
    #   \\ - Backslash
    #   < - Less than
    #   > - Greater than
    #   \( \) - Parentheses
    #   \{ \} - Braces
    #   Control chars (C0 range \x00-\x1f + DEL \x7f) - subsumes tab/newline/CR
    if [[ "$title" =~ [\$\`\'\"\|\;\&\\\<\>\(\)\{\}] ]] || [[ "$title" =~ [[:cntrl:]] ]]; then
        cc_log_error "Seed title contains forbidden characters: $title"
        echo "Error: Seed title contains forbidden characters" >&2
        echo "  Title: $title" >&2
        echo "  Forbidden: \$ \` ' \" | ; & \\ < > ( ) { } and control characters" >&2
        echo "  Reason: Shell injection prevention + menu safety" >&2
        return 1
    fi

    cc_log_debug "Valid seed title: $title"
    return 0
}
