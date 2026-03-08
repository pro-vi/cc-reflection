#!/usr/bin/env bash
# reflection module for cc-hall
# Surfaces reflection seeds, settings, and actions

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
HALL_MODULE_ICON="◇"

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

    # ── Guide ──────────────────────────────────────────────────

    printf '%s\t%s\n' \
        "$(hall_icon guide) $(hall_ansi_bold "Guide")" \
        "rf-info guide"

    # ── Seed entries (single bun call via list-menu-entries) ──────

    local _rf_group_open=false
    local _rf_dim_pipe
    _rf_dim_pipe=$(hall_ansi_dim "│")

    _rf_subheader() {
        if $_rf_group_open; then
            printf '%s\t%s\n' "$(hall_ansi_dim "╰─")" "rf-noop"
        fi
        printf '%s\t%s\n' "$(hall_ansi_dim "╭─ $1 ──")" "rf-noop"
        _rf_group_open=true
    }

    local _rf_seeds=""
    if command -v bun &>/dev/null; then
        _rf_seeds=$(cc_bun_run "$REFLECTION_ROOT/lib/reflection-state.ts" list-menu-entries "$filter" "$mode" 2>/dev/null || true)
    fi

    local _rf_seed_count=0
    [ -n "$_rf_seeds" ] && _rf_seed_count=$(echo "$_rf_seeds" | wc -l | tr -d ' ')

    _rf_subheader "Seeds $(hall_ansi_dim "($filter · $_rf_seed_count)")"

    if [ -n "$_rf_seeds" ]; then
        # Prepend │ to each seed entry
        while IFS=$'\t' read -r _rf_label _rf_cmd; do
            printf '%s\t%s\n' "$_rf_dim_pipe $_rf_label" "$_rf_cmd"
        done <<< "$_rf_seeds"
    else
        printf '%s\t%s\n' \
            "$_rf_dim_pipe $(hall_ansi_dim "(no seeds)")" \
            "rf-noop"
    fi

    # ── Settings ──────────────────────────────────────────────

    _rf_subheader "Settings"

    # Mode
    local display_mode opposite_mode
    [ "$mode" = "interactive" ] && display_mode="Interactive" && opposite_mode="Auto" || { display_mode="Auto"; opposite_mode="Interactive"; }
    printf '%s\t%s\n' \
        "$(hall_ansi_dim "│") $(hall_ansi_bold "Mode"): $display_mode $(hall_ansi_dim "→ $opposite_mode")" \
        "cc-reflect-toggle-mode"

    # Model
    local current_model next_model
    case "$model" in
        opus)   current_model="Opus";   next_model="Sonnet" ;;
        sonnet) current_model="Sonnet"; next_model="Haiku"  ;;
        haiku)  current_model="Haiku";  next_model="Opus"   ;;
        *)      current_model="Opus";   next_model="Sonnet" ;;
    esac
    printf '%s\t%s\n' \
        "$(hall_ansi_dim "│") $(hall_ansi_bold "Model"): $current_model $(hall_ansi_dim "→ $next_model")" \
        "cc-reflect-toggle-model"

    # Filter
    local filter_display next_filter
    case "$filter" in
        active)   filter_display="Active";   next_filter="Outdated" ;;
        outdated) filter_display="Outdated"; next_filter="Archived" ;;
        archived) filter_display="Archived"; next_filter="All"      ;;
        all)      filter_display="All";      next_filter="Active"   ;;
        *)        filter_display="Active";   next_filter="Outdated" ;;
    esac
    printf '%s\t%s\n' \
        "$(hall_ansi_dim "│") $(hall_ansi_bold "Filter"): $filter_display $(hall_ansi_dim "→ $next_filter")" \
        "cc-reflect-toggle-filter"

    # Context turns
    local context_display next_context
    case "$context_turns" in
        0)  context_display="Off";      next_context="3"   ;;
        3)  context_display="3 turns";  next_context="5"   ;;
        5)  context_display="5 turns";  next_context="10"  ;;
        10) context_display="10 turns"; next_context="Off" ;;
        *)  context_display="$context_turns"; next_context="3" ;;
    esac
    printf '%s\t%s\n' \
        "$(hall_ansi_dim "│") $(hall_ansi_bold "Context"): $context_display $(hall_ansi_dim "→ $next_context")" \
        "cc-reflect-toggle-context"

    # Permissions
    local perm_display next_perm
    if [ "$permissions" = "enabled" ]; then
        perm_display="On"; next_perm="Off"
    else
        perm_display="Off"; next_perm="On"
    fi
    printf '%s\t%s\n' \
        "$(hall_ansi_dim "│") $(hall_ansi_bold "Skip Perms"): $perm_display $(hall_ansi_dim "→ $next_perm")" \
        "cc-reflect-toggle-permissions"

    # ── Actions ──────────────────────────────────────────────

    _rf_subheader "Actions"

    printf '%s\t%s\n' \
        "$(hall_ansi_dim "│") $(hall_ansi_bold "Archive Outdated")" \
        "cc-reflect-archive-outdated"
    printf '%s\t%s\n' \
        "$(hall_ansi_dim "│") $(hall_ansi_bold "Archive All")" \
        "cc-reflect-archive-all"
    printf '%s\t%s\n' \
        "$(hall_ansi_dim "│") $(hall_ansi_bold "Purge Archived")" \
        "cc-reflect-purge-archived"

    # Close final group
    if $_rf_group_open; then
        printf '%s\t%s\n' "$(hall_ansi_dim "╰─")" "rf-noop"
    fi
}
