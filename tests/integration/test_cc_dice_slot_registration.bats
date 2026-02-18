#!/usr/bin/env bats

# test_cc_dice_slot_registration.bats - Verify cc-dice reflection slot install wiring
#
# WHY: Fresh installs must register the reflection slot so stop-dice can trigger /reflection.
# CRITICAL: Uses a fake HOME + fake cc-dice CLI for hermetic behavior.

load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../" && pwd)"

setup() {
    export REAL_HOME="$HOME"
    export HOME="$(mktemp -d)"
    # Hermetic PATH: only system tools + test-local bin (no host cc-dice leakage)
    export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.local/bin"
    mkdir -p "$HOME/.local/bin" "$HOME/.claude/dice"
}

teardown() {
    rm -rf "$HOME"
    export HOME="$REAL_HOME"
}

load_install_functions() {
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'

    print_success() { echo -e "${GREEN}✓${NC} $1"; }
    print_error() { echo -e "${RED}✗${NC} $1"; }
    print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
    print_info() { echo -e "${BLUE}ℹ${NC} $1"; }

    eval "$(awk '/^get_cc_dice_cli\(\)/{found=1} found{print; if(/^}$/){found=0}}' "$SCRIPT_DIR/install.sh")"
    eval "$(awk '/^register_reflection_slot\(\)/{found=1} found{print; if(/^}$/){found=0}}' "$SCRIPT_DIR/install.sh")"
}

install_fake_cc_dice() {
    cat > "$HOME/.local/bin/cc-dice" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
state_file="${HOME}/.claude/dice/test-slots.txt"
log_file="${HOME}/.claude/dice/test-calls.log"
cmd="${1:-}"
slot="${2:-}"

touch "$state_file" "$log_file"

case "$cmd" in
  status)
    grep -qx "$slot" "$state_file"
    ;;
  register)
    echo "register $*" >> "$log_file"
    if ! grep -qx "$slot" "$state_file"; then
      echo "$slot" >> "$state_file"
    fi
    ;;
  unregister)
    echo "unregister $*" >> "$log_file"
    grep -vx "$slot" "$state_file" > "${state_file}.tmp" || true
    mv "${state_file}.tmp" "$state_file"
    ;;
  *)
    exit 2
    ;;
esac
EOF
    chmod +x "$HOME/.local/bin/cc-dice"
}

@test "register_reflection_slot registers once and preserves existing slot" {
    load_install_functions
    install_fake_cc_dice

    run register_reflection_slot
    assert_success
    assert_output --partial "Registered 'reflection' slot with cc-dice"

    run grep -xc "reflection" "$HOME/.claude/dice/test-slots.txt"
    assert_success
    assert_output "1"

    run register_reflection_slot
    assert_success
    assert_output --partial "Reflection slot already registered with cc-dice"

    run grep -c "^register " "$HOME/.claude/dice/test-calls.log"
    assert_success
    assert_output "1"
}

@test "register_reflection_slot degrades gracefully when cc-dice is unavailable" {
    load_install_functions
    rm -f "$HOME/.local/bin/cc-dice"
    local old_path="$PATH"
    PATH="/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.local/bin"

    run register_reflection_slot
    assert_success
    assert_output --partial "cc-dice CLI not found. Skipping slot registration."
    PATH="$old_path"
}
