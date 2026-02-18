#!/usr/bin/env bats
# Unit tests for install.sh hook configuration logic
# Tests jq commands and hook format without touching real settings

load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'

setup() {
    # Create temp directory for test files
    TEST_DIR=$(mktemp -d)
    TEST_SETTINGS="$TEST_DIR/settings.json"
    TEST_HOOK="$TEST_DIR/reflection-stop.ts"

    # Create mock hook file
    echo '// mock hook' > "$TEST_HOOK"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# ============================================================================
# HOOK FORMAT TESTS
# ============================================================================

@test "hook object has correct structure" {
    # This is the format install.sh should produce
    local hook_obj='{"hooks": [{"type": "command", "command": "bun /path/to/hook.ts"}]}'

    # Validate it's valid JSON
    run bash -c "echo '$hook_obj' | jq '.'"
    assert_success

    # Check structure
    run bash -c "echo '$hook_obj' | jq -r '.hooks[0].type'"
    assert_output "command"

    run bash -c "echo '$hook_obj' | jq -r '.hooks[0].command'"
    assert_output "bun /path/to/hook.ts"
}

@test "hook object matches Claude Code new format" {
    local hook_obj='{"hooks": [{"type": "command", "command": "bun ~/.claude/hooks/reflection-stop.ts"}]}'

    # Must have .hooks array
    run bash -c "echo '$hook_obj' | jq 'has(\"hooks\")'"
    assert_output "true"

    # hooks must be array
    run bash -c "echo '$hook_obj' | jq '.hooks | type'"
    assert_output '"array"'

    # Each hook must have type and command
    run bash -c "echo '$hook_obj' | jq '.hooks[0] | has(\"type\") and has(\"command\")'"
    assert_output "true"
}

# ============================================================================
# FRESH INSTALL (no existing settings.json)
# ============================================================================

@test "creates settings.json with Stop hook when file doesn't exist" {
    # Simulate fresh install - no settings.json
    [ ! -f "$TEST_SETTINGS" ]

    # Create minimal settings with Stop hook (simulating install.sh logic)
    cat > "$TEST_SETTINGS" << 'EOF'
{
  "hooks": {
    "Stop": [{"hooks": [{"type": "command", "command": "bun ~/.claude/hooks/reflection-stop.ts"}]}]
  }
}
EOF

    # Verify structure
    run jq -r '.hooks.Stop[0].hooks[0].command' "$TEST_SETTINGS"
    assert_output "bun ~/.claude/hooks/reflection-stop.ts"
}

# ============================================================================
# EXISTING SETTINGS WITHOUT HOOKS
# ============================================================================

@test "adds hooks section to settings without hooks" {
    # Settings with other config but no hooks
    cat > "$TEST_SETTINGS" << 'EOF'
{
  "theme": "dark",
  "model": "sonnet"
}
EOF

    local hook_obj='{"hooks": [{"type": "command", "command": "bun ~/.claude/hooks/reflection-stop.ts"}]}'

    # Add hooks section with Stop hook
    run jq --argjson hook "$hook_obj" '.hooks.Stop = [$hook]' "$TEST_SETTINGS"
    assert_success

    # Verify original settings preserved
    result=$(echo "$output" | jq -r '.theme')
    [ "$result" = "dark" ]

    # Verify hook added
    result=$(echo "$output" | jq -r '.hooks.Stop[0].hooks[0].command')
    [ "$result" = "bun ~/.claude/hooks/reflection-stop.ts" ]
}

# ============================================================================
# EXISTING SETTINGS WITH OTHER HOOKS
# ============================================================================

@test "appends Stop hook to existing hooks section" {
    # Settings with existing hooks but no Stop
    cat > "$TEST_SETTINGS" << 'EOF'
{
  "hooks": {
    "SessionStart": [{"hooks": [{"type": "command", "command": "bun ~/.claude/hooks/session.ts"}]}]
  }
}
EOF

    local hook_obj='{"hooks": [{"type": "command", "command": "bun ~/.claude/hooks/reflection-stop.ts"}]}'

    # Add Stop hook (simulating install.sh logic)
    run jq --argjson hook "$hook_obj" '.hooks.Stop = [$hook]' "$TEST_SETTINGS"
    assert_success

    # Verify existing hook preserved
    result=$(echo "$output" | jq -r '.hooks.SessionStart[0].hooks[0].command')
    [ "$result" = "bun ~/.claude/hooks/session.ts" ]

    # Verify new hook added
    result=$(echo "$output" | jq -r '.hooks.Stop[0].hooks[0].command')
    [ "$result" = "bun ~/.claude/hooks/reflection-stop.ts" ]
}

@test "appends to existing Stop hooks array" {
    # Settings with existing Stop hook
    cat > "$TEST_SETTINGS" << 'EOF'
{
  "hooks": {
    "Stop": [{"hooks": [{"type": "command", "command": "bun ~/.claude/hooks/other-stop.ts"}]}]
  }
}
EOF

    local hook_obj='{"hooks": [{"type": "command", "command": "bun ~/.claude/hooks/reflection-stop.ts"}]}'

    # Append to Stop array (not replace)
    run jq --argjson hook "$hook_obj" '.hooks.Stop = .hooks.Stop + [$hook]' "$TEST_SETTINGS"
    assert_success

    # Verify original Stop hook preserved
    result=$(echo "$output" | jq -r '.hooks.Stop[0].hooks[0].command')
    [ "$result" = "bun ~/.claude/hooks/other-stop.ts" ]

    # Verify new hook appended
    result=$(echo "$output" | jq -r '.hooks.Stop[1].hooks[0].command')
    [ "$result" = "bun ~/.claude/hooks/reflection-stop.ts" ]

    # Verify array length
    result=$(echo "$output" | jq '.hooks.Stop | length')
    [ "$result" = "2" ]
}

# ============================================================================
# IDEMPOTENCY (don't add duplicate hooks)
# ============================================================================

@test "detects existing reflection-stop hook" {
    # Settings with reflection-stop already configured
    cat > "$TEST_SETTINGS" << 'EOF'
{
  "hooks": {
    "Stop": [{"hooks": [{"type": "command", "command": "bun ~/.claude/hooks/reflection-stop.ts"}]}]
  }
}
EOF

    # Check if hook already exists
    run bash -c "grep -q 'reflection-stop' '$TEST_SETTINGS' && echo 'exists' || echo 'not found'"
    assert_output "exists"
}

@test "conditional add only when hook missing" {
    # Settings without reflection-stop
    cat > "$TEST_SETTINGS" << 'EOF'
{
  "hooks": {
    "Stop": [{"hooks": [{"type": "command", "command": "bun ~/.claude/hooks/other.ts"}]}]
  }
}
EOF

    local hook_obj='{"hooks": [{"type": "command", "command": "bun ~/.claude/hooks/reflection-stop.ts"}]}'

    # Conditional add (simulating install.sh check)
    if ! grep -q "reflection-stop" "$TEST_SETTINGS" 2>/dev/null; then
        jq --argjson hook "$hook_obj" '.hooks.Stop = .hooks.Stop + [$hook]' "$TEST_SETTINGS" > "${TEST_SETTINGS}.new"
        mv "${TEST_SETTINGS}.new" "$TEST_SETTINGS"
    fi

    # Verify hook was added
    run jq -r '.hooks.Stop | length' "$TEST_SETTINGS"
    assert_output "2"
}

@test "skip add when hook already present" {
    # Settings with reflection-stop already configured
    cat > "$TEST_SETTINGS" << 'EOF'
{
  "hooks": {
    "Stop": [{"hooks": [{"type": "command", "command": "bun ~/.claude/hooks/reflection-stop.ts"}]}]
  }
}
EOF

    local hook_obj='{"hooks": [{"type": "command", "command": "bun ~/.claude/hooks/reflection-stop.ts"}]}'
    local original_length=$(jq '.hooks.Stop | length' "$TEST_SETTINGS")

    # Conditional add (simulating install.sh check)
    if ! grep -q "reflection-stop" "$TEST_SETTINGS" 2>/dev/null; then
        jq --argjson hook "$hook_obj" '.hooks.Stop = .hooks.Stop + [$hook]' "$TEST_SETTINGS" > "${TEST_SETTINGS}.new"
        mv "${TEST_SETTINGS}.new" "$TEST_SETTINGS"
    fi

    # Verify hook was NOT added again
    run jq -r '.hooks.Stop | length' "$TEST_SETTINGS"
    assert_output "$original_length"
}

# ============================================================================
# EDGE CASES
# ============================================================================

@test "handles empty hooks object" {
    cat > "$TEST_SETTINGS" << 'EOF'
{
  "hooks": {}
}
EOF

    local hook_obj='{"hooks": [{"type": "command", "command": "bun ~/.claude/hooks/reflection-stop.ts"}]}'

    run jq --argjson hook "$hook_obj" '.hooks.Stop = [$hook]' "$TEST_SETTINGS"
    assert_success

    result=$(echo "$output" | jq -r '.hooks.Stop[0].hooks[0].command')
    [ "$result" = "bun ~/.claude/hooks/reflection-stop.ts" ]
}

@test "handles null hooks.Stop" {
    cat > "$TEST_SETTINGS" << 'EOF'
{
  "hooks": {
    "Stop": null
  }
}
EOF

    local hook_obj='{"hooks": [{"type": "command", "command": "bun ~/.claude/hooks/reflection-stop.ts"}]}'

    # Use conditional to handle null
    run jq --argjson hook "$hook_obj" '
        .hooks.Stop = (
            if .hooks.Stop then
                .hooks.Stop + [$hook]
            else
                [$hook]
            end
        )
    ' "$TEST_SETTINGS"
    assert_success

    result=$(echo "$output" | jq -r '.hooks.Stop[0].hooks[0].command')
    [ "$result" = "bun ~/.claude/hooks/reflection-stop.ts" ]
}

@test "preserves complex existing configuration" {
    # Real-world-like settings with multiple hook types
    cat > "$TEST_SETTINGS" << 'EOF'
{
  "theme": "dark",
  "hooks": {
    "UserPromptSubmit": [
      {"hooks": [{"type": "command", "command": "bun ~/.claude/hooks/iching.ts", "timeout": 5000}]}
    ],
    "PreToolUse": [
      {"matcher": "*", "hooks": [{"type": "command", "command": "bun ~/.claude/hooks/pre.ts"}]},
      {"matcher": "Write|Edit", "hooks": [{"type": "command", "command": "prov capture --pre"}]}
    ],
    "Stop": [
      {"hooks": [{"type": "command", "command": "bun ~/.claude/hooks/stop-dice.ts"}]}
    ]
  },
  "model": "opus"
}
EOF

    local hook_obj='{"hooks": [{"type": "command", "command": "bun ~/.claude/hooks/reflection-stop.ts"}]}'

    run jq --argjson hook "$hook_obj" '.hooks.Stop = .hooks.Stop + [$hook]' "$TEST_SETTINGS"
    assert_success

    # Verify all existing config preserved
    result=$(echo "$output" | jq -r '.theme')
    [ "$result" = "dark" ]

    result=$(echo "$output" | jq -r '.model')
    [ "$result" = "opus" ]

    result=$(echo "$output" | jq -r '.hooks.UserPromptSubmit[0].hooks[0].command')
    [ "$result" = "bun ~/.claude/hooks/iching.ts" ]

    result=$(echo "$output" | jq '.hooks.PreToolUse | length')
    [ "$result" = "2" ]

    # Verify new hook appended
    result=$(echo "$output" | jq '.hooks.Stop | length')
    [ "$result" = "2" ]

    result=$(echo "$output" | jq -r '.hooks.Stop[1].hooks[0].command')
    [ "$result" = "bun ~/.claude/hooks/reflection-stop.ts" ]
}

# ============================================================================
# OLD FORMAT DETECTION (should not produce)
# ============================================================================

@test "does not produce old string array format" {
    cat > "$TEST_SETTINGS" << 'EOF'
{"hooks": {}}
EOF

    local hook_obj='{"hooks": [{"type": "command", "command": "bun ~/.claude/hooks/reflection-stop.ts"}]}'

    result=$(jq --argjson hook "$hook_obj" '.hooks.Stop = [$hook]' "$TEST_SETTINGS")

    # Should NOT be a string array (old format)
    # Old format: .hooks.Stop[0] is a string like "bun ..."
    # New format: .hooks.Stop[0] is an object with .hooks array
    run bash -c "echo '$result' | jq '.hooks.Stop[0] | type'"
    assert_output '"object"'

    # Verify it has the .hooks nested structure (new format requirement)
    run bash -c "echo '$result' | jq '.hooks.Stop[0] | has(\"hooks\")'"
    assert_output "true"
}

@test "rejects old format in test validation" {
    # Old format that should NOT be used
    local old_format='["bun ~/.claude/hooks/reflection-stop.ts"]'

    # This is NOT valid new format - hooks should be objects with .hooks array
    run bash -c "echo '$old_format' | jq '.[0] | type'"
    assert_output '"string"'  # Old format has strings directly

    # New format has objects
    local new_format='[{"hooks": [{"type": "command", "command": "bun ~/.claude/hooks/reflection-stop.ts"}]}]'
    run bash -c "echo '$new_format' | jq '.[0] | type'"
    assert_output '"object"'  # New format has objects
}
