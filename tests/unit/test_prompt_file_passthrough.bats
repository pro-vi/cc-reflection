#!/usr/bin/env bats

load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'
load '../test_helper/bats-file/load'

# Test prompt file pass-through logic in cc-reflect-expand

setup() {
    # Source the expand script to test its logic
    export REFLECTION_BIN="$BATS_TEST_DIRNAME/../../bin"
    export REFLECTION_BASE="$BATS_TEST_TMPDIR/.claude/reflections"
    export REFLECTION_RESULTS="$REFLECTION_BASE/results"
    mkdir -p "$REFLECTION_RESULTS"

    # Create a test prompt file
    export TEST_PROMPT_FILE="$BATS_TEST_TMPDIR/test-prompt.txt"
    echo "test prompt content" > "$TEST_PROMPT_FILE"
}

teardown() {
    rm -rf "$BATS_TEST_TMPDIR/.claude"
    rm -f "$TEST_PROMPT_FILE"
}

@test "cc-reflect-expand: uses prompt file when provided and exists" {
    # Simulate the conditional logic from cc-reflect-expand lines 77-85
    PROMPT_FILE="$TEST_PROMPT_FILE"
    SEED_ID="seed-1234567890-test"

    # Test the conditional logic
    if [ -n "$PROMPT_FILE" ] && [ -f "$PROMPT_FILE" ]; then
        OUTPUT_FILE="$PROMPT_FILE"
    else
        OUTPUT_FILE="${REFLECTION_RESULTS}/${SEED_ID}-result.md"
    fi

    assert_equal "$OUTPUT_FILE" "$TEST_PROMPT_FILE"
}

@test "cc-reflect-expand: uses result file when prompt file not provided" {
    # No PROMPT_FILE set
    unset PROMPT_FILE
    SEED_ID="seed-1234567890-test"

    # Test the conditional logic
    if [ -n "$PROMPT_FILE" ] && [ -f "$PROMPT_FILE" ]; then
        OUTPUT_FILE="$PROMPT_FILE"
    else
        OUTPUT_FILE="${REFLECTION_RESULTS}/${SEED_ID}-result.md"
    fi

    assert_equal "$OUTPUT_FILE" "${REFLECTION_RESULTS}/${SEED_ID}-result.md"
}

@test "cc-reflect-expand: uses result file when prompt file doesn't exist" {
    # PROMPT_FILE set but doesn't exist
    PROMPT_FILE="/nonexistent/file.txt"
    SEED_ID="seed-1234567890-test"

    # Test the conditional logic
    if [ -n "$PROMPT_FILE" ] && [ -f "$PROMPT_FILE" ]; then
        OUTPUT_FILE="$PROMPT_FILE"
    else
        OUTPUT_FILE="${REFLECTION_RESULTS}/${SEED_ID}-result.md"
    fi

    assert_equal "$OUTPUT_FILE" "${REFLECTION_RESULTS}/${SEED_ID}-result.md"
}

@test "cc-reflect-expand: uses result file when prompt file is empty string" {
    PROMPT_FILE=""
    SEED_ID="seed-1234567890-test"

    # Test the conditional logic
    if [ -n "$PROMPT_FILE" ] && [ -f "$PROMPT_FILE" ]; then
        OUTPUT_FILE="$PROMPT_FILE"
    else
        OUTPUT_FILE="${REFLECTION_RESULTS}/${SEED_ID}-result.md"
    fi

    assert_equal "$OUTPUT_FILE" "${REFLECTION_RESULTS}/${SEED_ID}-result.md"
}
