#!/usr/bin/env bats
# Test that all Claude CLI invocations use centralized flag getters

load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'

# ============================================================================
# CRITICAL: Verify all Claude invocations use centralized flags
# ============================================================================
#
# These tests ensure that no Claude invocation is missing MODEL_FLAG or
# PERMISSIONS_FLAG. This prevents incidents where new invocations forget
# to respect user's toggle settings.
#
# If these tests fail, it means a Claude invocation was added or modified
# without using the centralized flag getters.

@test "bin/cc-reflect: all Claude invocations use MODEL_FLAG" {
    # Find all lines containing 'claude' command
    # Should all include $MODEL_FLAG or \$MODEL_FLAG (escaped for tmux)
    run grep -n 'claude ' bin/cc-reflect
    assert_success

    # Extract lines that invoke claude
    claude_lines=$(echo "$output" | grep -E 'claude[[:space:]]' | grep -v '^[[:space:]]*#')

    # Each line should contain either $MODEL_FLAG or \$MODEL_FLAG
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            line_num=$(echo "$line" | cut -d: -f1)
            line_content=$(echo "$line" | cut -d: -f2-)

            # Skip comment lines
            if echo "$line_content" | grep -q '^[[:space:]]*#'; then
                continue
            fi

            # Verify MODEL_FLAG is present
            if ! echo "$line_content" | grep -qE '(\$MODEL_FLAG|\\$MODEL_FLAG)'; then
                echo "Line $line_num missing MODEL_FLAG: $line_content" >&2
                return 1
            fi
        fi
    done <<< "$claude_lines"
}

@test "bin/cc-reflect: all Claude invocations use PERMISSIONS_FLAG" {
    run grep -n 'claude ' bin/cc-reflect
    assert_success

    claude_lines=$(echo "$output" | grep -E 'claude[[:space:]]' | grep -v '^[[:space:]]*#')

    while IFS= read -r line; do
        if [ -n "$line" ]; then
            line_num=$(echo "$line" | cut -d: -f1)
            line_content=$(echo "$line" | cut -d: -f2-)

            # Skip comment lines
            if echo "$line_content" | grep -q '^[[:space:]]*#'; then
                continue
            fi

            # Verify PERMISSIONS_FLAG is present
            if ! echo "$line_content" | grep -qE '(\$PERMISSIONS_FLAG|\\$PERMISSIONS_FLAG)'; then
                echo "Line $line_num missing PERMISSIONS_FLAG: $line_content" >&2
                return 1
            fi
        fi
    done <<< "$claude_lines"
}

@test "bin/cc-reflect-expand: all Claude invocations use MODEL_FLAG" {
    run grep -n 'claude ' bin/cc-reflect-expand
    assert_success

    claude_lines=$(echo "$output" | grep -E 'claude[[:space:]]' | grep -v '^[[:space:]]*#')

    while IFS= read -r line; do
        if [ -n "$line" ]; then
            line_num=$(echo "$line" | cut -d: -f1)
            line_content=$(echo "$line" | cut -d: -f2-)

            # Skip comment lines
            if echo "$line_content" | grep -q '^[[:space:]]*#'; then
                continue
            fi

            # Skip log lines (cc_log_info, cc_log_debug, echo, etc.)
            if echo "$line_content" | grep -qE '(cc_log_|echo )'; then
                continue
            fi

            # Verify MODEL_FLAG is present
            if ! echo "$line_content" | grep -qE '(\$MODEL_FLAG|\\$MODEL_FLAG|'"'"'\$MODEL_FLAG)'; then
                echo "Line $line_num missing MODEL_FLAG: $line_content" >&2
                return 1
            fi
        fi
    done <<< "$claude_lines"
}

@test "bin/cc-reflect-expand: all Claude invocations use PERMISSIONS_FLAG" {
    run grep -n 'claude ' bin/cc-reflect-expand
    assert_success

    claude_lines=$(echo "$output" | grep -E 'claude[[:space:]]' | grep -v '^[[:space:]]*#')

    while IFS= read -r line; do
        if [ -n "$line" ]; then
            line_num=$(echo "$line" | cut -d: -f1)
            line_content=$(echo "$line" | cut -d: -f2-)

            # Skip comment lines
            if echo "$line_content" | grep -q '^[[:space:]]*#'; then
                continue
            fi

            # Skip log lines (cc_log_info, cc_log_debug, echo, etc.)
            if echo "$line_content" | grep -qE '(cc_log_|echo )'; then
                continue
            fi

            # Verify PERMISSIONS_FLAG is present
            if ! echo "$line_content" | grep -qE '(\$PERMISSIONS_FLAG|\\$PERMISSIONS_FLAG|'"'"'\$PERMISSIONS_FLAG)'; then
                echo "Line $line_num missing PERMISSIONS_FLAG: $line_content" >&2
                return 1
            fi
        fi
    done <<< "$claude_lines"
}

@test "bin/cc-reflect: verify exact count of Claude invocations" {
    # According to documentation in lib/cc-common.sh, there should be 2 invocations in cc-reflect
    # Lines 149 and 167

    run grep -n 'claude ' bin/cc-reflect
    assert_success

    # Count non-comment lines containing 'claude '
    count=$(echo "$output" | grep -E 'claude[[:space:]]' | grep -v '^[[:space:]]*#' | wc -l)
    count=$(echo "$count" | tr -d '[:space:]')

    # Should have exactly 2 invocations
    assert_equal "$count" "2"
}

@test "bin/cc-reflect-expand: verify exact count of Claude invocations" {
    # According to current implementation:
    # - Interactive mode: 2 invocations (ORIGINAL_TMUX + current TMUX branches)
    # - Auto mode: 1 invocation (claude -p)
    # Total: 3 invocations

    run grep -n 'claude ' bin/cc-reflect-expand
    assert_success

    # Count non-comment, non-log lines containing 'claude '
    # Filter: lines after the colon that start with # (comments)
    count=$(echo "$output" | grep -E 'claude[[:space:]]' | grep -vE ':[[:space:]]*#' | grep -vE '(cc_log_|echo )' | wc -l)
    count=$(echo "$count" | tr -d '[:space:]')

    # Should have exactly 3 invocations
    assert_equal "$count" "3"
}

@test "verify total Claude invocation count matches implementation" {
    # Current implementation:
    # - cc-reflect: 2 invocations (enhance commands)
    # - cc-reflect-expand: 3 invocations (2 interactive + 1 auto)
    # Total: 5 invocations

    cc_reflect_count=$(grep -nE 'claude[[:space:]]' bin/cc-reflect | grep -vE ':[[:space:]]*#' | grep -vE '(cc_log_|echo )' | wc -l | tr -d '[:space:]')
    cc_expand_count=$(grep -nE 'claude[[:space:]]' bin/cc-reflect-expand | grep -vE ':[[:space:]]*#' | grep -vE '(cc_log_|echo )' | wc -l | tr -d '[:space:]')

    total=$((cc_reflect_count + cc_expand_count))

    assert_equal "$total" "5"
}

@test "grep audit: MODEL_FLAG usage" {
    # This test documents the grep command for manual auditing
    # Should find all 5 invocation sites

    run bash -c "grep -n '\$MODEL_FLAG' bin/cc-reflect bin/cc-reflect-expand | wc -l"
    assert_success

    count=$(echo "$output" | tr -d '[:space:]')

    # Should find at least 5 references (one per invocation site)
    # May find more due to variable assignments
    [ "$count" -ge 5 ]
}

@test "grep audit: PERMISSIONS_FLAG usage" {
    # This test documents the grep command for manual auditing
    # Should find all 5 invocation sites

    run bash -c "grep -n '\$PERMISSIONS_FLAG' bin/cc-reflect bin/cc-reflect-expand | wc -l"
    assert_success

    count=$(echo "$output" | tr -d '[:space:]')

    # Should find at least 5 references (one per invocation site)
    # May find more due to variable assignments
    [ "$count" -ge 5 ]
}

@test "verify flags are retrieved inside tmux session block in cc-reflect" {
    # Lines 154-155 and 165-166 should retrieve flags INSIDE the tmux session block
    # This is critical because flags need to be fresh, not stale from outside

    # Look for the escaped pattern: MODEL_FLAG=\$(cc_get_model_flag)
    run bash -c "grep 'MODEL_FLAG.*cc_get_model_flag' bin/cc-reflect | grep '\\\\' | wc -l"
    assert_success
    # Should find at least 2 (one for each enhance command)
    [ "$output" -ge 2 ]

    run bash -c "grep 'PERMISSIONS_FLAG.*cc_get_permissions_flag' bin/cc-reflect | grep '\\\\' | wc -l"
    assert_success
    # Should find at least 2 (one for each enhance command)
    [ "$output" -ge 2 ]
}

@test "verify flags are retrieved at startup in cc-reflect-expand" {
    # cc-reflect-expand retrieves flags at script startup (lines 55-61)
    # before spawning tmux sessions

    run grep -n 'cc_get_model_flag\|cc_get_permissions_flag' bin/cc-reflect-expand
    assert_success

    # Should have exactly 2 calls (one for each flag)
    count=$(echo "$output" | wc -l | tr -d '[:space:]')
    assert_equal "$count" "2"
}

@test "no hardcoded model specifications" {
    # Verify no claude invocations use hardcoded --model values
    # All should use $MODEL_FLAG

    # Look for patterns like 'claude --model sonnet' or 'claude --model haiku'
    # Should NOT find any (all should use $MODEL_FLAG)

    run grep -E 'claude[[:space:]].*--model[[:space:]]+(sonnet|haiku|opus)' bin/cc-reflect bin/cc-reflect-expand

    # Should fail to find any hardcoded models
    assert_failure
}

@test "no hardcoded permissions flags" {
    # Verify no claude invocations use hardcoded --dangerously-skip-permissions
    # All should use $PERMISSIONS_FLAG

    # Look for hardcoded flag (not via variable)
    # Exclude lines that are part of flag variable definitions

    run bash -c "grep 'claude ' bin/cc-reflect bin/cc-reflect-expand | grep -v '\$PERMISSIONS_FLAG' | grep -- '--dangerously-skip-permissions'"

    # Should fail to find any hardcoded permissions flags
    assert_failure
}

@test "enhancement commands pass FILE environment variable to Claude" {
    # REGRESSION TEST: Verify FILE is passed through to enhancement Claude processes
    #
    # Context: The prompt builder expects $FILE to be available (see lib/prompt-builder.sh:68),
    # but after refactoring to modular prompts (commit f5fcd2c), the FILE variable was no
    # longer passed through to the new tmux windows spawned by enhancement commands.
    #
    # This test prevents regression by ensuring all enhancement invocations include FILE=

    # Interactive enhancement: should have FILE='$FILE' before claude command
    run grep "claude-spawn-interactive" -A 15 bin/cc-reflect
    assert_success
    # Look for the tmux send-keys line with FILE= prefix before claude
    echo "$output" | grep -q "FILE=.*claude.*MODEL_FLAG"

    # Auto enhancement: should have FILE='$FILE' before claude command
    run grep "claude-enhance-auto" -A 10 bin/cc-reflect
    assert_success
    # Look for the claude -p line with FILE= prefix
    echo "$output" | grep -q "FILE=.*claude -p"
}
