# Explain How the Reflection Hooks Are Triggered

## Task
Document and explain the complete trigger mechanism for the cc-reflection hooks system, including:
- When hooks execute (lifecycle events and conditions)
- How eligibility is determined
- The depth-scaled probability mechanism
- The one-per-session cooldown system

## Context
cc-reflection has two active hooks that encourage Claude to use the reflection skill:
1. **SessionStart hook** (`bin/reflection-session-start.ts`) — Captures session UUID at Claude Code startup
2. **UserPromptSubmit hook** (`skill-activation-reflection.ts` archived, formerly active) — Suggests reflection during conversation

Hooks are configurable in `~/.claude/hooks/` and are registered to Claude Code via plugin hooks.json.

## Key Files to Reference
- `bin/reflection-session-start.ts` (lines 1-60) — SessionStart hook implementation
- `internal_docs/archived-hooks/skill-activation-reflection.ts` (lines 1-92) — UserPromptSubmit hook (archived but functional)
- `internal_docs/archived-hooks/post-tool-use-reflection-check.ts` (lines 1-100) — PostToolUse hook (archived variant)
- `lib/transcript-utils.ts` (lines 1-100+) — Eligibility logic, transcript path resolution, trigger markers
- `lib/session-id.ts` — Session ID calculation (cross-language sync between bash and TypeScript)

## Expected Output Structure
Document should cover:

### 1. Hook Lifecycle
- **SessionStart**: When triggered (Claude Code startup), what it does (writes session UUID to `~/.claude/reflections/sessions/<projectHash>/current`)
- **UserPromptSubmit**: When triggered (before Claude sees each user message), eligibility checks, probability roll

### 2. Eligibility System
Explain how `checkEligibility()` from transcript-utils.ts determines if a hook should attempt trigger:
- Checks one-per-session marker at `~/.claude/reflections/.session-triggered`
- Counts exchanges in transcript file (JSONL format at `~/.claude/projects/<slug>/<session-id>.jsonl`)
- Returns eligibility + threshold based on exchange depth

### 3. Depth-Scaled Probability
Document the thresholds based on conversation depth (multiples of 7 exchanges):
- **0-6 exchanges**: Never trigger
- **7-13 exchanges**: Roll 20 only (5% of rolls)
- **14-20 exchanges**: Roll 19-20 (10% of rolls)
- **21+ exchanges**: Roll 18-20 (15% of rolls)

### 4. One-Per-Session Cooldown
Explain how `markTriggered()` writes the session-triggered marker:
- File path: `~/.claude/reflections/.session-triggered`
- Prevents same suggestion appearing multiple times in session
- Marker is cleared on session restart/compact

### 5. Hook-to-Skill Invocation
Document how Natural 20 hooks communicate with Claude:
- **UserPromptSubmit**: Outputs message, exits 0 (user sees it, Claude doesn't; uses stdout)
- **PostToolUse**: Outputs to stderr, exits 2 (both user and Claude see it)
- Why the difference in exit codes matters for visibility

## Success Criteria
Done when:
- All 4 hook lifecycle events are documented with specific file paths and line ranges
- Eligibility algorithm is explained with actual thresholds
- The probability mechanism is described with concrete examples (e.g., "At 15 exchanges, Natural 20 has ~5% chance")
- Session isolation and cross-language sync are covered
- Hook output visibility behavior is explained (why different exit codes/streams matter)

## Out of Scope
- Implementation details of the reflection skill itself (`~/.claude/skills/reflection/SKILL.md`)
- How to install or configure the hooks
- The Three Examinations framework (covered in SKILL.md)
