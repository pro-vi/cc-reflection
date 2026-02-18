#!/usr/bin/env bats
# Unit tests for lib/prompt-builder.sh - modular system prompt builder

load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'

setup() {
    # Source the prompt builder
    source "${BATS_TEST_DIRNAME}/../../lib/prompt-builder.sh"
}

# ============================================================================
# BASIC FUNCTIONALITY
# ============================================================================

@test "prompt-builder.sh can be sourced without errors" {
    run bash -c "source lib/prompt-builder.sh"
    assert_success
}

@test "build_system_prompt function exists" {
    run bash -c "source lib/prompt-builder.sh && type build_system_prompt"
    assert_success
    assert_output --partial 'build_system_prompt is a function'
}

# ============================================================================
# HARDENING BLOCKS (isolated tests)
# ============================================================================

@test "_mission_contract includes output file" {
    source "${BATS_TEST_DIRNAME}/../../lib/prompt-builder.sh"
    result=$(_mission_contract "/tmp/test.md" "test")
    [[ "$result" == *"/tmp/test.md"* ]]
    [[ "$result" == *"MISSION CONTRACT"* ]]
}

@test "_mission_contract includes agent role" {
    source "${BATS_TEST_DIRNAME}/../../lib/prompt-builder.sh"
    result=$(_mission_contract "/tmp/test.md" "prompt enhancement")
    [[ "$result" == *"prompt enhancement"* ]]
    [[ "$result" == *"file-writing"* ]]
}

@test "_mission_contract includes success definition" {
    source "${BATS_TEST_DIRNAME}/../../lib/prompt-builder.sh"
    result=$(_mission_contract "/tmp/out.md" "test")
    [[ "$result" == *"session succeeds when"* ]]
    [[ "$result" == *"Investigation without output is failure"* ]]
}

@test "_never_constraints includes all NEVER rules" {
    source "${BATS_TEST_DIRNAME}/../../lib/prompt-builder.sh"
    result=$(_never_constraints)
    [[ "$result" == *"NEVER"* ]]
    [[ "$result" == *"invent file paths"* ]]
    [[ "$result" == *"add scope"* ]]
    [[ "$result" == *"guess at code structure"* ]]
}

@test "_never_constraints includes self-sufficiency bias" {
    source "${BATS_TEST_DIRNAME}/../../lib/prompt-builder.sh"
    result=$(_never_constraints)
    [[ "$result" == *"self-sufficiency"* ]]
}

@test "_verification_gate includes checklist" {
    source "${BATS_TEST_DIRNAME}/../../lib/prompt-builder.sh"
    result=$(_verification_gate "/tmp/out.md")
    [[ "$result" == *"[ ]"* ]]  # Has checkboxes
    [[ "$result" == *"/tmp/out.md"* ]]
}

@test "_verification_gate includes all verification items" {
    source "${BATS_TEST_DIRNAME}/../../lib/prompt-builder.sh"
    result=$(_verification_gate "/tmp/out.md")
    [[ "$result" == *"exists and contains"* ]]
    [[ "$result" == *"file paths mentioned"* ]]
    [[ "$result" == *"Original intent preserved"* ]]
    [[ "$result" == *"Success criteria"* ]]
}

@test "_verification_gate includes MANDATORY label" {
    source "${BATS_TEST_DIRNAME}/../../lib/prompt-builder.sh"
    result=$(_verification_gate "/tmp/out.md")
    [[ "$result" == *"MANDATORY"* ]]
}

# ============================================================================
# ENHANCE MODES
# ============================================================================

@test "enhance-interactive generates valid prompt" {
    run build_system_prompt enhance-interactive
    assert_success

    # Should contain core sections
    assert_output --partial 'file-writing prompt enhancement agent'
    assert_output --partial '$FILE'
    assert_output --partial 'Investigation Guidelines'
    assert_output --partial 'Output Format'
    assert_output --partial 'Validation Rules'
}

@test "enhance-interactive includes interactive style" {
    run build_system_prompt enhance-interactive
    assert_success

    # Should indicate interactive mode
    assert_output --partial 'Interactive'
    assert_output --partial 'interactive session'
}

@test "enhance-auto generates valid prompt" {
    run build_system_prompt enhance-auto
    assert_success

    # Should contain core sections
    assert_output --partial 'file-writing prompt enhancement agent'
    assert_output --partial '$FILE'
    assert_output --partial 'Investigation Guidelines'
}

@test "enhance-auto includes auto-execute style" {
    run build_system_prompt enhance-auto
    assert_success

    # Should indicate auto mode
    assert_output --partial 'Auto-execute'
    assert_output --partial 'non-interactive'
    assert_output --partial 'Done'
}

@test "enhance modes now include mission contract" {
    run build_system_prompt enhance-auto
    assert_success
    assert_output --partial 'MISSION CONTRACT'
    assert_output --partial 'file-writing prompt enhancement agent'
    assert_output --partial 'session succeeds when'
}

@test "enhance modes now include never constraints" {
    run build_system_prompt enhance-interactive
    assert_success
    assert_output --partial 'Constraints'
    assert_output --partial 'NEVER'
    assert_output --partial 'invent file paths'
}

@test "enhance modes now include verification gate" {
    run build_system_prompt enhance-auto
    assert_success
    assert_output --partial 'Verification Gate'
    assert_output --partial 'MANDATORY'
    assert_output --partial '[ ]'
}

# ============================================================================
# EXPAND MODES
# ============================================================================

@test "expand-interactive requires output_file parameter" {
    run build_system_prompt expand-interactive
    assert_failure
    assert_output --partial 'require output_file parameter'
}

@test "expand-interactive generates valid prompt with output_file" {
    run build_system_prompt expand-interactive /tmp/test-output.md
    assert_success

    # Should contain core sections
    assert_output --partial 'thought-agent'
    assert_output --partial 'Reflection seed'
    assert_output --partial '/tmp/test-output.md'
    assert_output --partial 'Investigation Guidelines'
}

@test "expand-auto requires output_file parameter" {
    run build_system_prompt expand-auto
    assert_failure
    assert_output --partial 'require output_file parameter'
}

@test "expand-auto generates valid prompt with output_file" {
    run build_system_prompt expand-auto /tmp/test-output.md
    assert_success

    # Should contain core sections
    assert_output --partial 'thought-agent'
    assert_output --partial 'Reflection seed'
    assert_output --partial '/tmp/test-output.md'
}

@test "expand-auto includes auto-execute style" {
    run build_system_prompt expand-auto /tmp/test-output.md
    assert_success

    # Should indicate auto mode
    assert_output --partial 'Auto-execute'
    assert_output --partial 'Done'
}

# ============================================================================
# SHARED SECTIONS
# ============================================================================

@test "all modes include investigation guidelines" {
    # Test enhance-interactive
    run build_system_prompt enhance-interactive
    assert_success
    assert_output --partial 'Investigation Guidelines'
    assert_output --partial 'Read'
    assert_output --partial 'Grep'
    assert_output --partial 'Bash'

    # Test expand-interactive
    run build_system_prompt expand-interactive /tmp/test.md
    assert_success
    assert_output --partial 'Investigation Guidelines'
}

@test "all modes include output format guidance" {
    # Test enhance-auto
    run build_system_prompt enhance-auto
    assert_success
    assert_output --partial 'Output Format'
    assert_output --partial 'Context'
    assert_output --partial 'actionable'

    # Test expand-auto
    run build_system_prompt expand-auto /tmp/test.md
    assert_success
    assert_output --partial 'Output Format'
}

@test "all modes include validation rules" {
    # Test enhance-interactive
    run build_system_prompt enhance-interactive
    assert_success
    assert_output --partial 'Validation Rules'
    assert_output --partial 'file path'
    assert_output --partial 'exist'

    # Test expand-interactive
    run build_system_prompt expand-interactive /tmp/test.md
    assert_success
    assert_output --partial 'Validation Rules'
}

# ============================================================================
# ERROR HANDLING
# ============================================================================

@test "invalid mode returns error" {
    run build_system_prompt invalid-mode
    assert_failure
    assert_output --partial 'Unknown mode'
}

@test "error message lists valid modes" {
    run build_system_prompt wrong-mode
    assert_failure
    assert_output --partial 'enhance-interactive'
    assert_output --partial 'enhance-auto'
    assert_output --partial 'expand-interactive'
    assert_output --partial 'expand-auto'
}

@test "empty mode parameter returns error" {
    run build_system_prompt ""
    assert_failure
}

# ============================================================================
# MODE-SPECIFIC CONTENT
# ============================================================================

@test "enhance modes mention $FILE, not seed" {
    run build_system_prompt enhance-interactive
    assert_success
    assert_output --partial '$FILE'
    refute_output --partial 'seed JSON'
}

@test "expand modes mention seed, have appropriate context" {
    run build_system_prompt expand-interactive /tmp/test.md
    assert_success
    assert_output --partial 'seed'
    assert_output --partial 'title'
    assert_output --partial 'rationale'
    assert_output --partial 'anchors'
}

@test "interactive modes do not say 'Done' in auto style" {
    run build_system_prompt enhance-interactive
    assert_success
    # Should NOT have auto-execute "Done" instruction
    refute_output --partial 'output only: "Done"'
}

@test "auto modes instruct to output 'Done' when complete" {
    run build_system_prompt enhance-auto
    assert_success
    assert_output --partial 'Done'
}

# ============================================================================
# OUTPUT FILE INTERPOLATION
# ============================================================================

@test "expand modes interpolate output_file path correctly" {
    run build_system_prompt expand-interactive /path/to/output.md
    assert_success
    assert_output --partial '/path/to/output.md'

    run build_system_prompt expand-auto /different/path.txt
    assert_success
    assert_output --partial '/different/path.txt'
}

# ============================================================================
# OUTPUT FILE HARDENING (defense-in-depth)
# These tests verify the expand agent has strong output file anchoring
# ============================================================================

@test "expand modes have mission contract framing" {
    run build_system_prompt expand-auto /tmp/test-output.md
    assert_success
    assert_output --partial 'MISSION CONTRACT'
    assert_output --partial 'file-writing thought-agent'
    assert_output --partial 'session succeeds when'
}

@test "expand modes mention output file multiple times (defense-in-depth)" {
    output=$(build_system_prompt expand-auto /tmp/test-output.md)
    mention_count=$(echo "$output" | grep -c "/tmp/test-output.md" || true)

    # Should mention output file at least 5 times for defense-in-depth
    [ "$mention_count" -ge 5 ]
}

@test "expand modes have mandatory verification gate" {
    run build_system_prompt expand-auto /tmp/test-output.md
    assert_success
    assert_output --partial 'VERIFY OUTPUT (MANDATORY)'
    assert_output --partial 'test -f'
    assert_output --partial 'If verification fails, return to step 4'
}

@test "expand modes have completion checklist" {
    run build_system_prompt expand-auto /tmp/test-output.md
    assert_success
    assert_output --partial 'Completion Checklist'
    assert_output --partial '[ ] File'
    assert_output --partial 'Unchecked = incomplete mission'
}

@test "expand-auto style reinforces output file requirement" {
    run build_system_prompt expand-auto /tmp/test-output.md
    assert_success
    assert_output --partial 'Your final action MUST be writing to'
}

# ============================================================================
# CONSISTENCY CHECKS
# ============================================================================

@test "all modes produce non-empty output" {
    modes=("enhance-interactive" "enhance-auto")

    for mode in "${modes[@]}"; do
        run build_system_prompt "$mode"
        assert_success
        # Should have substantial content (at least 50 lines)
        line_count=$(echo "$output" | wc -l | tr -d ' ')
        [ "$line_count" -gt 50 ]
    done

    # Expand modes with output file
    run build_system_prompt expand-interactive /tmp/test.md
    assert_success
    line_count=$(echo "$output" | wc -l | tr -d ' ')
    [ "$line_count" -gt 50 ]
}

@test "shared sections are identical across modes" {
    # Get investigation guidelines from enhance mode
    enhance_output=$(build_system_prompt enhance-interactive)
    enhance_has_guidelines=$(echo "$enhance_output" | grep -c "Investigation Guidelines" || true)

    # Get investigation guidelines from expand mode
    expand_output=$(build_system_prompt expand-interactive /tmp/test.md)
    expand_has_guidelines=$(echo "$expand_output" | grep -c "Investigation Guidelines" || true)

    # Both should have investigation guidelines
    [ "$enhance_has_guidelines" -gt 0 ]
    [ "$expand_has_guidelines" -gt 0 ]
}

# ============================================================================
# USER'S CORRECTED ENHANCE PROMPT INTEGRATION
# ============================================================================

@test "enhance modes use user's corrected prompt as foundation" {
    run build_system_prompt enhance-interactive
    assert_success

    # Should have user's specified structure
    assert_output --partial 'Inputs'
    assert_output --partial 'Deliverable'
    assert_output --partial 'Procedure'
    assert_output --partial 'Understand the task'
    assert_output --partial 'Investigate the codebase'
    assert_output --partial 'Rewrite the prompt'
    assert_output --partial 'validation'
    assert_output --partial 'Save'
}

@test "enhance modes preserve user intent without $SEED_JSON references" {
    run build_system_prompt enhance-interactive
    assert_success

    # Should NOT mention seed JSON (user's correction)
    refute_output --partial 'SEED_JSON'
    refute_output --partial 'seed.json'
}

@test "enhance modes emphasize supportive tone" {
    run build_system_prompt enhance-interactive
    assert_success

    # User wanted supportive, not gatekeeping
    assert_output --partial 'Preserve the user'
    refute_output --partial 'reject'
    refute_output --partial 'NEEDS REFINEMENT'
}

# ============================================================================
# GOLDEN/SNAPSHOT TESTS
# ============================================================================

@test "enhance-interactive matches golden snapshot" {
    # Ensure no session context injection
    export REFLECTION_BASE=$(mktemp -d)

    run build_system_prompt enhance-interactive
    assert_success

    # Compare against golden file
    diff <(echo "$output") "$BATS_TEST_DIRNAME/../golden/enhance-interactive.golden"
}

@test "enhance-auto matches golden snapshot" {
    export REFLECTION_BASE=$(mktemp -d)

    run build_system_prompt enhance-auto
    assert_success

    diff <(echo "$output") "$BATS_TEST_DIRNAME/../golden/enhance-auto.golden"
}

@test "expand-interactive matches golden snapshot" {
    export REFLECTION_BASE=$(mktemp -d)

    # Use fixed path for deterministic output
    run build_system_prompt expand-interactive /tmp/golden-test-output.md
    assert_success

    diff <(echo "$output") "$BATS_TEST_DIRNAME/../golden/expand-interactive.golden"
}

@test "expand-auto matches golden snapshot" {
    export REFLECTION_BASE=$(mktemp -d)

    run build_system_prompt expand-auto /tmp/golden-test-output.md
    assert_success

    diff <(echo "$output") "$BATS_TEST_DIRNAME/../golden/expand-auto.golden"
}
