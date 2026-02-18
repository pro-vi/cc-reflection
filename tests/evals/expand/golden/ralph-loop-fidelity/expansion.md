# Ralph Loop Fidelity and Completion Enhancement

## Context

The oracle-loop skill (`~/.claude/skills/oracle-loop/skill.md`, 967 lines) is a comprehensive skill for designing verification strategies for Ralph loops. It supports three modes (Ground Zero, Oracle-Ready, Oracle-Poor), provides extensive templates, and integrates with file-anchored PROGRESS.md patterns.

**Current state observed in hermes project:**
- 5 PROGRESS files exist: PROGRESS_0_BOOTSTRAP through PROGRESS_4_ENTITY
- PROGRESS_3_AGENT.md shows "Phase 4 Complete — UI (one item deferred: 'Research this' button requires Net Worth tab)"
- The word "deferred" appears 6+ times across phases, indicating partial completion is happening but tracked informally
- Sub-items exist under checkboxes but as plain text, not nested checkboxes
- 1274 commits in project history suggest potential micro-commit patterns

**Related skills available for composition:**
- `second-opinion` - Consults Gemini-3-Pro + GPT-5.1-Codex in parallel for external validation
- `code-reviewer` - Reviews code changes with 80%+ confidence threshold
- `simplify` - Reduces complexity before commits
- `casting` - Type safety verification
- `svelte` - Svelte/SvelteKit validation
- `vercel-ai-sdk` - AI SDK type patterns

The Ralph loop plugin (`~/.claude/plugins/marketplaces/claude-plugins-official/plugins/ralph-loop/`) handles loop mechanics via `setup-ralph-loop.sh` which creates `.claude/ralph-loop.local.md` with YAML frontmatter tracking iteration count, max iterations, and completion promise.

---

## Concerns

### 1. Fidelity Parameter Missing

The oracle-loop skill outputs Ralph commands with hardcoded quality patterns. Users must manually decide which checkpoint skills to invoke and when. The skill already knows available skills but doesn't ask upfront about quality trade-offs.

**Evidence:** PROGRESS_3_AGENT.md lines 39-45 list skill invocations:
```
- /casting — before committing any phase with new types
- /second-opinion — at each phase checkpoint
- /svelte — Phase 2 and 4 (all component work)
- /simplify — before each commit
```
This is manually specified per-task rather than being a reusable configuration.

### 2. User Input Handling Breaks Autonomy

The current oracle-loop mentions `[CHECKPOINT] Human reviews` for visual verification. The Ralph loop design assumes pausing for user input when needed. However, pausing defeats the autonomous iteration purpose.

**Better model:** Items requiring human input go to a "needs human" queue that surfaces at loop end, rather than blocking the loop mid-iteration.

### 3. Binary Checkboxes Don't Capture Partial State

PROGRESS_3_AGENT.md shows items marked complete with "deferred" notes in plain text (line 60, 372, 680, 736, 797). The status line "Phase 4 Complete — UI (one item deferred...)" demonstrates the workaround pattern.

**Current pattern:**
```markdown
- [x] **Feature X**
  - Sub-requirement A (done)
  - Sub-requirement B (deferred to Phase 5)
```

**Proposed pattern:**
```markdown
- [ ] Feature X
  - [x] Sub-requirement A
  - [x] Core implementation
  - [ ] Accessibility audit ← surfaces in summary
```

### 4. Commit Granularity Unspecified

The oracle-loop skill says "commit after each phase's checkpoints pass" but doesn't specify granularity. With 1274 commits in hermes, there's evidence of micro-commits that need squashing. The skill should specify: "commit after each major item" vs "batch by section."

---

## Proposed Solution

### Fidelity Levels

Add a `FIDELITY` argument to `/oracle-loop`:

| Level | Description | Skills Invoked |
|-------|-------------|----------------|
| Quick | Oracles after major phases only | None (just test/lint/typecheck) |
| Standard | Code review + second-opinion at phase end | `/code-reviewer`, `/second-opinion` per phase |
| Thorough | Full quality gate after each subsection | All relevant skills after each item |

The oracle-loop skill already lists available skills in the system. On invocation:
1. Ask fidelity level upfront (default: Standard)
2. Auto-compose skill invocations based on task type and fidelity
3. Generate PROGRESS.md with appropriate checkpoint markers

### Deferred Queue Pattern

Replace blocking `[CHECKPOINT]` with queue surfacing:

```markdown
## Deferred Items (needs human)
- Phase 2, Item 3.2: Visual review of dashboard layout
- Phase 4, Item 1.1: Accessibility audit for modal

These items will be listed in the end-of-loop summary.
```

The loop continues autonomously. At completion, output:
```
## Loop Complete

3 items need human review:
- [ ] Phase 2/3.2: Visual review dashboard layout
- [ ] Phase 4/1.1: Accessibility audit modal
- [x] Phase 3/2.4: Second-opinion resolved (logged)
```

### Nested Checkbox Schema

PROGRESS.md template should use:

```markdown
- [ ] 4.1 AgentPanel component
  - [x] Basic structure
  - [x] Session grouping
  - [ ] Accessibility audit ← tracked

**Partial items surfaced:**
- 4.1: AgentPanel (2/3 complete, missing accessibility)
```

The end-of-loop summary walks the checkbox tree and reports:
- Fully complete items
- Partially complete items (with specific gaps)
- Deferred/needs-human items

### Commit Batching

Add to oracle-loop output:

```markdown
## Commit Strategy
- After each section (batched): "feat(agent): add validation layer"
- NOT after each checkbox item (micro-commits)
- Squash threshold: 3+ commits per phase → offer squash
```

---

## Implementation Steps

1. **Update `oracle-loop/skill.md` ARGUMENTS section:**
   - Add `--fidelity [quick|standard|thorough]` (default: standard)
   - Document what each level means

2. **Add skill composition logic:**
   - Section detecting task type (exists)
   - Add mapping: task type × fidelity → skill list
   - Generate checkpoint markers in PROGRESS.md template

3. **Add nested checkbox support:**
   - Update PROGRESS.md templates to use nested checkboxes
   - Add "Partial items" summary section template
   - Add end-of-loop summary format

4. **Add deferred queue:**
   - Replace `[CHECKPOINT]` blocking pattern with `[DEFERRED: reason]` marker
   - Add "Deferred Items" section to PROGRESS.md template
   - Document queue surfacing in completion output

5. **Add commit strategy section:**
   - Default: batch by section
   - Optional: `--commit-granularity [item|section|phase]`
   - Add squash guidance when micro-commits detected

---

## Acceptance Criteria

- [ ] `/oracle-loop --fidelity quick "task"` generates PROGRESS.md with no checkpoint skills
- [ ] `/oracle-loop --fidelity thorough "task"` generates all-skill checkpoints per item
- [ ] Default (standard) generates phase-level checkpoints with second-opinion + code-reviewer
- [ ] PROGRESS.md templates use nested checkboxes for sub-requirements
- [ ] End-of-loop summary lists partial completions with specific gaps
- [ ] Deferred items queued and surfaced at loop end, not blocking mid-loop
- [ ] Commit guidance explicit (section-level by default)

---

## Trade-offs

**Complexity vs Usability:** Adding fidelity levels increases skill complexity but reduces per-task configuration burden. The skill already has templates for different task types; fidelity is orthogonal.

**Autonomy vs Oversight:** Deferring human checkpoints increases autonomy but risks accumulating issues. The queue pattern preserves human oversight while not blocking iteration.

**Nested Checkboxes vs Simplicity:** Nested checkboxes add tracking complexity but match how work actually progresses (core done, polish pending).

---

## Out of Scope

- Ralph plugin changes (this is skill-level, not plugin-level)
- Automatic squash implementation (guidance only)
- UI for deferred queue (PROGRESS.md text-based)
