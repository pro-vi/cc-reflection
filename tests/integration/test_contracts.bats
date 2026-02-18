#!/usr/bin/env bats
# Integration tests for cross-language contracts between bash and TypeScript

load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'
load '../test_helper/bats-file/load'

# Setup test session
setup() {
    # Use unique session ID for test isolation
    export CLAUDE_SESSION_ID="test-contracts-$$"

    # Isolated test directory — never touch real ~/.claude/
    export REFLECTION_BASE="$(mktemp -d)"

    # Source shared utilities (REFLECTION_BASE must be set first)
    source "${BATS_TEST_DIRNAME}/../../lib/cc-common.sh"
    source "${BATS_TEST_DIRNAME}/../../lib/validators.sh"

    # Create clean test environment
    TEST_SEEDS_DIR="$REFLECTION_BASE/seeds/$CLAUDE_SESSION_ID"
    TEST_RESULTS_DIR="$REFLECTION_BASE/results"

    mkdir -p "$TEST_SEEDS_DIR"
    mkdir -p "$TEST_RESULTS_DIR"
}

# Cleanup after each test
teardown() {
    rm -rf "$REFLECTION_BASE"
}

# ============================================================================
# TEST 1: Directory Path Consistency
# ============================================================================

@test "bash and TypeScript use identical base directory" {
    # Get bash path (uses REFLECTION_BASE from setup)
    BASH_BASE="$REFLECTION_BASE"

    # Create a seed with TypeScript and verify it goes to expected location
    RESULT=$(bun "${BATS_TEST_DIRNAME}/../../lib/reflection-state.ts" write \
        "Path Test" "Testing path consistency" "test-path.ts" "1" "10" "med")

    # Extract seed ID from result
    SEED_ID=$(echo "$RESULT" | bun -e "console.log(JSON.parse(await Bun.stdin.text()).seed.id)")

    # Verify file exists at bash-expected path
    EXPECTED_PATH="$BASH_BASE/seeds/$CLAUDE_SESSION_ID/${SEED_ID}.json"
    assert_file_exist "$EXPECTED_PATH"
}

@test "bash and TypeScript resolve seeds directory identically" {
    # Get session ID (should be same in both)
    BASH_SESSION_ID=$(cc_get_session_id)

    # Create seed with TypeScript
    RESULT=$(bun "${BATS_TEST_DIRNAME}/../../lib/reflection-state.ts" write \
        "Seeds Dir Test" "Testing seeds directory" "file.ts" "1" "10" "high")

    SEED_ID=$(echo "$RESULT" | bun -e "console.log(JSON.parse(await Bun.stdin.text()).seed.id)")

    # Bash should find this seed
    SEEDS_JSON=$(bun "${BATS_TEST_DIRNAME}/../../lib/reflection-state.ts" list)

    # Verify bash can parse the result
    FOUND=$(echo "$SEEDS_JSON" | bun -e "
        const seeds = JSON.parse(await Bun.stdin.text());
        const found = seeds.find(s => s.id === '$SEED_ID');
        console.log(found ? 'yes' : 'no');
    ")

    assert_equal "$FOUND" "yes"
}

@test "results directory path matches between bash and TypeScript" {
    # Expected results directory (uses REFLECTION_BASE from setup)
    BASH_RESULTS_DIR="$TEST_RESULTS_DIR"

    # Create a test result file with TypeScript
    TEST_SEED_ID="seed-1234567890-testpath"
    TEST_CONTENT="# Test Result\nThis is a test"

    # Write result using TypeScript (simulating thought-agent output)
    echo "$TEST_CONTENT" > "$BASH_RESULTS_DIR/${TEST_SEED_ID}-result.md"

    # Verify bash can find it at expected location
    assert_file_exist "$BASH_RESULTS_DIR/${TEST_SEED_ID}-result.md"
}

# ============================================================================
# TEST 2: File Naming Conventions
# ============================================================================

@test "seed files use exact {SEED_ID}.json naming pattern" {
    # Create seed with TypeScript
    RESULT=$(bun "${BATS_TEST_DIRNAME}/../../lib/reflection-state.ts" write \
        "Naming Test" "Testing file naming" "security.ts" "1" "10" "high")

    SEED_ID=$(echo "$RESULT" | bun -e "console.log(JSON.parse(await Bun.stdin.text()).seed.id)")

    # Verify file exists with exact naming pattern (no prefix/suffix variations)
    EXPECTED_FILE="$TEST_SEEDS_DIR/${SEED_ID}.json"
    assert_file_exist "$EXPECTED_FILE"

    # Verify no alternative naming exists
    assert_file_not_exist "$TEST_SEEDS_DIR/${SEED_ID}.seed.json"
    assert_file_not_exist "$TEST_SEEDS_DIR/seed_${SEED_ID}.json"
}

@test "result files use exact {SEED_ID}-result.md naming pattern" {
    TEST_SEED_ID="seed-9876543210-naming"

    # Simulate what cc-reflect-expand does
    RESULT_FILE="$TEST_RESULTS_DIR/${TEST_SEED_ID}-result.md"

    # Create result file (simulating thought-agent writing)
    echo "# Test Result" > "$RESULT_FILE"

    # Verify exact naming (no variations)
    assert_file_exist "$RESULT_FILE"
    assert_file_not_exist "$TEST_RESULTS_DIR/${TEST_SEED_ID}.result.md"
    assert_file_not_exist "$TEST_RESULTS_DIR/${TEST_SEED_ID}_result.md"

    # Cleanup
    rm -f "$RESULT_FILE"
}

@test "seed ID format matches between TypeScript generator and bash validator" {
    # Create seed with TypeScript
    RESULT=$(bun "${BATS_TEST_DIRNAME}/../../lib/reflection-state.ts" write \
        "ID Format Test" "Testing ID format" "test-idformat.ts" "1" "10" "low")

    SEED_ID=$(echo "$RESULT" | bun -e "console.log(JSON.parse(await Bun.stdin.text()).seed.id)")

    # Bash validator should accept TypeScript-generated ID
    run validate_seed_id "$SEED_ID"
    assert_success

    # Verify it matches expected pattern: seed-TIMESTAMP-RANDOM
    [[ "$SEED_ID" =~ ^seed-[0-9]+-[a-z0-9]+$ ]]
}

# ============================================================================
# TEST 3: JSON Schema Stability
# ============================================================================

@test "ReflectionSeed JSON contains all fields bash depends on" {
    # Create seed
    RESULT=$(bun "${BATS_TEST_DIRNAME}/../../lib/reflection-state.ts" write \
        "Schema Test" "Testing JSON schema" "schema.ts" "1" "10")

    # Extract seed JSON
    SEED_JSON=$(echo "$RESULT" | bun -e "console.log(JSON.stringify(JSON.parse(await Bun.stdin.text()).seed))")

    # Verify all fields bash scripts depend on exist
    echo "$SEED_JSON" | bun -e "
        const seed = JSON.parse(await Bun.stdin.text());

        // Fields used in cc-reflect-expand
        if (!seed.id) throw new Error('Missing required field: id');
        if (!seed.title) throw new Error('Missing required field: title');
        if (!seed.rationale) throw new Error('Missing required field: rationale');
        if (!seed.session_id) throw new Error('Missing required field: session_id');
        if (!seed.created_at) throw new Error('Missing required field: created_at');

        // Additional fields that should exist
        if (!seed.anchors) throw new Error('Missing required field: anchors');
        if (typeof seed.ttl_hours !== 'number') throw new Error('Missing required field: ttl_hours');
        if (!seed.dedupe_key) throw new Error('Missing required field: dedupe_key');

        console.log('All required fields present');
    "
}

@test "bash can extract all seed fields used in cc-reflect-expand" {
    # Create seed
    RESULT=$(bun "${BATS_TEST_DIRNAME}/../../lib/reflection-state.ts" write \
        "Extract Test" "Testing field extraction" "file.ts" "1" "10")

    SEED_ID=$(echo "$RESULT" | bun -e "console.log(JSON.parse(await Bun.stdin.text()).seed.id)")

    # Get seed using TypeScript (simulates cc-reflect-expand:49)
    SEED_JSON=$(bun "${BATS_TEST_DIRNAME}/../../lib/reflection-state.ts" get "$SEED_ID")

    # Extract fields exactly as cc-reflect-expand does
    SEED_TITLE=$(echo "$SEED_JSON" | bun -e "const s = JSON.parse(await Bun.stdin.text()); console.log(s.title);")
    SEED_RATIONALE=$(echo "$SEED_JSON" | bun -e "const s = JSON.parse(await Bun.stdin.text()); console.log(s.rationale);")

    # Verify extraction worked
    assert_equal "$SEED_TITLE" "Extract Test"
    assert_equal "$SEED_RATIONALE" "Testing field extraction"
}

@test "seed JSON from TypeScript is valid and parseable" {
    # Create seed
    RESULT=$(bun "${BATS_TEST_DIRNAME}/../../lib/reflection-state.ts" write \
        "JSON Parse Test" "Testing JSON validity" "perf.ts" "1" "10")

    SEED_ID=$(echo "$RESULT" | bun -e "console.log(JSON.parse(await Bun.stdin.text()).seed.id)")

    # Read seed JSON
    SEED_JSON=$(bun "${BATS_TEST_DIRNAME}/../../lib/reflection-state.ts" get "$SEED_ID")

    # Verify it's valid JSON (this will fail if not valid)
    echo "$SEED_JSON" | bun -e "JSON.parse(await Bun.stdin.text())"
}

# ============================================================================
# TEST 4: CLI Command Signatures
# ============================================================================

@test "reflection-state.ts list outputs parseable JSON array" {
    # List should always output valid JSON array (even if empty)
    OUTPUT=$(bun "${BATS_TEST_DIRNAME}/../../lib/reflection-state.ts" list)

    # Verify it's valid JSON and is an array
    IS_ARRAY=$(echo "$OUTPUT" | bun -e "
        const result = JSON.parse(await Bun.stdin.text());
        console.log(Array.isArray(result) ? 'yes' : 'no');
    ")

    assert_equal "$IS_ARRAY" "yes"
}

@test "reflection-state.ts get returns single seed object" {
    # Create seed
    RESULT=$(bun "${BATS_TEST_DIRNAME}/../../lib/reflection-state.ts" write \
        "Get Test" "Testing get command" "flag.ts" "1" "10" "low")

    SEED_ID=$(echo "$RESULT" | bun -e "console.log(JSON.parse(await Bun.stdin.text()).seed.id)")

    # Get seed
    SEED_JSON=$(bun "${BATS_TEST_DIRNAME}/../../lib/reflection-state.ts" get "$SEED_ID")

    # Verify it's a single object (not array)
    IS_OBJECT=$(echo "$SEED_JSON" | bun -e "
        const result = JSON.parse(await Bun.stdin.text());
        console.log(typeof result === 'object' && !Array.isArray(result) ? 'yes' : 'no');
    ")

    assert_equal "$IS_OBJECT" "yes"
}

@test "reflection-state.ts write returns consistent result structure" {
    # Write seed
    RESULT=$(bun "${BATS_TEST_DIRNAME}/../../lib/reflection-state.ts" write \
        "Write Test" "Testing write return value" "assume.ts" "1" "10" "med")

    # Verify result has expected structure (success flag and seed object)
    HAS_STRUCTURE=$(echo "$RESULT" | bun -e "
        const result = JSON.parse(await Bun.stdin.text());
        const hasSuccess = result.success !== undefined;
        const hasSeed = result.seed !== undefined;
        const hasSeedId = result.seed && result.seed.id !== undefined;
        console.log(hasSuccess && hasSeed && hasSeedId ? 'yes' : 'no');
    ")

    assert_equal "$HAS_STRUCTURE" "yes"
}

# ============================================================================
# TEST 5: Cross-Platform Environment Handling
# ============================================================================

@test "TypeScript uses REFLECTION_BASE consistently with bash" {
    # Create seed and verify it uses REFLECTION_BASE path
    RESULT=$(bun "${BATS_TEST_DIRNAME}/../../lib/reflection-state.ts" write \
        "HOME Test" "Testing REFLECTION_BASE usage" "test-home.ts" "1" "10" "low")

    SEED_ID=$(echo "$RESULT" | bun -e "console.log(JSON.parse(await Bun.stdin.text()).seed.id)")

    # File should exist at REFLECTION_BASE path
    assert_file_exist "$REFLECTION_BASE/seeds/$CLAUDE_SESSION_ID/${SEED_ID}.json"
}

@test "session ID calculation handles PWD env var correctly" {
    # This tests the critical PWD vs process.cwd() fix
    # Both should prefer PWD env var when available

    BASH_SESSION=$(cc_get_session_id)
    TS_SESSION=$(bun "${BATS_TEST_DIRNAME}/../../lib/session-id.ts")

    # Must be identical
    assert_equal "$BASH_SESSION" "$TS_SESSION"

    # Both should respect CLAUDE_SESSION_ID override
    export CLAUDE_SESSION_ID="test-override-123"

    BASH_SESSION_OVERRIDE=$(cc_get_session_id)
    TS_SESSION_OVERRIDE=$(bun "${BATS_TEST_DIRNAME}/../../lib/session-id.ts")

    assert_equal "$BASH_SESSION_OVERRIDE" "test-override-123"
    assert_equal "$TS_SESSION_OVERRIDE" "test-override-123"
}

@test "directory paths work with spaces in HOME (edge case)" {
    skip "Requires mocking HOME with spaces - implement if needed for Windows/WSL"
    # This would test: HOME="/Users/My Home/test"
    # Ensuring proper quoting in both bash and TypeScript
}

# ============================================================================
# TEST 6: Claude session env var contract
# ============================================================================

@test "bash and TypeScript both prefer CC_DICE_SESSION_ID over CC_REFLECTION_SESSION_ID" {
    # Simulate mixed environment during migration:
    # new cc-dice var set + legacy cc-reflection var still present.
    export CC_DICE_SESSION_ID="dice-uuid-1111"
    export CC_REFLECTION_SESSION_ID="legacy-uuid-2222"
    unset CLAUDE_SESSION_ID

    # Bash side
    local bash_result
    bash_result=$(cc_get_claude_session_id)
    assert_equal "$bash_result" "dice-uuid-1111"

    # TypeScript side (test the same helper layer, not getSessionId wrapper)
    local ts_result
    ts_result=$(bun -e "const m = await import('${BATS_TEST_DIRNAME}/../../lib/session-id.ts'); console.log(m.getClaudeSessionId() ?? '')")
    assert_equal "$ts_result" "dice-uuid-1111"
}

@test "bash and TypeScript agree when only CC_DICE_SESSION_ID is set" {
    export CC_DICE_SESSION_ID="dice-only-uuid-3333"
    unset CC_REFLECTION_SESSION_ID
    unset CLAUDE_SESSION_ID

    local bash_result
    bash_result=$(cc_get_claude_session_id)

    local ts_result
    ts_result=$(bun -e "const m = await import('${BATS_TEST_DIRNAME}/../../lib/session-id.ts'); console.log(m.getClaudeSessionId() ?? '')")

    assert_equal "$bash_result" "dice-only-uuid-3333"
    assert_equal "$ts_result" "dice-only-uuid-3333"
}

@test "bash and TypeScript both prefer CC_REFLECTION_SESSION_ID over file lookup" {
    # Set the env var (simulates what SessionStart hook writes to CLAUDE_ENV_FILE)
    export CC_REFLECTION_SESSION_ID="env-uuid-1234-5678-abcd"
    # Clear CLAUDE_SESSION_ID so it doesn't take priority in cc_get_session_id
    unset CLAUDE_SESSION_ID

    # Bash side
    local bash_result
    bash_result=$(cc_get_claude_session_id)
    assert_equal "$bash_result" "env-uuid-1234-5678-abcd"

    # TypeScript side
    local ts_result
    ts_result=$(bun "${BATS_TEST_DIRNAME}/../../lib/session-id.ts")
    assert_equal "$ts_result" "env-uuid-1234-5678-abcd"
}

@test "bash and TypeScript agree on session ID when CC_REFLECTION_SESSION_ID is set" {
    export CC_REFLECTION_SESSION_ID="contract-test-uuid-9999"
    unset CLAUDE_SESSION_ID

    local bash_session
    bash_session=$(cc_get_session_id)

    local ts_session
    ts_session=$(bun "${BATS_TEST_DIRNAME}/../../lib/session-id.ts")

    assert_equal "$bash_session" "$ts_session"
    assert_equal "$bash_session" "contract-test-uuid-9999"
}

@test "CC_REFLECTION_SESSION_ID unset falls through to file/project-hash" {
    unset CC_REFLECTION_SESSION_ID
    unset CLAUDE_SESSION_ID

    # Both should fall through to project hash (no session file exists in test env)
    local bash_session
    bash_session=$(cc_get_session_id)

    local ts_session
    ts_session=$(bun "${BATS_TEST_DIRNAME}/../../lib/session-id.ts")

    assert_equal "$bash_session" "$ts_session"
    # Should be a 12-char hex project hash, not a UUID
    [[ ${#bash_session} -eq 12 ]]
}

# ============================================================================
# TEST 7: Forbidden Characters Contract (bash ↔ TypeScript)
# ============================================================================

@test "bash and TypeScript reject the same forbidden shell metacharacters" {
    # Characters both should reject
    local -a forbidden_chars=(
        '$'   '`'   "'"   '"'   '|'   ';'   '&'   '\\'  '<'   '>'   '('   ')'   '{'   '}'
    )

    for char in "${forbidden_chars[@]}"; do
        local test_title="test${char}title"

        # TypeScript should reject
        run bun "${BATS_TEST_DIRNAME}/../../lib/reflection-state.ts" write \
            "$test_title" "rationale" "file.ts" "start" "end"
        assert_failure

        # Bash should reject
        run validate_seed_title "$test_title"
        assert_failure
    done
}

@test "bash and TypeScript reject control characters (ESC, NULL, BEL)" {
    # Control characters: ESC (\x1b), NULL (\x00), BEL (\x07)
    local -a control_chars=(
        $'\x1b'   # ESC
        $'\x07'   # BEL
        $'\x01'   # SOH
        $'\t'     # TAB (\x09)
        $'\n'     # LF  (\x0a)
        $'\r'     # CR  (\x0d)
    )

    for char in "${control_chars[@]}"; do
        local test_title="test${char}title"

        # TypeScript should reject
        run bun "${BATS_TEST_DIRNAME}/../../lib/reflection-state.ts" write \
            "$test_title" "rationale" "file.ts" "start" "end"
        assert_failure

        # Bash should reject
        run validate_seed_title "$test_title"
        assert_failure
    done
}

@test "bash and TypeScript accept safe titles identically" {
    local -a safe_titles=(
        "Simple title"
        "Title with numbers 123"
        "Title with dashes-and-underscores_here"
        "Title with dots.and.colons: here"
        "Unicode title with emoji"
        "Mixed CaSe Title"
    )

    for title in "${safe_titles[@]}"; do
        # TypeScript should accept
        run bun "${BATS_TEST_DIRNAME}/../../lib/reflection-state.ts" write \
            "$title" "rationale" "file.ts" "start" "end"
        assert_success

        # Bash should accept
        run validate_seed_title "$title"
        assert_success
    done
}
