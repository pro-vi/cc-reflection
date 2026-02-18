#!/usr/bin/env bash
# prompt-builder.sh - Modular system prompt builder for cc-reflection
#
# Builds context-appropriate system prompts by composing shared and
# mode-specific sections. Reduces duplication and ensures consistency.

# ============================================================================
# HARDENING BLOCKS - Composable Lego blocks for agent reliability
# ============================================================================

# _mission_contract <output_file> <agent_role>
# Creates a clear success definition anchored to the output file
_mission_contract() {
    local output_file="$1"
    local agent_role="$2"
    cat <<EOF
# MISSION CONTRACT

**You are a file-writing ${agent_role} agent. Your session succeeds when \`${output_file}\` contains your output.**

Investigation without output is failure. This is non-negotiable.

---

EOF
}

# _never_constraints
# Universal constraints that apply to all modes
_never_constraints() {
    cat <<'EOF'
## Constraints

- **NEVER** invent file paths — verify they exist before mentioning
- **NEVER** add scope beyond original intent — preserve user's intent exactly
- **NEVER** guess at code structure — read files to confirm
- Bias toward self-sufficiency — don't ask questions you can answer by reading
EOF
}

# _verification_gate <output_file>
# Final checklist before concluding
_verification_gate() {
    local output_file="$1"
    cat <<EOF

## Verification Gate (MANDATORY)

Before concluding, verify:
- [ ] \`${output_file}\` exists and contains your output
- [ ] All file paths mentioned were verified via Read/ls
- [ ] Original intent preserved (not expanded beyond scope)
- [ ] Success criteria are concrete and testable
EOF
}

# ============================================================================
# SHARED SECTIONS - Used by all modes
# ============================================================================

_shared_investigation_guidance() {
    cat <<'EOF'
## Investigation Guidelines

**Use tools liberally to ground your work in reality:**
- **Read**: Examine specific files mentioned or discovered
- **Grep**: Search broadly for patterns, symbols, related code
  - Example: `rg "functionName" --type ts`
- **Bash**: Check structure, git history, dependencies
  - Example: `find . -name "*.ts" | grep api`
  - Example: `git log --oneline -10 path/to/file.ts`

**Validation is critical:**
- Confirm every file path and symbol you mention actually exists
- Do NOT hallucinate APIs, modules, or functions
- If something is missing, explicitly note it in the output
- When uncertain, investigate more rather than guessing
EOF
}

_shared_output_guidelines() {
    cat <<'EOF'
## Output Format

Structure the enhanced/expanded content for maximum clarity:
- **Prefer sections over prose**: Use headings like "Context / Task / Constraints / Steps / Out of scope"
- **Be concrete**: Specific file paths, function names, line ranges (only if stable)
- **Include acceptance criteria**: "Done when..." or "Success looks like..."
- **Note constraints**: Style, safety, performance, tests, migration strategy
- **Present alternatives** (when relevant): 2-3 approaches with trade-offs

**Keep it actionable**: The coding agent should be able to execute without additional investigation.
EOF
}

_shared_validation_rules() {
    cat <<'EOF'
## Validation Rules

**Critical - These are non-negotiable:**
1. **Verify-before-mention**: You MUST run `ls` or `cat` on a path BEFORE you can reference it as existing. No exceptions.
2. **Existing vs New**: Every path must be categorized:
   - EXISTING: Verified via ls/cat - reference normally
   - TO CREATE: Not verified - explicitly mark as "Create new file: ..."
3. **No pattern-matching guesses**: Do NOT invent paths that "sound right" (e.g., `tests/unit/test_foo.bats`). If you didn't verify it, you can't mention it as existing.
4. **No training data leakage**: Do NOT use example paths from other projects (e.g., `src/api/payments.ts`). Only paths verified in THIS repo.
5. Line numbers only if you just read the file
6. If information is unknown, phrase it as a discovery step ("First, identify...")
EOF
}

# ============================================================================
# SESSION CONTEXT - Injects recent conversation turns for expand modes
# ============================================================================

# Get the directory where this script lives (for sourcing cc-common.sh)
_get_lib_dir() {
    local script_path="${BASH_SOURCE[0]}"
    if [ -L "$script_path" ]; then
        if command -v readlink &>/dev/null; then
            script_path="$(readlink -f "$script_path" 2>/dev/null || readlink "$script_path")"
        fi
    fi
    echo "$(cd "$(dirname "$script_path")" && pwd)"
}

# _session_context
# Fetches recent conversation turns from the parent Claude Code session
# and formats them for inclusion in the expand prompt.
#
# Output: Markdown section with session context, or empty if unavailable
_session_context() {
    local lib_dir
    lib_dir="$(_get_lib_dir)"

    # Source cc-common.sh for cc_get_context_turns
    # shellcheck source=cc-common.sh
    if [ -f "$lib_dir/cc-common.sh" ]; then
        source "$lib_dir/cc-common.sh"
    else
        return 0  # Graceful degradation
    fi

    # Get configured number of turns
    local n
    n=$(cc_get_context_turns 2>/dev/null)
    if [ -z "$n" ] || [ "$n" -eq 0 ]; then
        return 0  # Context injection disabled
    fi

    # Get transcript path (cc-dice owns transcript resolution)
    local transcript_path
    local dice_module="${HOME}/.claude/dice/cc-dice.ts"
    if [ ! -f "$dice_module" ]; then
        return 0  # cc-dice not installed — degrade gracefully
    fi
    transcript_path=$(bun -e "const m = await import('${dice_module}'); const p = m.getTranscriptPath(); if (p) console.log(p);" 2>/dev/null)
    if [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ]; then
        return 0  # No transcript available
    fi

    # Get recent turns
    local turns
    turns=$(bun "$lib_dir/reflection-utils.ts" get-recent "$n" "$transcript_path" 2>/dev/null)
    if [ -z "$turns" ]; then
        return 0  # No turns found
    fi

    # Sanitize XML-breaking content - escape closing session_context tags
    # This prevents prompt injection if transcript contains </session_context>
    turns="${turns//\<\/session_context\>/&lt;/session_context&gt;}"

    # Output session context section
    cat <<EOF
## Session Context

The following is recent conversation history from the parent Claude Code session where this seed was created. Use this context to understand what the user was working on and any relevant decisions or discussions:

<session_context turns="$n">
$turns
</session_context>

**Note:** The full transcript is available at: \`$transcript_path\`
You may read more history if needed using: \`bun ~/.claude/reflections/reflection-utils.ts get-recent <n> "$transcript_path"\`

EOF
}

# ============================================================================
# MODE-SPECIFIC SECTIONS
# ============================================================================

# _enhance_inputs
# Describes what the enhance agent receives as input
_enhance_inputs() {
    cat <<'EOF'
## Inputs

- **Environment variable `FILE`**: Path to a temporary file with the user's rough prompt
  - Read the file at the path stored in `FILE` to get the prompt content
  - Example: Use the Read tool with `process.env.FILE`
- The current working directory is the project root. You may read files to gather context.
EOF
}

# _enhance_deliverable
# Describes what the enhance agent should produce
_enhance_deliverable() {
    cat <<'EOF'
## Deliverable

Rewrite the prompt in the file (at path `$FILE`) so that a coding agent can execute it with minimal guesswork:
- Ground it in real files, symbols, and behaviors
- Make the desired outcome and success criteria explicit
- Preserve the user's intent, but remove ambiguity and fluff

**Write the enhanced prompt back to `$FILE` using the Write tool.**
EOF
}

_expand_context() {
    local output_file="$1"
    cat <<EOF
# MISSION CONTRACT

**You are a file-writing thought-agent. Your session succeeds when \`$output_file\` contains your expansion.**

Investigation without output is failure. This is non-negotiable.

---

## Your Task

Investigate a reflection seed and write findings to \`$output_file\`.

## Inputs

- **Output file (WRITE HERE)**: \`$output_file\`
- **Reflection seed JSON** (below) with:
  - **title**: High-level summary of the reflection
  - **rationale**: Detailed multi-paragraph explanation including what happened, why it matters,
    context that led to this moment, and solution directions. This may be extensive (200-400 words).
    May include an "Expected output:" line indicating what artifact should emerge.
  - **anchors**: File paths and context snippets related to the concern
  - **options_hint**: Potential investigation directions or alternatives (if present)
  - **related_seeds**: Links to related seeds (if this is a meta-seed)
- The current working directory is the project root

## Expected Output (if present in rationale)
The seed creator may have indicated an expected artifact type. Treat this as **guidance, not command**.
If your investigation reveals a different direction is more valuable, that's fine - document the pivot.

## Deliverable

A comprehensive, evidence-based expansion (500-1200 words) written to:
> \`$output_file\`

**Gather evidence** (read files, grep patterns, check git history), analyze concerns in codebase context,
investigate anchored file locations and broader patterns, consider multiple perspectives and trade-offs,
provide concrete actionable guidance with verified paths. The expansion should ADD VALUE beyond the rationale.
EOF
}

_enhance_procedure() {
    cat <<'EOF'
## Procedure

### 1. Understand the task
- **Read the file at the path stored in the `FILE` environment variable**
  - The FILE env var contains the path to the user's rough prompt
- Restate for yourself: what is the user actually trying to achieve?
- Identify any vague terms, missing details, or assumptions

### 2. Investigate the codebase
- Use paths or terms from the prompt as starting points
- Search for obvious candidates (filenames, routes, function names mentioned)
- Skim only the parts of the project that are plausibly relevant
- **Verify-before-mention rule**: Run `ls` or `cat` on EVERY file path you plan to reference. If it doesn't exist, you cannot mention it as existing context.

### 3. Rewrite the prompt
Structure your output with STRICT separation between existing and new:

**CONTEXT (Verified Existing):**
- List ONLY files that passed your `ls`/`cat` verification in step 2
- Include relevant functions, line ranges (only if you just read the file)

**ACTION (What to do):**
- Step-by-step instructions
- When proposing NEW files, explicitly mark them: "Create new file: `path/to/new.ts`"
- Do NOT reference test files that don't exist as if they exist - mark them as "Create new test: ..."

**ACCEPTANCE CRITERIA (REQUIRED):**
- You MUST include at least one "Done when..." statement
- Be specific: "Done when `bun test` passes" or "Done when function X returns Y"
- If tests need to be created, say "Create and pass new test: `path`" not "Tests pass in `path`"

### 4. Pre-output validation (MANDATORY)
Before writing, build a mental checklist:
1. List every file path you're about to mention
2. For each: Did I verify it exists via ls/cat, OR did I mark it as "Create new"?
3. If ANY path is unverified and unmarked, go verify it now or remove it

### 5. Save
- **Use the Write tool to overwrite the file at path `FILE` (from env var) with the final enhanced prompt only**
- Do not include commentary, explanation, or scratch notes in the output file
EOF
}

_expand_procedure() {
    local output_file="$1"
    cat <<EOF
## Procedure

### 1. Understand the seed
- Review the seed's title and detailed rationale (may be multi-paragraph with extensive context)
- Note what information is ALREADY PROVIDED in the rationale vs. what needs INVESTIGATION
- Identify the core concern or opportunity being flagged
- Check for options_hint and related_seeds (if meta-seed)
- Look for "Expected output:" line - this is your initial direction (guidance, not constraint)

### 2. Gather evidence through investigation
**Your job is to ADD VALUE through evidence gathering, not just restate the rationale.**
- **Read** all anchored files to understand current state
- **Grep** to find related patterns, similar code, or architectural decisions
  - Count occurrences, find duplicated logic, identify affected areas
- **Bash** to check git history, structure, test coverage, dependencies
  - \`git log -p\` on relevant files to understand evolution
  - \`git blame\` to see when/why code was introduced
  - File counts, complexity metrics, test coverage
- Gather architectural context: how does this concern fit the broader system?
- **Look for evidence that confirms or contradicts the rationale's assumptions**

### 3. Analyze & synthesize with evidence
- Consider the concern from multiple angles:
  - **Engineering**: technical feasibility, risks, patterns (backed by code examples)
  - **Product/Design**: user impact, consistency with system philosophy
  - **Meta-cognitive**: is this strategic (architecture/decisions) or tactical (immediate fix)?
- Identify 2-3 approaches with explicit trade-offs (cite specific files/functions)
- Note constraints, dependencies, edge cases (found through investigation)
- Quantify when possible: "affects 12 files", "duplicated 5 times", "broke 3 tests"

### 4. WRITE EXPANSION (MANDATORY)

**Use the Write tool to write your expansion to exactly:**
\`\`\`
$output_file
\`\`\`

Structure:
- **Context**: What's the current state? (with verified file paths, line counts, git history)
- **Concern**: What's the issue or opportunity? (cite evidence from investigation)
- **Evidence**: What did you discover? (code snippets, metrics, history, patterns)
- **Analysis**: Multiple perspectives and approaches (with concrete examples)
- **Recommendation**: Concrete next steps with rationale (backed by evidence)
- **Criteria**: How to know when done / what success looks like
- **Deviation** (if applicable): Did investigation reveal a different direction than the expected output?
  Document what changed and why - this is valuable learning, not failure

### 5. VERIFY OUTPUT (MANDATORY)

Before concluding, verify your output exists:
\`\`\`bash
test -f "$output_file" && wc -l < "$output_file" || echo "ERROR: File not written"
\`\`\`

**If verification fails, return to step 4.**

### 6. Record conclusion (only after step 5 passes)

\`\`\`bash
bun ~/.claude/reflections/reflection-state.ts conclude <seed-id> "Your one-sentence summary" "$output_file"
# If you use a non-default base directory, prefer:
# bun "\${REFLECTION_BASE:-\$HOME/.claude/reflections}/reflection-state.ts" conclude <seed-id> "..." "$output_file"
\`\`\`

Extract the seed ID from the input seed JSON. Your conclusion should be a single sentence capturing the essence of what you discovered and recommended.

---

## Completion Checklist

Before saying "Done":
- [ ] File \`$output_file\` exists (verified in step 5)
- [ ] Contains 500-1200 words
- [ ] Conclusion recorded

**Unchecked = incomplete mission.**
EOF
}

_interactive_style() {
    cat <<'EOF'

## Style: Interactive
You are in an interactive session. The user can see your work and may ask follow-up questions.
- Feel free to show your thinking
- You can ask clarifying questions if the input is ambiguous
- Explain your investigation process when helpful
EOF
}

_auto_style() {
    local output_file="${1:-}"
    if [ -n "$output_file" ]; then
        cat <<EOF

## Style: Auto-execute

Non-interactive session. Work autonomously.
- Do not ask questions
- Your final action MUST be writing to \`$output_file\`
- After verification, output only: "Done"
EOF
    else
        cat <<'EOF'

## Style: Auto-execute
This is a non-interactive session. Complete the task autonomously.
- Work systematically through each step
- Do not ask questions or wait for user input
- When finished, output only: "Done"
EOF
    fi
}

# ============================================================================
# BUILDER FUNCTION
# ============================================================================

# build_system_prompt <mode> [output_file]
#
# Modes:
#   enhance-interactive: Enhance $FILE in interactive session
#   enhance-auto: Enhance $FILE autonomously
#   expand-interactive: Expand seed to output_file interactively
#   expand-auto: Expand seed to output_file autonomously
#
# Args:
#   mode: One of the modes above
#   output_file: Required for expand modes (where to write expansion)
#
# Returns:
#   Complete system prompt to stdout
#
build_system_prompt() {
    local mode="$1"
    local output_file="${2:-}"

    case "$mode" in
    enhance-interactive)
        _mission_contract '$FILE' "prompt enhancement"
        _enhance_inputs
        echo ""
        _enhance_deliverable
        echo ""
        _never_constraints
        echo ""
        _enhance_procedure
        echo ""
        _shared_investigation_guidance
        echo ""
        _shared_output_guidelines
        echo ""
        _shared_validation_rules
        echo ""
        _verification_gate '$FILE'
        echo ""
        _interactive_style
        ;;

    enhance-auto)
        _mission_contract '$FILE' "prompt enhancement"
        _enhance_inputs
        echo ""
        _enhance_deliverable
        echo ""
        _never_constraints
        echo ""
        _enhance_procedure
        echo ""
        _shared_investigation_guidance
        echo ""
        _shared_output_guidelines
        echo ""
        _shared_validation_rules
        echo ""
        _verification_gate '$FILE'
        echo ""
        _auto_style
        ;;

    expand-interactive)
        if [ -z "$output_file" ]; then
            echo "Error: expand modes require output_file parameter" >&2
            return 1
        fi
        _expand_context "$output_file"
        echo ""
        _session_context  # Inject recent conversation context if available
        _expand_procedure "$output_file"
        echo ""
        _shared_investigation_guidance
        echo ""
        _shared_output_guidelines
        echo ""
        _shared_validation_rules
        echo ""
        _interactive_style
        ;;

    expand-auto)
        if [ -z "$output_file" ]; then
            echo "Error: expand modes require output_file parameter" >&2
            return 1
        fi
        _expand_context "$output_file"
        echo ""
        _session_context  # Inject recent conversation context if available
        _expand_procedure "$output_file"
        echo ""
        _shared_investigation_guidance
        echo ""
        _shared_output_guidelines
        echo ""
        _shared_validation_rules
        echo ""
        _auto_style "$output_file"
        ;;

    *)
        echo "Error: Unknown mode '$mode'" >&2
        echo "Valid modes: enhance-interactive, enhance-auto, expand-interactive, expand-auto" >&2
        return 1
        ;;
    esac
}

# Export the main function
export -f build_system_prompt
