#!/usr/bin/env bash

# CC-Reflection Installer
# Installs the reflection system for Claude Code

set -e

REPO_URL="https://github.com/pro-vi/cc-reflection.git"
CLONE_DIR="${HOME}/.local/share/cc-reflection"
INSTALL_DIR="${HOME}/.local/bin"
SKILLS_DIR="${HOME}/.claude/skills"
REFLECTION_BASE="${HOME}/.claude/reflections"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║          CC-Reflection Installer for Claude Code               ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

resolve_source_dir() {
    if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/lib/reflection-state.ts" 2>/dev/null ]; then
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    else
        # Running via curl or from a location without source files — clone repo
        if [ -d "$CLONE_DIR/.git" ]; then
            git -C "$CLONE_DIR" pull --quiet 2>/dev/null || true
        else
            print_info "Cloning cc-reflection..."
            git clone --quiet --depth 1 "$REPO_URL" "$CLONE_DIR"
        fi
        SCRIPT_DIR="$CLONE_DIR"
    fi
}

check_dependencies() {
    print_info "Checking dependencies..."

    local missing=()

    if ! command -v git &> /dev/null; then
        missing+=("git (clone source for curl installs)")
    fi

    if ! command -v bun &> /dev/null; then
        missing+=("bun (runtime for state management)")
    fi

    if ! command -v fzf &> /dev/null; then
        missing+=("fzf (menu interface)")
    fi

    if ! command -v tmux &> /dev/null; then
        missing+=("tmux (session management)")
    fi

    if ! command -v jq &> /dev/null; then
        missing+=("jq (JSON processing for settings.json)")
    fi

    if ! command -v claude &> /dev/null; then
        missing+=("claude (Claude Code CLI)")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        print_error "Missing dependencies:"
        for dep in "${missing[@]}"; do
            echo "  - $dep"
        done
        echo ""
        echo "Install missing dependencies:"
        echo "  git:   https://git-scm.com/downloads"
        echo "  bun:   curl -fsSL https://bun.sh/install | bash"
        echo "  fzf:   brew install fzf  (or apt-get install fzf)"
        echo "  tmux:  brew install tmux (or apt-get install tmux)"
        echo "  jq:    brew install jq   (or apt-get install jq)"
        echo "  claude: See https://docs.claude.com/en/docs/claude-code"
        echo ""
        return 1
    fi

    print_success "All dependencies found"
    return 0
}

install_global() {
    print_info "Installing globally..."

    # Create directories
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$REFLECTION_BASE"/{seeds,results}

    # Symlink executables
    ln -sf "$SCRIPT_DIR/bin/cc-reflect" "$INSTALL_DIR/"
    ln -sf "$SCRIPT_DIR/bin/cc-reflect-expand" "$INSTALL_DIR/"
    ln -sf "$SCRIPT_DIR/bin/cc-reflect-toggle-mode" "$INSTALL_DIR/"
    ln -sf "$SCRIPT_DIR/bin/cc-reflect-toggle-permissions" "$INSTALL_DIR/"
    ln -sf "$SCRIPT_DIR/bin/cc-reflect-toggle-haiku" "$INSTALL_DIR/"
    ln -sf "$SCRIPT_DIR/bin/cc-reflect-toggle-filter" "$INSTALL_DIR/"
    ln -sf "$SCRIPT_DIR/bin/cc-reflect-toggle-context" "$INSTALL_DIR/"
    ln -sf "$SCRIPT_DIR/bin/cc-reflect-rebuild-menu" "$INSTALL_DIR/"
    ln -sf "$SCRIPT_DIR/bin/cc-reflect-preview-seed" "$INSTALL_DIR/"
    ln -sf "$SCRIPT_DIR/bin/cc-reflect-delete-seed" "$INSTALL_DIR/"
    ln -sf "$SCRIPT_DIR/bin/cc-reflect-archive-seed" "$INSTALL_DIR/"
    ln -sf "$SCRIPT_DIR/bin/cc-reflect-build-menu" "$INSTALL_DIR/"
    ln -sf "$SCRIPT_DIR/bin/cc-reflect-header" "$INSTALL_DIR/"
    print_success "Installed binaries to $INSTALL_DIR"

    # Symlink reflection scripts (so git pull auto-updates)
    ln -sf "$SCRIPT_DIR/lib/reflection-state.ts" "$REFLECTION_BASE/"
    ln -sf "$SCRIPT_DIR/lib/session-id.ts" "$REFLECTION_BASE/"
    ln -sf "$SCRIPT_DIR/lib/reflection-utils.ts" "$REFLECTION_BASE/"
    ln -sf "$SCRIPT_DIR/lib/transcript.ts" "$REFLECTION_BASE/"
    print_success "Installed reflection scripts to $REFLECTION_BASE"

    # Check cc-dice dependency (dice mechanics moved to cc-dice)
    if [ ! -d "${HOME}/.claude/dice" ]; then
        echo ""
        print_error "cc-dice not installed. Dice-based reflection hooks will not work."
        print_info  "Install cc-dice first:"
        echo "  curl -fsSL https://raw.githubusercontent.com/pro-vi/cc-dice/main/install.sh | bash"
        echo ""
    else
        print_success "cc-dice detected at ${HOME}/.claude/dice"
    fi

    # Symlink reflection skill (so /reflection is available in Claude Code)
    # NOTE: Use symlink so git pull updates the skill automatically
    local skill_src="$SCRIPT_DIR/.claude/skills/reflection"
    local skill_dest="$SKILLS_DIR/reflection"
    if [ -d "$skill_src" ]; then
        mkdir -p "$SKILLS_DIR"

        # If the destination already exists as a real directory/file (not a symlink),
        # leave it alone to avoid clobbering a user-managed install.
        if [ -e "$skill_dest" ] && [ ! -L "$skill_dest" ]; then
            print_warning "Reflection skill already exists at $skill_dest (not a symlink) — leaving as-is"
            print_warning "To switch to the repo-linked skill, remove it and re-run install:"
            print_warning "  rm -rf \"$skill_dest\""
            print_warning "  ./install.sh"
        else
            ln -sfn "$skill_src" "$skill_dest"
            print_success "Installed reflection skill to $skill_dest"
        fi
    else
        print_warning "Skill not found at $skill_src"
        print_warning "You can still install it manually:"
        print_warning "  mkdir -p \"$SKILLS_DIR\""
        print_warning "  ln -s \"$skill_src\" \"$skill_dest\""
    fi

    # Symlink SessionStart hook (always installed — registers session UUID)
    local hooks_dir="${HOME}/.claude/hooks"
    mkdir -p "$hooks_dir"
    ln -sf "$SCRIPT_DIR/bin/reflection-session-start.ts" "$hooks_dir/"
    if ! register_session_start_hook "$hooks_dir/reflection-session-start.ts"; then
        print_warning "SessionStart hook symlinked but not registered in settings.json"
        print_warning "CC_REFLECTION_SESSION_ID won't be available until manually registered"
    fi

    # Create default config if not exists
    if [ ! -f "$REFLECTION_BASE/config.json" ]; then
        # Initialize with bun to create default config
        bun "$REFLECTION_BASE/reflection-state.ts" list > /dev/null 2>&1 || true
        print_success "Created default config at $REFLECTION_BASE/config.json"
    fi

    # Check and configure PATH
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        print_warning "$INSTALL_DIR is not in PATH"

        # Detect shell config
        local shell_config=""
        case "$SHELL" in
            */zsh)  shell_config="$HOME/.zshrc" ;;
            */bash) shell_config="$HOME/.bashrc" ;;
            */fish) shell_config="$HOME/.config/fish/config.fish" ;;
            *)      shell_config="$HOME/.profile" ;;
        esac

        # Check if already configured but not loaded
        if grep -q '\.local/bin' "$shell_config" 2>/dev/null; then
            print_info "PATH already in $shell_config (reload shell to apply)"
        elif [ -t 0 ]; then
            echo ""
            read -p "Add ~/.local/bin to PATH in $shell_config? [Y/n] " -n 1 -r
            echo ""
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                echo "" >> "$shell_config"
                echo '# Added by cc-reflection installer' >> "$shell_config"
                if [[ "$SHELL" == */fish ]]; then
                    echo 'set -gx PATH $HOME/.local/bin $PATH' >> "$shell_config"
                else
                    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$shell_config"
                fi
                print_success "Added PATH to $shell_config"
            fi
        else
            # Non-interactive (curl | bash): auto-add PATH
            echo "" >> "$shell_config"
            echo '# Added by cc-reflection installer' >> "$shell_config"
            if [[ "$SHELL" == */fish ]]; then
                echo 'set -gx PATH $HOME/.local/bin $PATH' >> "$shell_config"
            else
                echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$shell_config"
            fi
            print_success "Added PATH to $shell_config"
        fi
    fi

    print_success "Global installation complete"
}

# Generic hook registration helpers
# $1 = event name (e.g. "Stop", "SessionStart")
# $2 = grep pattern to identify this hook (e.g. "reflection-stop")
# $3 = full path to hook .ts file (register only)

unregister_hook() {
    local event_name="$1"
    local grep_pattern="$2"
    local settings_file="${HOME}/.claude/settings.json"
    if [ ! -f "$settings_file" ]; then
        return 0
    fi
    if ! grep -q "$grep_pattern" "$settings_file" 2>/dev/null; then
        return 0
    fi
    cp "$settings_file" "$settings_file.bak"
    local tmp_file
    tmp_file=$(mktemp) || { print_error "Failed to create temp file"; return 1; }
    if ! jq --arg event "$event_name" --arg pattern "$grep_pattern" '
        if .hooks[$event] then
            .hooks[$event] |= (
                map(
                    if .hooks then
                        .hooks |= map(select(.command | tostring | contains($pattern) | not))
                    else
                        .
                    end
                )
                | map(select((.hooks // []) | length > 0))
            )
        else
            .
        end
    ' "$settings_file" > "$tmp_file"; then
        rm -f "$tmp_file"
        print_error "Failed to parse settings.json (restored from backup)"
        cp "$settings_file.bak" "$settings_file"
        return 2
    fi
    if ! mv "$tmp_file" "$settings_file"; then
        rm -f "$tmp_file"
        print_error "Failed to write settings.json (restored from backup)"
        cp "$settings_file.bak" "$settings_file"
        return 2
    fi
    return 0
}

register_hook() {
    local event_name="$1"
    local grep_pattern="$2"
    local hook_path="$3"
    local settings_file="${HOME}/.claude/settings.json"

    if [ -f "$settings_file" ]; then
        # Remove old entry before adding new one
        if grep -q "$grep_pattern" "$settings_file" 2>/dev/null; then
            if ! unregister_hook "$event_name" "$grep_pattern"; then
                print_error "Failed to update settings.json — $event_name hook not registered"
                return 1
            fi
        fi

        cp "$settings_file" "$settings_file.bak"
        local hook_cmd
        local quoted_path
        quoted_path=$(jq -nr --arg p "$hook_path" '$p | @sh')
        hook_cmd="bun ${quoted_path}"
        local hook_obj
        hook_obj=$(jq -n --arg cmd "$hook_cmd" '{hooks: [{type: "command", command: $cmd}]}' )
        local tmp_file
        tmp_file=$(mktemp) || { print_error "Failed to create temp file"; return 1; }
        if ! jq --arg event "$event_name" --argjson hook "$hook_obj" '
            .hooks[$event] = (
                if .hooks[$event] then
                    .hooks[$event] + [$hook]
                else
                    [$hook]
                end
            )
        ' "$settings_file" > "$tmp_file"; then
            rm -f "$tmp_file"
            print_error "Failed to parse settings.json (restored from backup)"
            cp "$settings_file.bak" "$settings_file"
            return 1
        fi
        if ! mv "$tmp_file" "$settings_file"; then
            rm -f "$tmp_file"
            print_error "Failed to write settings.json (restored from backup)"
            cp "$settings_file.bak" "$settings_file"
            return 1
        fi
        print_success "Registered $event_name hook in settings.json"
    else
        echo '{
  "hooks": {
    "'"$event_name"'": [{"hooks": [{"type": "command", "command": "bun \"'"$hook_path"'\""}]}]
  }
}' > "$settings_file"
        print_success "Created settings.json with $event_name hook"
    fi
}

# Convenience wrappers (preserve existing call sites)
# Legacy Stop hook wrappers are kept for uninstall migration cleanup.
unregister_stop_hook()          { unregister_hook "Stop" "reflection-stop" ; }
register_stop_hook()            { register_hook "Stop" "reflection-stop" "$1" ; }
unregister_session_start_hook() { unregister_hook "SessionStart" "reflection-session-start" ; }
register_session_start_hook()   { register_hook "SessionStart" "reflection-session-start" "$1" ; }

get_cc_dice_cli() {
    if command -v cc-dice > /dev/null 2>&1; then
        command -v cc-dice
        return 0
    fi
    local fallback="${HOME}/.local/bin/cc-dice"
    if [ -f "$fallback" ]; then
        echo "$fallback"
        return 0
    fi
    return 1
}

register_reflection_slot() {
    local dice_cli=""
    if ! dice_cli="$(get_cc_dice_cli)"; then
        echo ""
        print_info "cc-dice CLI not found. Skipping slot registration."
        print_info "Install cc-dice for automatic /reflection prompting:"
        echo "  cd ../cc-dice && ./install.sh"
        return
    fi

    # Check if slot already exists (preserve user customization)
    echo ""
    if "$dice_cli" status reflection > /dev/null 2>&1; then
        print_success "Reflection slot already registered with cc-dice"
        return
    fi

    print_info "Registering reflection slot with cc-dice..."
    if "$dice_cli" register reflection \
        --die 20 --target 20 \
        --type accumulator \
        --accumulation-rate 7 \
        --cooldown per-session \
        --message $'Invoke /reflection before ending. 吾日三省吾身' \
        > /dev/null 2>&1; then
        print_success "Registered 'reflection' slot with cc-dice"
    else
        print_warning "Failed to register reflection slot with cc-dice"
        print_info "Register manually:"
        echo "  cc-dice register reflection --die 20 --target 20 --type accumulator --accumulation-rate 7 --cooldown per-session --message 'Invoke /reflection before ending.'"
    fi
}

configure_editor() {
    print_info "Configuring EDITOR environment variable..."

    local shell_config=""
    # Detect user's shell from $SHELL environment variable
    # (Can't use $BASH_VERSION/$ZSH_VERSION since this script runs in bash)
    case "$SHELL" in
        */zsh)
            shell_config="$HOME/.zshrc"
            ;;
        */bash)
            shell_config="$HOME/.bashrc"
            ;;
        */fish)
            shell_config="$HOME/.config/fish/config.fish"
            ;;
        *)
            shell_config="$HOME/.profile"
            ;;
    esac

    if [[ "$SHELL" == */fish ]]; then
        local editor_line='set -gx EDITOR cc-reflect'
    else
        local editor_line='export EDITOR="cc-reflect"'
    fi

    if grep -q "cc-reflect" "$shell_config" 2>/dev/null; then
        print_success "EDITOR already configured in $shell_config"
    elif [ -t 0 ]; then
        echo ""
        print_warning "This will set EDITOR=cc-reflect in $shell_config"
        print_warning "This affects all programs that use \$EDITOR (git commit, crontab -e, etc.)"
        read -p "Proceed? [y/N] " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "" >> "$shell_config"
            echo "# CC-Reflection: Set cc-reflect as editor for Claude Code" >> "$shell_config"
            echo "$editor_line" >> "$shell_config"
            print_success "Added EDITOR configuration to $shell_config"
            print_warning "Run: source $shell_config"
        else
            print_info "Skipped EDITOR configuration"
        fi
    else
        print_info "Set EDITOR manually in $shell_config:"
        echo "  $editor_line"
    fi
}

show_usage() {
    echo "Usage: ./install.sh [command]"
    echo ""
    echo "Commands:"
    echo "  (default)     Install cc-reflection globally"
    echo "  uninstall, -u Remove installation"
    echo "  check, -c     Verify installation status"
    echo "  help, -h      Show this help"
    echo ""
}

show_check() {
    echo ""
    local version="unknown"
    local package_json="$SCRIPT_DIR/package.json"
    if [ -f "$package_json" ]; then
        version=$(jq -r '.version // "unknown"' "$package_json" 2>/dev/null || echo "unknown")
    fi
    echo "CC-Reflection v${version}"
    echo ""

    local errors=0
    local warnings=0

    # Check binaries
    echo "Binaries (~/.local/bin/):"
    if [ -L "$INSTALL_DIR/cc-reflect" ]; then
        echo -e "  ${GREEN}✓${NC} cc-reflect"
    else
        echo -e "  ${RED}✗${NC} cc-reflect (not installed)"
        errors=$((errors + 1))
    fi
    if [ -L "$INSTALL_DIR/cc-reflect-expand" ]; then
        echo -e "  ${GREEN}✓${NC} cc-reflect-expand"
    else
        echo -e "  ${RED}✗${NC} cc-reflect-expand (not installed)"
        errors=$((errors + 1))
    fi

    # Version mismatch detection
    if [ -L "$INSTALL_DIR/cc-reflect" ]; then
        local installed_target=$(readlink "$INSTALL_DIR/cc-reflect" 2>/dev/null)
        if [ -n "$installed_target" ] && [ ! -f "$installed_target" ]; then
            echo -e "  ${RED}✗${NC} Symlink broken (target missing)"
            errors=$((errors + 1))
        elif [ -n "$installed_target" ]; then
            local installed_dir=$(dirname "$installed_target")
            if [ "$installed_dir" != "$SCRIPT_DIR/bin" ] && [ -d "$SCRIPT_DIR/bin" ]; then
                echo -e "  ${YELLOW}⚠${NC} Installed from different location"
                echo "      Installed: $installed_dir"
                echo "      Current:   $SCRIPT_DIR/bin"
                warnings=$((warnings + 1))
            fi
        fi
    fi

    # Check skill
    echo ""
    echo "Skill:"
    if [ -L "$SKILLS_DIR/reflection" ] || [ -d "$SKILLS_DIR/reflection" ]; then
        echo -e "  ${GREEN}✓${NC} reflection skill installed"
    else
        echo -e "  ${YELLOW}⚠${NC} reflection skill not installed"
        warnings=$((warnings + 1))
    fi

    # Check hooks
    echo ""
    echo "Hook:"
    local settings_file="${HOME}/.claude/settings.json"

    # Check SessionStart hook
    local session_start_hook="${HOME}/.claude/hooks/reflection-session-start.ts"
    if [ -f "$session_start_hook" ]; then
        echo -e "  ${GREEN}✓${NC} SessionStart hook: session UUID"
        if [ -f "$settings_file" ] && grep -q "reflection-session-start" "$settings_file" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Registered in settings.json"
        else
            echo -e "  ${YELLOW}⚠${NC} Not registered in settings.json"
            warnings=$((warnings + 1))
        fi
    else
        echo -e "  ${YELLOW}⚠${NC} SessionStart hook not installed (session UUID unavailable)"
        warnings=$((warnings + 1))
    fi

    # Check cc-dice slot
    echo ""
    echo "Dice (cc-dice):"
    local dice_cli=""
    if dice_cli="$(get_cc_dice_cli)" && "$dice_cli" status reflection > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Reflection slot registered"
    elif [ -n "$dice_cli" ]; then
        echo -e "  ${YELLOW}⚠${NC} Reflection slot not registered (run: ./install.sh)"
        warnings=$((warnings + 1))
    else
        echo -e "  ${YELLOW}⚠${NC} cc-dice not installed (no automatic /reflection prompting)"
        warnings=$((warnings + 1))
    fi

    # Check config
    echo ""
    echo "Data (~/.claude/reflections/):"
    if [ -d "$REFLECTION_BASE" ]; then
        local seed_count=$(find "$REFLECTION_BASE/seeds" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
        echo -e "  ${GREEN}✓${NC} Directory exists"
        echo "    Seeds: $seed_count"
    else
        echo -e "  ${YELLOW}⚠${NC} Directory not created yet"
    fi

    # Check EDITOR
    echo ""
    echo "Environment:"
    if [ "$EDITOR" = "cc-reflect" ] || [[ "$EDITOR" == *"cc-reflect"* ]]; then
        echo -e "  ${GREEN}✓${NC} EDITOR=$EDITOR"
    else
        echo -e "  ${YELLOW}⚠${NC} EDITOR=${EDITOR:-not set} (should be cc-reflect)"
        warnings=$((warnings + 1))
    fi

    # Check PATH
    if [[ ":$PATH:" == *":$INSTALL_DIR:"* ]]; then
        echo -e "  ${GREEN}✓${NC} ~/.local/bin in PATH"
    else
        echo -e "  ${YELLOW}⚠${NC} ~/.local/bin not in PATH"
        warnings=$((warnings + 1))
    fi

    # Summary
    echo ""
    if [ $errors -eq 0 ] && [ $warnings -eq 0 ]; then
        echo -e "${GREEN}Status: OK${NC}"
    elif [ $errors -eq 0 ]; then
        echo -e "${YELLOW}Status: OK with $warnings warning(s)${NC}"
    else
        echo -e "${RED}Status: $errors error(s), $warnings warning(s)${NC}"
        echo "Run: ./install.sh"
    fi
    echo ""
}

uninstall() {
    print_info "Uninstalling cc-reflection..."

    # Remove binaries
    rm -f "$INSTALL_DIR/cc-reflect"
    rm -f "$INSTALL_DIR/cc-reflect-expand"
    rm -f "$INSTALL_DIR/cc-reflect-toggle-mode"
    rm -f "$INSTALL_DIR/cc-reflect-toggle-permissions"
    rm -f "$INSTALL_DIR/cc-reflect-toggle-haiku"
    rm -f "$INSTALL_DIR/cc-reflect-toggle-filter"
    rm -f "$INSTALL_DIR/cc-reflect-toggle-context"
    rm -f "$INSTALL_DIR/cc-reflect-rebuild-menu"
    rm -f "$INSTALL_DIR/cc-reflect-preview-seed"
    rm -f "$INSTALL_DIR/cc-reflect-delete-seed"
    rm -f "$INSTALL_DIR/cc-reflect-archive-seed"
    rm -f "$INSTALL_DIR/cc-reflect-build-menu"
    rm -f "$INSTALL_DIR/cc-reflect-header"
    print_success "Removed binaries from $INSTALL_DIR"

    # Remove skill symlink only if it points to this repo (safe for user-managed skills)
    local skill_link="$SKILLS_DIR/reflection"
    local expected_target="$SCRIPT_DIR/.claude/skills/reflection"
    if [ -L "$skill_link" ]; then
        local target=""
        target=$(readlink "$skill_link" 2>/dev/null || echo "")
        if [ "$target" = "$expected_target" ]; then
            rm -f "$skill_link"
            print_success "Removed reflection skill symlink"
        else
            print_info "Kept reflection skill (points elsewhere: ${target:-<unknown>})"
        fi
    fi

    # Unregister hooks from settings.json, then delete files
    local hook_cleanup_failed=false

    # Legacy Stop hook cleanup (migration from pre-cc-dice installs)
    local unreg_stop_rc=0
    unregister_stop_hook || unreg_stop_rc=$?
    case "$unreg_stop_rc" in
        0)
            rm -f "${HOME}/.claude/hooks/reflection-stop.ts"
            rm -f "${HOME}/.claude/hooks/reflection-stop-simple.ts"
            print_success "Removed legacy Stop hook entries/files"
            ;;
        *)
            hook_cleanup_failed=true
            print_error "Failed to remove legacy Stop hook from settings.json"
            echo "  Legacy stop hook files kept to avoid dangling settings.json references."
            ;;
    esac

    # SessionStart hook
    local unreg_start_rc=0
    unregister_session_start_hook || unreg_start_rc=$?
    case "$unreg_start_rc" in
        0)
            print_success "Removed SessionStart hook from settings.json"
            rm -f "${HOME}/.claude/hooks/reflection-session-start.ts"
            print_success "Removed SessionStart hook file"
            ;;
        *)
            hook_cleanup_failed=true
            print_error "Failed to remove SessionStart hook from settings.json"
            ;;
    esac

    # Unregister reflection slot from cc-dice
    local dice_cli=""
    if dice_cli="$(get_cc_dice_cli)" && "$dice_cli" status reflection > /dev/null 2>&1; then
        if "$dice_cli" unregister reflection > /dev/null 2>&1; then
            print_success "Removed 'reflection' slot from cc-dice"
        else
            print_warning "Failed to remove reflection slot from cc-dice"
        fi
    fi

    # Ask about data
    echo ""
    if [ -t 0 ]; then
        read -p "Remove reflection data (~/.claude/reflections)? [y/N] " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$REFLECTION_BASE"
            print_success "Removed reflection data"
        else
            print_info "Kept reflection data at $REFLECTION_BASE"
        fi
    else
        print_info "Kept reflection data at $REFLECTION_BASE"
        print_info "Remove manually: rm -rf $REFLECTION_BASE"
    fi

    if [ "$hook_cleanup_failed" = true ]; then
        print_warning "Uninstall incomplete — hook cleanup failed (see above)"
        return 1
    fi

    print_success "Standalone uninstall complete"
    print_info "To uninstall plugin: /plugin uninstall cc-reflection"
}

# Main
print_header

case "${1:-}" in
    ""|install)
        if ! check_dependencies; then
            exit 1
        fi
        resolve_source_dir
        install_global
        register_reflection_slot
        configure_editor
        echo ""
        print_success "Installation complete!"
        echo ""
        print_info "Next steps:"
        echo "  1. Reload shell: source ~/.bashrc (or ~/.zshrc)"
        echo "  2. Verify: cc-reflect --check"
        echo "  3. Start Claude Code: claude"
        echo ""
        ;;

    uninstall|-u)
        resolve_source_dir
        uninstall
        ;;

    check|-c)
        resolve_source_dir
        show_check
        ;;

    help|--help|-h)
        show_usage
        ;;

    *)
        print_error "Unknown command: $1"
        echo ""
        show_usage
        exit 1
        ;;
esac
