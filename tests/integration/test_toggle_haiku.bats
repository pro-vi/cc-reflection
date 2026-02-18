#!/usr/bin/env bats

# test_toggle_haiku.bats - Integration tests for model toggle functionality
#
# WHY: Ensures toggle script, bash functions, and TypeScript state manager work together correctly
# TESTS: Toggle script execution, config persistence, model flag generation

load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load

setup() {
    TEST_DIR=$(mktemp -d)
    export REFLECTION_BASE="$TEST_DIR/.claude/reflections"
    mkdir -p "$REFLECTION_BASE"
    source "$BATS_TEST_DIRNAME/../../lib/cc-common.sh"

    ORIGINAL_PWD=$(pwd)
    cd "$TEST_DIR"
}

teardown() {
    cd "$ORIGINAL_PWD"
    rm -rf "$TEST_DIR"
}

@test "toggle-haiku script exists and is executable" {
    TOGGLE_SCRIPT="$BATS_TEST_DIRNAME/../../bin/cc-reflect-toggle-haiku"
    [ -x "$TOGGLE_SCRIPT" ]
}

@test "model starts as opus by default" {
    model=$(bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" get-model)
    assert_equal "$model" "opus"
}

@test "toggle cycles opus to sonnet" {
    TOGGLE_SCRIPT="$BATS_TEST_DIRNAME/../../bin/cc-reflect-toggle-haiku"

    # Ensure starting at opus
    bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" set-model opus > /dev/null

    # Toggle: opus → sonnet
    run "$TOGGLE_SCRIPT"
    assert_success
    assert_output "sonnet"

    # Verify state changed
    model=$(bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" get-model)
    assert_equal "$model" "sonnet"
}

@test "toggle cycles sonnet to haiku" {
    bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" set-model sonnet > /dev/null

    TOGGLE_SCRIPT="$BATS_TEST_DIRNAME/../../bin/cc-reflect-toggle-haiku"
    run "$TOGGLE_SCRIPT"
    assert_success
    assert_output "haiku"

    model=$(bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" get-model)
    assert_equal "$model" "haiku"
}

@test "toggle cycles haiku back to opus" {
    bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" set-model haiku > /dev/null

    TOGGLE_SCRIPT="$BATS_TEST_DIRNAME/../../bin/cc-reflect-toggle-haiku"
    run "$TOGGLE_SCRIPT"
    assert_success
    assert_output "opus"

    model=$(bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" get-model)
    assert_equal "$model" "opus"
}

@test "model state persists in config.json" {
    CONFIG_FILE="$REFLECTION_BASE/config.json"

    # Set to haiku and verify
    bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" set-model haiku > /dev/null
    model=$(grep '"model"' "$CONFIG_FILE" | grep -o '"opus"\|"sonnet"\|"haiku"' | tr -d '"')
    assert_equal "$model" "haiku"

    # Set to opus and verify
    bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" set-model opus > /dev/null
    model=$(grep '"model"' "$CONFIG_FILE" | grep -o '"opus"\|"sonnet"\|"haiku"' | tr -d '"')
    assert_equal "$model" "opus"
}

@test "TypeScript set-model validates input" {
    run bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" set-model invalid
    assert_failure
    assert_output --partial "Invalid model"
}

@test "TypeScript get-model returns valid model names" {
    for m in opus sonnet haiku; do
        bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" set-model "$m" > /dev/null
        model=$(bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" get-model)
        assert_equal "$model" "$m"
    done
}

@test "cc_get_model_flag returns correct flag" {
    # Opus: explicit flag
    bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" set-model opus > /dev/null
    flag=$(cc_get_model_flag)
    assert_equal "$flag" "--model opus"

    # Sonnet: empty (CLI default)
    bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" set-model sonnet > /dev/null
    flag=$(cc_get_model_flag)
    assert_equal "$flag" ""

    # Haiku: explicit flag
    bun "$BATS_TEST_DIRNAME/../../lib/reflection-state.ts" set-model haiku > /dev/null
    flag=$(cc_get_model_flag)
    assert_equal "$flag" "--model haiku"

}
