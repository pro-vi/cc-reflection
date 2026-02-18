# CC-Reflection Expand Flow: Complete Architecture

## Context
You're studying how reflection seeds get expanded into detailed prompts within CC-Reflection. The expand flow is triggered when a user selects a seed from the Ctrl+G menu and converts it into an actionable insight.

## Task
Document the complete expand flow as it exists in the codebase, from seed selection to thought-agent output delivery. Make it concrete with file paths, function names, and specific behaviors.

## User Story

**When a user:**
1. Presses Ctrl+G in Claude Code
2. Sees a reflection seed menu (from `bin/cc-reflect`)
3. Selects a seed → wants to understand what happens next

**Expected output:**
A clear walkthrough of how `bin/cc-reflect-expand` processes that seed and returns a result.

## Critical Files & Symbols

**Main entry point:**
- `bin/cc-reflect-expand` (lines 1-210): Spawn point for thought-agent
  - Parameter 1: MODE ("interactive" or "auto")
  - Parameter 2: SEED_ID (format: `seed-TIMESTAMP-RANDOM`)
  - Parameter 3: PROMPT_FILE (optional, used in Ctrl+G flow)

**Seed retrieval:**
- `lib/reflection-state.ts:get()` – Fetches seed JSON by ID from disk
- Output format: ReflectionSeed JSON with fields: id, title, rationale, anchors, options_hint, ttl_hours, created_at, dedupe_key, session_id

**System prompt generation:**
- `lib/prompt-builder.sh` – Modular prompt construction
  - Functions: `build_system_prompt()` (takes mode + output_file)
  - Modes: "expand-interactive", "expand-auto"
  - Output: Full system prompt including seed JSON

**Execution branches:**

1. **Interactive mode** (`bin/cc-reflect-expand` lines 112-165):
   - Tmux: `new-window` in separate window
   - Command: `claude --append-system-prompt "$(cat $SYSTEM_PROMPT_FILE)"`
   - User interaction: Input box prefilled with "Begin investigation"
   - Output destination: `$OUTPUT_FILE` (PROMPT_FILE if Ctrl+G, else `~/.claude/reflections/results/seed-XXX-result.md`)

2. **Auto mode** (`bin/cc-reflect-expand` lines 167-205):
   - Tmux: `new-window` in current session
   - Command: `claude -p "Begin investigation" --append-system-prompt "$(cat $SYSTEM_PROMPT_FILE)"`
   - User interaction: None (auto-executes with `-p` flag)
   - Output destination: Same as interactive

**Output delivery:**
- If called from Ctrl+G (PROMPT_FILE provided): Expansion written to temp prompt file → Claude Code reads it back into input box
- If standalone: Result written to `~/.claude/reflections/results/{SEED_ID}-result.md`

## Key Design Decisions to Document

1. **Two-mode expansion**: Why have both interactive and auto modes? Trade-offs between manual investigation vs. quick execution.

2. **System prompt composition**: How are investigation guidelines, output format rules, and seed context combined?

3. **Conditional output paths**: Why check for PROMPT_FILE? How does Ctrl+G integration differ from standalone?

4. **Tmux window naming**: Format `reflect:{SEED_ID:0:8}` – why truncate to 8 chars?

5. **ORIGINAL_TMUX preservation**: Why save TMUX before unsetting in `cc-reflect`, then restore in `cc-reflect-expand`?

## Acceptance Criteria

Document is complete when it:
- ✅ Traces end-to-end flow from menu selection to thought-agent completion
- ✅ Names every file, function, and parameter involved
- ✅ Explains the two execution modes (interactive vs. auto) with their differences
- ✅ Shows how output reaches main agent (Ctrl+G vs. standalone paths)
- ✅ Clarifies design choices (why this architecture?)
- ✅ Includes concrete command examples from actual implementation
- ✅ Validates all file paths and symbols exist in the codebase

## Out of Scope
- Reflection seed creation (that's `bin/cc-reflect` + plugin skill)
- State manager internals (just document the interface)
- BATS tests or validation functions (focus on happy path)
- How Claude uses reflection results (main agent concern, not expand concern)