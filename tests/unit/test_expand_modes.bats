#!/usr/bin/env bats

# Unit tests for cc-reflect-expand modes (interactive vs auto)

load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'

setup() {
    export REFLECTION_BASE="$(mktemp -d)"
    # Load shared utilities
    source "${BATS_TEST_DIRNAME}/../../lib/cc-common.sh"

    # Create temp directory for test
    TEST_DIR="${BATS_TEST_TMPDIR}/expand-modes-test"
    mkdir -p "$TEST_DIR"

    # Create mock seed file
    SESSION_ID=$(echo -n "$TEST_DIR" | md5sum | cut -d' ' -f1)
    SEED_DIR="$REFLECTION_BASE/seeds/${SESSION_ID}"
    mkdir -p "$SEED_DIR"

    SEED_ID="seed-1234567890-test1"
    cat > "$SEED_DIR/${SEED_ID}.json" <<'EOF'
{
  "id": "seed-1234567890-test1",
  "title": "Test seed for mode verification",
  "rationale": "Testing interactive vs auto mode behavior",
  "anchors": [],
  "options_hint": "test",
  "ttl_hours": 1,
  "created_at": "2025-11-07T00:00:00Z",
  "session_id": "test-session"
}
EOF

    # Create mock tmux (for testing outside tmux)
    export TMUX="fake-tmux-session"
    export ORIGINAL_TMUX="fake-original-tmux"
}

teardown() {
    rm -rf "$TEST_DIR"
    rm -rf "$REFLECTION_BASE"
}

@test "Interactive mode uses --append-system-prompt (not -p)" {
    # This test verifies the command structure, not actual execution

    # Read the expand script
    EXPAND_SCRIPT="${BATS_TEST_DIRNAME}/../../bin/cc-reflect-expand"

    # Verify interactive mode doesn't use -p flag
    run grep -A 5 'if \[ "$MODE" = "interactive" \]' "$EXPAND_SCRIPT"
    assert_success

    # Should use --append-system-prompt (with optional model and permissions flags)
    run grep 'claude.*--append-system-prompt' "$EXPAND_SCRIPT"
    assert_success

    # Interactive section should NOT contain -p
    run bash -c "sed -n '/if \[ \"\$MODE\" = \"interactive\" \]/,/else/p' '$EXPAND_SCRIPT' | grep -q 'claude -p'"
    assert_failure
}

@test "Auto mode uses tmux with -p flag and --append-system-prompt" {
    # Read the expand script
    EXPAND_SCRIPT="${BATS_TEST_DIRNAME}/../../bin/cc-reflect-expand"

    # Auto mode should use --append-system-prompt like interactive
    run bash -c "sed -n '/# Auto mode/,/^fi$/p' '$EXPAND_SCRIPT' | grep -q 'append-system-prompt'"
    assert_success

    # Should use -p flag to auto-execute
    run bash -c "sed -n '/# Auto mode/,/^fi$/p' '$EXPAND_SCRIPT' | grep -q 'claude.*-p'"
    assert_success
}

@test "Both modes spawn tmux windows for visibility" {
    EXPAND_SCRIPT="${BATS_TEST_DIRNAME}/../../bin/cc-reflect-expand"

    # Interactive mode should spawn tmux window
    run bash -c "sed -n '/if \[ \"\$MODE\" = \"interactive\" \]/,/^else$/p' '$EXPAND_SCRIPT' | grep -q 'tmux new-window'"
    assert_success

    # Auto mode should also spawn tmux window
    run bash -c "sed -n '/# Auto mode/,/^fi$/p' '$EXPAND_SCRIPT' | grep -q 'tmux new-window'"
    assert_success
}

@test "Ctrl-G flow writes to prompt file" {
    EXPAND_SCRIPT="${BATS_TEST_DIRNAME}/../../bin/cc-reflect-expand"

    # Check the OUTPUT_FILE logic
    run bash -c "grep -A 3 'if \[ -n \"\$PROMPT_FILE\" \]' '$EXPAND_SCRIPT'"
    assert_success
    assert_output --partial 'OUTPUT_FILE="$PROMPT_FILE"'
}

@test "Standalone flow writes to result file" {
    EXPAND_SCRIPT="${BATS_TEST_DIRNAME}/../../bin/cc-reflect-expand"

    # Check the else branch
    run bash -c "grep -A 5 'if \[ -n \"\$PROMPT_FILE\" \]' '$EXPAND_SCRIPT' | grep -A 2 'else'"
    assert_success
    assert_output --partial 'REFLECTION_RESULTS'
}

@test "Auto mode uses modular prompt builder" {
    EXPAND_SCRIPT="${BATS_TEST_DIRNAME}/../../bin/cc-reflect-expand"

    # Should use build_system_prompt with expand-auto mode
    run bash -c "grep -q 'build_system_prompt expand-auto' '$EXPAND_SCRIPT'"
    assert_success

    # Should source the prompt-builder.sh library
    run bash -c "grep -q 'prompt-builder.sh' '$EXPAND_SCRIPT'"
    assert_success
}

@test "Interactive mode uses modular prompt builder" {
    EXPAND_SCRIPT="${BATS_TEST_DIRNAME}/../../bin/cc-reflect-expand"

    # Should use build_system_prompt with expand-interactive mode
    run bash -c "grep -q 'build_system_prompt expand-interactive' '$EXPAND_SCRIPT'"
    assert_success

    # Should pass OUTPUT_FILE parameter to builder
    run bash -c "grep 'build_system_prompt expand-interactive.*OUTPUT_FILE' '$EXPAND_SCRIPT'"
    assert_success
}
