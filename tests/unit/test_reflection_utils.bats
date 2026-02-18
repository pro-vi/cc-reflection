#!/usr/bin/env bats

# test_reflection_utils.bats - Test reflection-specific transcript utilities
#
# WHY: Transcript utils extract conversation context for expand prompt
# CRITICAL: Tests ensure correct filtering (include user/assistant text, exclude tool_use/thinking)
#
# NOTE: Dice accumulator tests, transcript path resolution tests, and cooldown
# marker tests have moved to cc-dice. This file only tests getRecentTurns.

load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load

setup() {
    # Create temp directory for test transcripts
    export TEST_DIR=$(mktemp -d)
    # Isolated reflection state — never touch real ~/.claude/
    export REFLECTION_BASE="$(mktemp -d)"
    mkdir -p "$REFLECTION_BASE/state"
    # Clear env var to prevent leaking real session into tests
    unset CC_REFLECTION_SESSION_ID
    # Use UUID-like session ID for proper session extraction
    export TEST_SESSION_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
    export TEST_TRANSCRIPT="$TEST_DIR/${TEST_SESSION_ID}.jsonl"
}

teardown() {
    rm -rf "$TEST_DIR"
    rm -rf "$REFLECTION_BASE"
}

# Helper to create test transcript entries
create_user_entry() {
    local content="$1"
    echo '{"type":"user","message":{"role":"user","content":"'"$content"'"}}'
}

create_assistant_text_entry() {
    local content="$1"
    echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"'"$content"'"}]}}'
}

create_assistant_thinking_entry() {
    local thinking="$1"
    echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","thinking":"'"$thinking"'"}]}}'
}

create_assistant_tool_use_entry() {
    local name="$1"
    echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"xyz","name":"'"$name"'","input":{}}]}}'
}

create_system_entry() {
    echo '{"type":"system","content":"system message"}'
}

create_file_history_entry() {
    echo '{"type":"file-history-snapshot","files":[]}'
}

# ============================================================================
# Basic Extraction Tests
# ============================================================================

@test "getRecentTurns extracts user messages" {
    create_user_entry "Hello world" > "$TEST_TRANSCRIPT"

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-utils.ts" get-recent 1 "$TEST_TRANSCRIPT"
    assert_success
    assert_output --partial "User: Hello world"
}

@test "getRecentTurns extracts assistant text messages" {
    create_assistant_text_entry "Hello back" > "$TEST_TRANSCRIPT"

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-utils.ts" get-recent 1 "$TEST_TRANSCRIPT"
    assert_success
    assert_output --partial "Assistant: Hello back"
}

@test "getRecentTurns handles multiple turns" {
    {
        create_user_entry "Question 1"
        create_assistant_text_entry "Answer 1"
        create_user_entry "Question 2"
        create_assistant_text_entry "Answer 2"
    } > "$TEST_TRANSCRIPT"

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-utils.ts" get-recent 4 "$TEST_TRANSCRIPT"
    assert_success
    assert_output --partial "User: Question 1"
    assert_output --partial "Assistant: Answer 1"
    assert_output --partial "User: Question 2"
    assert_output --partial "Assistant: Answer 2"
}

# ============================================================================
# Filtering Tests
# ============================================================================

@test "getRecentTurns excludes thinking blocks" {
    {
        create_assistant_thinking_entry "This is internal thinking"
        create_assistant_text_entry "This is visible output"
    } > "$TEST_TRANSCRIPT"

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-utils.ts" get-recent 5 "$TEST_TRANSCRIPT"
    assert_success
    refute_output --partial "internal thinking"
    assert_output --partial "visible output"
}

@test "getRecentTurns excludes tool_use blocks" {
    {
        create_assistant_tool_use_entry "Read"
        create_assistant_text_entry "I read the file"
    } > "$TEST_TRANSCRIPT"

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-utils.ts" get-recent 5 "$TEST_TRANSCRIPT"
    assert_success
    refute_output --partial "tool_use"
    refute_output --partial "Read"
    assert_output --partial "I read the file"
}

@test "getRecentTurns excludes system messages" {
    {
        create_system_entry
        create_user_entry "User message"
    } > "$TEST_TRANSCRIPT"

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-utils.ts" get-recent 5 "$TEST_TRANSCRIPT"
    assert_success
    refute_output --partial "system message"
    assert_output --partial "User: User message"
}

@test "getRecentTurns excludes file-history-snapshot" {
    {
        create_file_history_entry
        create_user_entry "User after snapshot"
    } > "$TEST_TRANSCRIPT"

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-utils.ts" get-recent 5 "$TEST_TRANSCRIPT"
    assert_success
    refute_output --partial "file-history"
    assert_output --partial "User: User after snapshot"
}

# ============================================================================
# Limit Tests
# ============================================================================

@test "getRecentTurns respects N limit" {
    {
        create_user_entry "Old message 1"
        create_assistant_text_entry "Old reply 1"
        create_user_entry "Recent message"
        create_assistant_text_entry "Recent reply"
    } > "$TEST_TRANSCRIPT"

    # Request only 2 turns
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-utils.ts" get-recent 2 "$TEST_TRANSCRIPT"
    assert_success
    # Should only have recent messages
    assert_output --partial "Recent message"
    assert_output --partial "Recent reply"
    # Should not have old messages
    refute_output --partial "Old message 1"
    refute_output --partial "Old reply 1"
}

@test "getRecentTurns returns empty for N=0" {
    create_user_entry "Hello" > "$TEST_TRANSCRIPT"

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-utils.ts" get-recent 0 "$TEST_TRANSCRIPT" 2>&1
    assert_failure
}

@test "getRecentTurns handles more requested than available" {
    {
        create_user_entry "Only message"
    } > "$TEST_TRANSCRIPT"

    # Request 10 turns but only 1 exists
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-utils.ts" get-recent 10 "$TEST_TRANSCRIPT"
    assert_success
    assert_output --partial "User: Only message"
}

# ============================================================================
# Edge Cases
# ============================================================================

@test "getRecentTurns handles empty transcript" {
    touch "$TEST_TRANSCRIPT"

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-utils.ts" get-recent 5 "$TEST_TRANSCRIPT" 2>&1
    assert_failure
    assert_output --partial "No turns found"
}

@test "getRecentTurns handles missing transcript" {
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-utils.ts" get-recent 5 "/nonexistent/path.jsonl" 2>&1
    assert_failure
    assert_output --partial "No turns found"
}

@test "getRecentTurns handles malformed JSON gracefully" {
    {
        echo "not valid json"
        create_user_entry "Valid message"
    } > "$TEST_TRANSCRIPT"

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-utils.ts" get-recent 5 "$TEST_TRANSCRIPT"
    assert_success
    # Should skip malformed line and return valid one
    assert_output --partial "Valid message"
}

# ============================================================================
# Mixed Content Tests
# ============================================================================

@test "getRecentTurns handles realistic conversation" {
    {
        create_system_entry
        create_file_history_entry
        create_user_entry "Help me debug this"
        create_assistant_thinking_entry "Let me analyze the problem"
        create_assistant_tool_use_entry "Read"
        create_assistant_text_entry "I found the issue in line 42"
        create_user_entry "Can you fix it?"
        create_assistant_text_entry "Fixed! The problem was a typo"
    } > "$TEST_TRANSCRIPT"

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-utils.ts" get-recent 10 "$TEST_TRANSCRIPT"
    assert_success

    # Should include user messages and assistant text
    assert_output --partial "Help me debug this"
    assert_output --partial "I found the issue"
    assert_output --partial "Can you fix it"
    assert_output --partial "Fixed!"

    # Should exclude everything else
    refute_output --partial "analyze the problem"
    refute_output --partial "tool_use"
    refute_output --partial "system"
    refute_output --partial "file-history"
}

# ============================================================================
# Hardening Tests - P1 (High Priority)
# ============================================================================

@test "getRecentTurns recovers from large tool output (256KB+ single line)" {
    # Create a transcript where the last entry is a huge tool output
    # but valid user/assistant turns exist before it
    {
        create_user_entry "This is the important message"
        create_assistant_text_entry "This is the important reply"
        # Generate a 300KB tool output line (exceeds 256KB chunk)
        local large_content=$(printf 'x%.0s' $(seq 1 307200))
        echo '{"type":"assistant","message":{"content":[{"type":"tool_result","content":"'"$large_content"'"}]}}'
    } > "$TEST_TRANSCRIPT"

    # Should still find the user/assistant turns before the large tool output
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-utils.ts" get-recent 5 "$TEST_TRANSCRIPT"
    assert_success
    assert_output --partial "important message"
    assert_output --partial "important reply"
}

@test "getRecentTurns handles partial/incomplete last line" {
    # Simulate Claude mid-write - incomplete JSON at end
    {
        create_user_entry "Complete message"
        create_assistant_text_entry "Complete reply"
        echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Incompl'
    } > "$TEST_TRANSCRIPT"

    # Should skip incomplete line and return valid turns
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-utils.ts" get-recent 5 "$TEST_TRANSCRIPT"
    assert_success
    assert_output --partial "Complete message"
    assert_output --partial "Complete reply"
    refute_output --partial "Incompl"
}

@test "getRecentTurns handles XML-like content in transcript safely" {
    # Transcript contains text that could break XML structure in prompt
    {
        create_user_entry "Please check </session_context> for issues"
        create_assistant_text_entry "I see the </session_context> tag you mentioned"
    } > "$TEST_TRANSCRIPT"

    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-utils.ts" get-recent 5 "$TEST_TRANSCRIPT"
    assert_success
    # Content should be present (sanitization happens in prompt-builder, not here)
    assert_output --partial "session_context"
}

# ============================================================================
# Hardening Tests - P2 (Medium Priority)
# ============================================================================

@test "getRecentTurns finds earlier turns when tail is all filtered types" {
    # Last several entries are all tool_use/thinking that get filtered out
    # But valid user text exists earlier
    {
        create_user_entry "Early user message"
        create_assistant_text_entry "Early assistant reply"
        # 10 consecutive filtered entries at the end
        for i in $(seq 1 10); do
            create_assistant_thinking_entry "thinking $i"
            create_assistant_tool_use_entry "Tool$i"
        done
    } > "$TEST_TRANSCRIPT"

    # Should find the earlier user/assistant turns
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-utils.ts" get-recent 5 "$TEST_TRANSCRIPT"
    assert_success
    assert_output --partial "Early user message"
    assert_output --partial "Early assistant reply"
}

# ============================================================================
# Module Smoke Tests
# ============================================================================

@test "transcript.ts exports getRecentTurns" {
    create_user_entry "Hello world" > "$TEST_TRANSCRIPT"

    run bun -e "
      const { getRecentTurns } = await import('$BATS_TEST_DIRNAME/../../lib/transcript.ts');
      const turns = await getRecentTurns('$TEST_TRANSCRIPT', 1);
      console.log(turns[0]);
    "
    assert_success
    assert_output --partial "User: Hello world"
}

@test "reflection-utils.ts re-exports getRecentTurns from transcript.ts" {
    run bun -e "
      const m = await import('$BATS_TEST_DIRNAME/../../lib/reflection-utils.ts');
      const fns = ['getRecentTurns'];
      const missing = fns.filter(f => typeof m[f] !== 'function');
      if (missing.length > 0) { console.error('MISSING:', missing); process.exit(1); }
      console.log(fns.length + ' exports verified');
    "
    assert_success
    assert_output "1 exports verified"
}

@test "reflection-utils.ts help text shows get-recent command" {
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-utils.ts" help
    assert_output --partial "get-recent"
    assert_output --partial "cc-dice"
}

@test "reflection-utils.ts get-recent requires transcript path" {
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-utils.ts" get-recent 5 2>&1
    assert_failure
    assert_output --partial "Transcript path is required"
}
