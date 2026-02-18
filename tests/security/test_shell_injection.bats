#!/usr/bin/env bats

# Security Tests: Shell Injection Prevention
# Tests that malicious input is properly rejected or escaped

load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'
load '../test_helper/bats-file/load'
load '../test_helper/refute_equal'

# Setup test environment
setup() {
    export SCRIPT_DIR="$BATS_TEST_DIRNAME/../.."
    export TEST_BASE_DIR=$(mktemp -d)
    export SESSION_ID="security-test-$$"
    export SEEDS_DIR="$TEST_BASE_DIR/seeds/$SESSION_ID"
    mkdir -p "$SEEDS_DIR"
}

# Cleanup test environment
teardown() {
    if [ -d "$TEST_BASE_DIR" ]; then
        rm -rf "$TEST_BASE_DIR"
    fi
}

# ============================================================================
# TITLE VALIDATION TESTS
# ============================================================================

@test "validator: reject title with dollar sign" {
    source "$SCRIPT_DIR/lib/validators.sh"
    run validate_seed_title "Test \$(whoami) injection"
    assert_failure
    assert_output --partial "forbidden characters"
}

@test "validator: reject title with backticks" {
    source "$SCRIPT_DIR/lib/validators.sh"
    run validate_seed_title "Test \`whoami\` injection"
    assert_failure
    assert_output --partial "forbidden characters"
}

@test "validator: reject title with single quote" {
    source "$SCRIPT_DIR/lib/validators.sh"
    run validate_seed_title "Test' \$(evil) injection"
    assert_failure
    assert_output --partial "forbidden characters"
}

@test "validator: reject title with double quote" {
    source "$SCRIPT_DIR/lib/validators.sh"
    run validate_seed_title "Test\" injection"
    assert_failure
    assert_output --partial "forbidden characters"
}

@test "validator: reject title with pipe" {
    source "$SCRIPT_DIR/lib/validators.sh"
    run validate_seed_title "Test|malicious-command"
    assert_failure
    assert_output --partial "forbidden characters"
}

@test "validator: reject title with semicolon" {
    source "$SCRIPT_DIR/lib/validators.sh"
    run validate_seed_title "Test; rm -rf /"
    assert_failure
    assert_output --partial "forbidden characters"
}

@test "validator: reject title with ampersand" {
    source "$SCRIPT_DIR/lib/validators.sh"
    run validate_seed_title "Test & malicious"
    assert_failure
    assert_output --partial "forbidden characters"
}

@test "validator: reject title with backslash" {
    source "$SCRIPT_DIR/lib/validators.sh"
    run validate_seed_title "Test\\' injection"
    assert_failure
    assert_output --partial "forbidden characters"
}

@test "validator: reject title with redirection" {
    source "$SCRIPT_DIR/lib/validators.sh"
    run validate_seed_title "Test > /etc/passwd"
    assert_failure
    assert_output --partial "forbidden characters"
}

@test "validator: reject title with parentheses" {
    source "$SCRIPT_DIR/lib/validators.sh"
    run validate_seed_title "Test (subshell) injection"
    assert_failure
    assert_output --partial "forbidden characters"
}

@test "validator: reject title with braces" {
    source "$SCRIPT_DIR/lib/validators.sh"
    run validate_seed_title "Test { command; } injection"
    assert_failure
    assert_output --partial "forbidden characters"
}

@test "validator: reject empty title" {
    source "$SCRIPT_DIR/lib/validators.sh"
    run validate_seed_title ""
    assert_failure
    assert_output --partial "cannot be empty"
}

@test "validator: accept safe title" {
    source "$SCRIPT_DIR/lib/validators.sh"
    run validate_seed_title "Decision point: JWT vs OAuth trade-offs"
    assert_success
}

@test "validator: accept title with hyphens and underscores" {
    source "$SCRIPT_DIR/lib/validators.sh"
    run validate_seed_title "High churn: auth_service.ts modified 3 times"
    assert_success
}

@test "validator: accept title with numbers and special chars" {
    source "$SCRIPT_DIR/lib/validators.sh"
    run validate_seed_title "Scope expansion: 42 files modified in session!"
    assert_success
}

# ============================================================================
# STATE MANAGER VALIDATION TESTS
# ============================================================================

@test "state manager: reject seed with malicious title" {
    run bun "$SCRIPT_DIR/lib/reflection-state.ts" write \
        "Test \$(whoami) injection" \
        "rationale" \
        "file.ts" \
        "start" \
        "end"
    assert_failure
    assert_output --partial "forbidden characters"
}

@test "state manager: reject seed with pipe in title" {
    run bun "$SCRIPT_DIR/lib/reflection-state.ts" write \
        "Test|malicious-command" \
        "rationale" \
        "file.ts" \
        "start" \
        "end"
    assert_failure
    assert_output --partial "forbidden characters"
}

@test "state manager: reject seed with quote in title" {
    run bun "$SCRIPT_DIR/lib/reflection-state.ts" write \
        "Test' injection" \
        "rationale" \
        "file.ts" \
        "start" \
        "end"
    assert_failure
}

@test "state manager: reject empty title" {
    run bun "$SCRIPT_DIR/lib/reflection-state.ts" write \
        "" \
        "rationale" \
        "file.ts" \
        "start" \
        "end"
    assert_failure
    assert_output --partial "empty"
}

@test "state manager: accept safe title" {
    # Use unique title to avoid deduplication across test runs
    # Pass TEST_BASE_DIR to avoid polluting real seed directory
    run bun "$SCRIPT_DIR/lib/reflection-state.ts" --base-dir="$TEST_BASE_DIR" write \
        "Security test: Safe title validation check $$" \
        "This is a test seed with a safe title for security tests" \
        "tests/security/test_shell_injection.bats" \
        "@test safe title $$" \
        "assert_success"
    assert_success
}

# ============================================================================
# JSON LOAD VALIDATION TESTS
# ============================================================================

@test "list: skip seed with invalid ID format" {
    # Create malicious seed file directly in session directory
    cat > "$SEEDS_DIR/bad.json" <<EOF
{
  "id": "seed-123\$(whoami)abc",
  "title": "Innocent",
  "rationale": "test",
  "anchors": [],
  "priority": "med",
  "created_at": "2025-01-01T00:00:00Z",
  "ttl_hours": 2,
  "dedupe_key": "test123",
  "session_id": "$SESSION_ID"
}
EOF

    # Use CLAUDE_SESSION_ID to force same session, pass TEST_BASE_DIR
    CLAUDE_SESSION_ID="$SESSION_ID" run bun "$SCRIPT_DIR/lib/reflection-state.ts" --base-dir="$TEST_BASE_DIR" list all
    assert_success
    # Should not include the malicious seed in output
    refute_output --partial "seed-123\$(whoami)abc"
}

@test "list: skip seed with malicious title" {
    # Create seed with malicious title
    cat > "$SEEDS_DIR/evil.json" <<EOF
{
  "id": "seed-1762341091466-abc123",
  "title": "Test' \$(whoami) injection",
  "rationale": "test",
  "anchors": [],
  "priority": "med",
  "created_at": "2025-01-01T00:00:00Z",
  "ttl_hours": 2,
  "dedupe_key": "test456",
  "session_id": "$SESSION_ID"
}
EOF

    # Use CLAUDE_SESSION_ID to force same session, pass TEST_BASE_DIR
    CLAUDE_SESSION_ID="$SESSION_ID" run bun "$SCRIPT_DIR/lib/reflection-state.ts" --base-dir="$TEST_BASE_DIR" list all
    assert_success
    # Should not include the malicious title in output
    refute_output --partial "\$(whoami)"
}

@test "list: accept seed with safe title" {
    # Create valid seed file with current timestamp in seed ID (TTL uses seed ID, not created_at)
    CURRENT_TS="$(date +%s)000"
    FUTURE_DATE=$(date -u -v+1H +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "+1 hour" +"%Y-%m-%dT%H:%M:%SZ")
    cat > "$SEEDS_DIR/good.json" <<EOF
{
  "id": "seed-${CURRENT_TS}-xyz789",
  "title": "Decision point: secure authentication pattern",
  "rationale": "Need to choose between JWT and OAuth",
  "anchors": [{"path": "src/auth.ts", "context_start_text": "start", "context_end_text": "end"}],
  "priority": "med",
  "created_at": "$FUTURE_DATE",
  "ttl_hours": 2,
  "dedupe_key": "test789unique",
  "session_id": "$SESSION_ID"
}
EOF

    # Use CLAUDE_SESSION_ID to force same session, pass TEST_BASE_DIR
    CLAUDE_SESSION_ID="$SESSION_ID" run bun "$SCRIPT_DIR/lib/reflection-state.ts" --base-dir="$TEST_BASE_DIR" list all
    assert_success
    assert_output --partial "Decision point: secure authentication pattern"
}

# ============================================================================
# MENU PARSING TESTS
# ============================================================================

@test "menu parsing: pipe in title doesn't break parsing" {
    source "$SCRIPT_DIR/lib/cc-common.sh"

    # With TAB delimiter, pipes in label are perfectly fine
    menu_entry=$(printf '%s\t%s' "[REFLECT] Title with|pipe (Interactive)" "cc-reflect-expand interactive seed-123")

    run cc_parse_menu_command "$menu_entry"
    assert_success
    assert_output "cc-reflect-expand interactive seed-123"
}

@test "menu parsing: extracts command after last pipe" {
    source "$SCRIPT_DIR/lib/cc-common.sh"

    # TAB delimiter handles colons and pipes in labels
    menu_entry=$(printf '%s\t%s' "Label: with: colons" "actual-command seed-456")

    run cc_parse_menu_command "$menu_entry"
    assert_success
    assert_output "actual-command seed-456"
}
