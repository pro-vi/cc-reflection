#!/usr/bin/env bash
# menu-utils.sh - Menu construction utilities for cc-reflect
# WHY: Extract menu building logic for testability
# TESTED BY: tests/unit/test_menu_utils.bats

# Source common utilities
# WHY: Use CC_LIB_DIR to avoid clobbering SCRIPT_DIR exported from parent scripts
CC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CC_LIB_DIR/cc-common.sh"

# ============================================================================
# SECTION HEADERS
# ============================================================================

# Build a section header divider with title
# WHY: Visually separate menu sections with labeled dividers
# RETURNS: Section header in format "══ Title ════════<TAB>echo"
# NOTE: <TAB>echo makes it a no-op when selected (loops back to menu)
# NOTE: ANSI dim (2m) makes headers visually distinct/disabled-looking
#
# Usage: header=$(cc_section_header "Seeds")
cc_section_header() {
    local title="$1"
    local width=40
    local dashes=$(printf '═%.0s' $(seq 1 $((width - ${#title} - 4))))
    # Use ANSI dim escape code for "disabled" appearance
    printf '\033[2m══ %s %s\033[0m\t%s\n' "$title" "$dashes" "echo"
}

# ============================================================================
# EDITOR DETECTION
# ============================================================================

# Build editor menu entries for available editors
# WHY: Centralize editor detection logic for testing and maintainability
# RETURNS: Newline-separated menu entries in format "Label<TAB>command"
# NOTE: Uses Nerd Font icons if available (detected by cc_has_nerd_fonts)
#
# Usage: editor_menu=$(cc_build_editor_menu "$safe_file_path")
cc_build_editor_menu() {
    local safe_file="$1"
    local menu=""
    local icon=""

    # Vim is always available (fallback)
    icon=$(cc_get_editor_icon "vim")
    if [ -n "$icon" ]; then
        menu=$(printf '%s Edit with Vim\t%s' "$icon" "vi $safe_file")
    else
        menu=$(printf '%s\t%s' "Edit with Vim" "vi $safe_file")
    fi

    # Detect and add GUI editors
    if command -v code &>/dev/null; then
        cc_log_debug "Found: VS Code"
        icon=$(cc_get_editor_icon "vscode")
        if [ -n "$icon" ]; then
            menu="$menu"$'\n'$(printf '%s Edit with VS Code\t%s' "$icon" "code -w $safe_file")
        else
            menu="$menu"$'\n'$(printf '%s\t%s' "Edit with VS Code" "code -w $safe_file")
        fi
    fi

    if command -v cursor &>/dev/null; then
        cc_log_debug "Found: Cursor"
        icon=$(cc_get_editor_icon "cursor")
        if [ -n "$icon" ]; then
            menu="$menu"$'\n'$(printf '%s Edit with Cursor\t%s' "$icon" "cursor -w $safe_file")
        else
            menu="$menu"$'\n'$(printf '%s\t%s' "Edit with Cursor" "cursor -w $safe_file")
        fi
    fi

    if command -v windsurf &>/dev/null; then
        cc_log_debug "Found: Windsurf"
        icon=$(cc_get_editor_icon "windsurf")
        if [ -n "$icon" ]; then
            menu="$menu"$'\n'$(printf '%s Edit with Windsurf\t%s' "$icon" "windsurf -w $safe_file")
        else
            menu="$menu"$'\n'$(printf '%s\t%s' "Edit with Windsurf" "windsurf -w $safe_file")
        fi
    fi

    if command -v zed &>/dev/null; then
        cc_log_debug "Found: Zed"
        icon=$(cc_get_editor_icon "zed")
        if [ -n "$icon" ]; then
            menu="$menu"$'\n'$(printf '%s Edit with Zed\t%s' "$icon" "zed --wait $safe_file")
        else
            menu="$menu"$'\n'$(printf '%s\t%s' "Edit with Zed" "zed --wait $safe_file")
        fi
    fi

    if command -v agy &>/dev/null; then
        cc_log_debug "Found: Antigravity"
        icon=$(cc_get_editor_icon "antigravity")
        if [ -n "$icon" ]; then
            menu="$menu"$'\n'$(printf '%s Edit with Antigravity\t%s' "$icon" "agy -w $safe_file")
        else
            menu="$menu"$'\n'$(printf '%s\t%s' "Edit with Antigravity" "agy -w $safe_file")
        fi
    fi

    echo "$menu"
}

# ============================================================================
# REFLECTION SEED MENU
# ============================================================================

# Build menu entries for reflection seeds
# WHY: Separate seed menu building for testing
# RETURNS: Newline-separated menu entries for seeds (or empty if none)
# ARGS: seeds_json - JSON array of seeds
#       mode - "interactive" or "auto" (current expansion mode)
#
# Usage: seed_menu=$(cc_build_seed_menu "$seeds_json" "$mode")
cc_build_seed_menu() {
    local seeds_json="$1"
    local mode="${2:-interactive}"

    # Check if we have seeds
    if [ -z "$seeds_json" ] || [ "$seeds_json" = "[]" ]; then
        return 0 # No seeds, return empty
    fi

    # Use bun to format seeds into menu entries (one per seed, using current mode)
    # Emoji tiers: see CC_SEED_EMOJI_PATTERN in cc-common.sh
    # Note: Using \t (tab) as delimiter for fzf
    echo "$seeds_json" | bun -e "
        const seeds = JSON.parse(await Bun.stdin.text());
        const mode = '$mode';
        for (const seed of seeds) {
            // freshness_tier is computed by reflection-state.ts
            const emoji = seed.freshness_tier || '💭';
            // Show ✓ if seed has been expanded before
            const expanded = seed.expansions && seed.expansions.length > 0 ? ' ✓' : '';
            console.log(\`\${emoji} \${seed.title}\${expanded}\tcc-reflect-expand \${mode} \${seed.id}\`);
        }
    "
}

# ============================================================================
# ENHANCE PROMPT
# ============================================================================

# Build enhance prompt menu entry
# WHY: Separate enhance entry for flexible positioning in menu
# RETURNS: Single menu entry for prompt enhancement (tab-separated)
# ARGS: mode - Current expansion mode ("interactive" or "auto")
#
# Usage: enhance_entry=$(cc_build_enhance_entry "$mode")
cc_build_enhance_entry() {
    local mode="${1:-interactive}"
    local display_mode cmd
    if [ "$mode" = "interactive" ]; then
        display_mode="Interactive"
        cmd="claude-spawn-interactive"
    else
        display_mode="Auto"
        cmd="claude-enhance-auto"
    fi
    printf '%s\t%s\n' "Enhance Prompt ($display_mode)" "$cmd"
}

# ============================================================================
# SETTINGS MENU
# ============================================================================

# Build settings menu entries (toggles for mode, model, filter, context, permissions)
# WHY: Separate settings from actions for clearer menu organization
# RETURNS: Newline-separated menu entries for settings (with emojis)
# ARGS: mode - Current expansion mode ("interactive" or "auto")
#       permissions - Current permissions mode ("enabled" or "disabled")
#       model - Current model ("opus", "sonnet", or "haiku")
#       filter - Current menu filter ("all", "active", or "archived")
#       context_turns - Number of context turns for expand (0, 3, 5, 10)
#
# ORDER: Mode, Model, Filter, Context, Permissions (dangerous option last)
#
# Usage: settings_menu=$(cc_build_settings_menu "$mode" "$permissions" "$model" "$filter" "$context_turns")
cc_build_settings_menu() {
    local mode="${1:-interactive}"
    local permissions="${2:-disabled}"
    local model="${3:-opus}"
    local filter="${4:-active}"
    local context_turns="${5:-3}"

    # Capitalize mode for display
    local display_mode opposite_mode
    if [ "$mode" = "interactive" ]; then
        display_mode="Interactive"
        opposite_mode="Auto"
    else
        display_mode="Auto"
        opposite_mode="Interactive"
    fi

    # Build model display (cycle: opus → sonnet → haiku → opus)
    local current_model next_model
    case "$model" in
    "opus")
        current_model="Opus"
        next_model="Sonnet"
        ;;
    "sonnet")
        current_model="Sonnet"
        next_model="Haiku"
        ;;
    "haiku")
        current_model="Haiku"
        next_model="Opus"
        ;;
    *)
        current_model="Opus"
        next_model="Sonnet"
        ;;
    esac

    # Build filter display
    # Cycle: active (🌱💭) → outdated (💤) → archived (📦) → all → active
    local filter_display next_filter
    case "$filter" in
    "active")
        filter_display="Active 🌱💭"
        next_filter="Outdated"
        ;;
    "outdated")
        filter_display="Outdated 💤"
        next_filter="Archived"
        ;;
    "archived")
        filter_display="Archived 📦"
        next_filter="All"
        ;;
    "all")
        filter_display="All"
        next_filter="Active"
        ;;
    *)
        filter_display="Active 🌱💭"
        next_filter="Outdated"
        ;;
    esac

    # Build context display
    # Cycle: 0 → 3 → 5 → 10 → 0
    local context_display next_context
    case "$context_turns" in
    "0")
        context_display="Off"
        next_context="3"
        ;;
    "3")
        context_display="3 turns"
        next_context="5"
        ;;
    "5")
        context_display="5 turns"
        next_context="10"
        ;;
    "10")
        context_display="10 turns"
        next_context="Off"
        ;;
    *)
        context_display="$context_turns"
        next_context="3"
        ;;
    esac

    # Build permissions display with dynamic emoji
    # 🔒 = locked (requiring permissions) = disabled
    # 🔓 = unlocked (skipping permissions) = enabled
    local permissions_emoji permissions_status opposite_permissions
    if [ "$permissions" = "enabled" ]; then
        permissions_emoji="🔓"
        permissions_status="On"
        opposite_permissions="Off"
    else
        permissions_emoji="🔒"
        permissions_status="Off"
        opposite_permissions="On"
    fi

    # Output with tab delimiter - ORDER: Mode, Model, Filter, Context, Permissions
    printf '%s\t%s\n' "🔄 Mode: $display_mode (→ $opposite_mode)" "cc-reflect-toggle-mode"
    printf '%s\t%s\n' "🤖 Model: $current_model (→ $next_model)" "cc-reflect-toggle-model"
    printf '%s\t%s\n' "🔍 Filter: $filter_display (→ $next_filter)" "cc-reflect-toggle-filter"
    printf '%s\t%s\n' "💬 Context: $context_display (→ $next_context)" "cc-reflect-toggle-context"
    printf '%s\t%s\n' "$permissions_emoji Skip permissions: $permissions_status (→ $opposite_permissions)" "cc-reflect-toggle-permissions"
}

# ============================================================================
# ACTIONS MENU
# ============================================================================

# Build actions menu entries
# WHY: Separate destructive actions from settings
# RETURNS: Newline-separated menu entries for actions (tab-separated)
#
# Usage: actions_menu=$(cc_build_actions_menu)
cc_build_actions_menu() {
    # Archive only outdated (💤) seeds - keeps fresh ones
    printf '%s\t%s\n' "📦 Archive Outdated Seeds" "cc-reflect-archive-outdated"
}

# ============================================================================
# MENU DISPLAY PREPARATION
# ============================================================================

# Extract display labels from full menu (remove commands)
# WHY: fzf should only show labels, not full commands with paths
# TESTED BY: Menu display is clean without tabs or commands
#
# Usage: display_menu=$(cc_prepare_menu_display "$full_menu")
cc_prepare_menu_display() {
    local full_menu="$1"
    echo "$full_menu" | cut -d$'\t' -f1
}

# Find full menu line from display label
# WHY: After user selects label, we need to get full line for command extraction
# RETURNS: Full "Label<TAB>command" line
#
# Usage: full_line=$(cc_find_menu_line "$full_menu" "$selected_label")
cc_find_menu_line() {
    local full_menu="$1"
    local selected_label="$2"
    echo "$full_menu" | grep -F "$selected_label"$'\t'
}

# ============================================================================
# COMPLETE MENU BUILDER
# ============================================================================

# Build complete menu with all sections
# WHY: Single function to construct entire menu for consistency
# RETURNS: Full menu with editors, enhance, seeds, settings, and actions
# ARGS: safe_file - Path to reflection file
#       seeds_json - JSON array of seeds
#       mode - Current expansion mode ("interactive" or "auto")
#       permissions - Current permissions mode ("enabled" or "disabled")
#       model - Current model ("opus", "sonnet", or "haiku")
#       filter - Current menu filter ("all", "active", or "archived")
#       context_turns - Number of context turns for expand (0, 3, 5, 10)
#
# Menu structure:
#   1. Editor entries (no header)
#   2. Enhance Prompt entry
#   3. ── Seeds ── header (only if seeds exist)
#   4. Seed entries
#   5. ── Settings ── header
#   6. Settings entries
#   7. ── Actions ── header
#   8. Action entries
#
# Usage: menu=$(cc_build_complete_menu "$safe_file" "$seeds_json" "$mode" "$permissions" "$model" "$filter" "$context_turns")
cc_build_complete_menu() {
    local safe_file="$1"
    local seeds_json="$2"
    local mode="${3:-interactive}"
    local permissions="${4:-disabled}"
    local model="${5:-opus}"
    local filter="${6:-active}"
    local context_turns="${7:-3}"
    local menu=""

    # 1. Editor section (no header)
    menu=$(cc_build_editor_menu "$safe_file")

    # 2. Enhance Prompt entry (right after editors)
    menu="$menu
$(cc_build_enhance_entry "$mode")"

    # 3-4. Seeds section (only if we have seeds)
    if [ -n "$seeds_json" ] && [ "$seeds_json" != "[]" ]; then
        local seed_menu=$(cc_build_seed_menu "$seeds_json" "$mode")
        if [ -n "$seed_menu" ]; then
            # Build dynamic header based on filter
            local filter_label
            case "$filter" in
            "active") filter_label="Seeds (Active 🌱💭)" ;;
            "outdated") filter_label="Seeds (Outdated 💤)" ;;
            "archived") filter_label="Seeds (Archived 📦)" ;;
            "all") filter_label="Seeds (All)" ;;
            *) filter_label="Seeds" ;;
            esac
            menu="$menu
$(cc_section_header "$filter_label")
$seed_menu"
        fi
    fi

    # 5-6. Settings section
    menu="$menu
$(cc_section_header "Settings")
$(cc_build_settings_menu "$mode" "$permissions" "$model" "$filter" "$context_turns")"

    # 7-8. Actions section
    menu="$menu
$(cc_section_header "Actions")
$(cc_build_actions_menu)"

    echo "$menu"
}
