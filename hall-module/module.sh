#!/usr/bin/env bash
# reflection module for cc-hall
# Surfaces reflection seeds, enhance prompt, settings, and actions

# Resolve to cc-reflection root (module dir may be symlinked from ~/.claude/hall/modules/reflection/)
_MODULE_PATH="${BASH_SOURCE[0]}"
_MODULE_DIR="$(cd "$(dirname "$_MODULE_PATH")" && pwd -P)"
REFLECTION_ROOT="$(cd "$_MODULE_DIR/.." && pwd -P)"

# Source cc-reflection's own libraries (needed for cc_bun_run)
source "$REFLECTION_ROOT/lib/cc-common.sh"

# Source hall theme helpers
source "${HALL_LIB_DIR}/hall-theme.sh"

# Metadata
HALL_MODULE_LABEL="Reflection"
HALL_MODULE_ORDER=30

# Module-contributed keybindings for fzf
# These are collected by hall and added to the fzf invocation
HALL_MODULE_BINDINGS=(
    "ctrl-d:execute($REFLECTION_ROOT/bin/cc-reflect-delete-seed {})+reload(cc-hall reload)"
    "ctrl-a:execute($REFLECTION_ROOT/bin/cc-reflect-archive-seed {})+reload(cc-hall reload)"
    "ctrl-f:execute-silent($REFLECTION_ROOT/bin/cc-reflect-toggle-filter)+reload(cc-hall reload)"
)

# ── Config loading (pure bash, zero subprocess overhead) ──────────
# Reads ~/.claude/reflections/config.json directly instead of spawning
# 5 separate bun processes (~125ms each = 625ms saved)
_hall_reflection_load_config() {
    local config_file="${HOME}/.claude/reflections/config.json"

    # Defaults
    _REFLECT_MODE="interactive"
    _REFLECT_SKIP_PERMS="false"
    _REFLECT_MODEL="opus"
    _REFLECT_FILTER="active"
    _REFLECT_CONTEXT="3"

    [ -f "$config_file" ] || return 0

    local content
    content=$(<"$config_file")

    [[ "$content" =~ \"expansion_mode\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]] && _REFLECT_MODE="${BASH_REMATCH[1]}"
    [[ "$content" =~ \"skip_permissions\"[[:space:]]*:[[:space:]]*(true|false) ]] && _REFLECT_SKIP_PERMS="${BASH_REMATCH[1]}"
    [[ "$content" =~ \"model\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]] && _REFLECT_MODEL="${BASH_REMATCH[1]}"
    [[ "$content" =~ \"menu_filter\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]] && _REFLECT_FILTER="${BASH_REMATCH[1]}"
    [[ "$content" =~ \"context_turns\"[[:space:]]*:[[:space:]]*([0-9]+) ]] && _REFLECT_CONTEXT="${BASH_REMATCH[1]}"
}

# Entry generator
hall_reflection_entries() {
    _hall_reflection_load_config

    local mode="$_REFLECT_MODE"
    local model="$_REFLECT_MODEL"
    local filter="$_REFLECT_FILTER"
    local context_turns="$_REFLECT_CONTEXT"

    # Convert skip_permissions bool to display format
    local permissions="disabled"
    [ "$_REFLECT_SKIP_PERMS" = "true" ] && permissions="enabled"

    # ── Seed entries (single bun call via list-menu-entries) ──────
    if command -v bun &>/dev/null; then
        cc_bun_run "$REFLECTION_ROOT/lib/reflection-state.ts" list-menu-entries "$filter" "$mode" 2>/dev/null || true
    fi

    # ── Settings ──────────────────────────────────────────────
    hall_section_header "Settings"
    # Mode
    local opposite_mode
    [ "$mode" = "interactive" ] && display_mode="Interactive" && opposite_mode="Auto" || { display_mode="Auto"; opposite_mode="Interactive"; }
    printf '%s\t%s\n' "🔄 Mode: $display_mode $(hall_ansi_dim "→ $opposite_mode")" "cc-reflect-toggle-mode"

    # Model
    local current_model next_model
    case "$model" in
        opus)   current_model="Opus";   next_model="Sonnet" ;;
        sonnet) current_model="Sonnet"; next_model="Haiku"  ;;
        haiku)  current_model="Haiku";  next_model="Opus"   ;;
        *)      current_model="Opus";   next_model="Sonnet" ;;
    esac
    printf '%s\t%s\n' "🤖 Model: $current_model $(hall_ansi_dim "→ $next_model")" "cc-reflect-toggle-model"

    # Filter
    local filter_display next_filter
    case "$filter" in
        active)   filter_display="Active";   next_filter="Outdated" ;;
        outdated) filter_display="Outdated"; next_filter="Archived" ;;
        archived) filter_display="Archived"; next_filter="All"      ;;
        all)      filter_display="All";      next_filter="Active"   ;;
        *)        filter_display="Active";   next_filter="Outdated" ;;
    esac
    printf '%s\t%s\n' "🔍 Filter: $filter_display $(hall_ansi_dim "→ $next_filter")" "cc-reflect-toggle-filter"

    # Context turns
    local context_display
    case "$context_turns" in
        0)  context_display="Off"       ;;
        3)  context_display="3 turns"   ;;
        5)  context_display="5 turns"   ;;
        10) context_display="10 turns"  ;;
        *)  context_display="$context_turns" ;;
    esac
    printf '%s\t%s\n' "💬 Context: $context_display" "cc-reflect-toggle-context"

    # Permissions
    local perm_status
    [ "$permissions" = "enabled" ] && perm_status="On" || perm_status="Off"
    printf '%s\t%s\n' "🔓 Skip perms: $perm_status" "cc-reflect-toggle-permissions"

    # ── Actions ──────────────────────────────────────────────
    hall_section_header "Actions"
    printf '%s\t%s\n' "📦 Archive Outdated Seeds" "cc-reflect-archive-outdated"
}
