#!/usr/bin/env bats

# test_uninstall_hooks.bats - Verify uninstall handles settings.json failures safely
#
# WHY: Uninstall must not delete hook files if settings.json can't be cleaned,
#      otherwise Claude invokes a non-existent script on every event.
# CRITICAL: Tests use a fake HOME to avoid touching real ~/.claude/settings.json.
#
# NOTE: Stop hooks are now owned by cc-dice, but legacy reflection-stop
#       entries/files still require uninstall-time migration cleanup.

load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../" && pwd)"

setup() {
    # Create isolated fake HOME so we never touch real settings
    export REAL_HOME="$HOME"
    export HOME="$(mktemp -d)"
    # Keep host PATH for tools like jq, but ensure test-local binaries override.
    export PATH="$HOME/.local/bin:$PATH"
    mkdir -p "$HOME/.claude/hooks"
    mkdir -p "$HOME/.local/bin"

    # Hermetic cc-dice stub: prevents accidental use of a real host installation.
    cat > "$HOME/.local/bin/cc-dice" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$HOME/.local/bin/cc-dice"

    # Pre-seed shell config with .local/bin so install_global never prompts
    # for PATH addition. This ensures full-script tests have deterministic
    # stdin consumption (only the wizard read).
    local shell_config="$HOME/.zshrc"
    case "$SHELL" in
        */bash) shell_config="$HOME/.bashrc" ;;
        */fish) shell_config="$HOME/.config/fish/config.fish"; mkdir -p "$(dirname "$shell_config")" ;;
        *)      shell_config="$HOME/.zshrc" ;;
    esac
    echo 'export PATH="$HOME/.local/bin:$PATH"' > "$shell_config"
}

teardown() {
    rm -rf "$HOME"
    export HOME="$REAL_HOME"
}

# Source install.sh functions by defining them inline from the file.
# We extract each function block we need.
load_install_functions() {
    # Color vars
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'

    # Define helpers
    print_success() { echo -e "${GREEN}✓${NC} $1"; }
    print_error() { echo -e "${RED}✗${NC} $1"; }
    print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
    print_info() { echo -e "${BLUE}ℹ${NC} $1"; }

    # Source functions from install.sh
    # Generic hook helpers (must be loaded first — wrappers depend on them)
    eval "$(awk '/^unregister_hook\(\)/{found=1} found{print; if(/^}$/){found=0}}' "$SCRIPT_DIR/install.sh")"
    eval "$(awk '/^register_hook\(\)/{found=1} found{print; if(/^}$/){found=0}}' "$SCRIPT_DIR/install.sh")"
    # Convenience wrappers
    eval "$(awk '/^unregister_stop_hook\(\)/' "$SCRIPT_DIR/install.sh")"
    eval "$(awk '/^register_stop_hook\(\)/' "$SCRIPT_DIR/install.sh")"
    eval "$(awk '/^unregister_session_start_hook\(\)/' "$SCRIPT_DIR/install.sh")"
    eval "$(awk '/^register_session_start_hook\(\)/' "$SCRIPT_DIR/install.sh")"
}

# --- SessionStart hook tests ---

@test "unregister_session_start_hook preserves top-level settings object" {
    load_install_functions

    cat > "$HOME/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "SessionStart": [{"hooks": [{"type": "command", "command": "bun ~/.claude/hooks/reflection-session-start.ts"}]}]
  },
  "other": true
}
EOF

    run unregister_session_start_hook
    assert_success

    run jq -r 'type' "$HOME/.claude/settings.json"
    assert_success
    assert_output "object"

    run jq -r '.other' "$HOME/.claude/settings.json"
    assert_success
    assert_output "true"

    run jq '.hooks.SessionStart | length' "$HOME/.claude/settings.json"
    assert_success
    assert_output "0"
}

@test "unregister_session_start_hook returns 0 when no entry exists" {
    load_install_functions

    echo '{"hooks": {}}' > "$HOME/.claude/settings.json"

    run unregister_session_start_hook
    assert_success
}

@test "unregister_session_start_hook returns 0 when no settings file exists" {
    load_install_functions

    rm -f "$HOME/.claude/settings.json"

    run unregister_session_start_hook
    assert_success
}

@test "unregister_session_start_hook returns 2 on malformed settings.json" {
    load_install_functions

    echo '{ this is not valid json "reflection-session-start" }' > "$HOME/.claude/settings.json"

    run unregister_session_start_hook
    [ "$status" -eq 2 ]
    assert_output --partial "Failed to parse"
}

@test "unregister_session_start_hook restores backup on parse failure" {
    load_install_functions

    local settings="$HOME/.claude/settings.json"
    echo '{ broken json reflection-session-start }' > "$settings"
    local original_content
    original_content=$(cat "$settings")

    unregister_session_start_hook || true

    # settings.json should be restored to original content
    assert_equal "$(cat "$settings")" "$original_content"
    # backup should exist
    [ -f "$settings.bak" ]
}

@test "register_session_start_hook creates entry in valid settings.json" {
    load_install_functions

    echo '{"hooks": {}}' > "$HOME/.claude/settings.json"

    run register_session_start_hook "$HOME/.claude/hooks/reflection-session-start.ts"
    assert_success
    assert_output --partial "Registered SessionStart hook"

    run grep -c "reflection-session-start" "$HOME/.claude/settings.json"
    assert_output "1"
}

@test "register_session_start_hook failure does not delete hook file" {
    load_install_functions

    local hook_file="$HOME/.claude/hooks/reflection-session-start.ts"
    echo "// existing hook" > "$hook_file"
    echo '{ broken json "reflection-session-start" }' > "$HOME/.claude/settings.json"

    run register_session_start_hook "$hook_file"
    assert_failure

    # The hook file must still exist
    [ -f "$hook_file" ]
}

# --- Full-script uninstall tests ---

@test "install.sh uninstall exits zero when SessionStart cleanup succeeds" {
    load_install_functions

    cat > "$HOME/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "SessionStart": [{"hooks": [{"type": "command", "command": "bun ~/.claude/hooks/reflection-session-start.ts"}]}]
  }
}
EOF
    touch "$HOME/.claude/hooks/reflection-session-start.ts"
    mkdir -p "$HOME/.claude/reflections"

    run env HOME="$HOME" bash "$SCRIPT_DIR/install.sh" uninstall <<< "n"
    assert_success
    assert_output --partial "Standalone uninstall complete"

    # Hook file should be gone
    [ ! -f "$HOME/.claude/hooks/reflection-session-start.ts" ]
}

@test "install.sh uninstall removes legacy reflection-stop hooks and files" {
    load_install_functions

    cat > "$HOME/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "Stop": [{"hooks": [{"type": "command", "command": "bun ~/.claude/hooks/reflection-stop.ts"}]}],
    "SessionStart": [{"hooks": [{"type": "command", "command": "bun ~/.claude/hooks/reflection-session-start.ts"}]}]
  }
}
EOF
    touch "$HOME/.claude/hooks/reflection-stop.ts"
    touch "$HOME/.claude/hooks/reflection-stop-simple.ts"
    touch "$HOME/.claude/hooks/reflection-session-start.ts"
    mkdir -p "$HOME/.claude/reflections"

    run env HOME="$HOME" bash "$SCRIPT_DIR/install.sh" uninstall <<< "n"
    assert_success
    assert_output --partial "Removed legacy Stop hook entries/files"

    run jq '[.. | strings | select(contains("reflection-stop"))] | length' "$HOME/.claude/settings.json"
    assert_success
    assert_output "0"

    [ ! -f "$HOME/.claude/hooks/reflection-stop.ts" ]
    [ ! -f "$HOME/.claude/hooks/reflection-stop-simple.ts" ]
}
