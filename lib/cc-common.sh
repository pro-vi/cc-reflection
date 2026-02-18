#!/usr/bin/env bash
# cc-common.sh - Shared utilities for cc-reflection scripts

# Determine lib directory for this file
# WHY: Make cc-common.sh self-sufficient for finding reflection-state.ts
CC_LIB_DIR="${CC_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Base directory for reflection state (kept in sync with bin/cc-reflect scripts)
REFLECTION_BASE="${REFLECTION_BASE:-${HOME}/.claude/reflections}"

# ============================================================================
# LOGGING
# ============================================================================

# Log file location (centralized, not /tmp)
CC_LOG_DIR="${CC_LOG_DIR:-$REFLECTION_BASE/logs}"
mkdir -p "$CC_LOG_DIR" 2>/dev/null || true

CC_LOG_FILE="$CC_LOG_DIR/cc-reflection.log"

# Usage: cc_log INFO "message"
cc_log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local caller="${BASH_SOURCE[2]##*/}:${BASH_LINENO[1]}"

    # Logging must never pollute stdout/stderr on failure (e.g., unwritable HOME).
    if [ ! -d "$CC_LOG_DIR" ]; then
        mkdir -p "$CC_LOG_DIR" 2>/dev/null || return 0
    fi
    if [ ! -w "$CC_LOG_DIR" ]; then
        return 0
    fi

    {
        printf '[%s] [%s] [%s] %s\n' "$timestamp" "$level" "$caller" "$msg"
    } >>"$CC_LOG_FILE" 2>/dev/null || true
}

cc_log_info() { cc_log INFO "$@"; }
cc_log_warn() { cc_log WARN "$@"; }
cc_log_error() { cc_log ERROR "$@"; }
cc_log_debug() { cc_log DEBUG "$@"; }

# ============================================================================
# FRESHNESS TIER PATTERN
# ============================================================================
# Regex pattern for detecting seed menu lines by their freshness tier emoji
# SYNC: Must match FreshnessTier type in lib/reflection-state.ts:31
# Used by: cc-reflect-delete-seed, cc-reflect-archive-seed, cc-reflect-preview-seed
CC_SEED_EMOJI_PATTERN='^(🌱|💭|💤|📦)'

# ============================================================================
# NERD FONT DETECTION
# ============================================================================

# Check if Nerd Fonts are available
# WHY: Nerd Fonts provide beautiful editor-specific icons
# RETURNS: 0 if Nerd Fonts available, 1 otherwise
# CACHE: Result cached in CC_HAS_NERD_FONTS variable
cc_has_nerd_fonts() {
    # Return cached result if available
    if [ -n "$CC_HAS_NERD_FONTS" ]; then
        [ "$CC_HAS_NERD_FONTS" = "1" ] && return 0 || return 1
    fi

    # Check for Nerd Fonts using fc-list
    if command -v fc-list &>/dev/null; then
        if fc-list 2>/dev/null | grep -qi "nerd"; then
            CC_HAS_NERD_FONTS="1"
            return 0
        fi
    fi

    CC_HAS_NERD_FONTS="0"
    return 1
}

# Get editor icon based on Nerd Font availability
# ARGS: editor_name - "vim", "vscode", "cursor", "windsurf", "zed", "antigravity"
# RETURNS: Nerd Font icon if available, empty string otherwise
#
# NOTE: Uses \xNN hex escapes for bash 3.x compatibility (macOS default)
# The \uXXXX syntax requires bash 4.2+
cc_get_editor_icon() {
    local editor="$1"

    if ! cc_has_nerd_fonts; then
        echo ""
        return
    fi

    # UTF-8 hex encoding for Nerd Font icons (bash 3.x compatible)
    # U+E62B (Vim)    = \xee\x98\xab
    # U+E8DA (VSCode) = \xee\xa3\x9a
    case "$editor" in
    vim | vi)
        printf '\xee\x98\xab' # Vim icon (U+E62B)
        ;;
    vscode | code)
        printf '\xee\xa3\x9a' # VS Code icon (U+E8DA)
        ;;
    cursor)
        printf '\xee\xa3\x9a' # Use VS Code icon as fallback
        ;;
    windsurf)
        printf '\xee\xa3\x9a' # Use VS Code icon as fallback
        ;;
    zed)
        printf '\xee\xa3\x9a' # Use VS Code icon as fallback
        ;;
    antigravity | agy)
        printf '\xee\xa3\x9a' # Use VS Code icon as fallback
        ;;
    *)
        echo ""
        ;;
    esac
}

# ============================================================================
# SESSION ID
# ============================================================================

# Get project hash (12-char MD5 of directory path)
# Used for locating Claude Code session UUID and as fallback session ID
cc_get_project_hash() {
    if command -v md5sum &>/dev/null; then
        echo -n "$(pwd)" | md5sum | cut -d' ' -f1 | head -c 12
    elif command -v md5 &>/dev/null; then
        echo -n "$(pwd)" | md5 | cut -d' ' -f1 | head -c 12
    else
        echo ""
    fi
}

# Get Claude Code session UUID if available
# SYNC: Must match getClaudeSessionId() in lib/session-id.ts
# Resolution order:
# 1. CC_DICE_SESSION_ID env var (set by cc-dice SessionStart hook)
# 2. CC_REFLECTION_SESSION_ID env var (set by cc-reflection SessionStart hook)
# 3. File-based lookup (legacy)
# RETURNS: UUID string or empty if not available
cc_get_claude_session_id() {
    # Primary: env var set by cc-dice's SessionStart hook
    if [ -n "${CC_DICE_SESSION_ID:-}" ]; then
        echo "$CC_DICE_SESSION_ID"
        return 0
    fi

    # Backward compat: cc-reflection's SessionStart hook
    if [ -n "${CC_REFLECTION_SESSION_ID:-}" ]; then
        echo "$CC_REFLECTION_SESSION_ID"
        return 0
    fi

    # Fallback: file-based (legacy)
    local project_hash
    project_hash=$(cc_get_project_hash)
    if [ -z "$project_hash" ]; then
        echo ""
        return 1
    fi

    local session_file="${REFLECTION_BASE}/sessions/${project_hash}/current"
    if [ -f "$session_file" ]; then
        cat "$session_file" | tr -d '\n'
    else
        echo ""
    fi
}

# Get consistent session ID (matches TypeScript logic in lib/session-id.ts)
# WHY: Session ID must be identical between bash and TypeScript for seed storage
#
# PRIORITY:
# 1. CLAUDE_SESSION_ID environment variable (explicit override)
# 2. Claude Code session UUID (from hook - unique per conversation)
# 3. Project hash (fallback - 12-char MD5 of directory)
#
# TESTED BY: tests/test_session_id.bats::bash and TypeScript produce identical session IDs
#
# Usage: session_id=$(cc_get_session_id)
cc_get_session_id() {
    local id=""

    # 1. Prefer environment variable (explicit override)
    if [ -n "${CLAUDE_SESSION_ID:-}" ]; then
        id="$CLAUDE_SESSION_ID"
    fi

    # 2. Try Claude Code session UUID (from hook)
    # WHY: Unique per Claude Code conversation, enables proper freshness tracking
    if [ -z "$id" ]; then
        local claude_id
        claude_id=$(cc_get_claude_session_id)
        if [ -n "$claude_id" ]; then
            id="$claude_id"
        fi
    fi

    # 3. Fallback to project hash
    # WHY: Backward compatibility when running outside Claude Code or before first prompt
    if [ -z "$id" ]; then
        local project_hash
        project_hash=$(cc_get_project_hash)
        if [ -n "$project_hash" ]; then
            id="$project_hash"
        fi
    fi

    # 4. Last resort
    if [ -z "$id" ]; then
        cc_log_error "Neither md5sum nor md5 found"
        echo "unknown-session"
        return 1
    fi

    # Validate before returning (prevent path traversal)
    # WHY: Session ID is used in filesystem paths; reject anything suspicious
    if [[ ! "$id" =~ ^[A-Za-z0-9._-]{1,128}$ ]]; then
        cc_log_error "Invalid session ID rejected: $id"
        echo "unknown-session"
        return 1
    fi

    echo "$id"
    return 0
}

# ============================================================================
# MENU PARSING
# ============================================================================

# Robust menu command extraction
# WHY: Menu format uses TAB separator (invisible in display, clean UI)
# ASSUMPTION: Command portion never contains TAB character
# TESTED BY: tests/test_menu_parsing.bats::handle title with colons
#
# Usage: cmd=$(cc_parse_menu_command "$choice")
cc_parse_menu_command() {
    local choice="$1"

    if [ -z "$choice" ]; then
        cc_log_warn "Empty menu choice"
        return 1
    fi

    # Extract everything after the tab
    # Format: "Label text<TAB>command args"
    local cmd
    cmd=$(printf '%s' "$choice" | cut -d$'\t' -f2-)

    # Trim leading/trailing whitespace
    cmd=$(echo "$cmd" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    if [ -z "$cmd" ]; then
        cc_log_warn "Failed to extract command from: $choice"
        return 1
    fi

    cc_log_debug "Extracted command: $cmd"
    echo "$cmd"
}

# ============================================================================
# PARAMETER VALIDATION
# ============================================================================

# Validate required parameters
# WHY: Fail fast with clear error messages instead of cryptic failures later
# TESTED BY: tests/test_param_validation.bats::require multiple parameters
#
# Usage: cc_require_param "MODE" "$MODE" "SEED_ID" "$SEED_ID"
cc_require_param() {
    local all_valid=true

    while [ $# -gt 0 ]; do
        local name="$1"
        local value="$2"
        shift 2

        if [ -z "$value" ]; then
            cc_log_error "Required parameter missing: $name"
            echo "Error: Required parameter missing: $name" >&2
            all_valid=false
        fi
    done

    if [ "$all_valid" = false ]; then
        return 1
    fi
    return 0
}

# ============================================================================
# SAFE COMMAND EXECUTION
# ============================================================================

# Execute with proper error handling and logging
# WHY: Centralize error handling and logging for consistency
#
# Usage: cc_exec "description" command args...
cc_exec() {
    local description="$1"
    shift

    cc_log_info "Executing: $description"
    cc_log_debug "Command: $*"

    local output
    local exit_code

    output=$("$@" 2>&1)
    exit_code=$?

    if [ $exit_code -ne 0 ]; then
        cc_log_error "Failed: $description (exit code: $exit_code)"
        cc_log_error "Output: $output"
        echo "$output" >&2
        return $exit_code
    fi

    cc_log_info "Success: $description"
    echo "$output"
    return 0
}

# ============================================================================
# TEMP FILE MANAGEMENT
# ============================================================================

# Create unique temp file (avoids races)
# WHY: Multiple simultaneous expansions could conflict with same temp file
# TESTED BY: tests/test_temp_files.bats::simultaneous operations dont conflict
#
# Usage: tmpfile=$(cc_mktemp "prefix")
cc_mktemp() {
    local prefix="${1:-cc-reflection}"
    local tmpdir="$REFLECTION_BASE/tmp"
    mkdir -p "$tmpdir" 2>/dev/null

    local tmpfile
    # Use XXXXXX for unique suffix
    tmpfile=$(mktemp "$tmpdir/${prefix}.XXXXXX") || {
        cc_log_error "Failed to create temp file with prefix: $prefix"
        return 1
    }

    cc_log_debug "Created temp file: $tmpfile"
    echo "$tmpfile"
}

# Register cleanup handler
# WHY: Ensure temp files are cleaned up even on unexpected exit
# NOTE: Files are expanded and quoted at registration time (not trap execution)
#
# Usage: cc_cleanup_on_exit "$tmpfile1" "$tmpfile2"
cc_cleanup_on_exit() {
    # Quote each file path to handle spaces (printf %q escapes for shell)
    local quoted_files=""
    for f in "$@"; do
        quoted_files="$quoted_files $(printf '%q' "$f")"
    done

    # Register trap for EXIT, INT, TERM
    # shellcheck disable=SC2064  # Intentional: expand now, not at trap time
    trap "rm -f $quoted_files 2>/dev/null" EXIT INT TERM
    cc_log_debug "Registered cleanup for:$quoted_files"
}

# ============================================================================
# BUN INTERACTION
# ============================================================================

# Safe bun execution with error handling
# WHY: Provide clear error messages when bun is missing or scripts fail
#
# Usage: result=$(cc_bun_run "script.ts" "arg1" "arg2")
cc_bun_run() {
    local script="$1"
    shift

    if ! command -v bun &>/dev/null; then
        cc_log_error "bun not found"
        echo "Error: bun is required. Install: curl -fsSL https://bun.sh/install | bash" >&2
        return 1
    fi

    local output
    local exit_code

    # Don't redirect stderr to stdout - let warnings go to stderr so JSON output is clean
    output=$(bun "$script" "$@")
    exit_code=$?

    if [ $exit_code -ne 0 ]; then
        cc_log_error "bun script failed: $script (exit $exit_code)"
        cc_log_error "Output: $output"
        return $exit_code
    fi

    echo "$output"
}

# ============================================================================
# TMUX DETECTION
# ============================================================================

# Check if running in tmux
# WHY: Different behavior needed for tmux vs non-tmux environments
#
# Usage: if cc_in_tmux; then ...; fi
cc_in_tmux() {
    [ -n "$TMUX" ] || [ -n "$ORIGINAL_TMUX" ]
}

# Validate tmux session exists
# WHY: Prevent errors from stale TMUX environment variables
#
# Usage: if cc_validate_tmux_session "$TMUX"; then ...; fi
cc_validate_tmux_session() {
    local session_socket="$1"

    if [ -z "$session_socket" ]; then
        return 1
    fi

    # Extract socket path from TMUX format: /path,PID,INDEX
    local socket_path="${session_socket%%,*}"

    if [ -S "$socket_path" ]; then
        return 0
    else
        cc_log_warn "Tmux socket not found: $socket_path"
        return 1
    fi
}

# ============================================================================
# STRING UTILITIES
# ============================================================================

# Sanitize string for use in filenames or commands
# WHY: Prevent shell injection and filesystem issues
#
# Usage: safe_name=$(cc_sanitize_string "$user_input")
cc_sanitize_string() {
    local input="$1"

    # Remove/replace problematic characters
    # Allow: alphanumeric, dash, underscore, dot
    echo "$input" | tr -cd '[:alnum:]._-' | tr '[:upper:]' '[:lower:]'
}

# ============================================================================
# CONFIG MANAGEMENT
# ============================================================================

# Get current expansion mode from config.json
# WHY: Single source of truth for mode preference
# RETURNS: "interactive" or "auto"
#
# Usage: mode=$(cc_get_expansion_mode)
cc_get_expansion_mode() {
    local session_id=$(cc_get_session_id)
    local mode
    mode=$(bun "$CC_LIB_DIR/reflection-state.ts" get-mode 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$mode" ]; then
        cc_log_debug "Failed to get mode, defaulting to interactive"
        echo "interactive"
        return 0
    fi

    cc_log_debug "Current expansion mode: $mode"
    echo "$mode"
}

# Set expansion mode in config.json
# WHY: Persist user's mode preference across sessions
# ARGS: mode - "interactive" or "auto"
#
# Usage: cc_set_expansion_mode "auto"
cc_set_expansion_mode() {
    local mode="$1"
    local session_id=$(cc_get_session_id)

    if [ "$mode" != "interactive" ] && [ "$mode" != "auto" ]; then
        cc_log_error "Invalid expansion mode: $mode (expected: interactive or auto)"
        return 1
    fi

    if bun "$CC_LIB_DIR/reflection-state.ts" set-mode "$mode" >/dev/null 2>&1; then
        cc_log_debug "Set expansion mode to: $mode"
        return 0
    else
        cc_log_error "Failed to set expansion mode"
        return 1
    fi
}

# Get current permissions mode from config.json
# WHY: Single source of truth for permissions preference
# RETURNS: "enabled" or "disabled"
#
# Usage: mode=$(cc_get_permissions_mode)
cc_get_permissions_mode() {
    local session_id=$(cc_get_session_id)
    local mode
    mode=$(bun "$CC_LIB_DIR/reflection-state.ts" get-permissions 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$mode" ]; then
        cc_log_debug "Failed to get permissions mode, defaulting to disabled"
        echo "disabled"
        return 0
    fi

    cc_log_debug "Current permissions mode: $mode"
    echo "$mode"
}

# Set permissions mode in config.json
# WHY: Persist user's permissions preference across sessions
# ARGS: mode - "enabled" or "disabled"
#
# Usage: cc_set_permissions_mode "enabled"
cc_set_permissions_mode() {
    local mode="$1"
    local session_id=$(cc_get_session_id)

    if [ "$mode" != "enabled" ] && [ "$mode" != "disabled" ]; then
        cc_log_error "Invalid permissions mode: $mode (expected: enabled or disabled)"
        return 1
    fi

    if bun "$CC_LIB_DIR/reflection-state.ts" set-permissions "$mode" >/dev/null 2>&1; then
        cc_log_debug "Set permissions mode to: $mode"
        return 0
    else
        cc_log_error "Failed to set permissions mode"
        return 1
    fi
}

# Get permissions flag for claude CLI
# WHY: Centralize flag construction to avoid duplication
# RETURNS: "--dangerously-skip-permissions" or empty string
#
# Usage: PERMISSIONS_FLAG=$(cc_get_permissions_flag)
cc_get_permissions_flag() {
    local mode=$(cc_get_permissions_mode)

    if [ "$mode" = "enabled" ]; then
        echo "--dangerously-skip-permissions"
    else
        echo ""
    fi
}

# Get current model from config.json
# WHY: Single source of truth for model preference
# RETURNS: "opus", "sonnet", or "haiku"
#
# Usage: model=$(cc_get_model)
cc_get_model() {
    local model
    model=$(bun "$CC_LIB_DIR/reflection-state.ts" get-model 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$model" ]; then
        cc_log_debug "Failed to get model, defaulting to opus"
        echo "opus"
        return 0
    fi

    cc_log_debug "Current model: $model"
    echo "$model"
}

# Set model in config.json
# WHY: Persist user's model preference across sessions
# ARGS: model - "opus", "sonnet", or "haiku"
#
# Usage: cc_set_model "sonnet"
cc_set_model() {
    local model="$1"

    if [ "$model" != "opus" ] && [ "$model" != "sonnet" ] && [ "$model" != "haiku" ]; then
        cc_log_error "Invalid model: $model (expected: opus, sonnet, or haiku)"
        return 1
    fi

    if bun "$CC_LIB_DIR/reflection-state.ts" set-model "$model" >/dev/null 2>&1; then
        cc_log_debug "Set model to: $model"
        return 0
    else
        cc_log_error "Failed to set model"
        return 1
    fi
}

# Get model flag for claude CLI
# WHY: Centralize model selection based on model config
# RETURNS: "--model opus", "--model haiku", or empty string (sonnet is default)
#
# Usage: MODEL_FLAG=$(cc_get_model_flag)
cc_get_model_flag() {
    local model=$(cc_get_model)

    case "$model" in
        opus)   echo "--model opus" ;;
        haiku)  echo "--model haiku" ;;
        *)      echo "" ;;  # sonnet is Claude CLI default
    esac
}

# Valid menu filter values - single source of truth for bash
# SYNC: Must match MENU_FILTERS constant in lib/reflection-state.ts:42
# WHY: Prevents validation scatter across bash functions
VALID_MENU_FILTERS=("all" "active" "outdated" "archived")

# Validate menu filter value (internal helper)
# Returns 0 if valid, 1 if invalid
_cc_is_valid_menu_filter() {
    local filter="$1"
    for valid in "${VALID_MENU_FILTERS[@]}"; do
        [ "$filter" = "$valid" ] && return 0
    done
    return 1
}

# Get current menu filter from config.json
# WHY: Single source of truth for menu filter preference
# RETURNS: "all", "active", "outdated", or "archived"
#
# Usage: filter=$(cc_get_menu_filter)
cc_get_menu_filter() {
    local session_id=$(cc_get_session_id)
    local filter
    filter=$(bun "$CC_LIB_DIR/reflection-state.ts" get-filter 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$filter" ]; then
        cc_log_debug "Failed to get menu filter, defaulting to active"
        echo "active"
        return 0
    fi

    cc_log_debug "Current menu filter: $filter"
    echo "$filter"
}

# Set menu filter in config.json
# WHY: Persist user's filter preference across sessions
# ARGS: filter - one of VALID_MENU_FILTERS (all, active, outdated, archived)
#
# Usage: cc_set_menu_filter "active"
cc_set_menu_filter() {
    local filter="$1"

    if ! _cc_is_valid_menu_filter "$filter"; then
        cc_log_error "Invalid menu filter: $filter (expected: ${VALID_MENU_FILTERS[*]})"
        return 1
    fi

    if bun "$CC_LIB_DIR/reflection-state.ts" set-filter "$filter" >/dev/null 2>&1; then
        cc_log_debug "Set menu filter to: $filter"
        return 0
    else
        cc_log_error "Failed to set menu filter"
        return 1
    fi
}

# Cycle menu filter: all -> active -> archived -> all
# WHY: Provide quick toggle through filter states
# RETURNS: The new filter state
#
# Usage: new_filter=$(cc_cycle_menu_filter)
cc_cycle_menu_filter() {
    local new_filter
    new_filter=$(bun "$CC_LIB_DIR/reflection-state.ts" cycle-filter 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$new_filter" ]; then
        cc_log_error "Failed to cycle menu filter"
        echo "active"
        return 1
    fi

    cc_log_debug "Cycled menu filter to: $new_filter"
    echo "$new_filter"
}

# Get current context turns from config.json
# WHY: Controls how many recent conversation turns to inject into expand prompt
# RETURNS: Number 0-20 (0 = disabled, default 3)
#
# Usage: turns=$(cc_get_context_turns)
cc_get_context_turns() {
    local turns
    turns=$(bun "$CC_LIB_DIR/reflection-state.ts" get-context-turns 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$turns" ]; then
        cc_log_debug "Failed to get context turns, defaulting to 3"
        echo "3"
        return 0
    fi

    cc_log_debug "Current context turns: $turns"
    echo "$turns"
}

# Set context turns in config.json
# WHY: Persist user's context preference across sessions
# ARGS: turns - number 0-20 (0 = disabled)
#
# Usage: cc_set_context_turns 5
cc_set_context_turns() {
    local turns="$1"

    # Validate it's a number in range 0-20
    if ! [[ "$turns" =~ ^[0-9]+$ ]] || [ "$turns" -lt 0 ] || [ "$turns" -gt 20 ]; then
        cc_log_error "Invalid context turns: $turns (expected: 0-20)"
        return 1
    fi

    if bun "$CC_LIB_DIR/reflection-state.ts" set-context-turns "$turns" >/dev/null 2>&1; then
        cc_log_debug "Set context turns to: $turns"
        return 0
    else
        cc_log_error "Failed to set context turns"
        return 1
    fi
}

# Cycle context turns: 0 -> 3 -> 5 -> 10 -> 0
# WHY: Provide quick toggle through common context levels
# RETURNS: The new context turns value
#
# Usage: new_turns=$(cc_cycle_context_turns)
cc_cycle_context_turns() {
    local new_turns
    new_turns=$(bun "$CC_LIB_DIR/reflection-state.ts" cycle-context-turns 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$new_turns" ]; then
        cc_log_error "Failed to cycle context turns"
        echo "3"
        return 1
    fi

    cc_log_debug "Cycled context turns to: $new_turns"
    echo "$new_turns"
}

# ============================================================================
# CLAUDE CLI INVOCATION SITES
# ============================================================================
#
# All Claude CLI invocations MUST use centralized flag getters:
#   MODEL_FLAG=$(cc_get_model_flag)              # --model opus, --model haiku, or empty (sonnet)
#   PERMISSIONS_FLAG=$(cc_get_permissions_flag)  # --dangerously-skip-permissions or empty
#
# CRITICAL: When calling Claude INSIDE tmux sessions or nested shells,
#           call the getter functions IN THAT CONTEXT to get fresh values.
#           Variables set outside the tmux session become stale.
#
# Audit: grep -n 'cc_get_model_flag\|cc_get_permissions_flag' bin/*
#
